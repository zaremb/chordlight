import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "GuideModel.js" as GuideModel

Panel {
  id: root

  moduleName: "io.github.zaremb.chordlight"
  ipcTarget: "io.github.zaremb.chordlight"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property var preview: ({})
  property bool confirmDisable: false
  property bool showDiff: false
  readonly property string previewPosition: service ? String(service.displayPosition || "bottom-center") : "bottom-center"
  readonly property string previewDescriptionMode: service ? String(service.descriptionMode || "inline") : "inline"
  readonly property int previewSizePercent: Math.round(GuideModel.pillSizeFactor(service ? service.pillSize : "medium") * 100)
  readonly property int previewStackSpacing: GuideModel.stackGapUnits(service ? service.stackGap : "tight")
  readonly property real previewPillHeight: previewPillHeightSample.implicitHeight
  readonly property int previewHistoryCount: service ? Number(service.historyCount) : 2
  readonly property string previewStackDirection: service ? String(service.stackDirection || "normal") : "normal"
  readonly property int previewHistoryDurationSeconds: service ? Number(service.historyDurationSeconds) : 3
  readonly property string previewHistoryTransparency: service ? String(service.historyTransparency || "balanced") : "balanced"

  readonly property bool onboarding: !service || service.integrationState !== "enabled"
  readonly property string displayedHash: preview && typeof preview.currentHash === "string"
    ? preview.currentHash : ""
  readonly property string displayedDiff: preview && typeof preview.proposedDiff === "string"
    ? preview.proposedDiff : ""
  readonly property string bridgeSourceUrl: "https://github.com/zaremb/chordlight/blob/main/bridge.lua"
  readonly property bool enableReady: !!root.service && root.preview
    && root.preview.safeToPatch === true && root.displayedHash !== ""
    && !root.service.integrationMutationRunning

  function htmlEscape(value) {
    return String(value || "").replace(/&/g, "&amp;")
      .replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/ /g, "&nbsp;")
  }

  function diffAddedColor() {
    var luminance = Color.menu.background.r * 0.2126
      + Color.menu.background.g * 0.7152 + Color.menu.background.b * 0.0722
    return luminance < 0.5 ? "#8bd49c" : "#236b3e"
  }

  function diffRemovedColor() {
    var luminance = Color.menu.background.r * 0.2126
      + Color.menu.background.g * 0.7152 + Color.menu.background.b * 0.0722
    return luminance < 0.5 ? "#f08a8a" : "#a52d3c"
  }

  function safetyColor() {
    var luminance = Color.menu.background.r * 0.2126
      + Color.menu.background.g * 0.7152 + Color.menu.background.b * 0.0722
    if (root.preview && root.preview.safeToPatch === true)
      return luminance < 0.5 ? "#8bd49c" : "#236b3e"
    return luminance < 0.5 ? "#f0c674" : "#8a5a00"
  }

  function symlinkPathsMatch() {
    var logical = root.preview ? root.preview.logicalPath : ""
    var resolved = root.preview ? root.preview.resolvedPath : ""
    return logical !== "" && resolved !== "" && logical === resolved
  }

  function symlinkCheckSummary() {
    if (root.symlinkPathsMatch()) return "OK — logical and resolved paths match"
    if (root.preview && root.preview.logicalPath && root.preview.resolvedPath)
      return "Review required — paths differ"
    return "Review required — paths unavailable"
  }

  function safetySummary() {
    if (root.preview && root.preview.safeToPatch === true) return "OK — safe to enable"
    var reason = root.pathValue("reasonCode")
    return reason === "—" ? "Review required" : "Review required — " + reason
  }

  function gitCheckSummary() {
    if (!root.preview || root.preview.gitManaged !== true) return "Not tracked"
    var rootPath = root.pathValue("gitRoot")
    return "Tracked — " + rootPath + (root.preview.gitDirty === true ? " (working tree changed)" : " (clean)")
  }

  function diffMarkup() {
    var lines = displayedDiff.split("\n")
    var output = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var color = line.indexOf("+++") === 0 || line.indexOf("---") === 0
        ? String(Color.menu.text)
        : line.indexOf("+") === 0 ? diffAddedColor()
        : line.indexOf("-") === 0 ? diffRemovedColor() : String(Color.menu.text)
      output.push("<font color=\"" + color + "\">" + htmlEscape(line) + "</font>")
    }
    return output.join("<br/>")
  }

  function syncService() {
    service = bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor(moduleName) : null
    refreshPreview()
  }

  function refreshPreview() {
    preview = service && service.integrationDetails ? service.integrationDetails : ({})
  }

  function open() {
    if (service && service.integrationState !== "enabled") service.inspectIntegration()
    showDiff = false
    refreshPreview()
    controller.show()
  }

  function close() { controller.hide() }
  function toggle() { if (opened) close(); else open() }
  function closeForPopoutSwitch() { close() }

  function pathValue(name) {
    var value = preview ? preview[name] : ""
    return value === null || value === undefined || value === "" ? "—" : String(value)
  }

  function statusText() {
    if (!service) return "Service unavailable; browse-only mode"
    if (service.integrationMutationRunning || service.integrationState === "enabling") return "Patching configuration…"
    if (service.integrationInspectRunning) return "Verifying integration status…"
    if (service.integrationState === "error") return "Integration error: " + pathValue("reasonCode")
    if (service.integrationState === "disconnected") return "Visual guide is disconnected from the current configuration"
    if (service.integrationState === "enabled") return "Visual guide enabled"
    return "Ready for review"
  }

  function enableLabel() {
    if (!service) return "Service unavailable"
    if (service.integrationMutationRunning) return "Working…"
    return "Enable visual keybinding guide"
  }

  function enableIntegration() {
    if (root.enableReady) root.service.enableIntegration(root.displayedHash)
  }

  function openBridgeSource() {
    Qt.openUrlExternally(root.bridgeSourceUrl)
  }

  function previewScale() {
    return previewSizePercent / 100
  }
  readonly property int previewScreenGutter: Style.space(32)

  function previewPillX(position, canvasWidth, pillWidth, scale) {
    var visualWidth = pillWidth * scale
    var visualX = position.endsWith("-left") ? 0
      : position.endsWith("-right") ? canvasWidth - visualWidth
      : (canvasWidth - visualWidth) / 2
    return visualX - (1 - scale) * pillWidth / 2
  }
  function previewHistoryOpacity(level) {
    return GuideModel.historyOpacity(previewHistoryTransparency, level)
  }
  function updateDisplaySetting(name, value) {
    return root.service && typeof root.service.setDisplaySetting === "function"
      ? root.service.setDisplaySetting(name, value) : false
  }

  function settingsStatusLabel() {
    if (!root.service) return "SETTINGS UNAVAILABLE"
    if (root.service.settingsStatus === "saved") return "SETTINGS SAVED"
    if (root.service.settingsStatus === "saving") return "SAVING SETTINGS"
    if (root.service.settingsStatus === "loading") return "LOADING SETTINGS"
    return "SETTINGS ERROR"
  }

  function previewRows() {
    var rows = []
    var historyRows = []
    if (previewHistoryCount > 1)
      historyRows.push({ combo: "SUPER + LEFT", description: "Left", scale: GuideModel.historyScale(1), opacity: previewHistoryOpacity(1) })
    if (previewHistoryCount > 0)
      historyRows.push({ combo: "SUPER + RIGHT", description: "Right", scale: GuideModel.historyScale(0), opacity: previewHistoryOpacity(0) })
    var currentRow = { combo: "SUPER + K", description: "Launch", scale: 1.0, opacity: 1.0 }
    var currentAtTop = (previewPosition.indexOf("top-") === 0)
      !== (previewStackDirection === "inverted")
    if (currentAtTop) {
      rows.push(currentRow)
      for (var historyIndex = historyRows.length - 1; historyIndex >= 0; historyIndex--)
        rows.push(historyRows[historyIndex])
    } else {
      rows = historyRows
      rows.push(currentRow)
    }

    var scales = []
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
      scales.push(Number(rows[rowIndex].scale))
    var offsets = GuideModel.stackRowOffsets(
      scales,
      previewPillHeight,
      Style.space(previewStackSpacing),
      previewPosition.indexOf("top-") === 0)
    for (var offsetIndex = 0; offsetIndex < rows.length; offsetIndex++)
      rows[offsetIndex].targetY = offsets[offsetIndex]
    return rows
  }

  onBarChanged: syncService()
  Component.onCompleted: syncService()

  Timer {
    interval: 250
    repeat: true
    running: root.service === null
    onTriggered: root.syncService()
  }

  ChordHintPill {
    id: previewPillHeightSample
    visible: false
    combo: "SUPER + SHIFT + K"
    description: "Preview shortcut"
    descriptionMode: root.previewDescriptionMode
    showChordBorder: root.service ? root.service.showChordBorder : true
    backgroundOpacity: root.service ? root.service.backgroundOpacity : 84
    sizeFactor: root.previewScale()
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onIntegrationDetailsChanged() { root.refreshPreview() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.hostWidget || root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar || (root.hostWidget ? root.hostWidget.bar : null)
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(1080))
    contentHeight: panel.fittedContentHeight(
      root.onboarding
        ? onboardingColumn.implicitHeight + Style.spacing.popupPadding * 2
        : Style.space(760),
      Style.space(800))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onReturnRequested: root.enableIntegration()
    }

    Flickable {
      id: onboardingScroll
      visible: root.onboarding
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      contentWidth: width
      contentHeight: onboardingColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: onboardingColumn
        width: onboardingScroll.width
        spacing: Style.space(12)

        Column {
          width: parent.width
          spacing: Style.space(3)

          Text {
            width: parent.width
            text: "SET UP CHORDLIGHT"
            color: Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            width: parent.width
            text: "A little light for every shortcut."
            color: Color.foreground
            opacity: 0.68
            font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width
            visible: !root.service || root.service.integrationMutationRunning
              || root.service.integrationInspectRunning
              || root.service.integrationState === "error"
              || root.service.integrationState === "disconnected"
            text: root.statusText()
            color: root.service && root.service.integrationState === "error" ? Color.urgent : Color.foreground
            opacity: 0.78
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

          Column {
            visible: root.onboarding
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { width: parent.width }

            Text {
              width: parent.width
              text: "CONFIGURATION REVIEW"
              color: Color.foreground
              opacity: 0.82
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              width: parent.width
              text: "Chordlight checks the Hyprland file before it changes anything."
              color: Color.foreground
              opacity: 0.78
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            BorderSurface {
              width: parent.width
              implicitHeight: detailsColumn.implicitHeight + Style.space(16)
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
              borderSpec: Border.flat(Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12), 1)
              radius: Style.cornerRadius

              Column {
                id: detailsColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                spacing: Style.space(7)

                Text { width: parent.width; text: "Safety"; color: Color.foreground; opacity: 0.68; font.pixelSize: Style.font.caption; font.bold: true }
                Text { width: parent.width; text: root.safetySummary(); color: root.safetyColor(); font.pixelSize: Style.font.body; font.bold: true; wrapMode: Text.WordWrap }
                Text {
                  width: parent.width
                  text: root.enableReady
                    ? "Chordlight can add its small local bridge without changing your existing bindings."
                    : "Automatic setup needs review before Chordlight can change this file."
                  color: Color.foreground
                  opacity: 0.76
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Row {
                  width: parent.width
                  spacing: Style.space(16)

                  Column {
                    width: (parent.width - parent.spacing) / 2
                    spacing: Style.space(2)
                    Text { width: parent.width; text: "Symlink check"; color: Color.foreground; opacity: 0.62; font.pixelSize: Style.font.caption; font.bold: true }
                    Text { width: parent.width; text: root.symlinkCheckSummary(); color: root.symlinkPathsMatch() ? Color.foreground : root.safetyColor(); opacity: 0.86; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                  }

                  Column {
                    width: (parent.width - parent.spacing) / 2
                    spacing: Style.space(2)
                    Text { width: parent.width; text: "Git check"; color: Color.foreground; opacity: 0.62; font.pixelSize: Style.font.caption; font.bold: true }
                    Text { width: parent.width; text: root.gitCheckSummary(); color: Color.foreground; opacity: 0.86; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle }
                  }
                }

                Column {
                  visible: !root.symlinkPathsMatch()
                  width: parent.width
                  spacing: Style.space(2)
                  Text { width: parent.width; text: "Logical path: " + root.pathValue("logicalPath"); color: Color.foreground; opacity: 0.78; elide: Text.ElideMiddle; font.pixelSize: Style.font.caption }
                  Text { width: parent.width; text: "Resolved path: " + root.pathValue("resolvedPath"); color: Color.foreground; opacity: 0.78; elide: Text.ElideMiddle; font.pixelSize: Style.font.caption }
                }
              }
            }

            Text {
              width: parent.width
              visible: !!root.service && root.preview && root.preview.safeToPatch !== true
              text: "Automatic patching is unavailable for this path. Review the reason above, then use Copy manual snippet to add the bridge yourself."
              color: root.safetyColor()
              opacity: 0.9
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            PanelSeparator {
              width: parent.width
              visible: root.displayedDiff !== ""
            }

            Text {
              width: parent.width
              visible: root.displayedDiff !== ""
              text: "WHAT CHORDLIGHT CHANGES"
              color: Color.foreground
              opacity: 0.82
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              width: parent.width
              visible: root.displayedDiff !== ""
              text: "One small, local bridge is added to Hyprland so the visual guide can see registered keyboard shortcuts."
              color: Color.foreground
              opacity: 0.78
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              visible: root.displayedDiff !== ""
              spacing: Style.space(14)

              Text {
                text: root.showDiff ? "Hide exact change" : "Review exact change"
                color: Color.accent
                opacity: 0.86
                font.pixelSize: Style.font.caption
                font.underline: diffToggleMouse.containsMouse
                MouseArea {
                  id: diffToggleMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showDiff = !root.showDiff
                }
              }

              Text {
                text: "View bridge source"
                color: Color.accent
                opacity: 0.86
                font.pixelSize: Style.font.caption
                font.underline: bridgeSourceMouse.containsMouse
                MouseArea {
                  id: bridgeSourceMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openBridgeSource()
                }
              }
            }

            BorderSurface {
              width: parent.width
              height: Style.space(170)
              visible: root.displayedDiff !== "" && root.showDiff
              color: Qt.rgba(0, 0, 0, 0.18)
              borderSpec: Border.flat(Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12), 1)
              radius: Style.cornerRadius

              Flickable {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                contentWidth: Math.max(width, diffText.paintedWidth)
                contentHeight: Math.max(height, diffText.paintedHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                  id: diffText
                  width: Math.max(parent.width, paintedWidth)
                  text: root.diffMarkup()
                  textFormat: TextEdit.RichText
                  readOnly: true
                  selectByMouse: true
                  color: Color.foreground
                  font.family: "monospace"
                  font.pixelSize: Style.font.caption
                  wrapMode: TextEdit.NoWrap
                }
              }
            }

            Button {
              width: parent.width
              text: root.enableLabel()
              selected: root.enableReady
              focusable: true
              enabled: root.enableReady
              onClicked: root.enableIntegration()
            }

            Text {
              width: parent.width
              visible: !!root.service && root.service.integrationState === "error"
              text: "Reason: " + root.pathValue("reasonCode") + "\nReview the configuration, then recheck before trying again."
              color: Color.urgent
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              visible: !!root.service && root.preview && root.preview.safeToPatch !== true
              spacing: Style.space(8)
              Button {
                width: (parent.width - Style.space(8)) / 2
                text: "Recheck"
                enabled: !!root.service
                onClicked: if (root.service) { root.service.inspectIntegration(); root.refreshPreview() }
              }
              Button {
                width: (parent.width - Style.space(8)) / 2
                text: "Copy manual snippet"
                enabled: !!root.service && root.service.manualSnippet !== ""
                onClicked: Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(root.service.manualSnippet) + " | wl-copy"])
              }
            }
          }
      }
    }

    Column {
      id: enabledLayout
      visible: !root.onboarding
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      spacing: Style.space(12)

      Row {
        id: enabledHeader
        width: parent.width
        spacing: Style.space(12)

        Row {
          width: parent.width - statusActions.implicitWidth - enabledHeader.spacing
          spacing: Style.space(10)

          ChordCompactPillMark {
            anchors.verticalCenter: parent.verticalCenter
            scale: 1.25
            transformOrigin: Item.Center
            iconColor: Color.accent
          }

          Column {
            width: parent.width - Style.space(42)
            spacing: Style.space(2)
            Text {
              width: parent.width
              text: "CHORDLIGHT"
              color: Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Preview and adjust shortcut hints."
              color: Color.foreground
              opacity: 0.72
              font.pixelSize: Style.font.caption
            }
          }
        }

        Row {
          id: statusActions
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Text {
            id: activeStatus
            anchors.verticalCenter: parent.verticalCenter
            text: "●  ACTIVE"
            color: Color.accent
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.settingsStatusLabel()
            color: root.service && root.service.settingsStatus === "error" ? Color.urgent : Color.foreground
            opacity: root.service && root.service.settingsStatus === "saved" ? 0.58 : 0.9
            font.pixelSize: Style.font.caption * 0.85
            font.bold: true
          }

          Button {
            text: root.confirmDisable ? "Confirm disable" : "Disable guide"
            selected: root.confirmDisable
            onClicked: {
              if (!root.confirmDisable) root.confirmDisable = true
              else root.service.disableIntegration(root.displayedHash)
            }
          }
          Button {
            visible: root.confirmDisable
            text: "Cancel"
            onClicked: root.confirmDisable = false
          }
        }
      }

      Item {
        id: editorBody
        width: parent.width
        height: Math.max(0, parent.height - enabledHeader.implicitHeight
          - enabledLayout.spacing)
        readonly property bool wideLayout: width >= Style.space(760)
        readonly property real columnGap: Style.space(22)

        Item {
          id: previewPane
          x: 0
          y: 0
          width: editorBody.wideLayout
            ? (editorBody.width - editorBody.columnGap) * 0.48 : editorBody.width
          height: editorBody.wideLayout
            ? editorBody.height
            : Math.min(editorBody.height, width * 10 / 16
              + previewHeading.implicitHeight + previewFooter.implicitHeight
              + previewPaneContent.spacing * 4)

          Column {
            id: previewPaneContent
            anchors.fill: parent
            spacing: Style.space(10)

            Column {
              id: previewHeading
              width: parent.width
              spacing: Style.space(2)
              Text {
                text: "PREVIEW"
                color: Color.foreground
                opacity: 0.84
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                text: "Updates as you change the settings"
                color: Color.foreground
                opacity: 0.62
                font.pixelSize: Style.font.caption
              }
            }

            Item {
              width: parent.width
              height: Math.max(0, (previewPaneContent.height - previewHeading.implicitHeight
                - previewCanvasCard.height - previewFooter.implicitHeight
                - previewPaneContent.spacing * 4) / 2)
            }

            BorderSurface {
              id: previewCanvasCard
              width: parent.width
              height: width * 10 / 16
              color: Qt.darker(Color.background, 1.4)
              borderSpec: Border.flat(Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12), 1)
              radius: Style.cornerRadius

              Item {
                id: previewCanvas
                anchors.fill: parent
                anchors.margins: Style.space(7)
                clip: true

                Column {
                  id: codeBackdrop
                  anchors.fill: parent
                  anchors.margins: Style.space(14)
                  spacing: Style.space(5)
                  z: 0

                  Row {
                    width: parent.width
                    spacing: Style.space(8)
                    Text {
                      text: "~/hypr/keybinds.conf"
                      color: Color.foreground
                      opacity: 0.62
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption
                    }
                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(6)
                      height: width
                      radius: width / 2
                      color: Color.accent
                      opacity: 0.7
                    }
                    Text {
                      text: "HYPRLAND CONFIG"
                      color: Color.foreground
                      opacity: 0.42
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption * 0.8
                    }
                  }

                  Rectangle {
                    width: parent.width
                    height: 1
                    color: Color.foreground
                    opacity: 0.12
                  }

                  Repeater {
                    model: [
                      { number: "12", code: '<font color="#7f849c"># Chordlight capture profile</font>' },
                      { number: "13", code: '<font color="#89ddff">$mod</font> <font color="#7f849c">=</font> <font color="#e0af68">SUPER</font>' },
                      { number: "14", code: '<font color="#c0caf5">bind</font> = <font color="#89ddff">$mod</font>, <font color="#bb9af7">LEFT</font>, <font color="#c0caf5">workspace</font>, <font color="#e0af68">-1</font>' },
                      { number: "15", code: '<font color="#c0caf5">bind</font> = <font color="#89ddff">$mod</font>, <font color="#bb9af7">RIGHT</font>, <font color="#c0caf5">workspace</font>, <font color="#e0af68">+1</font>' },
                      { number: "16", code: '<font color="#c0caf5">bind</font> = <font color="#89ddff">$mod</font>, <font color="#bb9af7">K</font>, <font color="#c0caf5">exec</font>, <font color="#9ece6a">launcher</font>' },
                      { number: "17", code: '<font color="#c0caf5">bind</font> = <font color="#89ddff">$mod</font>, <font color="#bb9af7">S</font>, <font color="#c0caf5">exec</font>, <font color="#9ece6a">screen-capture</font>' },
                      { number: "18", code: '<font color="#c0caf5">exec-once</font> = <font color="#9ece6a">~/.local/bin/session-ready</font>' },
                      { number: "19", code: '<font color="#c0caf5">monitor</font> = <font color="#e0af68">DP-1</font>, <font color="#e0af68">2560x1600@165</font>, <font color="#e0af68">0x0</font>, <font color="#e0af68">1</font>' },
                      { number: "20", code: '<font color="#c0caf5">general</font> { <font color="#c0caf5">gaps_in</font> = <font color="#e0af68">4</font> }' },
                      { number: "21", code: '<font color="#c0caf5">decoration</font> { <font color="#c0caf5">rounding</font> = <font color="#e0af68">9</font> }' },
                      { number: "22", code: '<font color="#bb9af7">$</font> <font color="#9ece6a">echo</font> <font color="#e0af68">"history fades; shortcuts stay"</font>' },
                      { number: "23", code: '<font color="#c0caf5">bind</font> = <font color="#89ddff">$mod</font>, <font color="#bb9af7">Q</font>, <font color="#c0caf5">killactive</font>' },
                      { number: "24", code: '<font color="#c0caf5">input</font> { <font color="#c0caf5">kb_layout</font> = <font color="#e0af68">us</font> }' },
                      { number: "25", code: '<font color="#c0caf5">animations</font> { <font color="#c0caf5">enabled</font> = <font color="#9ece6a">yes</font> }' },
                      { number: "26", code: '<font color="#c0caf5">misc</font> { <font color="#c0caf5">disable_hyprland_logo</font> = <font color="#9ece6a">true</font> }' },
                      { number: "27", code: '<font color="#7f849c"># Keep the useful things close</font>' }
                    ]

                    delegate: Row {
                      required property var modelData
                      width: codeBackdrop.width
                      spacing: Style.space(10)

                      Text {
                        width: Style.space(20)
                        text: String(modelData.number)
                        color: Color.foreground
                        opacity: 0.28
                        horizontalAlignment: Text.AlignRight
                        font.family: "monospace"
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        width: parent.width - Style.space(30)
                        text: String(modelData.code)
                        color: Color.foreground
                        opacity: 0.78
                        font.family: "monospace"
                        font.pixelSize: Style.font.caption
                        textFormat: Text.RichText
                        elide: Text.ElideRight
                      }
                    }
                  }
                }

                Item {
                  id: previewStack
                  readonly property var rows: root.previewRows()
                  width: Math.max(0, previewCanvas.width - root.previewScreenGutter * 2)
                  height: rows.length * root.previewPillHeight
                    + Math.max(0, rows.length - 1) * Style.space(root.previewStackSpacing)
                  x: root.previewPosition.endsWith("-left") ? root.previewScreenGutter
                    : root.previewPosition.endsWith("-right")
                      ? previewCanvas.width - width - root.previewScreenGutter
                      : (previewCanvas.width - width) / 2
                  y: root.previewPosition.indexOf("top-") === 0
                    ? root.previewScreenGutter : previewCanvas.height - height - root.previewScreenGutter
                  z: 1

                  Repeater {
                    id: previewRepeater
                    model: previewStack.rows

                    delegate: Item {
                      id: previewRow
                      required property var modelData
                      required property int index
                      readonly property real rowScale: Number(modelData.scale)

                      width: previewStack.width
                      height: previewPill.implicitHeight
                      y: Number(modelData.targetY || 0)

                      ChordHintPill {
                        id: previewPill
                        combo: String(previewRow.modelData.combo || "")
                        description: String(previewRow.modelData.description || "")
                        descriptionMode: root.previewDescriptionMode
                        showChordBorder: root.service ? root.service.showChordBorder : true
                        backgroundOpacity: root.service ? root.service.backgroundOpacity : 84
                        sizeFactor: root.previewScale()
                        maxWidth: previewRow.width
                        width: Math.max(0, Math.min(implicitWidth, maxWidth))
                        height: implicitHeight
                        x: root.previewPillX(root.previewPosition, previewRow.width, width, previewRow.rowScale)
                        opacity: Number(previewRow.modelData.opacity)
                        scale: previewRow.rowScale
                      }
                    }
                  }
                }
              }
            }

            Row {
              id: previewFooter
              width: parent.width
              spacing: Style.space(7)

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(5)
                height: width
                radius: width / 2
                color: Color.accent
                opacity: 0.65
              }

              Text {
                id: previewRatioLabel
                text: "16:10  /  DESKTOP PREVIEW"
                color: Color.foreground
                opacity: 0.48
                font.family: "monospace"
                font.pixelSize: Style.font.caption * 0.8
              }

              Item {
                width: Math.max(0, parent.width - Style.space(5)
                  - previewRatioLabel.implicitWidth - previewScaleNote.implicitWidth
                  - parent.spacing * 3)
                height: 1
              }

              Text {
                id: previewScaleNote
                text: "PILLS AT REAL SCALE"
                color: Color.accent
                opacity: 0.56
                font.family: "monospace"
                font.pixelSize: Style.font.caption * 0.8
              }
            }

            Item {
              width: parent.width
              height: Math.max(0, (previewPaneContent.height - previewHeading.implicitHeight
                - previewCanvasCard.height - previewFooter.implicitHeight
                - previewPaneContent.spacing * 4) / 2)
            }
          }
        }

        Flickable {
          id: settingsScroll
          x: editorBody.wideLayout ? previewPane.width + editorBody.columnGap : 0
          y: editorBody.wideLayout ? 0 : previewPane.height + editorBody.columnGap
          width: editorBody.wideLayout
            ? editorBody.width - previewPane.width - editorBody.columnGap : editorBody.width
          height: editorBody.wideLayout
            ? editorBody.height : Math.max(0, editorBody.height - y)
          contentWidth: width
          contentHeight: settingsContent.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: settingsContent
            width: settingsScroll.width
            spacing: Style.space(12)

            Text {
              width: parent.width
              text: "DISPLAY"
              color: Color.foreground
              opacity: 0.82
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Choose where and how shortcut hints appear."
              color: Color.foreground
              opacity: 0.68
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              visible: !!root.service && root.service.settingsStatus === "error"
              text: root.service ? String(root.service.settingsError || "Settings could not be loaded or saved.") : ""
              color: Color.urgent
              opacity: 0.9
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "POSITION"
              color: Color.foreground
              opacity: 0.70
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Grid {
              id: positionGrid
              width: parent.width
              columns: 3
              spacing: Style.space(4)
              Repeater {
                model: [
                  { label: "Top left", value: "top-left", icon: "↖" },
                  { label: "Top center", value: "top-center", icon: "↑" },
                  { label: "Top right", value: "top-right", icon: "↗" },
                  { label: "Bottom left", value: "bottom-left", icon: "↙" },
                  { label: "Bottom center", value: "bottom-center", icon: "↓" },
                  { label: "Bottom right", value: "bottom-right", icon: "↘" }
                ]
                Button {
                  required property var modelData
                  width: (positionGrid.width - Style.space(8)) / 3
                  text: modelData.icon + "  " + modelData.label
                  selected: root.previewPosition === modelData.value
                  onClicked: root.updateDisplaySetting("position", modelData.value)
                }
              }
            }

            PanelSeparator { width: parent.width; strength: 0.08 }

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: "DESCRIPTION"
                color: Color.foreground
                opacity: 0.70
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Grid {
                id: descriptionChoices
                width: parent.width
                columns: 3
                spacing: Style.space(4)
                Repeater {
                  model: ["Inline", "Below", "Hidden"]
                  Button {
                    required property string modelData
                    width: (descriptionChoices.width - Style.space(8)) / 3
                    text: modelData
                    selected: root.previewDescriptionMode === modelData.toLowerCase()
                    onClicked: root.updateDisplaySetting("descriptionMode", modelData.toLowerCase())
                  }
                }
              }
            }

            PanelSeparator { width: parent.width; strength: 0.08 }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "CHORD BORDER"
                color: Color.foreground
                opacity: 0.70
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Row {
                width: parent.width
                spacing: Style.space(4)
                Repeater {
                  model: ["Show", "Hide"]
                  Button {
                    required property string modelData
                    required property int index
                    width: (parent.width - Style.space(4)) / 2
                    text: modelData
                    selected: (root.service ? root.service.showChordBorder : true) === (index === 0)
                    onClicked: root.updateDisplaySetting("showChordBorder", index === 0)
                  }
                }
              }
            }

            PanelSeparator { width: parent.width; strength: 0.08 }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "BACKGROUND OPACITY  " + Math.round(backgroundOpacitySlider.liveValue) + "%"
                color: Color.foreground
                opacity: 0.70
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              PanelSlider {
                id: backgroundOpacitySlider
                bar: root.bar
                width: parent.width
                minimum: 0
                maximum: 100
                step: 1
                integer: true
                value: root.service ? root.service.backgroundOpacity : 84
                enabled: !!root.service
                onMoved: function(v) { root.updateDisplaySetting("backgroundOpacity", Math.round(v)) }
                onReleased: function(v) { root.updateDisplaySetting("backgroundOpacity", Math.round(v)) }
              }
            }

            PanelSeparator { width: parent.width; strength: 0.08 }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "PILL SIZE"
                color: Color.foreground
                opacity: 0.70
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Grid {
                id: sizeChoices
                width: parent.width
                columns: 3
                spacing: Style.space(4)
                Repeater {
                  model: [80, 100, 120]
                  Button {
                    required property int modelData
                    required property int index
                    width: (sizeChoices.width - Style.space(8)) / 3
                    text: ["Small", "Medium", "Large"][index]
                    selected: root.previewSizePercent === modelData
                    onClicked: root.updateDisplaySetting("pillSize", ["small", "medium", "large"][index])
                  }
                }
              }
            }

            PanelSeparator { width: parent.width; strength: 0.08 }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "STACK"
                color: Color.foreground
                opacity: 0.84
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                width: parent.width
                text: "Adjust the spacing and order of stacked hints."
                color: Color.foreground
                opacity: 0.68
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Column {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: "STACK GAP"
                  color: Color.foreground
                  opacity: 0.70
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Grid {
                  id: gapChoices
                  width: parent.width
                  columns: 3
                  spacing: Style.space(4)
                  Repeater {
                    model: [
                      { label: "Tight", value: "tight" },
                      { label: "Default", value: "default" },
                      { label: "Loose", value: "loose" }
                    ]
                    Button {
                      required property var modelData
                      width: (gapChoices.width - Style.space(8)) / 3
                      text: modelData.label
                      selected: root.service && root.service.stackGap === modelData.value
                      onClicked: root.updateDisplaySetting("stackGap", modelData.value)
                    }
                  }
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: "STACK DIRECTION"
                  color: Color.foreground
                  opacity: 0.70
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  width: parent.width
                  text: "Normal keeps the current chord at the screen edge. Inverted moves it inward, with history toward the edge."
                  color: Color.foreground
                  opacity: 0.68
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
                Grid {
                  id: stackDirectionChoices
                  width: parent.width
                  columns: 2
                  spacing: Style.space(4)
                  Repeater {
                    model: [
                      { label: "Normal", value: "normal" },
                      { label: "Inverted", value: "inverted" }
                    ]
                    Button {
                      required property var modelData
                      width: (stackDirectionChoices.width - Style.space(4)) / 2
                      text: modelData.label
                      selected: root.previewStackDirection === modelData.value
                      onClicked: root.updateDisplaySetting("stackDirection", modelData.value)
                    }
                  }
                }
              }
            }

            PanelSeparator { width: parent.width; strength: 0.08 }

            Text {
              width: parent.width
              text: "HISTORY"
              color: Color.foreground
              opacity: 0.84
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Choose how previous chords remain visible after release."
              color: Color.foreground
              opacity: 0.68
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: "HISTORY COUNT"
                color: Color.foreground
                opacity: 0.70
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Grid {
                id: historyCountChoices
                width: parent.width
                columns: 3
                spacing: Style.space(4)
                Repeater {
                  model: [0, 1, 2]
                  Button {
                    required property int modelData
                    width: (historyCountChoices.width - Style.space(8)) / 3
                    text: modelData === 0 ? "Off" : String(modelData)
                    selected: root.previewHistoryCount === modelData
                    onClicked: root.updateDisplaySetting("historyCount", modelData)
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: "HISTORY TRANSPARENCY"
                color: Color.foreground
                opacity: 0.70
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                width: parent.width
                text: "Older chords fade toward the background."
                color: Color.foreground
                opacity: 0.68
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Grid {
                id: transparencyChoices
                width: parent.width
                columns: 3
                spacing: Style.space(4)
                Repeater {
                  model: [
                    { label: "Faded", value: "faded" },
                    { label: "Balanced", value: "balanced" },
                    { label: "Clear", value: "clear" }
                  ]
                  Button {
                    required property var modelData
                    width: (transparencyChoices.width - Style.space(8)) / 3
                    text: modelData.label
                    selected: root.previewHistoryTransparency === modelData.value
                    onClicked: root.updateDisplaySetting("historyTransparency", modelData.value)
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: "HISTORY DURATION"
                color: Color.foreground
                opacity: 0.70
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                width: parent.width
                text: "How long a released chord stays in history."
                color: Color.foreground
                opacity: 0.68
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Grid {
                id: durationChoices
                width: parent.width
                columns: 5
                spacing: Style.space(4)
                Repeater {
                  model: [1, 2, 3, 5, 10]
                  Button {
                    required property int modelData
                    width: (durationChoices.width - Style.space(16)) / 5
                    text: modelData + " sec"
                    selected: root.previewHistoryDurationSeconds === modelData
                    onClicked: root.updateDisplaySetting("historyDurationSeconds", modelData)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
