import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool installed: false
  property bool running: false
  property int desiredState: -1
  readonly property bool active: desiredState === -1 ? running : desiredState === 1
  property bool refreshing: false
  // Lifecycle state, one of: unknown, missing, daemonDown, idle, connecting,
  // connected, needsLogin, loginFailed, sessionExpired. Deliberately not
  // called `state`: that name already belongs to Item's state machine, and
  // shadowing it here would be asking for trouble.
  property string connState: "unknown"
  property string hint: ""
  property bool connecting: false
  property string statusText: "Checking…"
  property string cliVersion: ""
  property string daemonVersion: ""
  property bool versionMismatch: false
  property string ip: ""
  property string fqdn: ""
  property string profileName: "default"
  property bool managementConnected: false
  property bool signalConnected: false
  property int peerTotal: 0
  property int peerConnected: 0
  property int peerConnecting: 0
  property var peers: []
  property var relays: []
  property int relayTotal: 0
  property int relayAvailable: 0
  property var networks: []
  property bool networksLoaded: false
  property string networksError: ""
  property string pendingNetworkId: ""
  // Networks are only rendered inside the panel, so the background poll skips
  // the extra `netbird networks list` call until the panel is actually open.
  property bool wantNetworks: false
  property string lastError: ""
  property string actionStatus: ""

  // SSO login is a long-lived foreground process: `netbird up` prints a
  // verification URL and then blocks until the browser flow completes.
  property string loginUrl: ""
  property string loginCode: ""
  property bool loginActive: false
  property string loginOutput: ""

  // A daemon that never answers must not be polled at full rate forever.
  property int failureStreak: 0

  readonly property bool needsLogin: Model.needsLoginState(connState)
  readonly property bool daemonDown: connState === "daemonDown"
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  // Back off exponentially while the daemon is unreachable (capped at 5
  // minutes) so a stopped service costs one probe every few minutes instead
  // of a stuck process every 30 seconds.
  readonly property int effectiveIntervalSec: Math.min(300, refreshIntervalSec * Math.pow(2, Math.min(failureStreak, 4)))
  readonly property bool busy: whichProcess.running || statusProcess.running || actionProcess.running || loginProcess.running
  readonly property bool relaysDegraded: relayTotal > 0 && relayAvailable < relayTotal
  readonly property int networksSelected: Model.selectedNetworkCount(networks)
  property string statusOutput: ""
  property string statusError: ""
  property string actionOutput: ""
  property string actionError: ""
  property string networksOutput: ""
  property string networksErrorOutput: ""
  property string networkActionOutput: ""
  property string networkActionError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function clearStatus(message, newState) {
    running = false
    connecting = false
    if (desiredState === 0) desiredState = -1
    connState = newState || "idle"
    statusText = message || Model.stateLabel(connState)
    hint = Model.stateHint(connState)
    ip = ""
    fqdn = ""
    managementConnected = false
    signalConnected = false
    peerTotal = 0
    peerConnected = 0
    peerConnecting = 0
    peers = []
    relays = []
    relayTotal = 0
    relayAvailable = 0
    networks = []
    networksLoaded = false
    networksError = ""
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      clearStatus(parsed.message)
      lastError = parsed.error || ""
      return
    }
    running = parsed.running
    connecting = parsed.connecting
    connState = parsed.state
    hint = parsed.hint
    cliVersion = parsed.cliVersion
    daemonVersion = parsed.daemonVersion
    versionMismatch = parsed.versionMismatch
    // A login that succeeded elsewhere (or a session that came back) clears
    // any prompt still on screen.
    if (!parsed.needsLogin) clearLogin()
    if (desiredState !== -1 && running === (desiredState === 1)) desiredState = -1
    // "Needs login" is not a state a toggle can leave; drop the optimistic
    // switch position so the panel stops pretending it is connecting.
    if (parsed.needsLogin) desiredState = -1
    statusText = parsed.statusText
    ip = parsed.ip
    fqdn = parsed.fqdn
    profileName = parsed.profileName
    managementConnected = parsed.managementConnected
    signalConnected = parsed.signalConnected
    peerTotal = parsed.peerTotal
    peerConnected = parsed.peerConnected
    peerConnecting = parsed.peerConnecting
    peers = parsed.peers
    relays = parsed.relays
    relayTotal = parsed.relayTotal
    relayAvailable = parsed.relayAvailable
    lastError = ""
    // Networks only exist while the daemon is up; refresh them alongside
    // status so the panel never shows a stale selection.
    if (running && wantNetworks) refreshNetworks()
    else if (!running) {
      networks = []
      networksLoaded = false
    }
  }

  function refresh() {
    if (!installed) {
      if (!whichProcess.running) {
        refreshing = true
        whichProcess.command = ["which", "netbird"]
        whichProcess.running = true
      }
      return
    }
    if (!statusProcess.running) {
      refreshing = true
      statusOutput = ""
      statusError = ""
      // Without `timeout` this call does not fail when the daemon socket is
      // gone: the CLI retries the socket indefinitely, printing gRPC dial
      // errors, and every poll leaves another stuck process behind.
      statusProcess.command = ["timeout", "-k", "2", String(statusTimeoutSec), "netbird", "status", "--json"]
      statusProcess.running = true
      watchdog.restart()
    }
  }

  readonly property int statusTimeoutSec: 8

  function startLogin() {
    if (!installed || loginProcess.running) return
    loginUrl = ""
    loginCode = ""
    loginOutput = ""
    loginActive = true
    actionStatus = "Starting NetBird login…"
    // --no-browser keeps the browser choice with Omarchy instead of letting
    // the CLI shell out to xdg-open behind our back.
    loginProcess.command = ["netbird", "up", "--no-browser"]
    loginProcess.running = true
    loginTimeout.restart()
  }

  function cancelLogin() {
    if (loginProcess.running) loginProcess.running = false
    clearLogin()
    actionStatus = ""
  }

  function clearLogin() {
    loginActive = false
    loginUrl = ""
    loginCode = ""
  }

  function openLoginUrl() {
    if (loginUrl === "") return
    Quickshell.execDetached(["omarchy", "launch", "browser", loginUrl])
  }

  function handleLoginOutput(data) {
    var text = String(data || "")
    loginOutput += text + "\n"
    var prompt = Model.parseLoginPrompt(text)
    if (prompt.url !== "" && loginUrl === "") {
      loginUrl = prompt.url
      actionStatus = ""
      openLoginUrl()
    }
    if (prompt.code !== "" && loginCode === "") loginCode = prompt.code
  }

  function refreshNetworks() {
    if (!installed || daemonDown || networksProcess.running) return
    networksOutput = ""
    networksErrorOutput = ""
    networksProcess.command = ["timeout", "-k", "2", String(statusTimeoutSec), "netbird", "networks", "list"]
    networksProcess.running = true
  }

  function applyNetworks(raw) {
    var parsed = Model.parseNetworks(raw)
    if (!parsed.ok) {
      networksError = parsed.message || "Could not read networks"
      return
    }
    networks = parsed.networks
    networksLoaded = true
    networksError = ""
  }

  // `networks select` replaces the whole selection by default, so a single-row
  // toggle has to append (-a) on the way in and deselect by id on the way out.
  function setNetworkSelected(id, selected) {
    var networkId = String(id || "")
    if (!installed || networkId === "" || networkActionProcess.running) return
    pendingNetworkId = networkId
    networkActionOutput = ""
    networkActionError = ""
    networkActionProcess.command = selected
      ? ["netbird", "networks", "select", "-a", networkId]
      : ["netbird", "networks", "deselect", networkId]
    networkActionProcess.running = true
  }

  function toggleNetwork(network) {
    if (!network) return
    setNetworkSelected(network.id, !network.selected)
  }

  function selectAllNetworks() {
    if (!installed || networkActionProcess.running) return
    pendingNetworkId = ""
    networkActionProcess.command = ["netbird", "networks", "select", "all"]
    networkActionProcess.running = true
  }

  function deselectAllNetworks() {
    if (!installed || networkActionProcess.running) return
    pendingNetworkId = ""
    networkActionProcess.command = ["netbird", "networks", "deselect", "all"]
    networkActionProcess.running = true
  }

  function toggleNetbird() {
    if (!installed || actionProcess.running) return
    // Turning on while the daemon wants credentials is a login, not an `up`:
    // plain `netbird up` would block on the SSO flow with nothing on screen.
    if (!active && needsLogin) {
      startLogin()
      return
    }
    if (!active && daemonDown) {
      actionStatus = "NetBird daemon is not running"
      messageTimer.restart()
      return
    }
    desiredState = active ? 0 : 1
    actionStatus = desiredState === 1 ? "Connecting…" : "Disconnecting…"
    actionOutput = ""
    actionError = ""
    actionProcess.command = ["timeout", "-k", "2", "20", "netbird", desiredState === 1 ? "up" : "down"]
    actionProcess.running = true
  }

  function copy(value) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function copyPeerIp(peer) { if (peer) copy(peer.ip) }
  function copyPeerName(peer) { if (peer) copy(peer.fqdn || peer.name) }

  function launchTerminal(command, peer) {
    if (!peer || !peer.ip) return
    Quickshell.execDetached(["omarchy", "launch", "terminal", command, peer.ip])
  }

  function ssh(peer) { launchTerminal("ssh", peer) }
  function ping(peer) { launchTerminal("ping", peer) }

  Timer {
    interval: root.effectiveIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 700
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    // An abandoned SSO flow would otherwise keep `netbird up` alive forever.
    id: loginTimeout
    interval: 300000
    repeat: false
    onTriggered: if (root.loginActive) {
      root.cancelLogin()
      root.actionStatus = "Login timed out"
      messageTimer.restart()
    }
  }

  Timer {
    id: messageTimer
    interval: 2500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    // Backstop only: `timeout` in the command should end the call first.
    id: watchdog
    interval: (root.statusTimeoutSec + 7) * 1000
    repeat: false
    onTriggered: if (statusProcess.running) {
      statusProcess.running = false
      root.refreshing = false
      root.failureStreak = Math.min(root.failureStreak + 1, 6)
      root.clearStatus("", "daemonDown")
      root.lastError = "NetBird status timed out"
    }
  }

  Process {
    id: whichProcess
    running: false
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refresh()
      else {
        root.refreshing = false
        root.clearStatus("", "missing")
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root.statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root.statusError = text }
    onExited: function(exitCode) {
      watchdog.stop()
      root.refreshing = false
      var output = String(statusStdout.text || root.statusOutput || "")
      var error = String(statusStderr.text || root.statusError || "").trim()
      if (exitCode === 0) {
        root.failureStreak = 0
        root.applyStatus(output)
      } else if (Model.daemonUnreachable(exitCode, error + " " + output)) {
        // Unreachable daemon: back off instead of restarting a doomed call
        // every interval, and say so rather than claiming "Disconnected".
        root.failureStreak = Math.min(root.failureStreak + 1, 6)
        root.clearStatus("", "daemonDown")
        root.lastError = ""
      } else {
        root.failureStreak = 0
        root.clearStatus("", "idle")
        root.lastError = error
      }
    }
  }

  Process {
    id: loginProcess
    running: false
    command: []
    // Line-streamed, not collected: the verification URL has to reach the
    // panel while the process is still blocking on the browser flow.
    stdout: SplitParser { onRead: function(data) { root.handleLoginOutput(data) } }
    stderr: SplitParser { onRead: function(data) { root.handleLoginOutput(data) } }
    onExited: function(exitCode) {
      root.loginActive = false
      loginTimeout.stop()
      if (exitCode !== 0 && root.loginUrl === "") {
        root.actionStatus = (String(root.loginOutput || "").replace(/\s+/g, " ").trim() || "NetBird login failed")
        messageTimer.restart()
      } else {
        root.actionStatus = ""
      }
      root.clearLogin()
      delayedRefresh.restart()
    }
  }

  Process {
    id: networksProcess
    running: false
    stdout: StdioCollector { id: networksStdout; waitForEnd: true; onStreamFinished: root.networksOutput = text }
    stderr: StdioCollector { id: networksStderr; waitForEnd: true; onStreamFinished: root.networksErrorOutput = text }
    onExited: function(exitCode) {
      var output = String(networksStdout.text || root.networksOutput || "")
      var error = String(networksStderr.text || root.networksErrorOutput || "").trim()
      if (exitCode === 0) root.applyNetworks(output)
      else {
        root.networks = []
        root.networksLoaded = false
        root.networksError = (error || "Could not list networks").replace(/\s+/g, " ").trim()
      }
    }
  }

  Process {
    id: networkActionProcess
    running: false
    stdout: StdioCollector { id: networkActionStdout; waitForEnd: true; onStreamFinished: root.networkActionOutput = text }
    stderr: StdioCollector { id: networkActionStderr; waitForEnd: true; onStreamFinished: root.networkActionError = text }
    onExited: function(exitCode) {
      var output = String(networkActionStdout.text || root.networkActionOutput || "")
      var error = String(networkActionStderr.text || root.networkActionError || "").trim()
      root.pendingNetworkId = ""
      if (exitCode !== 0) {
        root.actionStatus = (error || output || "Network change failed").replace(/\s+/g, " ").trim()
        messageTimer.restart()
      }
      root.refreshNetworks()
      // Selecting a network rewires routes, so re-read the whole status too
      // once the daemon has had a moment to apply it.
      delayedRefresh.restart()
    }
  }

  Process {
    id: actionProcess
    running: false
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root.actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root.actionError = text }
    onExited: function(exitCode) {
      var output = String(actionStdout.text || root.actionOutput || "")
      var error = String(actionStderr.text || root.actionError || "").trim()
      if (exitCode !== 0) {
        root.desiredState = -1
        root.lastError = (error || output || "NetBird command failed").replace(/\s+/g, " ").trim()
        root.actionStatus = root.lastError
        messageTimer.restart()
      } else {
        root.lastError = ""
      }
      delayedRefresh.restart()
    }
  }
}
