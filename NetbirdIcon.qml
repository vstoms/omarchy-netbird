import QtQuick
import QtQuick.Shapes
import qs.Commons

// The NetBird mark, drawn as vector paths rather than loaded from the brand
// SVG, so it can be painted in the bar's foreground colour like every other
// bar icon. Omarchy's own logo widget (plugins/panels/dropbox/DropboxIcon.qml)
// does the same thing for the same reason: bar icons follow the theme.
//
// `monochrome: false` restores the brand oranges, which is what the panel hero
// can afford to show even when the bar should not.
//
// Path data is the original artwork, unmodified, from icons/netbird.svg.
Item {
  id: root

  property real iconSize: Style.font.icon
  // Fill for monochrome mode. Callers pass the bar or panel foreground, or an
  // urgent tint when the connection is degraded.
  property color color: Color.foreground
  property bool monochrome: true
  property color slashColor: Color.foreground
  property bool crossed: false

  // The artwork's viewBox: "0.015 36.7 512 405.4". The origin offset matters —
  // the paths start at y≈36.7, so the canvas has to be shifted to bring them
  // back to (0,0) before scaling.
  readonly property real viewX: 0.015
  readonly property real viewY: 36.7
  readonly property real viewWidth: 512
  readonly property real viewHeight: 405.4

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Item {
    id: canvas
    width: root.viewWidth
    height: root.viewHeight
    anchors.centerIn: parent
    scale: Math.min(root.width / root.viewWidth, root.height / root.viewHeight)

    Shape {
      x: -root.viewX
      y: -root.viewY
      width: canvas.width
      height: canvas.height
      antialiasing: true
      // Analytic antialiasing, so the mark stays crisp when the viewBox-sized
      // canvas is scaled down to ~20px. A layer would instead rasterise at
      // 512×405 per instance and downsample it.
      preferredRendererType: Shape.CurveRenderer
      opacity: root.crossed ? 0.38 : 1

      Mark {
        brandColor: "#f68330"
        PathSvg { path: "m363.915 69.9c-61.8 5.7-92.5 41.3-104.1 59.3l-5.2 9.1c-.4.8-.6 1.3-.6 1.3l-.1-.1-174.8 302.6h218l214.9-372.2z" }
      }
      Mark {
        brandColor: "#f68330"
        PathSvg { path: "m297.115 442.1-297.1-315.2s336-90.2 368.7 191.4z" }
      }
      Mark {
        // The darker wedge only reads as a separate shape in colour mode; in
        // monochrome it merges into the mark, which is the intent.
        brandColor: "#f35e32"
        PathSvg { path: "m253.115 140.8-91.2 157.9 135.2 143.4 71.6-124c-11.3-96.9-58.5-149.7-115.6-177.3" }
      }
    }
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

  component Mark: ShapePath {
    property color brandColor: "#f68330"

    fillColor: root.monochrome ? root.color : brandColor
    strokeWidth: 0
    // SVG's default fill-rule is nonzero; Shape defaults to odd-even, which
    // would punch holes in the overlapping parts of the mark.
    fillRule: ShapePath.WindingFill
  }
}
