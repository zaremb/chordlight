.pragma library

var CATEGORIES = [
  "windows", "workspaces", "applications", "system", "capture",
  "media", "clipboard", "notifications", "style", "other"
]
var MODIFIERS = ["SUPER", "SHIFT", "CTRL", "ALT"]
var PROTOCOL_PREFIX = "chordlight:v1:"

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function hasOnlyStrings(values, allowed) {
  if (!Array.isArray(values)) return false
  var seen = {}
  for (var i = 0; i < values.length; i++) {
    if (typeof values[i] !== "string" || allowed.indexOf(values[i]) === -1 || seen[values[i]]) return false
    seen[values[i]] = true
  }
  return true
}

function validId(value) {
  return typeof value === "string" && /^sha256:[0-9a-f]{64}$/.test(value)
}

function validSourceHash(value) {
  return validId(value)
}

function validCodeList(values) {
  if (!Array.isArray(values)) return false
  for (var i = 0; i < values.length; i++) {
    if (typeof values[i] !== "number" || !isFinite(values[i]) || Math.floor(values[i]) !== values[i] || values[i] < 1) return false
  }
  return true
}

function normalizedBinding(raw) {
  if (!isObject(raw)) return null
  var requiredStrings = ["id", "combo", "key", "description", "submap", "dispatcherKind"]
  for (var i = 0; i < requiredStrings.length; i++) {
    if (typeof raw[requiredStrings[i]] !== "string") return null
  }
  if (!validId(raw.id) || !hasOnlyStrings(raw.modifiers, MODIFIERS)) return null
  if (CATEGORIES.indexOf(raw.category) === -1) return null
  if (raw.phase !== "press" && raw.phase !== "release") return null
  if (!validCodeList(raw.xkbCodes)) return null
  if (typeof raw.trackable !== "boolean" || typeof raw.guideEligible !== "boolean") return null
  if (raw.repeat !== undefined && typeof raw.repeat !== "boolean") return null
  if (raw.available !== undefined && typeof raw.available !== "boolean") return null
  if (raw.unavailable !== undefined && typeof raw.unavailable !== "boolean") return null

  return {
    id: raw.id,
    combo: raw.combo,
    modifiers: raw.modifiers.slice(),
    key: raw.key,
    xkbCodes: raw.xkbCodes.slice(),
    description: raw.description,
    category: raw.category,
    phase: raw.phase,
    submap: raw.submap,
    dispatcherKind: raw.dispatcherKind,
    trackable: raw.trackable,
    guideEligible: raw.guideEligible,
    repeat: raw.repeat === true,
    available: raw.available !== false,
    unavailable: raw.unavailable === true
  }
}

function normalizeCatalog(raw) {
  var value = raw
  if (typeof value === "string") {
    try { value = JSON.parse(value) } catch (e) { return { ok: false, error: "invalid-json" } }
  }
  if (!isObject(value) || value.schemaVersion !== 1 || !validSourceHash(value.sourceHash)
      || typeof value.generatedAt !== "number" || !isFinite(value.generatedAt)
      || !Array.isArray(value.bindings)) {
    return { ok: false, error: "invalid-catalog" }
  }

  var bindings = []
  var byId = {}
  for (var i = 0; i < value.bindings.length; i++) {
    var binding = normalizedBinding(value.bindings[i])
    if (!binding || byId[binding.id]) return { ok: false, error: "invalid-binding" }
    byId[binding.id] = binding
    bindings.push(binding)
  }
  return {
    ok: true,
    catalog: {
      schemaVersion: 1,
      generatedAt: value.generatedAt,
      sourceHash: value.sourceHash,
      bindings: bindings,
      byId: byId
    }
  }
}

function catalogSourceChanged(currentCatalog, nextCatalog) {
  if (!isObject(nextCatalog) || !validSourceHash(nextCatalog.sourceHash)) return true
  if (!isObject(currentCatalog) || !validSourceHash(currentCatalog.sourceHash)) return true
  return currentCatalog.sourceHash !== nextCatalog.sourceHash
}

