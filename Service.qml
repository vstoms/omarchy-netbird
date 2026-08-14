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
  property string statusText: "Checking…"
  property string ip: ""
  property string fqdn: ""
  property string profileName: "default"
  property bool managementConnected: false
  property bool signalConnected: false
  property int peerTotal: 0
  property int peerConnected: 0
  property var peers: []
  property string lastError: ""
  property string actionStatus: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running || statusProcess.running || actionProcess.running
  property string statusOutput: ""
  property string statusError: ""
  property string actionOutput: ""
  property string actionError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function clearStatus(message) {
    running = false
    if (desiredState === 0) desiredState = -1
    statusText = message || "Disconnected"
    ip = ""
    fqdn = ""
    managementConnected = false
    signalConnected = false
    peerTotal = 0
    peerConnected = 0
    peers = []
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      clearStatus(parsed.message)
      lastError = parsed.error || ""
      return
    }
    running = parsed.running
    if (desiredState !== -1 && running === (desiredState === 1)) desiredState = -1
    statusText = parsed.statusText
    ip = parsed.ip
    fqdn = parsed.fqdn
    profileName = parsed.profileName
    managementConnected = parsed.managementConnected
    signalConnected = parsed.signalConnected
    peerTotal = parsed.peerTotal
    peerConnected = parsed.peerConnected
    peers = parsed.peers
    lastError = ""
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
      statusProcess.command = ["netbird", "status", "--json"]
      statusProcess.running = true
      watchdog.restart()
    }
  }

  function toggleNetbird() {
    if (!installed || actionProcess.running) return
    desiredState = active ? 0 : 1
    actionStatus = desiredState === 1 ? "Connecting…" : "Disconnecting…"
    actionOutput = ""
    actionError = ""
    actionProcess.command = ["netbird", desiredState === 1 ? "up" : "down"]
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
    interval: root.refreshIntervalSec * 1000
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
    id: messageTimer
    interval: 2500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: watchdog
    interval: 15000
    repeat: false
    onTriggered: if (statusProcess.running) {
      statusProcess.running = false
      root.refreshing = false
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
        root.clearStatus("Not installed")
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
      if (exitCode === 0) root.applyStatus(output)
      else {
        root.clearStatus("Disconnected")
        root.lastError = error
      }
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
