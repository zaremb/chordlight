import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "ServiceModel.js" as Model
import "GuideState.js" as GuideState

Item {
  id: root

  readonly property string moduleName: "io.github.zaremb.chordlight"
  property var shell: null
  property var manifest: null

  property string integrationState: "disabled"
  property bool integrationStateKnown: false
  property var integrationDetails: ({})
  property var catalog: null
  property var guideState: GuideState.initialState()
  readonly property bool guideVisible: guideState.phase === GuideState.PHASE_ACTIVE
  readonly property bool guideAwaitingLockCheck: guideState.phase === GuideState.PHASE_CHECKING
  readonly property string activeModifiers: String(guideState.modifiers || "")
  readonly property string activeGuideRoot: String(guideState.root || "")
  readonly property var activeHintIds: GuideState.pendingIds(guideState)
  readonly property var activeHintEntries: guideState.pendingEntries
  readonly property var recentHintEntries: guideState.history
  property string displayPosition: "bottom-center"
  property string descriptionMode: "inline"
  property string pillSize: "medium"
  property bool showChordBorder: true
  property int backgroundOpacity: 84
  property string stackGap: "tight"
  property int historyCount: 2
  property string stackDirection: "normal"
  property int historyDurationSeconds: 3
  property string historyTransparency: "balanced"
  property int guideDelayMs: 0
  property bool showInFullscreen: false
  property bool guideSuperEnabled: true
  property bool guideShiftEnabled: true
  property bool guideCtrlEnabled: true
  property bool guideAltEnabled: true
  property bool debugModeEnabled: false
  property var debugTraceQueue: []
  property string activeDebugTraceEntry: ""
  property int debugTraceWriteFailures: 0
  property int debugTraceDroppedEntries: 0
  property string settingsStatus: "loading"
  property string settingsError: ""
  property bool settingsLoaded: false
  property bool settingsDirectoryReady: false
  property bool settingsFileMissing: false
  // Suppression starts active until both independent sources have answered.
  // Unknown state must never briefly expose the guide over a protected surface.
  property bool desktopLocked: true
  property bool lockStateKnown: false
  property bool credentialPromptActive: true
  property bool credentialPromptStateKnown: false
  readonly property bool traceProtectionClear: Model.traceProtectionClear({
    lockStateKnown: root.lockStateKnown,
    desktopLocked: root.desktopLocked,
    credentialPromptStateKnown: root.credentialPromptStateKnown,
    credentialPromptActive: root.credentialPromptActive
  })
  readonly property bool debugTraceEligible: Model.debugTraceEligible({
    debugModeEnabled: root.debugModeEnabled,
    lockStateKnown: root.lockStateKnown,
    desktopLocked: root.desktopLocked,
    credentialPromptStateKnown: root.credentialPromptStateKnown,
    credentialPromptActive: root.credentialPromptActive
  })
  property bool activeWindowFullscreen: false
  property bool lockStatusRefreshPending: false
  property bool lockStatusTimedOut: false
  property bool layerStatusTimedOut: false
  property bool layerRefreshPending: false
  property int layerEventRevision: 0
  property int layerRequestRevision: 0

  onTraceProtectionClearChanged: {
    if (!traceProtectionClear) {
      // Pending events were captured while the desktop was previously clear,
      // but do not let them be written during a protected state.
      debugTraceQueue = []
      return
    }
    root.startNextDebugTraceWrite()
  }

  property string catalogState: "loading"
  property bool catalogPublicationPending: false
  property var pendingCatalogGeneration: null
  property var pendingCatalogPublicationContext: ({})
  property var pendingCatalogChangeEvents: []
  property var activeCatalogGenerationContext: ({})
  property string deferredBridgeReloadSourceHash: ""
  property string activeBridgeReloadSourceHash: ""
  property string pendingBridgeReloadSourceHash: ""
  property string lastBridgeReloadSourceHash: ""
  property string manualSnippet: ""
  property string lastProtocolError: ""
  property int bridgeEventCount: 0
  property var sessionDiagnostics: ({
    catalogLoadFailures: 0,
    integrationFailures: 0,
    fullscreenQueryCount: 0,
    fullscreenQueryFailures: 0,
    lockQueryFailures: 0,
    layerQueryFailures: 0
  })

  // These diagnostics remain intentionally in memory only. They are useful to
  // the feasibility IPC target and do not become a statistics implementation.
  property double pendingGuideReceivedMs: 0
  property int observedEventCount: 0
  property var latencySamples: []

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy/chordlight"
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string settingsDirectory: configHome + "/omarchy"
  readonly property string settingsPath: settingsDirectory + "/chordlight.toml"

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = decodeURIComponent(value.substring(7))
    return value
  }

  readonly property string generatorPath: localPath(Qt.resolvedUrl("scripts/generate-catalog"))
  readonly property string controllerPath: localPath(Qt.resolvedUrl("scripts/bridge-control"))
  readonly property string debugTraceWriterPath: localPath(Qt.resolvedUrl("scripts/debug-trace"))
  readonly property string debugTracePath: stateDir + "/debug/trace.jsonl"
  readonly property bool catalogGenerationRunning: catalogGenerationProcess.running
  readonly property bool integrationInspectRunning: integrationInspectProcess.running
  readonly property bool integrationMutationRunning: integrationMutationProcess.running

  function protocolPayload(event) {
    if (!event || String(event.name || "") !== "custom") return ""
    var payload = String(event.data || "")
    return payload.indexOf("chordlight:") === 0 ? payload : ""
  }

  function setDiagnostic(name, delta) {
    var next = {}
    for (var key in sessionDiagnostics) next[key] = sessionDiagnostics[key]
    next[name] = Number(next[name] || 0) + Number(delta || 1)
    sessionDiagnostics = next
  }

  function traceBinding(id) {
    var bindingId = String(id || "")
    var binding = catalog && catalog.byId ? catalog.byId[bindingId] : null
    return {
      id: bindingId,
      combo: String(binding && binding.combo || "").slice(0, 256)
    }
  }

  function traceState(state) {
    var source = state && typeof state === "object" ? state : GuideState.initialState()
    var pending = []
    var pendingIds = GuideState.pendingIds(source)
    for (var i = 0; i < pendingIds.length && i < 32; i++)
      pending.push(traceBinding(pendingIds[i]))

    var history = []
    var entries = Array.isArray(source.history) ? source.history : []
    for (var j = 0; j < entries.length && j < 2; j++) {
      var item = traceBinding(entries[j].id)
      item.sequence = Number(entries[j].sequence)
      item.completedAtMs = Number(entries[j].completedAt)
      item.expiresAtMs = Number(entries[j].expiresAt)
      history.push(item)
    }
    return {
      phase: String(source.phase || "idle"),
      root: String(source.root || ""),
      modifiers: String(source.modifiers || ""),
      nextSequence: Number(source.nextSequence || 1),
      pending: pending,
      history: history
    }
  }

  function enqueueDebugTrace(entry) {
    if (!debugTraceEligible) return false
    var queue = debugTraceQueue.slice()
    if (queue.length >= 512) {
      queue.shift()
      debugTraceDroppedEntries += 1
    }
    queue.push(JSON.stringify(entry))
    debugTraceQueue = queue
    root.startNextDebugTraceWrite()
    return true
  }

  function recordDebugTrace(kind, details) {
    if (!debugTraceEligible) return false
    var timestamp = Date.now()
    var entry = {
      schemaVersion: 1,
      timestamp: new Date(timestamp).toISOString(),
      timestampMs: timestamp,
      kind: String(kind || "")
    }
    if (details && typeof details === "object") {
      for (var key in details) entry[key] = details[key]
    }
    return enqueueDebugTrace(entry)
  }

  function startNextDebugTraceWrite() {
    if (!traceProtectionClear || debugTraceWriterProcess.running || activeDebugTraceEntry !== ""
        || debugTraceQueue.length === 0 || debugTraceWriterPath === "") return false
    var queue = debugTraceQueue.slice()
    activeDebugTraceEntry = queue.shift()
    debugTraceQueue = queue
    debugTraceWriterProcess.running = true
    return true
  }

  function finishDebugTraceWrite(success) {
    if (activeDebugTraceEntry === "") return
    if (success !== true) debugTraceWriteFailures += 1
    activeDebugTraceEntry = ""
    Qt.callLater(root.startNextDebugTraceWrite)
  }

  function recordGuideTransition(event, previous, next) {
    if (!debugTraceEligible) return
    var timestamp = Date.now()
    var input = { type: String(event && event.type || "") }
    if (event && event.reason) input.reason = String(event.reason).slice(0, 80)
    if (event && event.root) input.root = String(event.root)
    if (event && event.modifiers) input.modifiers = String(event.modifiers)
    if (event && event.id) input.binding = traceBinding(event.id)
    if (event && event.at !== undefined) input.atMs = Number(event.at)
    enqueueDebugTrace({
      schemaVersion: 1,
      timestamp: new Date(timestamp).toISOString(),
      timestampMs: timestamp,
      kind: "guide-transition",
      input: input,
      before: traceState(previous),
      after: traceState(next)
    })
  }

  function recordMatchedChord(parsed) {
    if (!debugTraceEligible) return
    var timestamp = Date.now()
    enqueueDebugTrace({
      schemaVersion: 1,
      timestamp: new Date(timestamp).toISOString(),
      timestampMs: timestamp,
      kind: "matched-chord",
      phase: String(parsed.phase || ""),
      binding: traceBinding(parsed.id),
      state: traceState(guideState)
    })
  }

  function recordProtocolIssue(error, type, id, phase) {
    if (!debugTraceEligible) return
    var timestamp = Date.now()
    enqueueDebugTrace({
      schemaVersion: 1,
      timestamp: new Date(timestamp).toISOString(),
      timestampMs: timestamp,
      kind: "protocol-issue",
      error: String(error || "").slice(0, 80),
      type: String(type || "").slice(0, 32),
      binding: id ? traceBinding(id) : null,
      phase: String(phase || ""),
      state: traceState(guideState)
    })
  }

  function recordDebugModeChange(enabled) {
    if (!debugTraceEligible) return false
    var timestamp = Date.now()
    enqueueDebugTrace({
      schemaVersion: 1,
      timestamp: new Date(timestamp).toISOString(),
      timestampMs: timestamp,
      kind: "debug-mode",
      enabled: enabled === true,
      state: traceState(guideState)
    })
    return true
  }

  function applyDebugModeEnabled(value) {
    var next = value === true
    if (next === debugModeEnabled) return false
    if (debugModeEnabled) recordDebugModeChange(false)
    debugModeEnabled = next
    if (debugModeEnabled) recordDebugModeChange(true)
    return true
  }

  function transitionGuide(event) {
    var previous = guideState
    var next = GuideState.transition(previous, event, {
      historyCount: historyCount,
      historyDurationMs: historyDurationSeconds * 1000
    })
    root.recordGuideTransition(event, previous, next)
    guideState = next
    root.scheduleHintHistoryExpiry()
    return next
  }

  function handleProtocolEvent(payload) {
    bridgeEventCount += 1
    observedEventCount += 1
    var parsed = Model.parseProtocol(payload, root.catalog)
    if (!parsed.ok) {
      lastProtocolError = parsed.error
      root.recordProtocolIssue(parsed.error, "unknown", "", "")
      return false
    }

    lastProtocolError = ""
    if (parsed.type === "guide") {
      if (parsed.phase === "down") {
        // A modifier can still precede matched-chord events even when its
        // visual guide is disabled, so refresh lock status before handling
        // either path. A previously clear result may already be stale.
        lockStateKnown = false
        root.requestLockStatus(true)
        if (!root.guideRootEnabled(parsed.root)) {
          root.clearGuide("disabled-guide-root-event")
          return true
        }
        pendingGuideReceivedMs = Date.now()
        root.transitionGuide({ type: "sessionStarted", root: parsed.root })
      } else {
        root.endGuide()
      }
      return true
    }
    if (parsed.type === "mods") {
      if (guideVisible || guideAwaitingLockCheck)
        root.transitionGuide({ type: "modifiersChanged", modifiers: parsed.modifiers })
      return true
    }
    if (parsed.type === "match") {
      if (!parsed.known) {
        lastProtocolError = "unknown-binding-id"
        root.recordProtocolIssue(lastProtocolError, parsed.type, parsed.id, parsed.phase)
        return false
      }
      root.recordMatchedChord(parsed)
      return true
    }
    if (parsed.type === "hint") {
      if (!parsed.known) {
        lastProtocolError = "unknown-binding-id"
        root.recordProtocolIssue(lastProtocolError, parsed.type, parsed.id, parsed.phase)
        return false
      }
      // The reducer accepts hints while eligibility checks are pending, then
      // clears them if those checks suppress the guide.
      root.transitionGuide({
        type: parsed.phase === "down" ? "hintDown" : "hintUp",
        id: parsed.id,
        at: Date.now()
      })
      return true
    }
    return false
  }

  function scheduleHintHistoryExpiry() {
    hintHistoryTimer.stop()
    var nextExpiry = GuideState.nextExpiryAt(guideState)
    if (nextExpiry === null) return
    var now = Date.now()
    hintHistoryTimer.interval = Math.max(1, Math.ceil(nextExpiry - now))
    hintHistoryTimer.start()
  }

  function expireHintHistory() {
    root.transitionGuide({ type: "expire", at: Date.now() })
  }

  Process {
    id: debugTraceWriterProcess
    command: ["python3", root.debugTraceWriterPath, "--path", root.debugTracePath]
    running: false
    stdinEnabled: true
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      if (root.activeDebugTraceEntry !== "")
        debugTraceWriterProcess.write(root.activeDebugTraceEntry + "\n")
    }
    onExited: function(exitCode) {
      root.finishDebugTraceWrite(exitCode === 0)
    }
    onRunningChanged: {
      // FailedToStart emits runningChanged without exited; normal exits run
      // onExited first, which clears the active entry before this handler.
      if (!debugTraceWriterProcess.running && root.activeDebugTraceEntry !== "")
        root.finishDebugTraceWrite(false)
    }
  }

  Timer {
    id: hintHistoryTimer
    interval: GuideState.HINT_HISTORY_MS
    repeat: false
    onTriggered: root.expireHintHistory()
  }

  Timer {
    id: settingsSaveTimer
    interval: 150
    repeat: false
    onTriggered: root.saveSettings()
  }

  Process {
    id: settingsDirectoryProcess
    command: ["mkdir", "-p", root.settingsDirectory]
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.settingsStatus = "error"
        root.settingsError = "Could not create the Chordlight settings directory."
        return
      }
      root.settingsDirectoryReady = true
      settingsFile.reload()
    }
  }

  function recordGuideVisible() {
    if (pendingGuideReceivedMs <= 0) return
    var next = latencySamples.slice()
    next.push(Math.max(0, Date.now() - pendingGuideReceivedMs))
    latencySamples = next
    pendingGuideReceivedMs = 0
  }

  function resetDiagnostics() {
    clearGuide("diagnostics-reset")
    observedEventCount = 0
    bridgeEventCount = 0
    latencySamples = []
    lastProtocolError = ""
  }

  function diagnosticsJson() {
    return JSON.stringify({
      eventCount: observedEventCount,
      bridgeEventCount: bridgeEventCount,
      sampleCount: latencySamples.length,
      samplesMs: latencySamples,
      guideVisible: guideVisible,
      catalogState: catalogState,
      integrationState: integrationState,
      debugModeEnabled: debugModeEnabled,
      debugTracePath: debugTracePath,
      debugTraceWriteFailures: debugTraceWriteFailures,
      debugTraceDroppedEntries: debugTraceDroppedEntries,
      lastProtocolError: lastProtocolError,
      sessionDiagnostics: sessionDiagnostics
    })
  }

  function loadCatalog(raw, traceContext) {
    var result = Model.normalizeCatalog(raw)
    var sourceChanged = !result.ok || Model.catalogSourceChanged(catalog, result.catalog)
    var context = traceContext && typeof traceContext === "object" ? traceContext : ({})
    root.recordDebugTrace("catalog-load", {
      source: String(context.source || "file-view"),
      trigger: String(context.trigger || ""),
      eventNames: Array.isArray(context.eventNames) ? context.eventNames : [],
      changed: context.changed === true ? true : context.changed === false ? false : null,
      sourceChanged: sourceChanged
    })
    if (sourceChanged) root.clearGuide("catalog-refresh")
    if (!result.ok) {
      catalog = null
      catalogState = "error"
      setDiagnostic("catalogLoadFailures", 1)
      return { ok: false, sourceChanged: true }
    }
    catalog = result.catalog
    catalogState = "ready"
    return { ok: true, sourceChanged: sourceChanged }
  }

  function openGuide() { transitionGuide({ type: "sessionOpened" }) }
  function closeGuide() { clearGuide("guide-closed") }

  function settingsEntry() {
    return Model.settingsFor(shell ? shell.barConfig : null, root.moduleName)
  }

  function currentSettingsObject() {
    return Model.normalizeSettings({
      display: {
        position: displayPosition,
        descriptionMode: descriptionMode,
        pillSize: pillSize,
        showChordBorder: showChordBorder,
        backgroundOpacity: backgroundOpacity,
        stackGap: stackGap,
        historyCount: historyCount,
        stackDirection: stackDirection,
        historyDurationSeconds: historyDurationSeconds,
        historyTransparency: historyTransparency
      },
      guide: {
        delayMs: guideDelayMs,
        showInFullscreen: showInFullscreen,
        keys: {
          super: guideSuperEnabled,
          shift: guideShiftEnabled,
          ctrl: guideCtrlEnabled,
          alt: guideAltEnabled
        }
      },
      debug: { traceEnabled: debugModeEnabled }
    })
  }

  function applySettings(value) {
    var next = Model.normalizeSettings(value)
    var previousHistoryCount = historyCount
    displayPosition = next.display.position
    descriptionMode = next.display.descriptionMode
    pillSize = next.display.pillSize
    showChordBorder = next.display.showChordBorder
    backgroundOpacity = next.display.backgroundOpacity
    stackGap = next.display.stackGap
    historyCount = next.display.historyCount
    stackDirection = next.display.stackDirection
    historyDurationSeconds = next.display.historyDurationSeconds
    historyTransparency = next.display.historyTransparency
    guideDelayMs = next.guide.delayMs
    showInFullscreen = next.guide.showInFullscreen
    guideSuperEnabled = next.guide.keys.super
    guideShiftEnabled = next.guide.keys.shift
    guideCtrlEnabled = next.guide.keys.ctrl
    guideAltEnabled = next.guide.keys.alt
    applyDebugModeEnabled(next.debug.traceEnabled)
    if (activeGuideRoot !== "" && !guideRootEnabled(activeGuideRoot)) {
      clearGuide("guide-root-disabled-by-setting")
    }
    if (previousHistoryCount !== historyCount)
      root.transitionGuide({ type: "settingsChanged", at: Date.now() })
  }

  function loadSettingsToml(raw) {
    var result = Model.parseSettingsToml(raw)
    if (!result.ok) {
      settingsLoaded = true
      settingsStatus = "error"
      settingsError = "Could not read Chordlight settings: " + result.error
      return false
    }
    settingsFileMissing = false
    settingsLoaded = true
    settingsError = ""
    applySettings(result.settings)
    settingsStatus = "saved"
    return true
  }

  function beginSettingsMigration() {
    if (!settingsFileMissing || !settingsDirectoryReady || !shell || settingsLoaded) return false
    settingsLoaded = true
    settingsError = ""
    applySettings(Model.settingsFromLegacyEntry(settingsEntry()))
    settingsStatus = "saving"
    settingsFile.setText(Model.serializeSettingsToml(currentSettingsObject()))
    return true
  }

  function handleSettingsLoadFailure(errorName) {
    if (!settingsDirectoryReady) return
    if (String(errorName) === "FileNotFound") {
      settingsFileMissing = true
      if (!beginSettingsMigration()) settingsStatus = "loading"
      return
    }
    settingsLoaded = true
    settingsStatus = "error"
    settingsError = "Could not load settings (" + String(errorName) + ")."
  }

  function queueSettingsSave() {
    if (!settingsLoaded) return false
    settingsError = ""
    settingsStatus = "saving"
    settingsSaveTimer.restart()
    return true
  }

  function saveSettings() {
    if (!settingsLoaded || !settingsDirectoryReady) return false
    settingsFile.setText(Model.serializeSettingsToml(currentSettingsObject()))
    return true
  }

  function setDisplaySetting(name, value) {
    if (!settingsLoaded) return false
    var next = currentSettingsObject()
    var propertyName = String(name || "")
    if (propertyName === "position") next.display.position = value
    else if (propertyName === "descriptionMode") next.display.descriptionMode = value
    else if (propertyName === "backgroundOpacity") next.display.backgroundOpacity = value
    else if (propertyName === "showChordBorder") next.display.showChordBorder = value
    else if (propertyName === "pillSize") next.display.pillSize = value
    else if (propertyName === "stackGap") next.display.stackGap = value
    else if (propertyName === "historyCount") next.display.historyCount = value
    else if (propertyName === "stackDirection") next.display.stackDirection = value
    else if (propertyName === "historyDurationSeconds") next.display.historyDurationSeconds = value
    else if (propertyName === "historyTransparency") next.display.historyTransparency = value
    else return false

    var normalized = Model.normalizeSettings(next)
    if (normalized.display[propertyName] !== value) return false
    if (normalized.display[propertyName] === currentSettingsObject().display[propertyName]) return false
    applySettings(normalized)
    queueSettingsSave()
    return true
  }

  function persistSettings() {
    return queueSettingsSave()
  }

  function setGuideDelayMs(value) {
    var next = Model.normalizeDelay(value)
    if (next === guideDelayMs) return false
    guideDelayMs = next
    return persistSettings()
  }

  function setShowInFullscreen(value) {
    var next = Model.normalizeFullscreen(value)
    if (next === showInFullscreen) return false
    showInFullscreen = next
    return persistSettings()
  }

  function setDebugModeEnabled(value) {
    var next = value === true
    if (!applyDebugModeEnabled(next)) return false
    return persistSettings()
  }

  function guideRootEnabled(rootName) {
    if (rootName === "SUPER") return guideSuperEnabled
    if (rootName === "SHIFT") return guideShiftEnabled
    if (rootName === "CTRL") return guideCtrlEnabled
    if (rootName === "ALT") return guideAltEnabled
    return false
  }

  function setGuideRootEnabled(rootName, value) {
    var next = Model.normalizeGuideRoot(value)
    if (rootName !== "SUPER" && rootName !== "SHIFT"
        && rootName !== "CTRL" && rootName !== "ALT") return false

    if (guideRootEnabled(rootName) === next) return false
    if (rootName === "SUPER") guideSuperEnabled = next
    else if (rootName === "SHIFT") guideShiftEnabled = next
    else if (rootName === "CTRL") guideCtrlEnabled = next
    else guideAltEnabled = next
    if (!next && activeGuideRoot === rootName) {
      clearGuide("guide-root-disabled")
    }
    return persistSettings()
  }

  function endGuide() {
    pendingGuideReceivedMs = 0
    root.transitionGuide({ type: "sessionEnded", reason: "guide-root-released" })
  }

  function clearGuide(reason) {
    pendingGuideReceivedMs = 0
    var hasState = guideState.phase !== GuideState.PHASE_IDLE
      || guideState.pendingEntries.length > 0 || guideState.history.length > 0
    if (!hasState) return false
    root.transitionGuide({ type: "reset", reason: String(reason || "explicit-clear") })
    return true
  }

  function suppressGuide(reason) {
    root.clearGuide(reason || "guide-suppressed")
  }

  function evaluatePendingGuide() {
    if (!guideAwaitingLockCheck) return false
    if (!lockStateKnown || !credentialPromptStateKnown) return false
    if (desktopLocked || credentialPromptActive) {
      clearGuide(desktopLocked ? "desktop-locked" : "polkit-prompt-active")
      return false
    }
    root.transitionGuide({ type: "sessionActivated" })
    return true
  }

  function setLockStateUnknown() {
    lockStateKnown = false
    desktopLocked = true
    suppressGuide("lock-state-unknown")
  }

  function recordLockStatus(raw, exitCode) {
    var parsed = Model.parseLockStatus(raw, exitCode)
    if (!parsed.ok) {
      setDiagnostic("lockQueryFailures", 1)
      setLockStateUnknown()
      return false
    }
    desktopLocked = parsed.locked
    lockStateKnown = true
    if (desktopLocked) suppressGuide("desktop-locked")
    else evaluatePendingGuide()
    return true
  }

  function requestLockStatus(forGuide) {
    if (lockStatusProcess.running) {
      if (forGuide === true) lockStatusRefreshPending = true
      return false
    }
    lockStatusTimeoutTimer.restart()
    lockStatusProcess.running = true
    return true
  }

  function requestLayerStatus() {
    if (layerStatusProcess.running) {
      layerRefreshPending = true
      return false
    }
    layerStatusDebounceTimer.restart()
    return true
  }

  function handlePolkitLayerEvent(name, data) {
    if (!Model.isPolkitLayerEvent(name, data)) return false
    layerEventRevision += 1
    if (name === "openlayer") {
      credentialPromptActive = true
      credentialPromptStateKnown = true
    } else {
      // Keep the guide hidden until a fresh inventory confirms that every
      // Omarchy Polkit surface has closed, including on multi-monitor setups.
      credentialPromptActive = true
      credentialPromptStateKnown = false
    }
    suppressGuide("polkit-layer-event:" + name)
    requestLayerStatus()
    return true
  }

  function recordLayerStatus(raw, exitCode) {
    if (layerRequestRevision !== layerEventRevision) {
      requestLayerStatus()
      return false
    }
    var parsed = Model.parseLayerStatus(raw, exitCode)
    if (!parsed.ok) {
      credentialPromptStateKnown = false
      credentialPromptActive = true
      setDiagnostic("layerQueryFailures", 1)
      suppressGuide("polkit-layer-query-failed")
      return false
    }
    credentialPromptActive = parsed.active
    credentialPromptStateKnown = true
    if (credentialPromptActive) suppressGuide("polkit-prompt-active")
    else evaluatePendingGuide()
    return true
  }

  function applyIntegrationResult(raw, exitCode) {
    if (exitCode !== 0) {
      integrationState = "error"
      integrationStateKnown = false
      setDiagnostic("integrationFailures", 1)
      return false
    }
    var parsed
    try { parsed = JSON.parse(String(raw || "")) } catch (e) {
      integrationState = "error"
      integrationStateKnown = false
      setDiagnostic("integrationFailures", 1)
      return false
    }
    integrationDetails = parsed
    if (parsed.managedBlockState === "present") {
      integrationState = "enabled"
      integrationStateKnown = true
      if (deferredBridgeReloadSourceHash !== "") {
        var deferredHash = deferredBridgeReloadSourceHash
        deferredBridgeReloadSourceHash = ""
        requestCatalogBridgeReload(deferredHash)
      }
    }
    else if (parsed.managedBlockState === "absent") {
      integrationState = (integrationState === "enabled" || integrationState === "disconnected")
        ? "disconnected" : "disabled"
      integrationStateKnown = true
      deferredBridgeReloadSourceHash = ""
      pendingBridgeReloadSourceHash = ""
      clearGuide("integration-removed")
    } else {
      integrationState = "error"
      integrationStateKnown = false
    }
    return integrationState !== "error"
  }

  function applyManualSnippet(raw, exitCode) {
    if (exitCode !== 0) return false
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && parsed.ok === true && typeof parsed.snippet === "string") {
        manualSnippet = parsed.snippet
        return true
      }
    } catch (e) {}
    return false
  }

  function inspectIntegration() {
    if (integrationInspectProcess.running || controllerPath === "") return false
    integrationInspectProcess.command = [controllerPath, "inspect"]
    integrationInspectProcess.running = true
    return true
  }

  function mutateIntegration(action, expectedHash) {
    var hash = String(expectedHash || "")
    if (!hash || integrationMutationProcess.running || controllerPath === "") return false
    integrationState = "enabling"
    integrationStateKnown = false
    integrationMutationAction = action
    integrationMutationProcess.command = [controllerPath, action, "--expected-hash", hash]
    integrationMutationProcess.running = true
    return true
  }

  function enableIntegration(expectedHash) { return mutateIntegration("enable", expectedHash) }
  function disableIntegration(expectedHash) { return mutateIntegration("disable", expectedHash) }

  function recordFullscreenResult(raw, exitCode) {
    var next = {}
    for (var key in sessionDiagnostics) next[key] = sessionDiagnostics[key]
    next.fullscreenQueryCount = Number(next.fullscreenQueryCount || 0) + 1
    sessionDiagnostics = next
    if (exitCode !== 0) {
      setDiagnostic("fullscreenQueryFailures", 1)
      return false
    }
    var parsed = Model.parseActiveWindow(raw)
    if (!parsed.ok) {
      setDiagnostic("fullscreenQueryFailures", 1)
      return false
    }
    activeWindowFullscreen = parsed.fullscreen
    return true
  }

  property bool fullscreenQueryPending: false

  function requestFullscreenRefresh() {
    fullscreenQueryPending = true
    fullscreenQueryTimer.restart()
  }

  function handleRawEvent(event) {
    if (!event) return
    var name = String(event.name || "")
    var data = String(event.data || "")
    if (handlePolkitLayerEvent(name, data)) return
    if (name === "custom") {
      var payload = protocolPayload(event)
      if (payload !== "") handleProtocolEvent(payload)
      return
    }
    if (Model.isCatalogChangeEvent(name)) {
      var pendingEvents = pendingCatalogChangeEvents.slice()
      if (pendingEvents.length < 64) pendingEvents.push(name.slice(0, 64))
      pendingCatalogChangeEvents = pendingEvents
      recordDebugTrace("hyprland-catalog-event", { name: name.slice(0, 64) })
      catalogChangeTimer.restart()
    }
    if (Model.isFullscreenEvent(name)) requestFullscreenRefresh()
  }

  Timer {
    id: catalogChangeTimer
    interval: 350
    repeat: false
    onTriggered: {
      root.recordDebugTrace("catalog-change-debounce-fired", {
        eventNames: root.pendingCatalogChangeEvents.slice()
      })
      root.regenerateCatalog("hyprland-event")
    }
  }

  property bool catalogRegenerationPending: false
  property string generatorOutput: ""

  function scheduleBridgeReloadForChangedCatalog(sourceHash) {
    var hash = String(sourceHash || "")
    if (hash === "") return false
    if (integrationState === "enabled") return requestCatalogBridgeReload(hash)
    if (!integrationStateKnown || integrationState === "enabling") {
      deferredBridgeReloadSourceHash = hash
      return true
    }
    deferredBridgeReloadSourceHash = ""
    return false
  }

  function requestCatalogBridgeReload(sourceHash) {
    var generation = { ok: true, sourceHash: String(sourceHash || ""), changed: true }
    if (integrationState !== "enabled") return false
    if (catalogBridgeReloadProcess.running) {
      if (generation.sourceHash === activeBridgeReloadSourceHash) {
        pendingBridgeReloadSourceHash = ""
        return false
      }
      pendingBridgeReloadSourceHash = generation.sourceHash
      return true
    }
    if (!Model.shouldReloadCatalogBridge(
          generation,
          integrationState,
          lastBridgeReloadSourceHash,
          activeBridgeReloadSourceHash,
          pendingBridgeReloadSourceHash)) return false
    activeBridgeReloadSourceHash = generation.sourceHash
    catalogBridgeReloadProcess.command = ["hyprctl", "reload"]
    catalogBridgeReloadProcess.running = true
    return true
  }

  function completeCatalogPublication(loaded) {
    var generation = pendingCatalogGeneration
    pendingCatalogGeneration = null
    catalogPublicationPending = false
    if (loaded && generation) {
      if (integrationState === "enabled" && catalogBridgeReloadProcess.running) {
        pendingBridgeReloadSourceHash = Model.pendingBridgeReloadAfterCatalog(
              generation.sourceHash,
              activeBridgeReloadSourceHash)
      } else if (generation.changed) {
        scheduleBridgeReloadForChangedCatalog(generation.sourceHash)
      }
    }
    if (catalogRegenerationPending) {
      catalogRegenerationPending = false
      catalogChangeTimer.restart()
    }
  }

  function regenerateCatalog(trigger) {
    var generationTrigger = String(trigger || "unspecified").slice(0, 64)
    if (catalogGenerationProcess.running || catalogPublicationPending) {
      catalogRegenerationPending = true
      recordDebugTrace("catalog-generation-deferred", {
        trigger: generationTrigger,
        eventNames: pendingCatalogChangeEvents.slice()
      })
      return false
    }
    if (generatorPath === "") {
      recordDebugTrace("catalog-generation-skipped", {
        trigger: generationTrigger,
        reason: "generator-path-empty"
      })
      return false
    }
    catalogRegenerationPending = false
    activeCatalogGenerationContext = {
      trigger: generationTrigger,
      eventNames: pendingCatalogChangeEvents.slice()
    }
    pendingCatalogChangeEvents = []
    recordDebugTrace("catalog-generation-started", activeCatalogGenerationContext)
    catalogGenerationProcess.command = ["python3", generatorPath, "--output-dir", stateDir]
    catalogGenerationProcess.running = true
    return true
  }

  FileView {
    id: catalogFile
    path: root.stateDir + "/catalog.json"
    watchChanges: false
    onLoaded: {
      var publicationPending = root.catalogPublicationPending
      var generation = root.pendingCatalogGeneration
      var context = root.pendingCatalogPublicationContext || ({})
      var loaded = root.loadCatalog(text(), {
        source: publicationPending ? "generated" : "file-view",
        trigger: String(context.trigger || ""),
        eventNames: Array.isArray(context.eventNames) ? context.eventNames : [],
        changed: generation ? generation.changed === true : null
      })
      if (publicationPending) {
        root.pendingCatalogPublicationContext = ({})
        root.completeCatalogPublication(loaded.ok)
      }
    }
    onLoadFailed: {
      var context = root.pendingCatalogPublicationContext || ({})
      root.recordDebugTrace("catalog-load-failed", {
        trigger: String(context.trigger || ""),
        eventNames: Array.isArray(context.eventNames) ? context.eventNames : []
      })
      root.pendingCatalogPublicationContext = ({})
      root.clearGuide("catalog-load-failed")
      root.catalog = null
      root.catalogState = "error"
      root.setDiagnostic("catalogLoadFailures", 1)
      if (root.catalogPublicationPending) root.completeCatalogPublication(false)
    }
  }

  Process {
    id: catalogGenerationProcess
    running: false
    stdout: StdioCollector { id: generatorStdout; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      root.generatorOutput = String(generatorStdout.text || "")
      var generated = Model.parseCatalogGeneration(root.generatorOutput, exitCode)
      var context = root.activeCatalogGenerationContext || ({})
      root.activeCatalogGenerationContext = ({})
      root.recordDebugTrace("catalog-generation-finished", {
        trigger: String(context.trigger || ""),
        eventNames: Array.isArray(context.eventNames) ? context.eventNames : [],
        exitCode: Number(exitCode),
        ok: generated.ok === true,
        changed: generated.ok === true ? generated.changed === true : null
      })
      if (!generated.ok) {
        root.catalogState = "error"
        root.setDiagnostic("catalogLoadFailures", 1)
        if (root.catalogRegenerationPending) {
          root.catalogRegenerationPending = false
          catalogChangeTimer.restart()
        }
        return
      }
      root.pendingCatalogGeneration = generated
      root.pendingCatalogPublicationContext = context
      root.catalogPublicationPending = true
      catalogFile.reload()
    }
  }

  Process {
    id: catalogBridgeReloadProcess
    running: false
    onExited: function(exitCode, exitStatus) {
      var completedHash = root.activeBridgeReloadSourceHash
      root.activeBridgeReloadSourceHash = ""
      if (exitCode === 0) root.lastBridgeReloadSourceHash = completedHash
      else root.setDiagnostic("integrationFailures", 1)

      if (root.pendingBridgeReloadSourceHash !== "") {
        var pendingHash = root.pendingBridgeReloadSourceHash
        root.pendingBridgeReloadSourceHash = ""
        Qt.callLater(function() { root.requestCatalogBridgeReload(pendingHash) })
      }
    }
  }

  Process {
    id: integrationInspectProcess
    running: false
    stdout: StdioCollector { id: integrationInspectStdout; waitForEnd: true }
    onExited: root.applyIntegrationResult(integrationInspectStdout.text, exitCode)
  }

  Process {
    id: manualSnippetProcess
    running: false
    stdout: StdioCollector { id: manualSnippetStdout; waitForEnd: true }
    onExited: root.applyManualSnippet(manualSnippetStdout.text, exitCode)
  }

  property string integrationMutationAction: ""
  Process {
    id: integrationMutationProcess
    running: false
    stdout: StdioCollector { id: integrationMutationStdout; waitForEnd: true }
    onExited: {
      var parsed = null
      try { parsed = JSON.parse(String(integrationMutationStdout.text || "")) } catch (e) {}
      if (exitCode !== 0 || !parsed || parsed.ok !== true) {
        root.integrationState = "error"
        root.integrationStateKnown = false
        root.setDiagnostic("integrationFailures", 1)
      } else {
        root.integrationDetails = parsed
        Qt.callLater(root.inspectIntegration)
      }
    }
  }

  Timer {
    id: integrationInspectTimer
    interval: 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.inspectIntegration()
  }

  Timer {
    id: fullscreenQueryTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (!root.fullscreenQueryPending || fullscreenQueryProcess.running) return
      root.fullscreenQueryPending = false
      fullscreenQueryProcess.running = true
    }
  }

  Process {
    id: fullscreenQueryProcess
    command: ["hyprctl", "-j", "activewindow"]
    running: false
    stdout: StdioCollector { id: fullscreenStdout; waitForEnd: true }
    onExited: {
      root.recordFullscreenResult(fullscreenStdout.text, exitCode)
      if (root.fullscreenQueryPending) fullscreenQueryTimer.restart()
    }
  }

  Timer {
    id: lockStatusTimeoutTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!lockStatusProcess.running) return
      root.lockStatusTimedOut = true
      root.setDiagnostic("lockQueryFailures", 1)
      root.setLockStateUnknown()
      lockStatusProcess.signal(9)
    }
  }

  Timer {
    id: lockStatusRetryTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      if (!root.lockStateKnown && !lockStatusProcess.running)
        root.requestLockStatus(false)
    }
  }

  Timer {
    id: visibleLockRefreshTimer
    interval: 100
    repeat: true
    running: root.guideVisible
    onTriggered: root.requestLockStatus(false)
  }

  Process {
    id: lockStatusProcess
    command: ["omarchy-shell", "lock", "isLocked"]
    running: false
    stdout: StdioCollector { id: lockStatusStdout; waitForEnd: true }
    onExited: {
      lockStatusTimeoutTimer.stop()
      if (root.lockStatusTimedOut) {
        root.lockStatusTimedOut = false
        if (root.lockStatusRefreshPending) {
          root.lockStatusRefreshPending = false
          Qt.callLater(function() { root.requestLockStatus(false) })
        }
        return
      }
      if (root.lockStatusRefreshPending) {
        root.lockStatusRefreshPending = false
        Qt.callLater(function() { root.requestLockStatus(false) })
        return
      }
      root.recordLockStatus(lockStatusStdout.text, exitCode)
    }
  }

  Timer {
    id: layerStatusDebounceTimer
    interval: 40
    repeat: false
    onTriggered: {
      if (layerStatusProcess.running) {
        root.layerRefreshPending = true
        return
      }
      root.layerRefreshPending = false
      root.layerRequestRevision = root.layerEventRevision
      root.layerStatusTimedOut = false
      layerStatusTimeoutTimer.restart()
      layerStatusProcess.running = true
    }
  }

  Timer {
    id: layerStatusRetryTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      if ((!root.credentialPromptStateKnown || root.credentialPromptActive)
          && !layerStatusProcess.running)
        root.requestLayerStatus()
    }
  }

  Timer {
    id: layerStatusTimeoutTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!layerStatusProcess.running) return
      root.layerStatusTimedOut = true
      root.credentialPromptStateKnown = false
      root.credentialPromptActive = true
      root.setDiagnostic("layerQueryFailures", 1)
      root.suppressGuide("polkit-layer-query-timeout")
      layerStatusProcess.signal(9)
    }
  }

  Process {
    id: layerStatusProcess
    command: ["hyprctl", "-j", "layers"]
    running: false
    stdout: StdioCollector { id: layerStatusStdout; waitForEnd: true }
    onExited: {
      layerStatusTimeoutTimer.stop()
      if (root.layerStatusTimedOut) {
        root.layerStatusTimedOut = false
        if (root.layerRefreshPending) {
          root.layerRefreshPending = false
          Qt.callLater(function() { root.requestLayerStatus() })
        }
        return
      }
      if (root.layerRequestRevision !== root.layerEventRevision) {
        root.layerRefreshPending = false
        Qt.callLater(function() { root.requestLayerStatus() })
        return
      }
      root.recordLayerStatus(layerStatusStdout.text, exitCode)
      if (root.layerRefreshPending) {
        root.layerRefreshPending = false
        Qt.callLater(function() { root.requestLayerStatus() })
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleRawEvent(event) }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettingsToml(text())
    onLoadFailed: function(error) { root.handleSettingsLoadFailure(FileViewError.toString(error)) }
    onSaved: {
      root.settingsStatus = "saved"
      root.settingsError = ""
    }
    onSaveFailed: function(error) {
      root.settingsStatus = "error"
      root.settingsError = "Could not save Chordlight settings (" + FileViewError.toString(error) + ")."
    }
    onFileChanged: reload()
  }

  IpcHandler {
    target: "chordlight-feasibility"
    function diagnostics(): string { return root.diagnosticsJson() }
    function reset(): string { root.resetDiagnostics(); return "ok" }
  }

  Component.onCompleted: Qt.callLater(function() {
    settingsDirectoryProcess.running = true
    root.inspectIntegration()
    manualSnippetProcess.command = [root.controllerPath, "manual-snippet"]
    manualSnippetProcess.running = true
    root.regenerateCatalog("startup")
    root.requestFullscreenRefresh()
    root.requestLockStatus(false)
    root.requestLayerStatus()
  })

  onShellChanged: Qt.callLater(function() {
    root.beginSettingsMigration()
  })

  SuperGuide {
    service: root
  }
}