function allowedModifierMask(mask) {
  if (typeof mask !== "string" || mask === "") return false
  var parts = mask.split("_")
  var seen = {}
  for (var i = 0; i < parts.length; i++) {
    if (MODIFIERS.indexOf(parts[i]) === -1 || seen[parts[i]]) return false
    seen[parts[i]] = true
    if (i > 0 && MODIFIERS.indexOf(parts[i]) <= MODIFIERS.indexOf(parts[i - 1])) return false
  }
  return true
}

function parseProtocol(payload, catalog) {
  if (typeof payload !== "string" || payload.indexOf(PROTOCOL_PREFIX) !== 0)
    return { ok: false, error: "wrong-prefix" }

  var guideDown = payload.match(/^chordlight:v1:guide:down:(SUPER|SHIFT|CTRL|ALT)$/)
  if (guideDown) return { ok: true, type: "guide", phase: "down", root: guideDown[1] }
  if (payload === PROTOCOL_PREFIX + "guide:up") return { ok: true, type: "guide", phase: "up" }

  var modifierMatch = payload.match(/^chordlight:v1:mods:(.*)$/)
  if (modifierMatch) {
    if (!allowedModifierMask(modifierMatch[1])) return { ok: false, error: "invalid-modifiers" }
    return { ok: true, type: "mods", modifiers: modifierMatch[1] }
  }

  var match = payload.match(/^chordlight:v1:match:(sha256:[0-9a-f]{64}):(press|release)$/)
  if (match) {
    var known = !!(catalog && catalog.byId && catalog.byId[match[1]])
    if (known && catalog.byId[match[1]].phase !== match[2]) return { ok: false, error: "phase-mismatch" }
    return { ok: true, type: "match", id: match[1], phase: match[2], known: known }
  }
  var hint = payload.match(/^chordlight:v1:hint:(sha256:[0-9a-f]{64}):(down|up)$/)
  if (hint) {
    var binding = catalog && catalog.byId ? catalog.byId[hint[1]] : null
    return { ok: true, type: "hint", id: hint[1], phase: hint[2],
      known: !!(binding && binding.trackable === true && binding.guideEligible === true) }
  }
  return { ok: false, error: "invalid-protocol" }
}

function normalizeDelay(value) {
  if (value === false || String(value).toLowerCase() === "disabled") return -1
  var number = Number(value)
  return [-1, 0, 80, 150, 250].indexOf(number) !== -1 ? number : 0
}

function normalizeFullscreen(value) {
  return value === true
}

function normalizeGuideRoot(value) {
  return value !== false
}

function defaultSettings() {
  return {
    schemaVersion: 1,
    display: {
      position: "bottom-center",
      descriptionMode: "inline",
      pillSize: "medium",
      showChordBorder: true,
      backgroundOpacity: 84,
      stackGap: "tight",
      historyCount: 2,
      stackDirection: "normal",
      historyDurationSeconds: 3,
      historyTransparency: "balanced"
    },
    guide: {
      delayMs: 0,
      showInFullscreen: false,
      keys: { super: true, shift: true, ctrl: true, alt: true }
    },
    debug: { traceEnabled: false }
  }
}

