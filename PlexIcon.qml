import QtQuick
import QtQuick.Shapes
import qs.Commons

// The Plex chevron, drawn natively so it takes the theme colour and stays
// crisp at bar size.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize * 0.72
  height: iconSize
  implicitWidth: width
  implicitHeight: height

  // Chevron geometry: arm thickness is just under half the width.
  readonly property real w: width
  readonly property real h: height
  readonly property real t: width * 0.46

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      startX: 0; startY: 0
      PathLine { x: root.t; y: 0 }
      PathLine { x: root.w; y: root.h / 2 }
      PathLine { x: root.t; y: root.h }
      PathLine { x: 0; y: root.h }
      PathLine { x: root.w - root.t; y: root.h / 2 }
      PathLine { x: 0; y: 0 }
    }
  }
}
