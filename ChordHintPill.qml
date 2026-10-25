import QtQuick
import qs.Commons
import qs.Ui
import "GuideModel.js" as GuideModel

BorderSurface {
  id: root

  property string combo: ""
  property string description: ""
  property string descriptionMode: "inline"
  property bool showChordBorder: true
  property int backgroundOpacity: 84
  property real sizeFactor: 1
  property real maxWidth: 2000

  readonly property real keyFontSize: Math.max(26, Style.font.displayLarge * 0.95) * sizeFactor
  readonly property real horizontalPadding: Style.space(16) * sizeFactor
  readonly property real verticalPadding: Style.space(12) * sizeFactor
  readonly property real contentSpacing: Style.space(10) * sizeFactor
  readonly property real descriptionFontSize: keyFontSize * 0.8
  readonly property bool hasDescription: descriptionMode !== "hidden" && description !== ""
  readonly property var rowKeys: GuideModel.comboParts(combo)
  readonly property real preferredContentWidth: descriptionMode === "inline" && hasDescription
    ? keyRow.implicitWidth + contentSpacing + descriptionLabel.implicitWidth
    : descriptionMode === "below" && hasDescription
      ? Math.max(keyRow.implicitWidth, belowDescription.implicitWidth)
      : keyRow.implicitWidth

  implicitWidth: Math.min(maxWidth, preferredContentWidth + horizontalPadding)
  implicitHeight: contentColumn.implicitHeight + verticalPadding
  width: implicitWidth
  height: implicitHeight
  clip: true
  color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, backgroundOpacity / 100)
  borderSpec: showChordBorder ? Border.flat(Color.accent, Math.max(2, Style.space(2))) : Border.none()
  radius: Style.space(8) * sizeFactor

  Column {
    id: contentColumn
    x: root.horizontalPadding / 2
    y: (root.height - implicitHeight) / 2
    width: Math.max(0, root.width - root.horizontalPadding)
    spacing: root.descriptionMode === "below" && root.hasDescription
      ? Style.space(4) * root.sizeFactor : 0

    Row {
      id: contentRow
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: root.contentSpacing
      clip: true

      Row {
        id: keyRow
        spacing: Style.space(8) * root.sizeFactor

        Repeater {
          model: root.rowKeys

          delegate: Row {
            required property string modelData
            required property int index
            spacing: Style.space(6) * root.sizeFactor

            Text {
              visible: index > 0
              text: "+"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: root.keyFontSize * 0.8
              font.weight: Font.Medium
              anchors.verticalCenter: parent.verticalCenter
            }

            BorderSurface {
              width: keyLabel.implicitWidth + Style.space(20) * root.sizeFactor
              height: keyLabel.implicitHeight + Style.space(10) * root.sizeFactor
              implicitWidth: width
              implicitHeight: height
              color: "transparent"
              borderSpec: Border.flat(
                Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.9),
                Math.max(2, Style.space(2)))
              radius: Math.max(Style.cornerRadius, Style.space(8) * root.sizeFactor)

              Text {
                id: keyLabel
                anchors.centerIn: parent
                text: String(modelData || "").toUpperCase()
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: root.keyFontSize
                font.weight: Font.Medium
                font.letterSpacing: Style.space(1) * root.sizeFactor
              }
            }
          }
        }
      }

      Text {
        id: descriptionLabel
        visible: root.descriptionMode === "inline" && root.hasDescription
        width: Math.min(implicitWidth, Math.max(0,
          contentColumn.width - keyRow.implicitWidth - root.contentSpacing))
        text: root.description
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: root.descriptionFontSize
        font.weight: Font.Medium
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      id: belowDescription
      visible: root.descriptionMode === "below" && root.hasDescription
      width: parent.width
      text: root.description
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: root.descriptionFontSize
      font.weight: Font.Medium
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }
}