function normalizeSettings(raw) {
  var source = isObject(raw) ? raw : {}
  var display = isObject(source.display) ? source.display : {}
  var guide = isObject(source.guide) ? source.guide : {}
  var keys = isObject(guide.keys) ? guide.keys : {}
  var debug = isObject(source.debug) ? source.debug : {}
  var defaults = defaultSettings()
  var positions = ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
  var descriptions = ["inline", "below", "hidden"]
  var sizes = ["small", "medium", "large"]
  var gaps = ["tight", "default", "loose"]
  var stackDirections = ["normal", "inverted"]
  var transparencies = ["faded", "balanced", "clear"]
  var duration = Number(display.historyDurationSeconds)
  var count = Number(display.historyCount)
  return {
    schemaVersion: 1,
    display: {
      position: positions.indexOf(display.position) !== -1 ? display.position : defaults.display.position,
      descriptionMode: descriptions.indexOf(display.descriptionMode) !== -1
        ? display.descriptionMode : defaults.display.descriptionMode,
      pillSize: sizes.indexOf(display.pillSize) !== -1 ? display.pillSize : defaults.display.pillSize,
      showChordBorder: typeof display.showChordBorder === "boolean"
        ? display.showChordBorder : defaults.display.showChordBorder,
      backgroundOpacity: typeof display.backgroundOpacity === "number"
        && isFinite(display.backgroundOpacity) && Math.floor(display.backgroundOpacity) === display.backgroundOpacity
        && display.backgroundOpacity >= 0 && display.backgroundOpacity <= 100
        ? display.backgroundOpacity : defaults.display.backgroundOpacity,
      stackGap: gaps.indexOf(display.stackGap) !== -1 ? display.stackGap : defaults.display.stackGap,
      historyCount: isFinite(count) && Math.floor(count) === count && count >= 0 && count <= 2
        ? count : defaults.display.historyCount,
      stackDirection: stackDirections.indexOf(display.stackDirection) !== -1
        ? display.stackDirection : defaults.display.stackDirection,
      historyDurationSeconds: [1, 2, 3, 5, 10].indexOf(duration) !== -1
        ? duration : defaults.display.historyDurationSeconds,
      historyTransparency: transparencies.indexOf(display.historyTransparency) !== -1
        ? display.historyTransparency : defaults.display.historyTransparency
    },
    guide: {
      delayMs: normalizeDelay(guide.delayMs),
      showInFullscreen: normalizeFullscreen(guide.showInFullscreen),
      keys: {
        super: normalizeGuideRoot(keys.super),
        shift: normalizeGuideRoot(keys.shift),
        ctrl: normalizeGuideRoot(keys.ctrl),
        alt: normalizeGuideRoot(keys.alt)
      }
    },
    debug: { traceEnabled: debug.traceEnabled === true }
  }
}

function settingsFromLegacyEntry(entry) {
  var legacy = isObject(entry) ? entry : {}
  return normalizeSettings({
    guide: {
      delayMs: legacy.guideDelayMs,
      showInFullscreen: legacy.showInFullscreen,
      keys: {
        super: legacy.guideSuperEnabled,
        shift: legacy.guideShiftEnabled,
        ctrl: legacy.guideCtrlEnabled,
        alt: legacy.guideAltEnabled
      }
    },
    debug: { traceEnabled: legacy.debugModeEnabled }
  })
}

function stripTomlComment(line) {
  var quote = ""
  var escaped = false
  for (var i = 0; i < line.length; i++) {
    var character = line.charAt(i)
    if (quote === "\"" && character === "\\" && !escaped) {
      escaped = true
      continue
    }
    if ((character === "\"" || character === "'") && !escaped) {
      if (quote === "") quote = character
      else if (quote === character) quote = ""
    }
    if (character === "#" && quote === "") return line.substring(0, i)
    escaped = false
  }
  return line
}

function parseTomlScalar(value, type) {
  var raw = String(value || "").trim()
  if (type === "string") {
    if (raw.charAt(0) === "\"") {
      try {
        var parsed = JSON.parse(raw)
        return typeof parsed === "string" ? { ok: true, value: parsed } : { ok: false }
      } catch (e) { return { ok: false } }
    }
    if (raw.length >= 2 && raw.charAt(0) === "'" && raw.charAt(raw.length - 1) === "'")
      return { ok: true, value: raw.substring(1, raw.length - 1) }
    return { ok: false }
  }
  if (type === "boolean") {
    if (raw === "true") return { ok: true, value: true }
    if (raw === "false") return { ok: true, value: false }
    return { ok: false }
  }
  if (type === "integer") {
    if (!/^-?(0|[1-9][0-9]*)$/.test(raw)) return { ok: false }
    var number = Number(raw)
    return isFinite(number) ? { ok: true, value: number } : { ok: false }
  }
  return { ok: false }
}

