import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "GuideModel.js" as GuideModel

Item {
  id: root

  property var service: null
  property bool delayedVisible: false
  property int focusRevision: 0
  property bool presentationReady: false

  readonly property bool eligible: service ? GuideModel.eligible({
    integrationState: service.integrationState,
    catalogState: service.catalogState,
    lockStateKnown: service.lockStateKnown,
    desktopLocked: service.desktopLocked,
    credentialPromptStateKnown: service.credentialPromptStateKnown,
    credentialPromptActive: service.credentialPromptActive,
    activeWindowFullscreen: service.activeWindowFullscreen,
    showInFullscreen: service.showInFullscreen
  }) : false
  readonly property int delayValue: service ? Number(service.guideDelayMs) : -1
  readonly property real pillSizeFactor: GuideModel.pillSizeFactor(service ? service.pillSize : "medium")
  readonly property int keyFontSize: Math.max(26, Style.font.displayLarge * 0.95) * pillSizeFactor
  readonly property int pillScreenGutter: Style.space(32)
  readonly property int maximumHintRows: Math.max(1, Math.min(2, Number(service ? service.historyCount : 2)) + 1)
  readonly property int hintRowSpacing: Style.space(GuideModel.stackGapUnits(service ? service.stackGap : "tight"))
  readonly property int hintFadeDurationMs: 180
  readonly property int hintMoveDurationMs: 180
  readonly property real hintPillHeight: pillHeightSample.implicitHeight
  readonly property real maximumHintStackHeight: maximumHintRows * hintPillHeight
    + (maximumHintRows - 1) * hintRowSpacing
  readonly property string displayPosition: service ? String(service.displayPosition || "bottom-center") : "bottom-center"
  readonly property string displayDescriptionMode: service ? String(service.descriptionMode || "inline") : "inline"
  readonly property string displayStackDirection: service ? String(service.stackDirection || "normal") : "normal"
  readonly property bool displayAtTop: displayPosition.indexOf("top-") === 0
  readonly property string currentMask: service && String(service.activeModifiers || "") !== ""
    ? String(service.activeModifiers)
    : service && String(service.activeGuideRoot || "") !== "" ? String(service.activeGuideRoot) : "SUPER"
  readonly property string currentGuideRoot: service && String(service.activeGuideRoot || "") !== ""
    ? String(service.activeGuideRoot) : "SUPER"
  readonly property bool showPrefixRow: service && service.guideVisible === true
    && String(service.activeGuideRoot || "") !== "" && eligible && delayedVisible
    && GuideModel.hasMatchingPrefix(service.catalog, currentMask, currentGuideRoot)
  readonly property var hintRows: GuideModel.hintRows(
    service ? service.catalog : null,
    service && Array.isArray(service.activeHintEntries) ? service.activeHintEntries : [],
    service && Array.isArray(service.recentHintEntries) ? service.recentHintEntries : [],
    currentMask,
    currentGuideRoot,
    showPrefixRow,
    {
      historyCount: service ? Number(service.historyCount) : 2,
      historyTransparency: service ? String(service.historyTransparency || "balanced") : "balanced"
    })
  readonly property bool hasHintHistory: service && Array.isArray(service.recentHintEntries)
    && service.recentHintEntries.length > 0
  readonly property bool hintVisible: eligible && hintRows.length > 0
    && (delayedVisible || hasHintHistory)

  ListModel {
    id: hintPresentationModel
  }

  function hintPresentationIndex(visualId) {
    var key = String(visualId || "")
    for (var i = 0; i < hintPresentationModel.count; i++) {
      if (String(hintPresentationModel.get(i).visualId || "") === key) return i
    }
    return -1
  }

  function removeHintPresentation(visualId) {
    var index = hintPresentationIndex(visualId)
    if (index >= 0 && hintPresentationModel.get(index).exiting === true)
      hintPresentationModel.remove(index)
  }

  function syncHintPresentation() {
    if (!presentationReady) return
    if (!eligible) {
      hintPresentationModel.clear()
      return
    }

    var rows = Array.isArray(hintRows) ? hintRows : []
    var visibleCount = Math.min(rows.length, maximumHintRows)
    var firstRow = rows.length - visibleCount
    var currentRowIndex = -1
    for (var currentIndex = firstRow; currentIndex < rows.length; currentIndex++) {
      if (String(rows[currentIndex].phase || "") === "current") {
        currentRowIndex = currentIndex
        break
      }
    }
    var hasCurrentRow = currentRowIndex >= 0
    var historyRowCount = visibleCount - (hasCurrentRow ? 1 : 0)
    var inverted = displayStackDirection === "inverted"
    var currentAtTop = displayAtTop !== inverted
    var desiredIds = ({})
    for (var desiredIndex = firstRow; desiredIndex < rows.length; desiredIndex++) {
      var desiredId = String(rows[desiredIndex].visualId || rows[desiredIndex].key || "")
      if (desiredId !== "") desiredIds[desiredId] = true
    }

    for (var existingIndex = 0; existingIndex < hintPresentationModel.count; existingIndex++) {
      var existing = hintPresentationModel.get(existingIndex)
      if (existing.exiting === true || desiredIds[String(existing.visualId || "")] === true) continue
      hintPresentationModel.setProperty(existingIndex, "exiting", true)
    }

    var slotScales = []
    for (var slot = 0; slot < maximumHintRows; slot++) slotScales.push(1)
    var placements = []
    for (var rowIndex = firstRow; rowIndex < rows.length; rowIndex++) {
      var row = rows[rowIndex]
      var visualId = String(row.visualId || row.key || "")
      if (visualId === "") continue
      var modelIndex = hintPresentationIndex(visualId)
      var isCurrentRow = rowIndex === currentRowIndex
      var historyIndex = rowIndex - firstRow
      var newestDistanceFromCurrent = historyRowCount - 1 - historyIndex
      var slotIndex
      if (isCurrentRow) {
        slotIndex = currentAtTop ? 0 : maximumHintRows - 1
      } else if (hasCurrentRow) {
        slotIndex = currentAtTop
          ? 1 + newestDistanceFromCurrent
          : maximumHintRows - 2 - newestDistanceFromCurrent
      } else if (inverted) {
        // Keep the current-side slot reserved while history remains, so a
        // new current row does not push the history stack back and forth.
        slotIndex = currentAtTop
          ? 1 + newestDistanceFromCurrent
          : maximumHintRows - 2 - newestDistanceFromCurrent
      } else if (displayAtTop) {
        slotIndex = historyRowCount - 1 - historyIndex
      } else {
        slotIndex = maximumHintRows - historyRowCount + historyIndex
      }
      var targetScale = Math.max(0.1, Number(row.scale === undefined ? 1 : row.scale) * pillSizeFactor)
      slotScales[slotIndex] = targetScale
      var values = {
        visualId: visualId,
        rowCombo: String(row.combo || ""),
        rowDescription: String(row.description || ""),
        phase: String(row.phase || (row.active === true ? "current" : "history")),
        targetY: 0,
        targetOpacity: Math.max(0, Math.min(1, Number(row.opacity === undefined ? 1 : row.opacity))),
        targetScale: targetScale,
        exiting: false
      }
      placements.push({ modelIndex: modelIndex, slotIndex: slotIndex, values: values })
    }

    var slotOffsets = GuideModel.stackRowOffsets(
      slotScales, hintPillHeight, hintRowSpacing, displayAtTop)
    for (var placementIndex = 0; placementIndex < placements.length; placementIndex++) {
      var placement = placements[placementIndex]
      var placementValues = placement.values
      placementValues.targetY = slotOffsets[placement.slotIndex]
      var modelIndex = placement.modelIndex
      if (modelIndex < 0) {
        hintPresentationModel.append(placementValues)
        continue
      }

      if (hintPresentationModel.get(modelIndex).exiting === true)
        hintPresentationModel.setProperty(modelIndex, "exiting", false)
      for (var role in placementValues)
        hintPresentationModel.setProperty(modelIndex, role, placementValues[role])
    }
  }

  onHintRowsChanged: syncHintPresentation()
  onEligibleChanged: syncHintPresentation()
  onDisplayAtTopChanged: syncHintPresentation()
  onDisplayStackDirectionChanged: syncHintPresentation()
  onMaximumHintRowsChanged: syncHintPresentation()
  onHintRowSpacingChanged: syncHintPresentation()
  onHintPillHeightChanged: syncHintPresentation()
  onPillSizeFactorChanged: syncHintPresentation()

  ChordHintPill {
    id: pillHeightSample
    visible: false
    combo: "SUPER + SHIFT + K"
    description: "Sample shortcut"
    descriptionMode: root.displayDescriptionMode
    showChordBorder: root.service ? root.service.showChordBorder : true
    backgroundOpacity: root.service ? root.service.backgroundOpacity : 84
    sizeFactor: root.pillSizeFactor
  }

  function pillX(pillWidth, scale, stackWidth) {
    var visualWidth = pillWidth * scale
    var x = displayPosition.endsWith("-left") ? 0
      : displayPosition.endsWith("-right") ? stackWidth - visualWidth
      : (stackWidth - visualWidth) / 2
    return x - (1 - scale) * pillWidth / 2
  }

  function focusedScreenName() {
    var revision = focusRevision
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  function syncVisibility() {
    var mode = GuideModel.delayMode(service && service.guideVisible === true, delayValue)
    if (!eligible || delayValue < 0 || mode === "disabled") {
      if (service && service.clearGuide)
        service.clearGuide(!eligible ? "guide-ineligible" : "guide-delay-disabled")
      hideGuide()
      return
    }
    if (mode === "hidden") {
      hideGuide()
      return
    }
    if (mode === "immediate") {
      guideDelayTimer.stop()
      delayedVisible = true
      return
    }
    if (!delayedVisible) {
      guideDelayTimer.interval = delayValue
      guideDelayTimer.restart()
    }
  }

  function hideGuide() {
    guideDelayTimer.stop()
    delayedVisible = false
  }

  Timer {
    id: guideDelayTimer
    repeat: false
    onTriggered: {
      if (root.eligible && root.service && root.service.guideVisible === true)
        root.delayedVisible = true
    }
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onGuideVisibleChanged() { root.syncVisibility() }
    function onGuideDelayMsChanged() { root.syncVisibility() }
    function onIntegrationStateChanged() { root.syncVisibility() }
    function onCatalogStateChanged() { root.syncVisibility() }
    function onDesktopLockedChanged() { root.syncVisibility() }
    function onCredentialPromptActiveChanged() { root.syncVisibility() }
    function onActiveWindowFullscreenChanged() { root.syncVisibility() }
    function onShowInFullscreenChanged() { root.syncVisibility() }
    function onDisplayPositionChanged() { root.syncHintPresentation() }
    function onDescriptionModeChanged() { root.syncHintPresentation() }
    function onPillSizeChanged() { root.syncHintPresentation() }
    function onStackGapChanged() { root.syncHintPresentation() }
    function onHistoryCountChanged() { root.syncHintPresentation() }
    function onHistoryTransparencyChanged() { root.syncHintPresentation() }
  }

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() { root.focusRevision += 1 }
  }

  Component.onCompleted: {
    presentationReady = true
    syncVisibility()
    syncHintPresentation()
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: hintWindow
        required property var modelData
        property bool hintFadeHold: false
        property bool hintWasVisible: false

        screen: modelData
        visible: GuideModel.focusedVisible(
          root.eligible && (root.hintVisible || hintFadeHold),
          modelData ? modelData.name : "",
          root.focusedScreenName())
        color: "transparent"
        implicitHeight: root.maximumHintStackHeight + Style.space(36)
        exclusionMode: ExclusionMode.Ignore
        anchors {
          top: root.displayAtTop
          bottom: !root.displayAtTop
          left: true
          right: true
        }

        WlrLayershell.namespace: "chordlight-guide"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        onVisibleChanged: {
          if (visible && root.service && root.service.recordGuideVisible)
            root.service.recordGuideVisible()
        }

        Component.onCompleted: hintWasVisible = root.hintVisible

        Connections {
          target: root
          function onHintVisibleChanged() {
            if (root.hintVisible) {
              hintWindow.hintWasVisible = true
              hintFadeTimer.stop()
              hintWindow.hintFadeHold = false
            } else if (hintWindow.hintWasVisible && root.eligible) {
              hintWindow.hintWasVisible = false
              hintWindow.hintFadeHold = true
              hintFadeTimer.restart()
            } else {
              hintWindow.hintWasVisible = false
              hintFadeTimer.stop()
              hintWindow.hintFadeHold = false
            }
          }

          function onEligibleChanged() {
            if (!root.eligible) {
              hintWindow.hintWasVisible = false
              hintFadeTimer.stop()
              hintWindow.hintFadeHold = false
            }
          }
        }

        Timer {
          id: hintFadeTimer
          interval: root.hintFadeDurationMs
          repeat: false
          onTriggered: hintWindow.hintFadeHold = false
        }

        Item {
          id: screenHost
          anchors.fill: parent

          Item {
            id: hintStack
            width: Math.max(0, parent.width - root.pillScreenGutter * 2)
            height: root.maximumHintStackHeight
            x: root.displayPosition.endsWith("-left") ? root.pillScreenGutter
              : root.displayPosition.endsWith("-right")
                ? parent.width - width - root.pillScreenGutter
                : (parent.width - width) / 2
            y: root.displayAtTop ? root.pillScreenGutter : parent.height - height - root.pillScreenGutter

            Repeater {
              model: hintPresentationModel

              delegate: ChordHintPill {
                id: hintPill
                required property int index
                required property string visualId
                required property string rowCombo
                required property string rowDescription
                required property string phase
                required property real targetY
                required property real targetOpacity
                required property real targetScale
                required property bool exiting

                property bool initialized: false
                property real renderedOpacity: 0
                property real renderedScale: 0.85

                visible: true
                combo: rowCombo
                description: rowDescription
                descriptionMode: root.displayDescriptionMode
                showChordBorder: root.service ? root.service.showChordBorder : true
                backgroundOpacity: root.service ? root.service.backgroundOpacity : 84
                sizeFactor: root.pillSizeFactor
                maxWidth: Math.max(0, screenHost.width - root.pillScreenGutter * 2)
                x: root.pillX(width, renderedScale, hintStack.width)
                y: targetY
                z: targetY
                width: Math.max(0, Math.min(implicitWidth, maxWidth))
                height: root.hintPillHeight
                opacity: renderedOpacity
                scale: renderedScale

                Behavior on x {
                  NumberAnimation { duration: root.hintMoveDurationMs; easing.type: Easing.OutCubic }
                }

                Behavior on y {
                  NumberAnimation { duration: root.hintMoveDurationMs; easing.type: Easing.OutCubic }
                }

                Behavior on opacity {
                  NumberAnimation { duration: root.hintFadeDurationMs; easing.type: Easing.OutCubic }
                }

                Behavior on scale {
                  NumberAnimation { duration: root.hintMoveDurationMs; easing.type: Easing.OutCubic }
                }

                onTargetOpacityChanged: {
                  if (initialized) renderedOpacity = targetOpacity
                }
                onTargetScaleChanged: {
                  if (initialized) renderedScale = targetScale
                }

                onExitingChanged: {
                  if (exiting) {
                    hintPresentationModel.setProperty(index, "targetY", y)
                    hintPresentationModel.setProperty(index, "targetOpacity", 0)
                    exitFadeTimer.restart()
                  } else {
                    exitFadeTimer.stop()
                  }
                }

                Component.onCompleted: {
                  initialized = true
                  renderedOpacity = exiting ? 0 : targetOpacity
                  renderedScale = targetScale
                  if (exiting) exitFadeTimer.restart()
                }

                Timer {
                  id: exitFadeTimer
                  interval: root.hintFadeDurationMs
                  repeat: false
                  onTriggered: root.removeHintPresentation(hintPill.visualId)
                }
              }
            }
          }
        }
      }
    }
  }
}
