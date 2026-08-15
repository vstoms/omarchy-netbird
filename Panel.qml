import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "vstoms.netbird"
  ipcTarget: "vstoms.netbird"
  manageIpc: false

  property int peerIndex: 0
  property int networkIndex: 0
  property bool cursorActive: false
  property string focusSection: "header"
  property bool relaysExpanded: false
  property string searchQuery: ""
  property bool searchActive: false
  // "2 minutes ago" has to keep counting while the panel sits open, so the
  // reference clock ticks independently of the status poll.
  property double nowMs: Date.now()
  // Which peer row is showing its detail block, by stable peer key.
  property string expandedPeerKey: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  // Peers mid-handshake are neither good news nor bad news; tint the theme's
  // foreground toward its urgent color so the state reads as "in progress"
  // in every palette instead of hardcoding an amber that clashes with some.
  readonly property color pending: Qt.tint(foreground, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.5))
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showDisconnected: settingBool("showDisconnectedPeers", true)
  readonly property bool showNetworks: settingBool("showNetworks", true)
  readonly property string adminUrl: String(setting("adminConsoleUrl", "https://app.netbird.io/"))
  readonly property var visiblePeers: filteredPeers()
  readonly property var visibleNetworks: showNetworks && netbird.active ? netbird.networks : []
  readonly property bool hasNetworks: visibleNetworks.length > 0
  readonly property bool monochromeIcon: settingBool("monochromeIcon", true)
  // Connected, but something underneath is unhealthy. Worth surfacing in the
  // bar: today this only shows up if you open the panel and read the rows.
  readonly property bool degraded: netbird.running
    && (!netbird.managementConnected || !netbird.signalConnected || netbird.relaysDegraded)
  // Bar icons use the bar's own foreground, which a theme can set separately
  // from the panel foreground.
  readonly property color barIconColor: !netbird.active
    ? Qt.darker(barForeground, 1.55)
    : (degraded && monochromeIcon ? urgent : barForeground)
  readonly property bool showStateCard: !netbird.installed || netbird.daemonDown || netbird.needsLogin || netbird.loginActive
  readonly property string daemonStartCommand: "sudo systemctl start netbird"
  readonly property bool hasStateAction: stateActionLabel !== ""
  // The card's primary action depends on why we are stuck.
  readonly property string stateActionLabel: {
    if (!netbird.installed) return ""
    if (netbird.loginActive) return netbird.loginUrl !== "" ? "Open login page" : ""
    if (netbird.needsLogin) return "Log in"
    if (netbird.daemonDown) return "Retry"
    return ""
  }
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && netbird.installed

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function settingBool(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "boolean") return value
    return String(value).toLowerCase() !== "false" && String(value) !== "0"
  }

  function filteredPeers() {
    return Model.filterPeers(netbird.peers, searchQuery, showDisconnected)
  }

  function openSearch() {
    searchActive = true
    Qt.callLater(function() { if (peerSearch) peerSearch.forceActiveFocus() })
  }

  function closeSearch(clear) {
    if (clear === true) searchQuery = ""
    searchActive = searchQuery !== ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function toggleDetails(peer) {
    if (!peer) return
    expandedPeerKey = expandedPeerKey === peer.key ? "" : peer.key
    // Opening a detail block should show a fresh "last handshake", not a
    // value left over from whenever the clock last ticked.
    if (expandedPeerKey !== "") nowMs = Date.now()
  }

  function isExpanded(peer) {
    return peer && peer.key !== "" && expandedPeerKey === peer.key
  }

  function selectedPeer() {
    if (visiblePeers.length === 0) return null
    return visiblePeers[Math.max(0, Math.min(peerIndex, visiblePeers.length - 1))]
  }

  function selectedNetwork() {
    if (visibleNetworks.length === 0) return null
    return visibleNetworks[Math.max(0, Math.min(networkIndex, visibleNetworks.length - 1))]
  }

  // Sections collapse when empty, so the cursor is kept on a section that is
  // actually on screen before and after every move.
  function ensureCursor() {
    if (peerIndex >= visiblePeers.length) peerIndex = Math.max(0, visiblePeers.length - 1)
    if (networkIndex >= visibleNetworks.length) networkIndex = Math.max(0, visibleNetworks.length - 1)
    if (focusSection === "peers" && visiblePeers.length === 0) focusSection = hasNetworks ? "networks" : "header"
    if (focusSection === "networks" && !hasNetworks) focusSection = visiblePeers.length > 0 ? "peers" : "header"
    if (focusSection === "state" && stateActionLabel === "") focusSection = "header"
  }

  function moveCursor(delta) {
    cursorActive = true
    ensureCursor()
    if (delta === 0) return

    if (focusSection === "header") {
      if (delta > 0) {
        if (hasStateAction) focusSection = "state"
        else if (hasNetworks) { focusSection = "networks"; networkIndex = 0 }
        else if (visiblePeers.length > 0) { focusSection = "peers"; peerIndex = 0 }
      }
    } else if (focusSection === "state") {
      if (delta < 0) focusSection = "header"
      else if (hasNetworks) { focusSection = "networks"; networkIndex = 0 }
      else if (visiblePeers.length > 0) { focusSection = "peers"; peerIndex = 0 }
    } else if (focusSection === "networks") {
      if (delta < 0) {
        if (networkIndex <= 0) focusSection = hasStateAction ? "state" : "header"
        else networkIndex--
      } else if (networkIndex < visibleNetworks.length - 1) {
        networkIndex++
      } else if (visiblePeers.length > 0) {
        focusSection = "peers"
        peerIndex = 0
      }
    } else if (focusSection === "peers") {
      if (delta < 0) {
        if (peerIndex <= 0) {
          if (hasNetworks) { focusSection = "networks"; networkIndex = visibleNetworks.length - 1 }
          else focusSection = hasStateAction ? "state" : "header"
        } else peerIndex--
      } else if (peerIndex < visiblePeers.length - 1) {
        peerIndex++
      }
    }
    ensureCursor()
    scrollSelectedIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") netbird.toggleNetbird()
    else if (focusSection === "state") runStateAction()
    else if (focusSection === "networks") netbird.toggleNetwork(selectedNetwork())
    else netbird.copyPeerIp(selectedPeer())
  }

  function setPeerCursor(index) {
    cursorActive = true
    focusSection = "peers"
    peerIndex = index
  }

  function setNetworkCursor(index) {
    cursorActive = true
    focusSection = "networks"
    networkIndex = index
  }

  function scrollItemIntoView(item) {
    if (!item || !panelFlick) return
    Qt.callLater(function() {
      if (!item) return
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      if (top < panelFlick.contentY) panelFlick.contentY = Math.max(0, top)
      else if (bottom > panelFlick.contentY + panelFlick.height)
        panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentHeight - panelFlick.height, bottom - panelFlick.height))
    })
  }

  function scrollSelectedIntoView() {
    if (focusSection === "peers" && peerColumn && peerIndex >= 0 && peerIndex < peerColumn.children.length)
      scrollItemIntoView(peerColumn.children[peerIndex])
    else if (focusSection === "networks" && networkColumn && networkIndex >= 0 && networkIndex < networkColumn.children.length)
      scrollItemIntoView(networkColumn.children[networkIndex])
  }

  function runStateAction() {
    if (!netbird.installed) return
    if (netbird.loginActive) netbird.openLoginUrl()
    else if (netbird.needsLogin) netbird.startLogin()
    else if (netbird.daemonDown) netbird.refresh()
  }

  function barTooltipText() {
    if (!netbird.installed) return "NetBird \u2014 not installed"
    if (netbird.daemonDown) return "NetBird \u2014 daemon not running"
    if (netbird.needsLogin) return "NetBird \u2014 login required"
    if (!netbird.active) return "NetBird \u2014 " + netbird.statusText
    var text = "NetBird \u2014 " + netbird.peerConnected + "/" + netbird.peerTotal + " peers connected"
    var problems = []
    if (!netbird.managementConnected) problems.push("management down")
    if (!netbird.signalConnected) problems.push("signal down")
    if (netbird.relaysDegraded) problems.push("relays degraded")
    if (problems.length > 0) text += " \u00b7 " + problems.join(", ")
    return text
  }

  function openAdmin() {
    if (adminUrl !== "") Quickshell.execDetached(["omarchy", "launch", "browser", adminUrl])
  }

  function connectionIcon(peer) {
    if (!peer) return "󰲛"
    if (peer.connecting) return "󰔟"
    if (!peer.connected) return "󰲛"
    if (String(peer.connectionType).toLowerCase() === "p2p") return "󰌷"
    if (String(peer.connectionType).toLowerCase() === "relayed") return "󰅟"
    return "󰲝"
  }

  function peerColor(peer) {
    if (!peer) return dim
    if (peer.connected) return foreground
    if (peer.connecting) return pending
    return dim
  }

  // Connected peers describe themselves (IP · P2P · 3 ms); the ones that are
  // still negotiating have no connection type or latency yet, so say what
  // they are doing instead of printing an empty "-".
  function peerSubtitle(peer) {
    if (!peer) return ""
    var parts = [peer.ip]
    if (peer.connecting) parts.push("Connecting…")
    else if (peer.idle) parts.push("Idle")
    else {
      if (peer.connectionType && peer.connectionType !== "-") parts.push(peer.connectionType)
      var latency = Model.formatLatency(peer.latencyMs)
      if (latency !== "") parts.push(latency)
    }
    return parts.join(" · ")
  }

  function relayTooltip() {
    var failed = []
    for (var i = 0; i < netbird.relays.length; i++) {
      var relay = netbird.relays[i]
      if (!relay.available) failed.push(relay.name + (relay.error ? ": " + relay.error : ""))
    }
    if (failed.length === 0) return "All relays reachable"
    return failed.join("\n")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = "header"
    searchQuery = ""
    searchActive = false
    expandedPeerKey = ""
    peerIndex = 0
    networkIndex = 0
    relaysExpanded = false
    panelFlick.contentY = 0
    netbird.refresh()
    // `wantNetworks` is bound to `opened`, but binding vs. handler order is not
    // guaranteed, so ask for the list explicitly on the way in.
    if (showNetworks) netbird.refreshNetworks()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onVisiblePeersChanged: ensureCursor()
  onVisibleNetworksChanged: ensureCursor()

  Service {
    id: netbird
    settings: root.settings
    wantNetworks: root.opened && root.showNetworks
  }

  Timer {
    interval: 10000
    repeat: true
    running: root.opened && root.expandedPeerKey !== ""
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { netbird.refresh(); return "ok" }
    function up(): string { if (!netbird.active) netbird.toggleNetbird(); return "ok" }
    function down(): string { if (netbird.active) netbird.toggleNetbird(); return "ok" }
    function toggleNetbird(): string { netbird.toggleNetbird(); return "ok" }
    function status(): string { return netbird.statusText }
    function networks(): string {
      var lines = []
      for (var i = 0; i < netbird.networks.length; i++) {
        var network = netbird.networks[i]
        lines.push((network.selected ? "[x] " : "[ ] ") + network.id + "\t" + Model.networkSubtitle(network))
      }
      return lines.length > 0 ? lines.join("\n") : "No networks available."
    }
    function selectNetwork(id: string): string { netbird.setNetworkSelected(id, true); return "ok" }
    function deselectNetwork(id: string): string { netbird.setNetworkSelected(id, false); return "ok" }
    function relays(): string {
      return netbird.relayAvailable + "/" + netbird.relayTotal + " relays available"
    }
    function state(): string { return netbird.connState }
    function login(): string { netbird.startLogin(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.barTooltipText()
    iconComponent: Component {
      Item {
        NetbirdIcon {
          anchors.centerIn: parent
          iconSize: Style.font.icon
          monochrome: root.monochromeIcon
          color: root.barIconColor
          slashColor: root.barIconColor
          crossed: !netbird.active
          opacity: netbird.refreshing ? 0.55 : 1
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) netbird.toggleNetbird()
      else if (buttonCode === Qt.MiddleButton) netbird.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While the search field has focus every keystroke belongs to it, not
      // to the panel's single-letter shortcuts. A binding rather than an
      // assignment so this can never latch on with the field gone.
      blocked: peerSearch.visible && peerSearch.activeFocus
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") netbird.toggleNetbird()
        else if (t === "r" || t === "R") netbird.refresh()
        else if (t === "c" || t === "C") netbird.copyPeerIp(root.selectedPeer())
        else if (t === "n" || t === "N") netbird.copyPeerName(root.selectedPeer())
        else if (t === "s" || t === "S") netbird.ssh(root.selectedPeer())
        else if (t === "p" || t === "P") netbird.ping(root.selectedPeer())
        else if (t === "a" || t === "A") root.openAdmin()
        else if (t === "w" || t === "W") netbird.toggleNetwork(root.selectedNetwork())
        else if (t === "e" || t === "E") root.relaysExpanded = !root.relaysExpanded
        else if (t === "d" || t === "D") root.toggleDetails(root.selectedPeer())
        else if (t === "/") root.openSearch()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              width: parent.width
              title: netbird.fqdn || "NetBird"
              meta: netbird.active
                ? netbird.peerConnected + "/" + netbird.peerTotal + " peers connected"
                  + (netbird.peerConnecting > 0 ? " · " + netbird.peerConnecting + " connecting" : "")
                : netbird.statusText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: netbird.active ? 1 : 0.5
              iconComponent: Component {
                NetbirdIcon {
                  iconSize: Style.font.display
                  monochrome: root.monochromeIcon
                  color: root.foreground
                  slashColor: root.foreground
                  crossed: !netbird.active
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: netbird.installed
                  checked: netbird.active
                  busy: netbird.busy || netbird.connecting
                  hasCursor: root.headerHasCursor
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "header" } }
                  onToggled: netbird.toggleNetbird()
                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: netbird.active
                      ? "Disconnect NetBird"
                      : (netbird.needsLogin ? "Log in to NetBird" : "Connect NetBird")
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: netbird.actionStatus !== "" || netbird.lastError !== ""
            width: parent.width
            text: netbird.actionStatus !== "" ? netbird.actionStatus : netbird.lastError
            color: netbird.lastError !== "" && netbird.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // One card for every state the daemon cannot fix by itself: not
          // installed, daemon down, needs login, session expired. Each one
          // gets the action that actually resolves it.
          CursorSurface {
            id: stateCard
            visible: root.showStateCard
            width: parent.width
            implicitHeight: stateColumn.implicitHeight + Style.space(20)
            hasCursor: root.cursorActive && root.focusSection === "state"
            foreground: root.foreground

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
              onEntered: if (root.stateActionLabel !== "") { root.cursorActive = true; root.focusSection = "state" }
            }

            Column {
              id: stateColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: netbird.hint !== "" ? netbird.hint : netbird.statusText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              // While a login is running the code is the thing the user has
              // to read off the screen, so it gets the prominent treatment.
              Text {
                visible: netbird.loginCode !== ""
                text: "Code: " + netbird.loginCode
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
              }

              Text {
                visible: netbird.loginActive && netbird.loginUrl === ""
                width: parent.width
                text: "Waiting for the login URL…"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: netbird.daemonDown
                width: parent.width
                text: root.daemonStartCommand
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Button {
                  visible: root.stateActionLabel !== ""
                  text: root.stateActionLabel
                  hasCursor: root.cursorActive && root.focusSection === "state"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.runStateAction()
                  onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "state" } }
                }
                Button {
                  visible: netbird.daemonDown
                  text: "Copy command"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: netbird.copy(root.daemonStartCommand)
                }
                Button {
                  visible: netbird.loginActive
                  text: "Cancel"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: netbird.cancelLogin()
                }
                Item { Layout.fillWidth: true }
              }
            }
          }

          // A CLI and daemon on different versions is a real source of odd
          // behaviour, and both numbers are already in the status payload.
          Text {
            visible: netbird.versionMismatch
            width: parent.width
            text: "CLI " + netbird.cliVersion + " and daemon " + netbird.daemonVersion
              + " versions differ. Restart the NetBird service after an update."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          GridLayout {
            visible: netbird.installed && netbird.active
            width: parent.width
            columns: 2
            columnSpacing: Style.space(16)
            rowSpacing: Style.space(5)

            StatusLabel { text: "NetBird IP" }
            StatusValue {
              text: netbird.ip || "—"
              MouseArea {
                anchors.fill: parent
                enabled: netbird.ip !== ""
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: netbird.copy(netbird.ip)
              }
            }
            StatusLabel { text: "Profile" }
            StatusValue { text: netbird.profileName || "default" }
            StatusLabel { text: "Management" }
            StatusValue {
              text: netbird.managementConnected ? "Connected" : "Disconnected"
              color: netbird.managementConnected ? root.foreground : root.urgent
            }
            StatusLabel { text: "Signal" }
            StatusValue {
              text: netbird.signalConnected ? "Connected" : "Disconnected"
              color: netbird.signalConnected ? root.foreground : root.urgent
            }
            StatusLabel {
              text: "Relays"
              visible: netbird.relayTotal > 0
            }
            StatusValue {
              id: relayValue
              visible: netbird.relayTotal > 0
              text: netbird.relayAvailable + "/" + netbird.relayTotal + " available  "
                + (root.relaysExpanded ? "󰅃" : "󰅀")
              color: netbird.relaysDegraded ? root.urgent : root.foreground
              MouseArea {
                id: relayMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.relaysExpanded = !root.relaysExpanded
              }
              PanelToolTip {
                visible: relayMouse.containsMouse
                text: root.relayTooltip()
                fontFamily: root.fontFamily
              }
            }
          }

          // Relay detail stays collapsed by default: it only matters when a
          // peer is stuck relayed or unreachable, and it is five extra rows.
          Column {
            visible: netbird.installed && netbird.active && root.relaysExpanded && netbird.relays.length > 0
            width: parent.width
            spacing: Style.space(3)

            Repeater {
              model: netbird.relays
              RowLayout {
                required property var modelData
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: modelData.available ? "󰄴" : "󰅙"
                  color: modelData.available ? root.dim : root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  Layout.fillWidth: true
                  text: modelData.name
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                Text {
                  text: modelData.error !== "" ? modelData.error : modelData.scheme
                  color: modelData.error !== "" ? root.urgent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  Layout.maximumWidth: parent.width * 0.45
                }
              }
            }
          }

          PanelSeparator {
            visible: netbird.installed && netbird.active
            foreground: root.foreground
          }

          // Networks (routes/resources) sit above peers: they are the thing a
          // user actually flips during a session, peers are reference data.
          Column {
            visible: netbird.installed && netbird.active && root.showNetworks
              && (root.hasNetworks || netbird.networksError !== "")
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(networksHeader.implicitHeight, networksActions.implicitHeight)
              PanelSectionHeader {
                id: networksHeader
                text: "NETWORKS"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              RowLayout {
                id: networksActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: netbird.networksSelected + "/" + root.visibleNetworks.length
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.rightMargin: Style.space(4)
                }
                PanelActionButton {
                  iconText: "󰄴"
                  tooltipText: "Select all networks"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: root.hasNetworks && netbird.networksSelected < root.visibleNetworks.length
                  onClicked: netbird.selectAllNetworks()
                }
                PanelActionButton {
                  iconText: "󰅙"
                  tooltipText: "Deselect all networks"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: netbird.networksSelected > 0
                  onClicked: netbird.deselectAllNetworks()
                }
              }
            }

            Text {
              visible: netbird.networksError !== ""
              width: parent.width
              text: netbird.networksError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Column {
              id: networkColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.visibleNetworks
                NetworkRow {
                  required property var modelData
                  required property int index
                  width: networkColumn.width
                  network: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            visible: netbird.installed && netbird.active && root.showNetworks && root.hasNetworks
            foreground: root.foreground
          }

          Column {
            visible: netbird.installed && netbird.active
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(peersHeader.implicitHeight, peerActions.implicitHeight)
              PanelSectionHeader {
                id: peersHeader
                text: "PEERS"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              RowLayout {
                id: peerActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  visible: root.searchQuery !== ""
                  text: root.visiblePeers.length + " of " + netbird.peers.length
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.rightMargin: Style.space(4)
                }
                PanelActionButton {
                  id: searchButton
                  iconText: "󰍉"
                  tooltipText: "Search peers  (/)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.searchActive && root.searchQuery === "" ? root.closeSearch(true) : root.openSearch()
                }
                PanelActionButton {
                  id: adminButton
                  iconText: "󰖟"
                  tooltipText: "Open NetBird admin console"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.openAdmin()
                }
              }
            }

            TextField {
              id: peerSearch
              visible: root.searchActive
              width: parent.width
              foreground: root.foreground
              placeholderText: "Search peers"
              text: root.searchQuery
              onTextChanged: {
                root.searchQuery = text
                root.peerIndex = 0
              }
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.closeSearch(true)
                  event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  root.focusSection = "peers"
                  root.cursorActive = true
                  root.closeSearch(false)
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.focusSection = "peers"
                  root.cursorActive = true
                  root.closeSearch(false)
                  event.accepted = true
                }
              }
            }

            Text {
              visible: root.visiblePeers.length === 0
              width: parent.width
              text: root.searchQuery !== "" ? "No peers match \"" + root.searchQuery + "\"." : "No peers found."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Column {
              id: peerColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.visiblePeers
                PeerRow {
                  required property var modelData
                  required property int index
                  width: peerColumn.width
                  peer: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  component StatusLabel: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    Layout.fillWidth: true
  }

  component StatusValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    Layout.fillWidth: true
  }

  component NetworkRow: CursorSurface {
    id: networkRow
    property var network: null
    property int rowIndex: 0
    readonly property bool pending: netbird.pendingNetworkId === (network ? network.id : "")

    hasCursor: root.cursorActive && root.focusSection === "networks" && root.networkIndex === rowIndex
    foreground: root.foreground
    implicitHeight: Math.max(networkContent.implicitHeight, networkSwitch.implicitHeight) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setNetworkCursor(networkRow.rowIndex)
      onClicked: netbird.toggleNetwork(networkRow.network)
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: networkRow.network && networkRow.network.domains.length > 0 ? "󰇗" : "󰩠"
        color: networkRow.network && networkRow.network.selected ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: networkContent
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          text: networkRow.network ? networkRow.network.id : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          visible: text !== ""
          text: Model.networkSubtitle(networkRow.network)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        id: networkSwitch
        Layout.alignment: Qt.AlignVCenter
        // The row owns the click, so the switch is display-only here.
        interactive: false
        checked: networkRow.network ? networkRow.network.selected : false
        busy: networkRow.pending
        foreground: root.foreground
        trackHeight: Math.max(18, Math.round(Style.spacing.controlHeight * 0.45))
      }
    }
  }

  component PeerRow: CursorSurface {
    id: peerRow
    property var peer: null
    property int rowIndex: 0
    readonly property bool expanded: root.isExpanded(peer)

    hasCursor: root.cursorActive && root.focusSection === "peers" && root.peerIndex === rowIndex
    foreground: root.foreground
    opacity: peer && peer.connected ? 1 : (peer && peer.connecting ? 0.8 : 0.55)
    implicitHeight: peerBody.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setPeerCursor(peerRow.rowIndex)
      onClicked: netbird.copyPeerIp(peerRow.peer)
    }

    Column {
      id: peerBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: root.connectionIcon(peerRow.peer)
          color: root.peerColor(peerRow.peer)
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
          id: peerContent
          Layout.fillWidth: true
          spacing: Style.space(1)
          Text {
            Layout.fillWidth: true
            text: peerRow.peer ? peerRow.peer.name : "Unknown"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: root.peerSubtitle(peerRow.peer)
            color: peerRow.peer && peerRow.peer.connecting ? root.pending : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        RowLayout {
          id: actionRow
          spacing: Style.space(2)
          Layout.alignment: Qt.AlignVCenter
          PanelActionButton {
            iconText: peerRow.expanded ? "󰅃" : "󰅀"
            tooltipText: peerRow.expanded ? "Hide details  (d)" : "Show details  (d)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.toggleDetails(peerRow.peer)
          }
          PanelActionButton {
            iconText: "󰆏"
            tooltipText: "Copy IP"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: peerRow.peer && peerRow.peer.ip !== ""
            onClicked: netbird.copyPeerIp(peerRow.peer)
          }
          PanelActionButton {
            visible: peerRow.peer && peerRow.peer.connected
            iconText: "󰆍"
            tooltipText: "SSH"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: netbird.ssh(peerRow.peer)
          }
          PanelActionButton {
            visible: peerRow.peer && peerRow.peer.connected
            iconText: "󰓅"
            tooltipText: "Ping"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: netbird.ping(peerRow.peer)
          }
        }
      }

      // Detail block: everything the status payload already knows about this
      // peer but the row has no room for. Answers "why is this relayed?".
      Column {
        visible: peerRow.expanded
        width: parent.width
        spacing: Style.space(4)

        PanelSeparator { foreground: root.foreground }

        DetailRow {
          label: "Connection"
          value: Model.connectionSummary(peerRow.peer)
        }
        DetailRow {
          label: "Endpoints"
          visible: peerRow.peer && peerRow.peer.endpointLocal !== ""
          value: peerRow.peer
            ? peerRow.peer.endpointLocal + "  \u2192  " + peerRow.peer.endpointRemote
            : ""
        }
        DetailRow {
          label: "Last handshake"
          visible: peerRow.peer && peerRow.peer.connected
          value: peerRow.peer ? Model.formatRelativeTime(peerRow.peer.lastHandshake, root.nowMs) : ""
        }
        DetailRow {
          label: "Transfer"
          visible: peerRow.peer && (peerRow.peer.received > 0 || peerRow.peer.sent > 0)
          value: peerRow.peer
            ? "\u2193 " + Model.formatBytes(peerRow.peer.received) + "   \u2191 " + Model.formatBytes(peerRow.peer.sent)
            : ""
        }
        DetailRow {
          label: "Routes"
          visible: peerRow.peer && peerRow.peer.networks.length > 0
          value: peerRow.peer ? peerRow.peer.networks.join(", ") : ""
        }
        DetailRow {
          label: "Quantum resistance"
          visible: peerRow.peer && peerRow.peer.quantumResistance
          value: "Enabled"
        }
        DetailRow {
          label: "Status"
          visible: peerRow.peer && !peerRow.peer.connected
          value: peerRow.peer
            ? peerRow.peer.status + (peerRow.peer.lastStatusUpdate !== ""
              ? " \u00b7 " + Model.formatRelativeTime(peerRow.peer.lastStatusUpdate, root.nowMs)
              : "")
            : ""
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          Button {
            text: "Copy name"
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: netbird.copyPeerName(peerRow.peer)
          }
          Button {
            visible: peerRow.peer && peerRow.peer.publicKey !== ""
            text: "Copy public key"
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: netbird.copy(peerRow.peer.publicKey)
          }
          Item { Layout.fillWidth: true }
        }
      }
    }
  }

  // Label/value pair used inside the expanded peer detail block.
  component DetailRow: RowLayout {
    id: detailRow
    property string label: ""
    property string value: ""

    width: parent ? parent.width : 0
    spacing: Style.space(10)
    visible: value !== ""

    Text {
      text: detailRow.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      Layout.alignment: Qt.AlignTop
    }
    Text {
      Layout.fillWidth: true
      text: detailRow.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      wrapMode: Text.WrapAnywhere
    }
  }
}