function settingTomlType(section, key) {
  if (section === "" && key === "schema_version") return "integer"
  if (section === "display") {
    if (key === "show_chord_border") return "boolean"
    if (["position", "description_mode", "pill_size", "stack_gap", "stack_direction", "history_transparency"].indexOf(key) !== -1)
      return "string"
    if (key === "background_opacity" || key === "history_count" || key === "history_duration_seconds") return "integer"
  }
  if (section === "guide") {
    if (key === "delay_ms") return "integer"
    if (key === "show_in_fullscreen") return "boolean"
  }
  if (section === "guide.keys" && ["super", "shift", "ctrl", "alt"].indexOf(key) !== -1)
    return "boolean"
  if (section === "debug" && key === "trace_enabled") return "boolean"
  return ""
}

function parseSettingsToml(text) {
  var parsed = { schema_version: 1, display: {}, guide: { keys: {} }, debug: {} }
  var section = ""
  var lines = String(text || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = stripTomlComment(lines[i]).trim()
    if (line === "") continue
    if (line.charAt(0) === "[") {
      var table = /^\[([A-Za-z0-9_.-]+)\]$/.exec(line)
      if (!table) return { ok: false, error: "invalid-table-at-line-" + (i + 1) }
      section = table[1]
      continue
    }
    var assignment = /^([A-Za-z0-9_-]+)\s*=\s*(.*?)\s*$/.exec(line)
    if (!assignment) return { ok: false, error: "invalid-assignment-at-line-" + (i + 1) }
    var key = assignment[1]
    var type = settingTomlType(section, key)
    if (type === "") continue
    var scalar = parseTomlScalar(assignment[2], type)
    if (!scalar.ok) return { ok: false, error: "invalid-value-for-" + (section ? section + "." : "") + key }
    if (section === "") parsed[key] = scalar.value
    else if (section === "guide.keys") parsed.guide.keys[key] = scalar.value
    else parsed[section][key] = scalar.value
  }
  if (parsed.schema_version !== 1) return { ok: false, error: "unsupported-schema-version" }
  var display = parsed.display
  var guide = parsed.guide
  var keys = guide.keys
  var validPosition = ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
  var validDescription = ["inline", "below", "hidden"]
  var validSize = ["small", "medium", "large"]
  var validGap = ["tight", "default", "loose"]
  var validStackDirection = ["normal", "inverted"]
  var validTransparency = ["faded", "balanced", "clear"]
  if (display.position !== undefined && validPosition.indexOf(display.position) === -1)
    return { ok: false, error: "invalid-value-for-display.position" }
  if (display.description_mode !== undefined && validDescription.indexOf(display.description_mode) === -1)
    return { ok: false, error: "invalid-value-for-display.description_mode" }
  if (display.pill_size !== undefined && validSize.indexOf(display.pill_size) === -1)
    return { ok: false, error: "invalid-value-for-display.pill_size" }
  if (display.background_opacity !== undefined
      && (display.background_opacity < 0 || display.background_opacity > 100))
    return { ok: false, error: "invalid-value-for-display.background_opacity" }
  if (display.stack_gap !== undefined && validGap.indexOf(display.stack_gap) === -1)
    return { ok: false, error: "invalid-value-for-display.stack_gap" }
  if (display.stack_direction !== undefined && validStackDirection.indexOf(display.stack_direction) === -1)
    return { ok: false, error: "invalid-value-for-display.stack_direction" }
  if (display.history_count !== undefined
      && (display.history_count < 0 || display.history_count > 2))
    return { ok: false, error: "invalid-value-for-display.history_count" }
  if (display.history_duration_seconds !== undefined
      && [1, 2, 3, 5, 10].indexOf(display.history_duration_seconds) === -1)
    return { ok: false, error: "invalid-value-for-display.history_duration_seconds" }
  if (display.history_transparency !== undefined
      && validTransparency.indexOf(display.history_transparency) === -1)
    return { ok: false, error: "invalid-value-for-display.history_transparency" }
  if (guide.delay_ms !== undefined && [-1, 0, 80, 150, 250].indexOf(guide.delay_ms) === -1)
    return { ok: false, error: "invalid-value-for-guide.delay_ms" }
  return {
    ok: true,
    settings: normalizeSettings({
      display: {
        position: display.position,
        descriptionMode: display.description_mode,
        pillSize: display.pill_size,
        showChordBorder: display.show_chord_border,
        backgroundOpacity: display.background_opacity,
        stackGap: display.stack_gap,
        historyCount: display.history_count,
        stackDirection: display.stack_direction,
        historyDurationSeconds: display.history_duration_seconds,
        historyTransparency: display.history_transparency
      },
      guide: {
        delayMs: guide.delay_ms,
        showInFullscreen: guide.show_in_fullscreen,
        keys: { super: keys.super, shift: keys.shift, ctrl: keys.ctrl, alt: keys.alt }
      },
      debug: { traceEnabled: parsed.debug.trace_enabled }
    })
  }
}

