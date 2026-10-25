import QtQuick 2.15
import QtTest 1.3
import "../../ServiceModel.js" as Model

TestCase {
  name: "ChordlightServiceModel"

  function id(letter) { return "sha256:" + Array(65).join(letter) }

  function validCatalog() {
    var binding = {
      id: id("b"),
      combo: "SUPER + RETURN",
      modifiers: ["SUPER"],
      key: "RETURN",
      xkbCodes: [36],
      description: "Terminal",
      category: "applications",
      phase: "press",
      submap: "",
      dispatcherKind: "exec",
      trackable: true,
      guideEligible: true,
      repeat: false
    }
    var release = JSON.parse(JSON.stringify(binding))
    release.id = id("c")
    release.phase = "release"
    return {
      schemaVersion: 1,
      generatedAt: 1,
      sourceHash: id("a"),
      bindings: [binding, release]
    }
  }

  function test_validCatalogAndLookup() {
    var result = Model.normalizeCatalog(validCatalog())
    verify(result.ok)
    compare(result.catalog.bindings.length, 2)
    compare(result.catalog.byId[id("b")].description, "Terminal")
  }

  function test_catalogSourceChangeUsesSourceHash() {
    var current = Model.normalizeCatalog(validCatalog()).catalog
    var sameSource = validCatalog()
    sameSource.generatedAt = 2
    var refreshed = Model.normalizeCatalog(sameSource).catalog
    verify(!Model.catalogSourceChanged(current, refreshed))

    var changedSource = validCatalog()
    changedSource.sourceHash = id("d")
    var changed = Model.normalizeCatalog(changedSource).catalog
    verify(Model.catalogSourceChanged(current, changed))
    verify(Model.catalogSourceChanged(null, current))
    verify(Model.catalogSourceChanged(current, null))
  }

  function test_catalogRejectsMalformedInputs() {
    verify(!Model.normalizeCatalog("not json").ok)
    var wrongSchema = validCatalog()
    wrongSchema.schemaVersion = 2
    verify(!Model.normalizeCatalog(wrongSchema).ok)

    var duplicate = validCatalog()
    duplicate.bindings.push(duplicate.bindings[0])
    verify(!Model.normalizeCatalog(duplicate).ok)

    var badBinding = validCatalog()
    badBinding.bindings[0].category = "invented"
    verify(!Model.normalizeCatalog(badBinding).ok)

    var badTypes = validCatalog()
    badTypes.bindings[0].trackable = "true"
    verify(!Model.normalizeCatalog(badTypes).ok)
  }

  function test_everyValidProtocolForm() {
    var catalog = Model.normalizeCatalog(validCatalog()).catalog
    compare(Model.parseProtocol("chordlight:v1:guide:down:ALT", catalog).root, "ALT")
    compare(Model.parseProtocol("chordlight:v1:guide:up", catalog).phase, "up")
    compare(Model.parseProtocol("chordlight:v1:mods:SUPER_SHIFT_CTRL_ALT", catalog).modifiers, "SUPER_SHIFT_CTRL_ALT")
    compare(Model.parseProtocol("chordlight:v1:mods:SHIFT_ALT", catalog).modifiers, "SHIFT_ALT")
    var press = Model.parseProtocol("chordlight:v1:match:" + id("b") + ":press", catalog)
    verify(press.ok)
    verify(press.known)
    compare(press.phase, "press")
    var release = Model.parseProtocol("chordlight:v1:match:" + id("c") + ":release", catalog)
    verify(release.ok)
    compare(release.phase, "release")
    var hintDown = Model.parseProtocol("chordlight:v1:hint:" + id("b") + ":down", catalog)
    verify(hintDown.ok)
    verify(hintDown.known)
    compare(hintDown.phase, "down")
    var hintUp = Model.parseProtocol("chordlight:v1:hint:" + id("c") + ":up", catalog)
    verify(hintUp.ok)
    verify(hintUp.known)
    compare(hintUp.phase, "up")
  }

  function test_protocolRejectsMalformedAndUnknownForms() {
    var catalog = Model.normalizeCatalog(validCatalog()).catalog
    verify(!Model.parseProtocol("chordlight:v1:super:down", catalog).ok)
    verify(!Model.parseProtocol("chordlight:v1:super:up", catalog).ok)
    verify(!Model.parseProtocol("chordlight:v2:super:down", catalog).ok)
    verify(!Model.parseProtocol("chordlight:v1:super:down:extra", catalog).ok)
    verify(!Model.parseProtocol("chordlight:v1:guide:down:CAPS", catalog).ok)
    verify(!Model.parseProtocol("chordlight:v1:guide:up:extra", catalog).ok)
    verify(!Model.parseProtocol("chordlight:v1:mods:SUPER_CTRL_SHIFT", catalog).ok)
    verify(!Model.parseProtocol("chordlight:v1:match:" + id("b") + ":press:extra", catalog).ok)
    verify(!Model.parseProtocol("chordlight:v1:match:" + id("b") + ":release", catalog).ok)
    verify(!Model.parseProtocol("chordlight:v1:hint:" + id("b") + ":down:extra", catalog).ok)
    verify(!Model.parseProtocol("chordlight:v1:hint:" + id("b") + ":press", catalog).ok)
    var unknown = Model.parseProtocol("chordlight:v1:match:" + id("d") + ":press", catalog)
    verify(unknown.ok)
    verify(!unknown.known)
    var unknownHint = Model.parseProtocol("chordlight:v1:hint:" + id("d") + ":down", catalog)
    verify(unknownHint.ok)
    verify(!unknownHint.known)

    var ineligibleCatalog = validCatalog()
    ineligibleCatalog.bindings[0].guideEligible = false
    var ineligibleHint = Model.parseProtocol("chordlight:v1:hint:" + id("b") + ":down",
      Model.normalizeCatalog(ineligibleCatalog).catalog)
    verify(ineligibleHint.ok)
    verify(!ineligibleHint.known)
  }

  function test_settingsAndBarConfigLookup() {
    compare(Model.normalizeDelay(0), 0)
    compare(Model.normalizeDelay(80), 80)
    compare(Model.normalizeDelay("150"), 150)
    compare(Model.normalizeDelay("disabled"), -1)
    compare(Model.normalizeDelay(-1), -1)
    compare(Model.normalizeDelay(99), 0)
    compare(Model.normalizeFullscreen(true), true)
    compare(Model.normalizeFullscreen("true"), false)
    compare(Model.normalizeGuideRoot(undefined), true)
    compare(Model.normalizeGuideRoot(true), true)
    compare(Model.normalizeGuideRoot(false), false)

    var barConfig = { layout: { left: [], center: [], right: [
      { id: "io.github.zaremb.chordlight", guideDelayMs: 150, showInFullscreen: true,
        guideSuperEnabled: false, guideShiftEnabled: true, guideCtrlEnabled: false, guideAltEnabled: true,
        extensionOption: "preserve-me" }
    ] } }
    var settings = Model.settingsFor(barConfig, "io.github.zaremb.chordlight")
    compare(settings.guideDelayMs, 150)
    compare(settings.showInFullscreen, true)
    compare(settings.guideSuperEnabled, false)
    compare(settings.guideCtrlEnabled, false)
    compare(settings.extensionOption, "preserve-me")
    compare(Model.settingsFor({}, "io.github.zaremb.chordlight").guideDelayMs, undefined)
  }

  function test_settingsTomlDefaultsAndRoundTrip() {
    var defaults = Model.normalizeSettings({})
    compare(defaults.display.position, "bottom-center")
    compare(defaults.display.descriptionMode, "inline")
    compare(defaults.display.pillSize, "medium")
    compare(defaults.display.showChordBorder, true)
    compare(defaults.display.stackGap, "tight")
    compare(defaults.display.historyCount, 2)
    compare(defaults.display.historyDurationSeconds, 3)
    compare(defaults.display.historyTransparency, "balanced")
    compare(defaults.guide.delayMs, 0)
    compare(defaults.guide.keys.super, true)
    compare(defaults.debug.traceEnabled, false)

    var source = Model.normalizeSettings({
      display: {
        position: "top-right",
        descriptionMode: "below",
        pillSize: "large",
        showChordBorder: false,
        stackGap: "tight",
        historyCount: 1,
        historyDurationSeconds: 10,
        historyTransparency: "faded"
      },
      guide: {
        delayMs: -1,
        showInFullscreen: true,
        keys: { super: false, shift: true, ctrl: false, alt: true }
      },
      debug: { traceEnabled: true }
    })
    var toml = Model.serializeSettingsToml(source)
    verify(toml.indexOf("[display]") !== -1)
    verify(toml.indexOf("[guide.keys]") !== -1)
    var result = Model.parseSettingsToml(toml)
    verify(result.ok)
    compare(result.settings.display.position, "top-right")
    compare(result.settings.display.descriptionMode, "below")
    compare(result.settings.display.pillSize, "large")
    compare(result.settings.display.showChordBorder, false)
    compare(result.settings.display.stackGap, "tight")
    compare(result.settings.display.historyCount, 1)
    compare(result.settings.display.historyDurationSeconds, 10)
    compare(result.settings.display.historyTransparency, "faded")
    compare(result.settings.guide.delayMs, -1)
    compare(result.settings.guide.showInFullscreen, true)
    compare(result.settings.guide.keys.super, false)
    compare(result.settings.guide.keys.alt, true)
    compare(result.settings.debug.traceEnabled, true)
  }

  function test_backgroundOpacityValidationAndPersistence() {
    compare(Model.normalizeSettings({}).display.backgroundOpacity, 84)
    var values = [0, 37, 100]
    for (var i = 0; i < values.length; i++) {
      var source = { display: { backgroundOpacity: values[i] } }
      var result = Model.parseSettingsToml(Model.serializeSettingsToml(source))
      verify(result.ok)
      compare(result.settings.display.backgroundOpacity, values[i])
    }
    var invalid = ["-1", "101", "0.5", '"50"', "true"]
    for (var j = 0; j < invalid.length; j++)
      verify(!Model.parseSettingsToml("[display]\nbackground_opacity = " + invalid[j]).ok)
  }

  function test_settingsTomlToleratesCommentsAndUnknownKeys() {
    var toml = [
      "schema_version = 1 # current format",
      "future_option = true",
      "[display]",
      "position = 'top-center' # single quoted TOML string",
      "extra = [1, 2, 3]",
      "[guide]",
      "show_in_fullscreen = true"
    ].join("\n")
    var result = Model.parseSettingsToml(toml)
    verify(result.ok)
    compare(result.settings.display.position, "top-center")
    compare(result.settings.display.historyCount, 2)
    compare(result.settings.guide.showInFullscreen, true)
  }

  function test_settingsTomlRejectsMalformedKnownValuesAndVersions() {
    verify(!Model.parseSettingsToml("[display\nposition = \\\"top-left\\\"").ok)
    verify(!Model.parseSettingsToml("[display]\nposition = 123").ok)
    verify(!Model.parseSettingsToml("[display]\nhistory_count = 3").ok)
    verify(!Model.parseSettingsToml('[display]\nshow_chord_border = "false"').ok)
    compare(Model.parseSettingsToml("[display]\nshow_chord_border = true").settings.display.showChordBorder, true)
    verify(!Model.parseSettingsToml('[display]\nposition = "left-center"').ok)
    verify(!Model.parseSettingsToml("[guide]\ndelay_ms = 60").ok)
    verify(!Model.parseSettingsToml("schema_version = 2").ok)
  }

  function test_legacySettingsImportKeepsOldGuidePreferences() {
    var legacy = Model.settingsFromLegacyEntry({
      guideDelayMs: 150,
      showInFullscreen: true,
      guideSuperEnabled: false,
      guideShiftEnabled: true,
      guideCtrlEnabled: false,
      guideAltEnabled: true,
      debugModeEnabled: true
    })
    compare(legacy.display.position, "bottom-center")
    compare(legacy.display.historyCount, 2)
    compare(legacy.guide.delayMs, 150)
    compare(legacy.guide.showInFullscreen, true)
    compare(legacy.guide.keys.super, false)
    compare(legacy.guide.keys.ctrl, false)
    compare(legacy.debug.traceEnabled, true)
  }

  function test_fullscreenAndEventClassification() {
    compare(Model.parseActiveWindow('{"fullscreen":true}').fullscreen, true)
    compare(Model.parseActiveWindow('{"fullscreen":2}').fullscreen, true)
    compare(Model.parseActiveWindow('{"fullscreen":0}').fullscreen, false)
    verify(!Model.parseActiveWindow('{"fullscreen":"1"}').ok)
    verify(!Model.parseActiveWindow('{"class":"kitty"}').ok)
    verify(Model.isCatalogChangeEvent("configreloaded"))
    verify(Model.isCatalogChangeEvent("activelayout"))
    verify(Model.isFullscreenEvent("activewindowv2"))
    verify(!Model.isFullscreenEvent("custom"))
  }

  function test_catalogGenerationResultAndReloadGuard() {
    var hash = id("a")
    var output = JSON.stringify({ ok: true, sourceHash: hash, bindingCount: 7, changed: true })
    var generation = Model.parseCatalogGeneration(output, 0)
    verify(generation.ok)
    compare(generation.sourceHash, hash)
    compare(generation.changed, true)
    compare(generation.bindingCount, 7)
    verify(!Model.parseCatalogGeneration(output, 1).ok)
    verify(!Model.parseCatalogGeneration("not json", 0).ok)
    verify(!Model.parseCatalogGeneration('{"ok":true,"sourceHash":"sha256:bad","bindingCount":0,"changed":true}', 0).ok)

    verify(Model.shouldReloadCatalogBridge(generation, "enabled", "", "", ""))
    verify(!Model.shouldReloadCatalogBridge(generation, "disabled", "", "", ""))
    verify(!Model.shouldReloadCatalogBridge(generation, "enabled", hash, "", ""))
    verify(!Model.shouldReloadCatalogBridge(generation, "enabled", "", hash, ""))
    verify(!Model.shouldReloadCatalogBridge(generation, "enabled", "", "", hash))
    var newerHash = id("c")
    compare(Model.pendingBridgeReloadAfterCatalog(newerHash, hash), newerHash)
    compare(Model.pendingBridgeReloadAfterCatalog(hash, hash), "")
    compare(Model.pendingBridgeReloadAfterCatalog("invalid", hash), "")
    generation.changed = false
    verify(!Model.shouldReloadCatalogBridge(generation, "enabled", "", "", ""))
  }

  function test_lockStatusFailsClosed() {
    verify(Model.parseLockStatus("true\n", 0).ok)
    compare(Model.parseLockStatus("true\n", 0).locked, true)
    verify(Model.parseLockStatus("false\n", 0).ok)
    compare(Model.parseLockStatus("false\n", 0).locked, false)
    verify(!Model.parseLockStatus("", 0).ok)
    verify(!Model.parseLockStatus("yes", 0).ok)
    verify(!Model.parseLockStatus("false", 1).ok)
  }

  function test_debugTracingRequiresKnownUnprotectedState() {
    var safe = {
      debugModeEnabled: true,
      lockStateKnown: true,
      desktopLocked: false,
      credentialPromptStateKnown: true,
      credentialPromptActive: false
    }
    verify(Model.traceProtectionClear(safe))
    verify(Model.debugTraceEligible(safe))

    var noDebug = JSON.parse(JSON.stringify(safe))
    noDebug.debugModeEnabled = false
    verify(Model.traceProtectionClear(noDebug))
    verify(!Model.debugTraceEligible(noDebug))

    var unknownLock = JSON.parse(JSON.stringify(safe))
    unknownLock.lockStateKnown = false
    verify(!Model.traceProtectionClear(unknownLock))
    verify(!Model.debugTraceEligible(unknownLock))

    var locked = JSON.parse(JSON.stringify(safe))
    locked.desktopLocked = true
    verify(!Model.traceProtectionClear(locked))
    verify(!Model.debugTraceEligible(locked))

    var unknownPrompt = JSON.parse(JSON.stringify(safe))
    unknownPrompt.credentialPromptStateKnown = false
    verify(!Model.traceProtectionClear(unknownPrompt))
    verify(!Model.debugTraceEligible(unknownPrompt))

    var promptActive = JSON.parse(JSON.stringify(safe))
    promptActive.credentialPromptActive = true
    verify(!Model.traceProtectionClear(promptActive))
    verify(!Model.debugTraceEligible(promptActive))

    verify(!Model.traceProtectionClear({}))
    verify(!Model.debugTraceEligible({ debugModeEnabled: true }))
  }

  function test_layerStatusAndPolkitEvents() {
    var clear = '{"eDP-1":{"levels":{"0":[],"3":[]}},"DP-1":{"levels":{"0":[]}}}'
    var active = '{"eDP-1":{"levels":{"0":[],"3":[{"namespace":"omarchy-polkit"}]}}}'
    verify(Model.parseLayerStatus(clear, 0).ok)
    compare(Model.parseLayerStatus(clear, 0).active, false)
    verify(Model.parseLayerStatus(active, 0).ok)
    compare(Model.parseLayerStatus(active, 0).active, true)
    verify(!Model.parseLayerStatus("not json", 0).ok)
    verify(!Model.parseLayerStatus("{}", 0).ok)
    verify(!Model.parseLayerStatus('{"eDP-1":{"levels":[]}}', 0).ok)
    verify(!Model.parseLayerStatus('{"eDP-1":{"levels":{}}}', 0).ok)
    verify(!Model.parseLayerStatus(clear, 1).ok)
    var lookalike = '{"eDP-1":{"levels":{"3":[{"namespace":"not-omarchy-polkit"}]}}}'
    verify(Model.parseLayerStatus(lookalike, 0).ok)
    compare(Model.parseLayerStatus(lookalike, 0).active, false)

    verify(Model.isPolkitLayerEvent("openlayer", "omarchy-polkit"))
    verify(Model.isPolkitLayerEvent("closelayer", "omarchy-polkit"))
    verify(Model.isPolkitLayerEvent("openlayer", "omarchy-polkit\n"))
    verify(!Model.isPolkitLayerEvent("openlayer", "other-layer"))
    verify(!Model.isPolkitLayerEvent("openwindow", "omarchy-polkit"))
  }
}
