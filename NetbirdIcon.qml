import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property real iconSize: Style.font.icon
  property color slashColor: Color.foreground
  property bool crossed: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Image {
    anchors.fill: parent
    source: "icons/netbird.svg"
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    opacity: root.crossed ? 0.38 : 1
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.18
    height: Math.max(2, parent.height * 0.13)
    radius: height / 2
    color: root.slashColor
    rotation: -45
  }
}
