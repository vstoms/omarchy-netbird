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
  property bool cursorActive: false
  property bool headerFocused: true

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showDisconnected: settingBool("showDisconnectedPeers", true)
  readonly property string adminUrl: String(setting("adminConsoleUrl", "https://app.netbird.io/"))
  readonly property var visiblePeers: filteredPeers()
  readonly property bool headerHasCursor: cursorActive && headerFocused && netbird.installed

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
    if (showDisconnected) return netbird.peers
    var result = []
    for (var i = 0; i < netbird.peers.length; i++)
      if (netbird.peers[i].connected) result.push(netbird.peers[i])
    return result
  }

  function selectedPeer() {
    if (visiblePeers.length === 0) return null
    return visiblePeers[Math.max(0, Math.min(peerIndex, visiblePeers.length - 1))]
  }

  function moveCursor(delta) {
    cursorActive = true
    if (headerFocused) {
      if (delta > 0 && visiblePeers.length > 0) headerFocused = false
      return
    }
    if (delta < 0 && peerIndex === 0) headerFocused = true
    else peerIndex = Math.max(0, Math.min(visiblePeers.length - 1, peerIndex + delta))
    scrollSelectedIntoView()
  }

  function activateCursor() {
    if (headerFocused) netbird.toggleNetbird()
    else netbird.copyPeerIp(selectedPeer())
  }

  function setPeerCursor(index) {
    cursorActive = true
    headerFocused = false
    peerIndex = index
  }

  function scrollSelectedIntoView() {
    if (!peerColumn || peerIndex < 0 || peerIndex >= peerColumn.children.length) return
    var item = peerColumn.children[peerIndex]
    Qt.callLater(function() {
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      if (top < panelFlick.contentY) panelFlick.contentY = top
      else if (bottom > panelFlick.contentY + panelFlick.height)
        panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height, bottom - panelFlick.height)
    })
  }

  function openAdmin() {
    if (adminUrl !== "") Quickshell.execDetached(["omarchy", "launch", "browser", adminUrl])
  }

  function connectionIcon(peer) {
    if (!peer || !peer.connected) return "󰲛"
    if (String(peer.connectionType).toLowerCase() === "p2p") return "󰌷"
    if (String(peer.connectionType).toLowerCase() === "relayed") return "󰅟"
    return "󰲝"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    headerFocused = true
    peerIndex = 0
    panelFlick.contentY = 0
    netbird.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onVisiblePeersChanged: peerIndex = Math.max(0, Math.min(peerIndex, visiblePeers.length - 1))

  Service {
    id: netbird
    settings: root.settings
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
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        NetbirdIcon {
          anchors.centerIn: parent
          iconSize: Style.font.icon
          slashColor: root.foreground
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
                : netbird.statusText
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: netbird.active ? 1 : 0.5
              iconComponent: Component {
                NetbirdIcon {
                  iconSize: Style.font.display
                  slashColor: root.foreground
                  crossed: !netbird.active
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: netbird.installed
                  checked: netbird.active
                  busy: netbird.busy
                  hasCursor: root.headerHasCursor
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) { root.cursorActive = true; root.headerFocused = true } }
                  onToggled: netbird.toggleNetbird()
                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: netbird.active ? "Disconnect NetBird" : "Connect NetBird"
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

          CursorSurface {
            visible: !netbird.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground
            Text {
              id: missingText
              anchors.fill: parent
              anchors.margins: Style.space(12)
              text: "NetBird CLI is not installed or not on PATH."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
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
          }

          PanelSeparator {
            visible: netbird.installed && netbird.active
            foreground: root.foreground
          }

          Column {
            visible: netbird.installed && netbird.active
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(peersHeader.implicitHeight, adminButton.implicitHeight)
              PanelSectionHeader {
                id: peersHeader
                text: "PEERS"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              PanelActionButton {
                id: adminButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰖟"
                tooltipText: "Open NetBird admin console"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.openAdmin()
              }
            }

            Text {
              visible: root.visiblePeers.length === 0
              width: parent.width
              text: "No peers found."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
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

  component PeerRow: CursorSurface {
    id: peerRow
    property var peer: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && !root.headerFocused && root.peerIndex === rowIndex
    foreground: root.foreground
    opacity: peer && peer.connected ? 1 : 0.55
    implicitHeight: Math.max(peerContent.implicitHeight, actionRow.implicitHeight) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setPeerCursor(peerRow.rowIndex)
      onClicked: netbird.copyPeerIp(peerRow.peer)
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: root.connectionIcon(peerRow.peer)
        color: peerRow.peer && peerRow.peer.connected ? root.foreground : root.dim
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
          text: {
            if (!peerRow.peer) return ""
            var parts = [peerRow.peer.ip]
            if (peerRow.peer.connectionType && peerRow.peer.connectionType !== "-") parts.push(peerRow.peer.connectionType)
            var latency = Model.formatLatency(peerRow.peer.latencyMs)
            if (latency !== "") parts.push(latency)
            return parts.join(" · ")
          }
          color: root.dim
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
  }
}