function serializeSettingsToml(raw) {
  var settings = normalizeSettings(raw)
  var d = settings.display
  var g = settings.guide
  return [
    "# Chordlight settings (schema version 1).",
    "schema_version = 1",
    "",
    "[display]",
    "position = " + JSON.stringify(d.position),
    "description_mode = " + JSON.stringify(d.descriptionMode),
    "pill_size = " + JSON.stringify(d.pillSize),
    "show_chord_border = " + d.showChordBorder,
    "background_opacity = " + d.backgroundOpacity,
    "stack_gap = " + JSON.stringify(d.stackGap),
    "history_count = " + d.historyCount,
    "stack_direction = " + JSON.stringify(d.stackDirection),
    "history_duration_seconds = " + d.historyDurationSeconds,
    "history_transparency = " + JSON.stringify(d.historyTransparency),
    "",
    "[guide]",
    "delay_ms = " + g.delayMs,
    "show_in_fullscreen = " + g.showInFullscreen,
    "",
    "[guide.keys]",
    "super = " + g.keys.super,
    "shift = " + g.keys.shift,
    "ctrl = " + g.keys.ctrl,
    "alt = " + g.keys.alt,
    "",
    "[debug]",
    "trace_enabled = " + settings.debug.traceEnabled,
    ""
  ].join("\n")
}

function settingsFor(barConfig, moduleName) {
  if (!isObject(barConfig) || !isObject(barConfig.layout)) return {}
  var sections = ["left", "center", "right"]
  var targetId = String(moduleName || "")
  for (var s = 0; s < sections.length; s++) {
    var entries = barConfig.layout[sections[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (isObject(entry) && String(entry.id || "") === targetId) return entry
    }
  }
  return {}
}

function parseActiveWindow(raw) {
  var value = raw
  if (typeof value === "string") {
    try { value = JSON.parse(value) } catch (e) { return { ok: false, error: "invalid-json" } }
  }
  if (!isObject(value)) return { ok: false, error: "invalid-activewindow" }
  if (typeof value.fullscreen === "boolean") return { ok: true, fullscreen: value.fullscreen }
  if (typeof value.fullscreen === "number" && isFinite(value.fullscreen) && Math.floor(value.fullscreen) === value.fullscreen)
    return { ok: true, fullscreen: value.fullscreen > 0 }
  return { ok: false, error: "missing-fullscreen" }
}

function parseLockStatus(raw, exitCode) {
  if (exitCode !== 0) return { ok: false, error: "lock-query-failed" }
  if (typeof raw !== "string") return { ok: false, error: "invalid-lock-status" }
  var value = raw.trim()
  if (value === "true") return { ok: true, locked: true }
  if (value === "false") return { ok: true, locked: false }
  return { ok: false, error: "invalid-lock-status" }
}

function traceProtectionClear(state) {
  if (!isObject(state)) return false
  return state.lockStateKnown === true
    && state.desktopLocked === false
    && state.credentialPromptStateKnown === true
    && state.credentialPromptActive === false
}

function debugTraceEligible(state) {
  return isObject(state)
    && state.debugModeEnabled === true
    && traceProtectionClear(state)
}

function parseLayerStatus(raw, exitCode) {
  if (exitCode !== 0) return { ok: false, error: "layer-query-failed" }
  var value = raw
  if (typeof value === "string") {
    try { value = JSON.parse(value) } catch (e) { return { ok: false, error: "invalid-layer-json" } }
  }
  if (!isObject(value)) return { ok: false, error: "invalid-layer-status" }

  var monitors = Object.keys(value)
  if (monitors.length === 0) return { ok: false, error: "missing-layer-monitors" }
  for (var m = 0; m < monitors.length; m++) {
    var monitor = value[monitors[m]]
    if (!isObject(monitor) || !isObject(monitor.levels))
      return { ok: false, error: "invalid-layer-monitor" }
    var levels = Object.keys(monitor.levels)
    if (levels.length === 0) return { ok: false, error: "missing-layer-levels" }
    for (var l = 0; l < levels.length; l++) {
      var layers = monitor.levels[levels[l]]
      if (!Array.isArray(layers)) return { ok: false, error: "invalid-layer-list" }
      for (var i = 0; i < layers.length; i++) {
        var layer = layers[i]
        if (!isObject(layer) || typeof layer.namespace !== "string")
          return { ok: false, error: "invalid-layer-entry" }
        if (layer.namespace === "omarchy-polkit") return { ok: true, active: true }
      }
    }
  }
  return { ok: true, active: false }
}

function isPolkitLayerEvent(name, data) {
  var eventName = String(name || "")
  return (eventName === "openlayer" || eventName === "closelayer")
    && String(data || "").trim() === "omarchy-polkit"
}

function isCatalogChangeEvent(name) {
  return ["configreloaded", "configreloadedv2", "activelayout", "activekeyboardlayout", "keyboardlayout"].indexOf(String(name || "")) !== -1
}

function parseCatalogGeneration(raw, exitCode) {
  if (Number(exitCode) !== 0) return { ok: false, error: "generator-failed" }
  var result
  try { result = JSON.parse(String(raw || "")) } catch (e) {
    return { ok: false, error: "invalid-generator-output" }
  }
  if (!isObject(result) || result.ok !== true
      || typeof result.sourceHash !== "string"
      || !/^sha256:[0-9a-f]{64}$/.test(result.sourceHash)
      || typeof result.changed !== "boolean"
      || !Number.isInteger(result.bindingCount) || result.bindingCount < 0) {
    return { ok: false, error: "invalid-generator-result" }
  }
  return {
    ok: true,
    sourceHash: result.sourceHash,
    changed: result.changed,
    bindingCount: result.bindingCount
  }
}

function shouldReloadCatalogBridge(generation, integrationState, lastReloadHash, activeReloadHash, pendingReloadHash) {
  return isObject(generation)
    && generation.ok === true
    && generation.changed === true
    && integrationState === "enabled"
    && typeof generation.sourceHash === "string"
    && /^sha256:[0-9a-f]{64}$/.test(generation.sourceHash)
    && generation.sourceHash !== String(lastReloadHash || "")
    && generation.sourceHash !== String(activeReloadHash || "")
    && generation.sourceHash !== String(pendingReloadHash || "")
}

function pendingBridgeReloadAfterCatalog(sourceHash, activeReloadHash) {
  var hash = String(sourceHash || "")
  if (!/^sha256:[0-9a-f]{64}$/.test(hash) || hash === String(activeReloadHash || "")) return ""
  return hash
}

function isFullscreenEvent(name) {
  return ["activewindow", "activewindowv2", "fullscreen"].indexOf(String(name || "")) !== -1
}
