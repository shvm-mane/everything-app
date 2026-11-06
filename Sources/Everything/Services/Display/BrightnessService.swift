// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import IOKit.graphics
import ObjectiveC.runtime
import os

struct BrightnessDisplay: Identifiable, Equatable {
    enum Method: Equatable {
        case system
        case ddc
        case software
    }

    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    var method: Method?
    var isActive: Bool
    var brightness: Double
    let readable: Bool
    var canChooseDimming = false
    var restorationFingerprint: String? = nil
}

final class BrightnessService: ObservableObject {
    static let shared = BrightnessService()
    private static let sharedKeyboardLightBridge = KeyboardLightBridge()
    static var keyboardLightIsSupported: Bool { sharedKeyboardLightBridge != nil }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display")

    @Published private(set) var displays: [BrightnessDisplay] = []
    @Published private(set) var drawableDisplays = Set<CGDirectDisplayID>()
    @Published private(set) var pendingDisplayIDs = Set<CGDirectDisplayID>()
    @Published private(set) var softwareDimmingPreferred = Set<CGDirectDisplayID>()
    @Published private(set) var extendedDimmingPreferred = Set<CGDirectDisplayID>()
    @Published private(set) var displayControlFailure: DisplayControlFailure?
    @Published private(set) var brightnessOSDSupported = false
    @Published private(set) var keyboardLightEnabled: Bool?
    @Published private(set) var displayBrightnessShortcutRegistrationFailed = false
    @Published private(set) var keyboardBrightnessShortcutRegistrationFailed = false
    @Published var focusedDisplayID: CGDirectDisplayID?

    var islandSliderShowsFocusedDisplay: Bool {
        BrightnessSupport.sliderShowsFocusedDisplay(
            controlEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.brightnessControlEnabled),
            shown: displays.filter { $0.isActive && $0.method != nil }.map(\.id), focused: focusedDisplayID)
    }

    private func focusKeyDisplay(_ id: CGDirectDisplayID) {
        guard BrightnessSupport.keyMovesFocus(islandOpen: NotchService.shared.expanded,
                                              focused: focusedDisplayID, key: id) else { return }
        focusedDisplayID = id
    }

    enum DisplayControlFailure: Equatable {
        case unavailable
        case lastActive
        case failed
        case closedLid
    }

    private struct Route {
        var method: BrightnessDisplay.Method
        var service: CFTypeRef?
        var maximum: UInt16
        var ddcReadable = false
        var ddcPathKey: String?
        var extendedDimming = false
        var lastDDCValue: UInt16?
    }

    private var deferredRestoration = BrightnessSupport.DeferredDisplayRestoration()
    private var lidNotificationPort: IONotificationPortRef?
    private var lidNotification: io_object_t = 0
    private var screenObserver: NSObjectProtocol?
    private var rebuildDebounce: DispatchWorkItem?
    private var wakeObservers: [NSObjectProtocol] = []
    private var wakeRebuild: DispatchWorkItem?
    private var displayPowerIsSuspended = false
    private static let wakeSettleDelay: TimeInterval = 3
    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private var keyOwnership = BrightnessSupport.BrightnessKeyOwnership()
    private var swallowedMediaKeys = Set<Bool>()
    private let keyThreadLock = NSLock()
    private var functionKeyTap: CFMachPort?
    private var functionKeyRunLoop: CFRunLoop?
    private var functionKeyThread: Thread?
    private var shouldStopFunctionKeyThread = false
    private var pendingFunctionKeyRestart = false
    private var functionKeysAdjustBrightness = true
    private var overlayReplacesNativeOSD = false
    private var functionKeysFollowPointer = false
    private var functionKeySystemTarget: CGDirectDisplayID?
    private var functionKeyStep = BrightnessSupport.KeyStep.standard
    private var swallowedKeyCodes = Set<Int>()
    private let workQueue = DispatchQueue(label: "com.vorssaint.utils.brightness", qos: .userInitiated)
    private let stateLock = NSLock()
    private var routes: [CGDirectDisplayID: Route] = [:]
    private struct PendingWrite {
        let value: Double
        let showOSD: Bool
        let sequence: UInt64
        let smooth: Bool
    }
    private var pendingLevels: [CGDirectDisplayID: PendingWrite] = [:]
    private var writeSequence: UInt64 = 0
    private var systemWritesInFlight = Set<CGDirectDisplayID>()
    private var ddcPendingSteps: [CGDirectDisplayID: Double] = [:]
    private var drainScheduled = false
    private struct RememberedLevel {
        var value: Double
        var fingerprint: String
    }
    private var lastApplied: [CGDirectDisplayID: RememberedLevel] = [:]
    private var levelKnownAt: [CGDirectDisplayID: Date] = [:]
    private static let levelTrustWindow: TimeInterval = 3
    private var ddcCommandEnds: [CGDirectDisplayID: UInt64] = [:]
    private var gammaBaselines: [CGDirectDisplayID: GammaTable] = [:]
    private static let rememberedGammaBaselines = 16
    private var dimmedDisplays = Set<CGDirectDisplayID>()

    private struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
        var count: UInt32
        var fingerprint: String
    }

    private static func displayFingerprint(_ id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id)):\(CGDisplayModelNumber(id)):\(CGDisplaySerialNumber(id))"
    }

    private static func restorationDisplayFingerprint(_ id: CGDirectDisplayID) -> String? {
        let fingerprint = displayFingerprint(id)
        guard fingerprint != "0:0:0", !fingerprint.contains(String(UInt32.max)),
              !fingerprint.hasPrefix("\(0x756E6B6E):") else { return nil }
        return fingerprint
    }

    private func rememberedLevel(for id: CGDirectDisplayID) -> Double? {
        guard let remembered = lastApplied[id],
              remembered.fingerprint == Self.displayFingerprint(id) else { return nil }
        return remembered.value
    }
    private var knownTopology = Set<CGDirectDisplayID>()
    private var knownActiveTopology = Set<CGDirectDisplayID>()
    private var knownMirrorSources: [CGDirectDisplayID: CGDirectDisplayID] = [:]
    private var builtInScreenName: String?
    private var knownDisplayFingerprints: [CGDirectDisplayID: String] = [:]
    private var managedDisabledIDs = Set<CGDirectDisplayID>()
    private var managedDisabledDisplays: [CGDirectDisplayID: BrightnessDisplay] = [:]
    private var running = false
    private var inputTapsSuspended = false
    private func tapsAreSuspended() -> Bool {
        keyThreadLock.withLock { inputTapsSuspended }
    }
    @Published private(set) var keyboardLightLevel: Float?
    private var keyboardNoticeWork: DispatchWorkItem?
    private var keyboardLevelWork: DispatchWorkItem?
    private var keyboardDragStart: Float??
    private var lastKeyboardLightLevel: Float = BrightnessSupport.defaultKeyboardLightLevel
    private var keyboardLightBridge: KeyboardLightBridge? { Self.sharedKeyboardLightBridge }
    private let displayBrightnessDecreaseHotkey = QuickToolHotkey(id: 59)
    private let displayBrightnessIncreaseHotkey = QuickToolHotkey(id: 60)
    private let keyboardBrightnessDecreaseHotkey = QuickToolHotkey(id: 57)
    private let keyboardBrightnessIncreaseHotkey = QuickToolHotkey(id: 58)
    private var rebuildGeneration = 0
    private var rebuildingTopology: BrightnessSupport.DisplayTopology?

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncKeyTap() }
        displayBrightnessDecreaseHotkey.onPress = { [weak self] in
            self?.stepDisplayBrightness(delta: -BrightnessSupport.brightnessKeyStep)
        }
        displayBrightnessIncreaseHotkey.onPress = { [weak self] in
            self?.stepDisplayBrightness(delta: BrightnessSupport.brightnessKeyStep)
        }
        keyboardBrightnessDecreaseHotkey.onPress = { [weak self] in
            self?.stepKeyboardLight(direction: -1)
        }
        keyboardBrightnessIncreaseHotkey.onPress = { [weak self] in
            self?.stepKeyboardLight(direction: 1)
        }
    }

    func setKeyboardLightEnabled(_ enabled: Bool) {
        guard keyboardLightEnabled != nil, let keyboardLightBridge else { return }
        finishKeyboardLightDrag()
        if !enabled, let level = keyboardLightLevel, level > 0 {
            lastKeyboardLightLevel = level
        }
        let target = enabled
            ? BrightnessSupport.keyboardLightOnLevel(lastNonzero: lastKeyboardLightLevel)
            : 0
        guard keyboardLightBridge.setBrightness(target) else {
            refreshKeyboardLight()
            return
        }
        keyboardLightLevel = target
        keyboardLightEnabled = target > 0
        showKeyboardLightNotice(target)
    }

    func setKeyboardLightLevel(_ level: Float) {
        guard keyboardLightEnabled != nil,
              let target = BrightnessSupport.sliderKeyboardLightLevel(level)
        else { return }
        keyboardLightLevel = target
        keyboardLightEnabled = target > 0
        if keyboardDragStart == nil, target > 0 { lastKeyboardLightLevel = target }
        guard keyboardLevelWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.keyboardLevelWork = nil
            self.commitKeyboardLightLevel()
        }
        keyboardLevelWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: work)
    }

    private func commitKeyboardLightLevel() {
        guard let target = keyboardLightLevel, let keyboardLightBridge else { return }
        guard keyboardLightBridge.setBrightness(target) else {
            refreshKeyboardLight()
            return
        }
        showKeyboardLightNotice(target)
    }

    func keyboardLightDragChanged(_ editing: Bool) {
        if editing {
            finishKeyboardLightDrag()
            let current = keyboardLightLevel
            keyboardDragStart = .some(current.flatMap { $0 > 0 ? $0 : nil })
        } else {
            finishKeyboardLightDrag()
        }
    }

    private func finishKeyboardLightDrag() {
        guard let start = keyboardDragStart else { return }
        keyboardDragStart = nil
        if let level = keyboardLightLevel, level > 0 {
            lastKeyboardLightLevel = level
        } else if let start {
            lastKeyboardLightLevel = start
        }
    }

    func refreshKeyboardLight() {
        guard keyboardLevelWork == nil else { return }
        guard let level = keyboardLightBridge?.brightness(), level >= 0, level <= 1 else {
            keyboardLightLevel = nil
            keyboardLightEnabled = nil
            return
        }
        keyboardLightLevel = level
        if level > 0 { lastKeyboardLightLevel = level }
        keyboardLightEnabled = level > 0
    }

    func stepKeyboardLight(direction: Int) {
        guard AppFeature.brightness.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.keyboardBrightnessShortcutsEnabled),
              direction != 0,
              let keyboardLightBridge,
              let current = keyboardLightLevel(using: keyboardLightBridge)
        else { return }
        finishKeyboardLightDrag()
        let target = BrightnessSupport.steppedKeyboardLightLevel(
            current: current, direction: direction)
        guard keyboardLightBridge.setBrightness(target) else {
            refreshKeyboardLight()
            return
        }
        keyboardLightLevel = target
        if target > 0 { lastKeyboardLightLevel = target }
        keyboardLightEnabled = target > 0
        showKeyboardLightNotice(target)
    }

    private func showKeyboardLightNotice(_ level: Float) {
        guard NotchSupport.routes(.keyboardLight), SessionActivity.shared.isActive,
              level.isFinite, (0...1).contains(level) else { return }
        NotchService.shared.showKeyboardLight(Double(level))
    }

    private func scheduleKeyboardLightNotice() {
        guard keyboardNoticeWork == nil, NotchSupport.routes(.keyboardLight),
              SessionActivity.shared.isActive, keyboardLightBridge != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.keyboardNoticeWork = nil
            guard NotchSupport.routes(.keyboardLight), SessionActivity.shared.isActive else { return }
            self.refreshKeyboardLight()
            if let level = self.keyboardLightLevel { self.showKeyboardLightNotice(level) }
        }
        keyboardNoticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func keyboardLightLevel(using bridge: KeyboardLightBridge) -> Float? {
        let level = bridge.brightness()
        guard level >= 0, level <= 1 else {
            keyboardLightEnabled = nil
            return nil
        }
        return level
    }

    func syncWithPreferences() {
        let wanted = AppFeature.brightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.brightnessControlEnabled)
        if wanted { start() } else if running { stop() }
        syncKeyTap()
        syncKeyboardBrightnessHotkeys()
        syncDisplayBrightnessHotkeys()
    }

    private func syncDisplayBrightnessHotkeys() {
        let enabled = running && AppFeature.brightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.displayBrightnessShortcutsEnabled)
        let decrease = GlobalShortcutRole.displayBrightnessDecrease.savedShortcut
        let increase = GlobalShortcutRole.displayBrightnessIncrease.savedShortcut
        let decreaseConflicts = enabled && decrease.conflictsWithSystemShortcut
            && !SystemShortcutTakeover.isTakenOver(GlobalShortcutRole.displayBrightnessDecrease.storageKey)
        let increaseConflicts = enabled && increase.conflictsWithSystemShortcut
            && !SystemShortcutTakeover.isTakenOver(GlobalShortcutRole.displayBrightnessIncrease.storageKey)
        let decreaseRegistered = displayBrightnessDecreaseHotkey.sync(
            enabled: enabled && !decreaseConflicts, shortcut: decrease,
            storageKey: GlobalShortcutRole.displayBrightnessDecrease.storageKey)
        let increaseRegistered = displayBrightnessIncreaseHotkey.sync(
            enabled: enabled && !increaseConflicts, shortcut: increase,
            storageKey: GlobalShortcutRole.displayBrightnessIncrease.storageKey)
        displayBrightnessShortcutRegistrationFailed = decreaseConflicts || increaseConflicts
            || !(decreaseRegistered && increaseRegistered)
    }

    private func stepDisplayBrightness(delta: Double) {
        guard running, AppFeature.brightness.isAvailable, SessionActivity.shared.isActive,
              UserDefaults.standard.bool(forKey: DefaultsKey.displayBrightnessShortcutsEnabled)
        else { return }
        let pointer = NSEvent.mouseLocation
        let pointerDisplay = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            .flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
        let eligible = Set(displays.filter { $0.isActive && $0.method != nil
            && !pendingDisplayIDs.contains($0.id) }.map(\.id))
        guard let id = BrightnessSupport.shortcutDisplay(
            followsPointer: UserDefaults.standard.bool(forKey: DefaultsKey.brightnessKeysEnabled),
            pointerDisplay: pointerDisplay, primaryDisplay: CGMainDisplayID(), eligible: eligible),
              let method = displays.first(where: { $0.id == id })?.method else { return }
        step(id, method: method, delta: keyStep.limited(delta),
             showOSD: UserDefaults.standard.bool(forKey: DefaultsKey.brightnessOSDEnabled))
    }

    private var keyStep: BrightnessSupport.KeyStep {
        .sanitized(UserDefaults.standard.string(forKey: DefaultsKey.brightnessKeyStep))
    }

    private func syncKeyboardBrightnessHotkeys() {
        let enabled = AppFeature.brightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.keyboardBrightnessShortcutsEnabled)
            && keyboardLightBridge != nil
        let decreaseShortcut = GlobalShortcutRole.keyboardBrightnessDecrease.savedShortcut
        let increaseShortcut = GlobalShortcutRole.keyboardBrightnessIncrease.savedShortcut
        let decreaseConflicts = enabled && decreaseShortcut.conflictsWithSystemShortcut
            && !SystemShortcutTakeover.isTakenOver(GlobalShortcutRole.keyboardBrightnessDecrease.storageKey)
        let increaseConflicts = enabled && increaseShortcut.conflictsWithSystemShortcut
            && !SystemShortcutTakeover.isTakenOver(GlobalShortcutRole.keyboardBrightnessIncrease.storageKey)
        let decreaseRegistered = keyboardBrightnessDecreaseHotkey.sync(
            enabled: enabled && !decreaseConflicts, shortcut: decreaseShortcut,
            storageKey: GlobalShortcutRole.keyboardBrightnessDecrease.storageKey)
        let increaseRegistered = keyboardBrightnessIncreaseHotkey.sync(
            enabled: enabled && !increaseConflicts, shortcut: increaseShortcut,
            storageKey: GlobalShortcutRole.keyboardBrightnessIncrease.storageKey)
        keyboardBrightnessShortcutRegistrationFailed = decreaseConflicts || increaseConflicts
            || !(decreaseRegistered && increaseRegistered)
    }

    private func start() {
        guard !running else { return }
        running = true
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
        installWakeObservers()
        refresh()
    }

    func stop() {
        keyboardNoticeWork?.cancel(); keyboardNoticeWork = nil
        keyboardLevelWork?.cancel(); keyboardLevelWork = nil
        keyboardDragStart = nil
        removeKeyTap()
        displayBrightnessDecreaseHotkey.unregister()
        displayBrightnessIncreaseHotkey.unregister()
        displayBrightnessShortcutRegistrationFailed = false
        guard running else { return }
        running = false
        removeFunctionKeyTap()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        removeWakeObservers()
        rebuildDebounce?.cancel()
        rebuildDebounce = nil
        stateLock.lock()
        rebuildGeneration += 1
        rebuildingTopology = nil
        routes = [:]
        pendingLevels = [:]
        writeSequence = 0
        systemWritesInFlight = []
        lastApplied = [:]
        knownTopology = []
        knownActiveTopology = []
        knownMirrorSources = [:]
        stateLock.unlock()
        ddcPendingSteps = [:]
        pendingDisplayIDs = []
        displayControlFailure = nil
        brightnessOSDSupported = false
        BrightnessOSD.teardown()
        if !displays.isEmpty { displays = [] }
        if !drawableDisplays.isEmpty { drawableDisplays = [] }
        workQueue.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.restoreManagedDisplays()
                self.workQueue.async { [weak self] in
                    guard let self else { return }
                    self.restoreAllGamma()
                    self.ddcCommandEnds = [:]
                    Self.log.log("brightness service stopped; displays and gamma restored")
                }
            }
        }
    }

    func refresh(force: Bool = false) {
        guard running, !displayPowerIsSuspended else { return }
        let topology = Self.currentTopology()
        let previousDisplays = displays
        stateLock.lock()
        guard BrightnessSupport.shouldQueueRebuild(topology: topology,
                                                   pending: rebuildingTopology,
                                                   force: force) else {
            stateLock.unlock()
            return
        }
        rebuildGeneration += 1
        let generation = rebuildGeneration
        rebuildingTopology = topology
        stateLock.unlock()
        var screenNames = Self.localizedScreenNames()
        if let id = screenNames.keys.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            builtInScreenName = screenNames[id]
        } else if let name = builtInScreenName {
            for id in topology.online where CGDisplayIsBuiltin(id) != 0 { screenNames[id] = name }
        }
        workQueue.async { [weak self] in
            self?.rebuild(generation: generation, previousDisplays: previousDisplays,
                          screenNames: screenNames)
        }
    }

    private static func localizedScreenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                             as? NSNumber)?.uint32Value else { continue }
            names[id] = screen.localizedName
        }
        return names
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID,
                       showOSD: Bool = false, smooth: Bool = false, announces: Bool = true) {
        guard value.isFinite else { return }
        let clamped = min(max(value, 0), 1)
        let shownInNotch = announces ? NotchService.shared.showBrightness(clamped) : false
        if let index = displays.firstIndex(where: { $0.id == id }),
           displays[index].brightness != clamped {
            displays[index].brightness = clamped
        }
        stateLock.lock()
        writeSequence &+= 1
        pendingLevels[id] = PendingWrite(value: clamped,
                                         showOSD: showOSD && !shownInNotch,
                                         sequence: writeSequence, smooth: smooth)
        lastApplied[id] = RememberedLevel(value: clamped,
                                          fingerprint: Self.displayFingerprint(id))
        levelKnownAt[id] = Date()
        let schedule = !drainScheduled
        if schedule { drainScheduled = true }
        stateLock.unlock()
        guard schedule else { return }
        workQueue.async { [weak self] in
            self?.drainPendingLevels()
        }
    }

    // MARK: - Display power

    var displaySwitchingAvailable: Bool { DisplayConfigurationBridge.configureEnabled != nil }

    func isDisplayPending(_ id: CGDirectDisplayID) -> Bool {
        pendingDisplayIDs.contains(id)
    }

    func canToggleDisplay(_ display: BrightnessDisplay) -> Bool {
        guard displaySwitchingAvailable, !isDisplayPending(display.id) else { return false }
        guard display.isActive else { return true }
        return BrightnessSupport.canDisableDisplay(drawableDisplayIDs: drawableDisplays,
                                                  target: display.id)
    }

    func toggleDisplay(_ display: BrightnessDisplay) {
        guard !isDisplayPending(display.id) else { return }
        guard displaySwitchingAvailable else {
            displayControlFailure = .unavailable
            return
        }
        let targetEnabled = !display.isActive
        if !targetEnabled {
            stateLock.lock()
            let online = knownTopology
            let active = knownActiveTopology
            stateLock.unlock()
            let drawable = Self.drawableDisplayIDs(online: online, active: active)
            guard BrightnessSupport.canDisableDisplay(drawableDisplayIDs: drawable,
                                                       target: display.id) else {
                displayControlFailure = .lastActive
                return
            }
        }

        displayControlFailure = nil
        pendingDisplayIDs.insert(display.id)
        workQueue.async { [weak self] in
            guard let self else { return }
            if !targetEnabled {
                let topology = Self.currentTopology()
                let drawable = Self.drawableDisplayIDs(online: topology.online,
                                                       active: topology.active)
                guard BrightnessSupport.canDisableDisplay(drawableDisplayIDs: drawable,
                                                           target: display.id) else {
                    self.finishDisplayToggle(id: display.id, enabled: targetEnabled,
                                             failure: .lastActive)
                    return
                }
                if let baseline = self.gammaBaselines[display.id],
                   baseline.fingerprint == Self.displayFingerprint(display.id) {
                    CGSetDisplayTransferByTable(display.id, baseline.count, baseline.red,
                                                baseline.green, baseline.blue)
                }
            }

            DispatchQueue.main.async { [weak self] in
                self?.commitDisplayToggle(display, enabled: targetEnabled)
            }
        }
    }

    private func commitDisplayToggle(_ display: BrightnessDisplay, enabled: Bool) {
        if !enabled {
            let topology = Self.currentTopology()
            let drawable = Self.drawableDisplayIDs(online: topology.online, active: topology.active)
            guard BrightnessSupport.canDisableDisplay(drawableDisplayIDs: drawable, target: display.id) else {
                finishDisplayToggle(id: display.id, enabled: enabled, failure: .lastActive)
                return
            }
        }
        if enabled, discardReplacedDisplay(display.id) {
            finishDisplayToggle(id: display.id, enabled: enabled, failure: .failed)
            refresh(force: true)
            return
        }
        let fingerprint = display.isBuiltIn ? nil : Self.restorationDisplayFingerprint(display.id)
        if !enabled { Self.rememberDisplaySwitchedOff(display.id, fingerprint: fingerprint) }
        let result = Self.configureDisplay(display.id, enabled: enabled)
        guard result == .success else {
            if !enabled { Self.forgetDisplaySwitchedOff(display.id) }
            if result == .closedLid {
                deferredRestoration.keep(display.id)
                deferredRestoration.record(display.id, result: .closedLid)
                syncLidObserver()
            }
            finishDisplayToggle(id: display.id, enabled: enabled,
                                failure: result == .closedLid ? .closedLid : .failed)
            return
        }

        stateLock.lock()
        if let fingerprint { knownDisplayFingerprints[display.id] = fingerprint }
        pendingLevels.removeValue(forKey: display.id)
        if enabled {
            managedDisabledIDs.remove(display.id)
            managedDisabledDisplays.removeValue(forKey: display.id)
            knownActiveTopology.insert(display.id)
        } else {
            managedDisabledIDs.insert(display.id)
            var disabled = display
            disabled.method = nil
            disabled.isActive = false
            disabled.restorationFingerprint = fingerprint
            managedDisabledDisplays[display.id] = disabled
            knownActiveTopology.remove(display.id)
        }
        stateLock.unlock()
        deferredRestoration.record(display.id, result: .success)
        syncLidObserver()
        if enabled { Self.forgetDisplaySwitchedOff(display.id) }
        finishDisplayToggle(id: display.id, enabled: enabled, failure: nil)
    }

    private func finishDisplayToggle(id: CGDirectDisplayID, enabled: Bool,
                                     failure: DisplayControlFailure?) {
        let finish = { [weak self] in
            guard let self else { return }
            self.pendingDisplayIDs.remove(id)
            self.displayControlFailure = failure
            if failure == nil, let index = self.displays.firstIndex(where: { $0.id == id }) {
                self.displays[index].isActive = enabled
                if !enabled { self.displays[index].method = nil }
                self.refresh(force: true)
            }
        }
        if Thread.isMainThread { finish() } else { DispatchQueue.main.async(execute: finish) }
    }

    private static func drawableDisplayIDs(online: Set<CGDirectDisplayID>,
                                           active: Set<CGDirectDisplayID>) -> Set<CGDirectDisplayID> {
        let virtual = Set(online.filter {
            displayInfoDictionary($0)?["kCGDisplayIsVirtualDevice"] as? Bool ?? false
        })
        return BrightnessSupport.drawableDisplayIDs(
            onlineDisplayIDs: online, activeDisplayIDs: active, virtualDisplayIDs: virtual)
    }

    private static func configureDisplay(
        _ id: CGDirectDisplayID, enabled: Bool
    ) -> BrightnessSupport.DisplayConfigurationResult {
        guard Thread.isMainThread else {
            log.error("refused to reconfigure display \(id) off the main thread")
            return .failed
        }
        guard let configure = DisplayConfigurationBridge.configureEnabled else { return .failed }
        guard BrightnessSupport.canConfigureDisplay(
            enabled: enabled, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
            lidClosed: enabled ? lidClosed() : nil) else { return .closedLid }
        var reference: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&reference) == .success,
              let configuration = reference else { return .failed }
        guard configure(configuration, id, enabled) == 0 else {
            CGCancelDisplayConfiguration(configuration)
            return .failed
        }
        return CGCompleteDisplayConfiguration(configuration, .forAppOnly) == .success ? .success : .failed
    }

    static func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    private func restoreDisplay(_ id: CGDirectDisplayID) -> BrightnessSupport.DisplayConfigurationResult {
        guard !discardReplacedDisplay(id) else { return .failed }
        let result: BrightnessSupport.DisplayConfigurationResult = canRestoreDisplay(id)
            ? Self.configureDisplay(id, enabled: true) : .failed
        deferredRestoration.record(id, result: result)
        syncLidObserver()
        if result == .success { displayControlFailure = nil }
        return result
    }

    private func canRestoreDisplay(_ id: CGDirectDisplayID) -> Bool {
        guard let current = Self.restorationDisplayFingerprint(id) else { return true }
        stateLock.lock()
        let original = managedDisabledDisplays[id]?.restorationFingerprint
        stateLock.unlock()
        return original == nil || original == current
    }

    private func syncLidObserver() {
        if running || !deferredRestoration.ids.isEmpty {
            installWakeObservers()
        } else {
            removeWakeObservers()
        }
        if deferredRestoration.ids.isEmpty {
            if lidNotification != 0 { IOObjectRelease(lidNotification) }
            lidNotification = 0
            if let lidNotificationPort { IONotificationPortDestroy(lidNotificationPort) }
            lidNotificationPort = nil
            return
        }
        guard lidNotificationPort == nil else { return }
        let root = IOServiceGetMatchingService(kIOMainPortDefault,
                                               IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return }
        defer { IOObjectRelease(root) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        let result = IOServiceAddInterestNotification(
            port, root, kIOGeneralInterest, { context, _, _, _ in
                guard let context else { return }
                let service = Unmanaged<BrightnessService>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak service] in service?.restoreDeferredDisplays() }
            }, Unmanaged.passUnretained(self).toOpaque(), &lidNotification)
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            Self.log.error("could not observe deferred display restoration: \(result)")
            return
        }
        lidNotificationPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        DispatchQueue.main.async { [weak self] in self?.restoreDeferredDisplays() }
    }

    private func restoreDeferredDisplays(retryFailures: Bool = false) {
        guard !displayPowerIsSuspended else { return }
        for id in deferredRestoration.candidates(lidClosed: Self.lidClosed(),
                                                 retryFailures: retryFailures) {
            guard restoreDisplay(id) == .success else { continue }
            stateLock.lock()
            managedDisabledIDs.remove(id)
            managedDisabledDisplays.removeValue(forKey: id)
            stateLock.unlock()
            Self.forgetDisplaySwitchedOff(id)
            refresh(force: true)
        }
    }

    private static func activeDisplayIDs() -> Set<CGDirectDisplayID> {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Set(ids.prefix(Int(count)))
    }

    private static func topology(online: Set<CGDirectDisplayID>) -> BrightnessSupport.DisplayTopology {
        let mirrorSources = Dictionary(uniqueKeysWithValues: online.compactMap { id in
            let source = CGDisplayMirrorsDisplay(id)
            return source == kCGNullDirectDisplay ? nil : (id, source)
        })
        return BrightnessSupport.DisplayTopology(
            online: online,
            active: BrightnessSupport.participatingDisplayIDs(
                activeDisplayIDs: activeDisplayIDs(), mirrorSources: mirrorSources),
            mirrorSources: mirrorSources)
    }

    private static func currentTopology() -> BrightnessSupport.DisplayTopology {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return topology(online: Set(ids.prefix(Int(count))))
    }

    private func recordDiscoveredTopology(online: Set<CGDirectDisplayID>,
                                          active: Set<CGDirectDisplayID>,
                                          mirrorSources: [CGDirectDisplayID: CGDirectDisplayID],
                                          fingerprints: [CGDirectDisplayID: String] = [:]) {
        knownTopology = online
        knownActiveTopology = active
        knownMirrorSources = mirrorSources
        knownDisplayFingerprints = knownDisplayFingerprints.filter {
            online.contains($0.key) || managedDisabledIDs.contains($0.key)
        }
        knownDisplayFingerprints.merge(fingerprints) { _, discovered in discovered }
        let replaced = fingerprints.keys.filter { id in
            guard let original = managedDisabledDisplays[id]?.restorationFingerprint else { return false }
            return original != fingerprints[id]
        }
        if !replaced.isEmpty {
            DispatchQueue.main.async { [weak self] in
                for id in replaced { _ = self?.discardReplacedDisplay(id) }
            }
        }
    }

    private func discardReplacedDisplay(_ id: CGDirectDisplayID) -> Bool {
        let fingerprint = Self.restorationDisplayFingerprint(id)
        stateLock.lock()
        if let fingerprint { knownDisplayFingerprints[id] = fingerprint }
        guard let original = managedDisabledDisplays[id]?.restorationFingerprint,
              let current = knownDisplayFingerprints[id], original != current else {
            stateLock.unlock()
            return false
        }
        managedDisabledIDs.remove(id)
        managedDisabledDisplays.removeValue(forKey: id)
        stateLock.unlock()
        deferredRestoration.record(id, result: .success)
        Self.forgetDisplaySwitchedOff(id)
        syncLidObserver()
        displays.removeAll { $0.id == id && $0.restorationFingerprint == original }
        return true
    }

    func restoreDisplaysBeforeTermination() {
        workQueue.sync { restoreAllGamma() }
        restoreManagedDisplays()
    }

    private func restoreManagedDisplays() {
        stateLock.lock()
        let ids = managedDisabledIDs
        stateLock.unlock()
        for id in ids {
            deferredRestoration.keep(id)
            guard restoreDisplay(id) == .success else { continue }
            stateLock.lock()
            managedDisabledIDs.remove(id)
            managedDisabledDisplays.removeValue(forKey: id)
            stateLock.unlock()
            Self.forgetDisplaySwitchedOff(id)
        }
    }

    private func restoreAllGamma() {
        for id in dimmedDisplays {
            guard let baseline = gammaBaselines[id],
                  Self.displayFingerprint(id) == baseline.fingerprint else { continue }
            CGSetDisplayTransferByTable(id, baseline.count, baseline.red,
                                        baseline.green, baseline.blue)
            Self.log.log("restored gamma baseline for display \(id)")
        }
        gammaBaselines = [:]
        dimmedDisplays = []
    }

    // MARK: - Displays switched off by this app

    private static func rememberDisplaySwitchedOff(_ id: CGDirectDisplayID, fingerprint: String?) {
        let defaults = UserDefaults.standard
        var fingerprints = defaults.dictionary(forKey: DefaultsKey.displaysSwitchedOffFingerprints)
            as? [String: String] ?? [:]
        fingerprints[String(id)] = fingerprint
        if fingerprints.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.displaysSwitchedOffFingerprints)
        } else {
            defaults.set(fingerprints, forKey: DefaultsKey.displaysSwitchedOffFingerprints)
        }
        var stored = defaults.array(forKey: DefaultsKey.displaysSwitchedOff) as? [Int] ?? []
        if !stored.contains(Int(id)) { stored.append(Int(id)) }
        defaults.set(stored, forKey: DefaultsKey.displaysSwitchedOff)
    }

    private static func forgetDisplaySwitchedOff(_ id: CGDirectDisplayID) {
        let defaults = UserDefaults.standard
        let stored = defaults.array(forKey: DefaultsKey.displaysSwitchedOff) as? [Int] ?? []
        let remaining = stored.filter { $0 != Int(id) }
        if remaining.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.displaysSwitchedOff)
            defaults.removeObject(forKey: DefaultsKey.displaysSwitchedOffFingerprints)
        } else {
            defaults.set(remaining, forKey: DefaultsKey.displaysSwitchedOff)
            var fingerprints = defaults.dictionary(forKey: DefaultsKey.displaysSwitchedOffFingerprints)
                as? [String: String] ?? [:]
            fingerprints.removeValue(forKey: String(id))
            if fingerprints.isEmpty {
                defaults.removeObject(forKey: DefaultsKey.displaysSwitchedOffFingerprints)
            } else {
                defaults.set(fingerprints, forKey: DefaultsKey.displaysSwitchedOffFingerprints)
            }
        }
    }

    func restoreDisplaysLeftOff() {
        let stored = UserDefaults.standard.array(forKey: DefaultsKey.displaysSwitchedOff) as? [Int] ?? []
        guard !stored.isEmpty else { return }
        guard DisplayConfigurationBridge.configureEnabled != nil else { return }
        let fingerprints = UserDefaults.standard.dictionary(forKey: DefaultsKey.displaysSwitchedOffFingerprints)
            as? [String: String] ?? [:]
        for id in stored {
            guard let displayID = CGDirectDisplayID(exactly: id) else { continue }
            let currentFingerprint = Self.restorationDisplayFingerprint(displayID)
            let display = BrightnessDisplay(
                id: displayID,
                name: Self.displayName(displayID, info: Self.displayInfoDictionary(displayID),
                                       screenNames: [:]),
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                method: nil, isActive: false, brightness: 1, readable: false,
                restorationFingerprint: fingerprints[String(displayID)])
            stateLock.lock()
            if let currentFingerprint {
                knownDisplayFingerprints[displayID] = currentFingerprint
            }
            managedDisabledIDs.insert(displayID)
            if managedDisabledDisplays[displayID] == nil {
                managedDisabledDisplays[displayID] = display
            }
            stateLock.unlock()
            deferredRestoration.keep(displayID)
            guard restoreDisplay(displayID) == .success else { continue }
            stateLock.lock()
            managedDisabledIDs.remove(displayID)
            managedDisabledDisplays.removeValue(forKey: displayID)
            stateLock.unlock()
            Self.forgetDisplaySwitchedOff(displayID)
        }
    }

    // MARK: - Brightness keys (follow the pointer)

    private func syncKeyTap() {
        guard !tapsAreSuspended() else { return }
        let defaults = UserDefaults.standard
        let wantsKeyRouting = defaults.bool(forKey: DefaultsKey.brightnessKeysEnabled)
        let wantsBrightnessOSD = BrightnessSupport.overlayReplacesNative(
            overlayEnabled: defaults.bool(forKey: DefaultsKey.brightnessOSDEnabled),
            islandRoutes: NotchSupport.routes(.brightness),
            islandShowsNotices: NotchService.shared.acceptsSystemFeedback
                && !NotchSupport.hidesNoticesUntilHover(in: defaults)) && brightnessOSDSupported
        let wantsKeyboardLight = NotchSupport.routes(.keyboardLight) && keyboardLightBridge != nil
        if !wantsKeyboardLight || !SessionActivity.shared.isActive {
            keyboardNoticeWork?.cancel(); keyboardNoticeWork = nil
        }
        let keyStep = self.keyStep
        let wantsFinerSteps = keyStep != .standard
        let wanted = SessionActivitySupport.tapShouldRun(
            featureWanted: (running && (wantsKeyRouting || wantsBrightnessOSD || wantsFinerSteps))
                || wantsKeyboardLight,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive)
        if wanted { installKeyTap() } else { removeKeyTap() }
        if wanted, running, BrightnessSupport.answersPlainBrightnessKeys(followsPointer: wantsKeyRouting,
                                                                          overlayReplacesNative: wantsBrightnessOSD,
                                                                          finerSteps: wantsFinerSteps) {
            let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
                .dictionary(forKey: "AppleSymbolicHotKeys")
            let adjusts = BrightnessSupport.functionKeysAdjustBrightness(symbolicHotKeys: hotKeys)
            let overlayReplaces = wantsBrightnessOSD
            let systemTarget = systemKeyTarget?.id
            keyThreadLock.withLock {
                functionKeysAdjustBrightness = adjusts
                overlayReplacesNativeOSD = overlayReplaces
                functionKeysFollowPointer = wantsKeyRouting
                functionKeySystemTarget = systemTarget
                functionKeyStep = keyStep
            }
            installFunctionKeyTap()
        } else {
            removeFunctionKeyTap()
        }
    }

    private var systemKeyTarget: BrightnessDisplay? {
        displays.first(where: { $0.isBuiltIn && $0.isActive && $0.method == .system })
            ?? displays.first(where: { $0.isActive && $0.method == .system })
    }

    private func installKeyTap() {
        guard !tapsAreSuspended(), keyTap == nil else { return }
        let systemDefined = CGEventType(rawValue: SystemKeyEvents.systemDefinedEventTypeRawValue)!
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<BrightnessService>.fromOpaque(userInfo).takeUnretainedValue()
            return service.handleKeyEvent(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(1 << systemDefined.rawValue),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        keyTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        keyTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeKeyTap() {
        guard let tap = keyTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let keyTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTapSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        keyTapSource = nil
        keyTap = nil
        keyOwnership = BrightnessSupport.BrightnessKeyOwnership()
        swallowedMediaKeys.removeAll()
    }

    // MARK: - Brightness keys on other keyboards

    func suspendInputTaps() {
        keyThreadLock.withLock { inputTapsSuspended = true }
        removeKeyTap()
        removeFunctionKeyTap()
    }

    func resumeInputTaps() {
        keyThreadLock.withLock { inputTapsSuspended = false }
        syncKeyTap()
    }

    private func installFunctionKeyTap() {
        let thread = keyThreadLock.withLock { () -> Thread? in
            guard !inputTapsSuspended else { return nil }
            if functionKeyThread != nil {
                if shouldStopFunctionKeyThread { pendingFunctionKeyRestart = true }
                return nil
            }
            shouldStopFunctionKeyThread = false
            pendingFunctionKeyRestart = false
            let thread = Thread { [weak self] in self?.runFunctionKeyTap() }
            thread.name = "EVERYTHING Brightness Keys"
            thread.qualityOfService = .userInteractive
            functionKeyThread = thread
            return thread
        }
        thread?.start()
    }

    private func removeFunctionKeyTap() {
        let snapshot = keyThreadLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopFunctionKeyThread = true
            pendingFunctionKeyRestart = false
            swallowedKeyCodes.removeAll()
            return (functionKeyRunLoop, functionKeyTap, functionKeyThread != nil)
        }
        if let tap = snapshot.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            keyThreadLock.withLock {
                shouldStopFunctionKeyThread = false
                functionKeyThread = nil
            }
        }
    }

    private func runFunctionKeyTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            keyThreadLock.withLock { functionKeyRunLoop = runLoop }
            let stopBeforeCreating = keyThreadLock.withLock { shouldStopFunctionKeyThread }
            guard !stopBeforeCreating else {
                if clearFunctionKeyThread() { installFunctionKeyTap() }
                return
            }
            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<BrightnessService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.routeFunctionKey(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearFunctionKeyThread()
                return
            }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            keyThreadLock.withLock { functionKeyTap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            if keyThreadLock.withLock({ shouldStopFunctionKeyThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if clearFunctionKeyThread() { installFunctionKeyTap() }
        }
    }

    private func clearFunctionKeyThread() -> Bool {
        keyThreadLock.withLock {
            let restart = pendingFunctionKeyRestart
            functionKeyTap = nil
            functionKeyRunLoop = nil
            functionKeyThread = nil
            shouldStopFunctionKeyThread = false
            pendingFunctionKeyRestart = false
            swallowedKeyCodes.removeAll()
            return restart
        }
    }

    private func routeFunctionKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let shouldSync = keyThreadLock.withLock { () -> Bool in
                guard SessionActivity.shared.isActive, AXIsProcessTrusted(),
                      !shouldStopFunctionKeyThread, let tap = functionKeyTap else {
                    return true
                }
                guard !inputTapsSuspended else { return false }
                CGEvent.tapEnable(tap: tap, enable: true)
                return false
            }
            if shouldSync {
                DispatchQueue.main.async { [weak self] in self?.syncKeyTap() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard !tapsAreSuspended() else {
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard BrightnessSupport.isBrightnessKeyCode(keyCode) else {
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else {
            let consumed = keyThreadLock.withLock { swallowedKeyCodes.remove(keyCode) != nil }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let consumed = keyThreadLock.withLock {
            if !isRepeat { swallowedKeyCodes.remove(keyCode) }
            return swallowedKeyCodes.contains(keyCode)
        }
        if isRepeat, !consumed { return Unmanaged.passUnretained(event) }
        let (adjusts, keyStep) = keyThreadLock.withLock { (functionKeysAdjustBrightness, functionKeyStep) }
        let modifiers = event.flags.intersection([.maskCommand, .maskControl,
                                                  .maskAlternate, .maskShift])
        guard let press = BrightnessSupport.brightnessFunctionKeyEvent(
            keyCode: keyCode,
            isKeyDown: true,
            isRepeat: isRepeat,
            hasModifiers: !modifiers.isEmpty,
            functionKeysAdjustBrightness: adjusts)
        else { return consumed ? nil : Unmanaged.passUnretained(event) }
        func leaveToSystem() -> Unmanaged<CGEvent>? {
            guard let count = keyStep.systemQuarterSteps else {
                return consumed ? nil : Unmanaged.passUnretained(event)
            }
            keyThreadLock.withLock { _ = swallowedKeyCodes.insert(keyCode) }
            let increase = press.delta > 0
            DispatchQueue.main.async { Self.postSystemQuarterSteps(increase: increase, count: count) }
            return nil
        }

        let (followsPointer, systemTarget, overlayReplacesNative) = keyThreadLock.withLock {
            (functionKeysFollowPointer, functionKeySystemTarget, overlayReplacesNativeOSD)
        }
        var pointerDisplay: CGDirectDisplayID = 0
        var matched: UInt32 = 0
        let underPointer = followsPointer
            && CGGetDisplaysWithPoint(event.location, 1, &pointerDisplay, &matched) == .success && matched > 0
        guard let displayID = BrightnessSupport.plainKeyTarget(followsPointer: followsPointer,
                                                               pointerDisplay: underPointer ? pointerDisplay : nil,
                                                               systemTarget: systemTarget)
        else { return leaveToSystem() }

        stateLock.lock()
        let route = routes[displayID]
        stateLock.unlock()
        guard let route, followsPointer || route.method == .system else { return leaveToSystem() }
        if route.method == .system {
            guard BrightnessSupport.stepsSystemRoutedDisplay(
                followsPointer: followsPointer,
                displayIsBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                overlayReplacesNative: overlayReplacesNative
            ), BrightnessBridge.setBrightness != nil else {
                return leaveToSystem()
            }
        }
        keyThreadLock.withLock { _ = swallowedKeyCodes.insert(keyCode) }
        DispatchQueue.main.async { [weak self] in
            self?.applyKeyStep(press, to: displayID, method: route.method)
        }
        return nil
    }

    private func applyKeyStep(_ press: BrightnessSupport.BrightnessKeyEvent,
                              to displayID: CGDirectDisplayID,
                              method: BrightnessDisplay.Method) {
        let showOSD = UserDefaults.standard.bool(forKey: DefaultsKey.brightnessOSDEnabled)
        step(displayID, method: method, delta: keyStep.limited(press.delta), showOSD: showOSD)
    }

    private static func postSystemQuarterSteps(increase: Bool, count: Int) {
        for event in BrightnessSupport.systemQuarterStepEvents(increase: increase, count: count) {
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func step(_ displayID: CGDirectDisplayID,
                      method: BrightnessDisplay.Method,
                      delta: Double,
                      showOSD: Bool) {
        focusKeyDisplay(displayID)
        let cached = displays.first(where: { $0.id == displayID })?.brightness
        if method == .system {
            guard let current = currentSystemBrightness(for: displayID, fallback: cached) else { return }
            commitStep(from: current, delta: delta, to: displayID, method: method, showOSD: showOSD)
            return
        }
        stateLock.lock()
        let known = levelKnownAt[displayID]
        let route = routes[displayID]
        stateLock.unlock()
        let fresh = BrightnessSupport.trustsRememberedLevel(lastKnownAt: known, now: Date(),
                                                            window: Self.levelTrustWindow)
        guard method == .ddc, let route, route.ddcReadable, !fresh,
              (!route.extendedDimming || (cached ?? 1) >= BrightnessSupport.extendedDimmingRange),
              let service = route.service else {
            guard let current = cached else { return }
            commitStep(from: current, delta: delta, to: displayID, method: method, showOSD: showOSD)
            return
        }
        if ddcPendingSteps[displayID] != nil {
            ddcPendingSteps[displayID, default: 0] += delta
            return
        }
        ddcPendingSteps[displayID] = 0
        workQueue.async { [weak self] in
            guard let self else { return }
            let probe = self.ddcProbeLuminance(for: displayID, service: service)
            if case let .replied(value, _) = probe {
                self.stateLock.lock()
                if self.routes[displayID]?.ddcPathKey == route.ddcPathKey,
                   self.routes[displayID]?.extendedDimming == route.extendedDimming {
                    self.routes[displayID]?.lastDDCValue = value
                }
                self.stateLock.unlock()
                self.forgetWriteOnlyDDCPath(route.ddcPathKey)
            } else {
                if case .writeOnly = probe {
                    self.rememberWriteOnlyDDCPath(route.ddcPathKey)
                }
                self.stateLock.lock()
                if self.routes[displayID]?.ddcPathKey == route.ddcPathKey {
                    self.routes[displayID]?.ddcReadable = false
                    self.routes[displayID]?.lastDDCValue = nil
                }
                self.stateLock.unlock()
                Self.log.log("ddc reads stopped answering for display \(displayID); future steps will write only")
            }
            DispatchQueue.main.async {
                let queued = self.ddcPendingSteps.removeValue(forKey: displayID) ?? 0
                var current = cached
                self.stateLock.lock()
                let superseded = self.levelKnownAt[displayID] != known
                let routeChanged = self.routes[displayID]?.ddcPathKey != route.ddcPathKey
                    || self.routes[displayID]?.extendedDimming != route.extendedDimming
                self.stateLock.unlock()
                guard !routeChanged else { return }
                if superseded {
                    current = self.displays.first(where: { $0.id == displayID })?.brightness ?? cached
                } else if case let .replied(value, maximum) = probe {
                    let hardware = BrightnessSupport.normalized(
                        current: value, maximum: BrightnessSupport.sanitizedMaximum(maximum))
                    let level = route.extendedDimming
                        ? BrightnessSupport.extendedDimmingLevel(
                            hardware: hardware, remembered: nil, pictureDimmed: false)
                        : hardware
                    Self.log.log("display \(displayID) reads \(level) before stepping")
                    current = level
                    if let index = self.displays.firstIndex(where: { $0.id == displayID }) {
                        self.displays[index].brightness = level
                    }
                }
                guard let current else { return }
                self.commitStep(from: current, delta: delta + queued, to: displayID,
                                method: method, showOSD: showOSD)
            }
        }
    }

    private func commitStep(from current: Double,
                            delta: Double,
                            to displayID: CGDirectDisplayID,
                            method: BrightnessDisplay.Method,
                            showOSD: Bool) {
        let stepped = BrightnessSupport.steppedBrightness(current, delta: delta)
        Self.log.log("key step display \(displayID) route \(String(describing: method), privacy: .public) \(current) to \(stepped)")
        setBrightness(stepped, for: displayID, showOSD: showOSD, smooth: true)
    }

    private func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !tapsAreSuspended() else { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let keyTap {
                CGEvent.tapEnable(tap: keyTap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncKeyTap() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == SystemKeyEvents.systemDefinedEventTypeRawValue,
              let nsEvent = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
        if BrightnessSupport.isKeyboardLightPress(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1) {
            let modifiers = nsEvent.modifierFlags
            if modifiers.intersection([.command, .control]).isEmpty,
               !modifiers.contains(.option) || modifiers.contains(.shift) {
                scheduleKeyboardLightNotice()
            }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != BrightnessSupport.systemQuarterStepMarker else {
            return Unmanaged.passUnretained(event)
        }
        guard running, let press = BrightnessSupport.brightnessKeyEvent(subtype: Int(nsEvent.subtype.rawValue),
                                                               data1: nsEvent.data1)
        else { return Unmanaged.passUnretained(event) }
        let owner = keyOwnership.owner(
            of: press,
            option: event.flags.contains(.maskAlternate),
            shift: event.flags.contains(.maskShift),
            commandOrControl: !event.flags.isDisjoint(with: [.maskCommand, .maskControl]))
        let increases = press.delta > 0
        guard press.isKeyDown else {
            return swallowedMediaKeys.remove(increases) != nil ? nil : Unmanaged.passUnretained(event)
        }
        if !press.isRepeat { swallowedMediaKeys.remove(increases) }
        let consumed = swallowedMediaKeys.contains(increases)
        if press.isRepeat, !consumed { return Unmanaged.passUnretained(event) }
        guard case .app(let ownedDelta) = owner
        else { return Unmanaged.passUnretained(event) }

        let defaults = UserDefaults.standard
        let followsPointer = defaults.bool(forKey: DefaultsKey.brightnessKeysEnabled)
        let showsOverlay = defaults.bool(forKey: DefaultsKey.brightnessOSDEnabled)
        let keyStep = self.keyStep
        let delta = keyStep.limited(ownedDelta)
        func leaveToSystem() -> Unmanaged<CGEvent>? {
            guard let count = BrightnessSupport.systemQuarterSteps(
                for: keyStep, command: event.flags.contains(.maskCommand),
                control: event.flags.contains(.maskControl),
                option: event.flags.contains(.maskAlternate))
            else { return consumed ? nil : Unmanaged.passUnretained(event) }
            swallowedMediaKeys.insert(increases)
            Self.postSystemQuarterSteps(increase: increases, count: count)
            return nil
        }
        let wantsBrightnessOSD = BrightnessSupport.overlayReplacesNative(
            overlayEnabled: showsOverlay, islandRoutes: NotchSupport.routes(.brightness),
            islandShowsNotices: NotchService.shared.showsSystemFeedback)
        let displayID: CGDirectDisplayID
        if followsPointer {
            let pointer = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: {
                NSMouseInRect(pointer, $0.frame, false)
            }), let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                           as? NSNumber)?.uint32Value else {
                return leaveToSystem()
            }
            displayID = id
        } else if wantsBrightnessOSD, let systemTarget = systemKeyTarget {
            displayID = systemTarget.id
        } else {
            return leaveToSystem()
        }

        stateLock.lock()
        let route = routes[displayID]
        stateLock.unlock()
        guard let route else { return leaveToSystem() }
        if route.method == .system {
            let isBuiltIn = displays.first(where: { $0.id == displayID })?.isBuiltIn
                ?? (CGDisplayIsBuiltin(displayID) != 0)
            guard BrightnessSupport.stepsSystemRoutedDisplay(
                followsPointer: followsPointer,
                displayIsBuiltIn: isBuiltIn,
                overlayReplacesNative: wantsBrightnessOSD && brightnessOSDSupported
            ), BrightnessBridge.setBrightness != nil else {
                return leaveToSystem()
            }
            swallowedMediaKeys.insert(increases)
            focusKeyDisplay(displayID)
            if let current = currentSystemBrightness(
                for: displayID,
                fallback: displays.first(where: { $0.id == displayID })?.brightness
            ) {
                let stepped = BrightnessSupport.steppedBrightness(current, delta: delta)
                Self.log.log("key step display \(displayID) route system \(current) to \(stepped)")
                setBrightness(stepped, for: displayID, showOSD: showsOverlay, smooth: true)
            }
            return nil
        }
        guard followsPointer else {
            return leaveToSystem()
        }
        swallowedMediaKeys.insert(increases)
        step(displayID, method: route.method, delta: delta, showOSD: showsOverlay)
        return nil
    }

    private func currentSystemBrightness(for id: CGDirectDisplayID,
                                         fallback: Double?) -> Double? {
        stateLock.lock()
        let queued = pendingLevels[id]?.value
        let requested = systemWritesInFlight.contains(id) ? rememberedLevel(for: id) : nil
        stateLock.unlock()
        if let queued { return queued }
        if let requested { return requested }
        var live: Float = -1
        if CGDisplayIsAsleep(id) == 0, let read = BrightnessBridge.getBrightness,
           read(id, &live) == 0, live >= 0, live <= 1 {
            return Double(live)
        }
        return fallback
    }

    // MARK: - Screen changes

    private func screensChanged() {
        guard running, !displayPowerIsSuspended, rebuildDebounce == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.rebuildDebounce = nil
            guard self.running, !self.displayPowerIsSuspended else { return }
            let reapplied = self.reapplyManagedDisplayDisables()
            let topology = Self.currentTopology()
            self.stateLock.lock()
            let changed = topology.online != self.knownTopology
                || topology.active != self.knownActiveTopology
                || topology.mirrorSources != self.knownMirrorSources
            self.stateLock.unlock()
            if changed || reapplied {
                Self.log.log("topology changed to \(topology.online.sorted().map(String.init).joined(separator: ","), privacy: .public); rebuilding")
                let drawable = Self.drawableDisplayIDs(online: topology.online,
                                                       active: topology.active)
                if Self.lidClosed() == true
                    || !self.restoreManagedDisplayIfHeadless(drawableDisplayIDs: drawable) {
                    self.refresh()
                }
            }
        }
        rebuildDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func restoreManagedDisplayIfHeadless(drawableDisplayIDs: Set<CGDirectDisplayID>) -> Bool {
        guard running, !displayPowerIsSuspended, Self.lidClosed() != true else { return false }
        stateLock.lock()
        let candidates = BrightnessSupport.headlessRecoveryCandidates(
            drawableDisplayIDs: drawableDisplayIDs,
            managedDisabledIDs: managedDisabledIDs,
            builtInDisabledIDs: Set(managedDisabledDisplays.values
                .filter(\.isBuiltIn).map(\.id)))
        stateLock.unlock()
        guard !candidates.isEmpty else { return false }

        pendingDisplayIDs.formUnion(candidates)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.running, !self.displayPowerIsSuspended, Self.lidClosed() != true else {
                self.pendingDisplayIDs.subtract(candidates)
                return
            }
            let topology = Self.currentTopology()
            guard Self.drawableDisplayIDs(online: topology.online, active: topology.active).isEmpty else {
                self.pendingDisplayIDs.subtract(candidates)
                self.refresh(force: true)
                return
            }
            self.stateLock.lock()
            let stillDisabled = candidates.filter { self.managedDisabledIDs.contains($0) }
            self.stateLock.unlock()
            defer { self.pendingDisplayIDs.subtract(candidates) }
            guard !stillDisabled.isEmpty else { return }
            self.performHeadlessDisplayRestoration(candidates: stillDisabled)
        }
        return true
    }

    private func performHeadlessDisplayRestoration(candidates: [CGDirectDisplayID]) {
        defer { pendingDisplayIDs.subtract(candidates) }
        var restored: CGDirectDisplayID?
        var failure: DisplayControlFailure = .closedLid
        for id in candidates {
            stateLock.lock()
            let stillDisabled = managedDisabledIDs.contains(id)
            stateLock.unlock()
            guard stillDisabled else { continue }
            if discardReplacedDisplay(id) {
                failure = .failed
                continue
            }
            let result: BrightnessSupport.DisplayConfigurationResult = canRestoreDisplay(id)
                ? Self.configureDisplay(id, enabled: true) : .failed
            deferredRestoration.recordHeadless(id, result: result)
            syncLidObserver()
            if result == .success { displayControlFailure = nil }
            if result == .success {
                restored = id
                break
            }
            if result == .failed { failure = .failed }
        }
        if let restored {
            deferredRestoration.cancelHeadless()
            syncLidObserver()
            stateLock.lock()
            managedDisabledIDs.remove(restored)
            managedDisabledDisplays.removeValue(forKey: restored)
            stateLock.unlock()
            Self.forgetDisplaySwitchedOff(restored)
            Self.log.log("restored display \(restored) after the active display set became empty")
        } else {
            Self.log.error("could not restore a display after the active display set became empty")
        }
        displayControlFailure = restored == nil ? failure : nil
        refresh(force: true)
    }

    // MARK: - Waking up

    private func installWakeObservers() {
        guard wakeObservers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        wakeObservers = [NSWorkspace.didWakeNotification,
                         NSWorkspace.screensDidWakeNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.displaysWokeUp()
            }
        }
        wakeObservers += [NSWorkspace.willSleepNotification,
                          NSWorkspace.screensDidSleepNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.displaysWillSleep()
            }
        }
    }

    private func removeWakeObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in wakeObservers { workspace.removeObserver(observer) }
        wakeObservers = []
        wakeRebuild?.cancel()
        wakeRebuild = nil
        displayPowerIsSuspended = false
    }

    private func displaysWillSleep() {
        displayPowerIsSuspended = true
        wakeRebuild?.cancel()
        wakeRebuild = nil
        rebuildDebounce?.cancel()
        rebuildDebounce = nil
        stateLock.lock()
        rebuildGeneration += 1
        rebuildingTopology = nil
        stateLock.unlock()
    }

    private func displaysWokeUp() {
        guard running || !deferredRestoration.ids.isEmpty else { return }
        displayPowerIsSuspended = true
        rebuildDebounce?.cancel()
        rebuildDebounce = nil
        wakeRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running || !self.deferredRestoration.ids.isEmpty else { return }
            self.wakeRebuild = nil
            self.displayPowerIsSuspended = false
            self.restoreDeferredDisplays(retryFailures: true)
            guard self.running else { return }
            _ = self.reapplyManagedDisplayDisables()
            Self.log.log("woke from sleep; rebuilding display routes")
            let topology = Self.currentTopology()
            let drawable = Self.drawableDisplayIDs(online: topology.online, active: topology.active)
            if self.restoreManagedDisplayIfHeadless(drawableDisplayIDs: drawable) { return }
            self.refresh(force: true)
        }
        wakeRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeSettleDelay, execute: work)
    }

    private func reapplyManagedDisplayDisables() -> Bool {
        guard running, !displayPowerIsSuspended else { return false }
        var reapplied = false
        stateLock.lock()
        let disabled = managedDisabledDisplays
        stateLock.unlock()
        for (id, display) in disabled.sorted(by: { $0.key < $1.key }) {
            guard !deferredRestoration.ids.contains(id), !pendingDisplayIDs.contains(id) else { continue }
            if !display.isBuiltIn {
                guard let original = display.restorationFingerprint,
                      Self.restorationDisplayFingerprint(id) == original else { continue }
            }
            let topology = Self.currentTopology()
            let drawable = Self.drawableDisplayIDs(online: topology.online, active: topology.active)
            guard BrightnessSupport.canDisableDisplay(drawableDisplayIDs: drawable, target: id) else { continue }
            let result = Self.configureDisplay(id, enabled: false)
            guard result == .success else {
                Self.log.error("could not reapply disabled state for display \(id); keeping the saved choice")
                continue
            }
            stateLock.lock()
            knownActiveTopology.remove(id)
            pendingLevels.removeValue(forKey: id)
            stateLock.unlock()
            reapplied = true
            Self.log.log("reapplied disabled state for display \(id) after a connection change")
        }
        return reapplied
    }

    // MARK: - Rebuild (work queue)

    private func rebuild(generation: Int, previousDisplays: [BrightnessDisplay],
                         screenNames: [CGDirectDisplayID: String]) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        let onlineIDs = Array(ids.prefix(Int(count)))
        let fingerprints = Dictionary(uniqueKeysWithValues: onlineIDs.compactMap { id in
            Self.restorationDisplayFingerprint(id).map { (id, $0) }
        })

        let seenTopology = Set(onlineIDs)
        let topology = Self.topology(online: seenTopology)
        let activeTopology = topology.active
        var built: [BrightnessDisplay] = []
        var newRoutes: [CGDirectDisplayID: Route] = [:]
        var ddcCandidates: [(index: Int, identity: BrightnessSupport.DisplayIdentity)] = []
        var virtualIDs = Set<CGDirectDisplayID>()

        for id in onlineIDs {
            let info = Self.displayInfoDictionary(id)
            if (info?["kCGDisplayIsVirtualDevice"] as? Bool ?? false) { virtualIDs.insert(id) }
            if let info,
               (info["kCGDisplayIsVirtualDevice"] as? Bool ?? false)
                || (info["kCGDisplayIsAirPlay"] as? Bool ?? false) {
                continue
            }
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let name = Self.displayName(id, info: info, screenNames: screenNames)
            let isActive = activeTopology.contains(id)

            if !isActive {
                stateLock.lock()
                let level = rememberedLevel(for: id) ?? 1.0
                stateLock.unlock()
                built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: isBuiltIn,
                                               method: nil, isActive: false,
                                               brightness: level, readable: false))
                continue
            }

            let asleep = CGDisplayIsAsleep(id) != 0
            var level: Float = -1
            if let read = BrightnessBridge.getBrightness,
               read(id, &level) == 0, level >= 0, level <= 1 {
                stateLock.lock()
                let remembered = rememberedLevel(for: id)
                stateLock.unlock()
                let trusted = asleep ? (remembered ?? Double(level)) : Double(level)
                built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: isBuiltIn,
                                               method: .system, isActive: true,
                                               brightness: trusted, readable: !asleep))
                newRoutes[id] = Route(method: .system, service: nil, maximum: 100)
                if !asleep {
                    stateLock.lock()
                    levelKnownAt[id] = Date()
                    stateLock.unlock()
                }
                continue
            }
            guard !isBuiltIn else { continue }
            ddcCandidates.append((built.count, Self.displayIdentity(id, info: info)))
            built.append(BrightnessDisplay(id: id, name: name, isBuiltIn: false,
                                           method: .ddc, isActive: true,
                                           brightness: 0.5, readable: false))
        }

        let drawableIDs = BrightnessSupport.drawableDisplayIDs(
            onlineDisplayIDs: seenTopology, activeDisplayIDs: activeTopology,
            virtualDisplayIDs: virtualIDs)

        stateLock.lock()
        let disabledSnapshots = managedDisabledDisplays
        let previousTopology = knownTopology
        let topologyChanged = seenTopology != knownTopology
            || activeTopology != knownActiveTopology
            || topology.mirrorSources != knownMirrorSources
        let discoveryIsCurrent = generation == rebuildGeneration
        let canPublishDiscovery = discoveryIsCurrent && topologyChanged
        if discoveryIsCurrent {
            recordDiscoveredTopology(online: seenTopology, active: activeTopology,
                                     mirrorSources: topology.mirrorSources,
                                     fingerprints: fingerprints)
        }
        stateLock.unlock()
        for (id, display) in disabledSnapshots where !seenTopology.contains(id) {
            built.append(display)
        }

        if canPublishDiscovery {
            let previousByID = Dictionary(uniqueKeysWithValues: previousDisplays.map { ($0.id, $0) })
            let discovered = built.map { display -> BrightnessDisplay in
                guard display.isActive,
                      let previous = previousByID[display.id], previous.isActive else {
                    var pending = display
                    if pending.isActive { pending.method = nil }
                    return pending
                }
                return BrightnessDisplay(id: display.id, name: display.name,
                                         isBuiltIn: display.isBuiltIn,
                                         method: previous.method, isActive: true,
                                         brightness: previous.brightness,
                                         readable: previous.readable,
                                         canChooseDimming: previous.canChooseDimming)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, generation == self.rebuildGeneration else { return }
                if self.displays != discovered { self.displays = discovered }
                if self.drawableDisplays != drawableIDs { self.drawableDisplays = drawableIDs }
            }
        }

        var softwareIndices = Set(ddcCandidates.map(\.index))
        var forcedSoftwareIDs = Set<CGDirectDisplayID>()
        var extendedDimmingIDs = Set<CGDirectDisplayID>()
        var softwarePathKeys: [CGDirectDisplayID: String] = [:]
        if !ddcCandidates.isEmpty, BrightnessBridge.ddcAvailable {
            let services = Self.externalServices()
            var scores: [(displayIndex: Int, serviceOrdinal: Int, score: Int)] = []
            for candidate in ddcCandidates {
                for service in services {
                    scores.append((candidate.index, service.identity.ordinal,
                                   BrightnessSupport.matchScore(service: service.identity,
                                                                display: candidate.identity)))
                }
            }
            var assignment = BrightnessSupport.assignServices(scores: scores)
            if assignment.isEmpty, ddcCandidates.count == 1, services.count == 1 {
                assignment = [ddcCandidates[0].index: services[0].identity.ordinal]
            }
            for candidate in ddcCandidates {
                guard let ordinal = assignment[candidate.index],
                      let matched = services.first(where: { $0.identity.ordinal == ordinal }) else {
                    continue
                }
                let id = built[candidate.index].id
                let ioDisplayLocation = candidate.identity.ioDisplayLocation.flatMap {
                    $0.isEmpty ? nil : $0
                } ?? matched.identity.ioDisplayLocation
                let pathKey = BrightnessSupport.ddcPathKey(
                    displayFingerprint: Self.displayFingerprint(id),
                    ioDisplayLocation: ioDisplayLocation)
                if let pathKey, forcedSoftwarePaths().contains(pathKey) {
                    forcedSoftwareIDs.insert(id)
                    softwarePathKeys[id] = pathKey
                    continue
                }
                let rememberedWriteOnly = !BrightnessSupport.shouldProbeDDC(
                    pathKey: pathKey, writeOnlyPaths: writeOnlyDDCPaths())
                let probe: DDCProbe
                if rememberedWriteOnly {
                    probe = .writeOnly
                    Self.log.log("ddc cached display \(id): writeOnly")
                } else {
                    probe = ddcProbeLuminance(for: id, service: matched.service,
                                              classifyingChannel: true)
                    Self.log.log("ddc probe display \(id): \(String(describing: probe), privacy: .public)")
                }
                switch probe {
                case .replied(let current, let maximum):
                    forgetWriteOnlyDDCPath(pathKey)
                    let ceiling = BrightnessSupport.sanitizedMaximum(maximum)
                    let hardware = BrightnessSupport.normalized(current: current, maximum: ceiling)
                    let wantsExtendedDimming = pathKey.map {
                        extendedDimmingPaths().contains($0)
                    } ?? false
                    if wantsExtendedDimming { extendedDimmingIDs.insert(id) }
                    if wantsExtendedDimming { captureGammaBaselineIfNeeded(id) }
                    let extendsDimming = wantsExtendedDimming
                        && gammaBaselines[id]?.fingerprint == Self.displayFingerprint(id)
                    stateLock.lock()
                    let remembered = rememberedLevel(for: id)
                    stateLock.unlock()
                    var level = extendsDimming
                        ? BrightnessSupport.extendedDimmingLevel(
                            hardware: hardware, remembered: remembered,
                            pictureDimmed: dimmedDisplays.contains(id))
                        : hardware
                    if extendsDimming {
                        if !previousTopology.contains(id) {
                            level = BrightnessSupport.reconnectedDimLevel(level)
                        }
                        let picture = BrightnessSupport.extendedDimmingComponents(for: level).picture
                        if picture < 0.999 || dimmedDisplays.contains(id) {
                            _ = applySoftwareDim(id, value: picture)
                        }
                    }
                    built[candidate.index] = BrightnessDisplay(
                        id: id, name: built[candidate.index].name, isBuiltIn: false,
                        method: .ddc, isActive: true, brightness: level,
                        readable: true, canChooseDimming: pathKey != nil)
                    newRoutes[id] = Route(method: .ddc, service: matched.service,
                                          maximum: ceiling, ddcReadable: true,
                                          ddcPathKey: pathKey, extendedDimming: extendsDimming,
                                          lastDDCValue: current)
                    stateLock.lock()
                    levelKnownAt[id] = Date()
                    stateLock.unlock()
                    softwareIndices.remove(candidate.index)
                case .writeOnly:
                    if let pathKey, extendedDimmingPaths().contains(pathKey) {
                        extendedDimmingIDs.insert(id)
                    }
                    rememberWriteOnlyDDCPath(pathKey)
                    stateLock.lock()
                    let remembered = rememberedLevel(for: id) ?? 0.5
                    let seed = routes[id]?.extendedDimming == true
                        ? BrightnessSupport.extendedDimmingComponents(for: remembered).hardware
                        : remembered
                    stateLock.unlock()
                    built[candidate.index] = BrightnessDisplay(
                        id: id, name: built[candidate.index].name, isBuiltIn: false,
                        method: .ddc, isActive: true, brightness: seed,
                        readable: false, canChooseDimming: pathKey != nil)
                    newRoutes[id] = Route(method: .ddc, service: matched.service,
                                          maximum: 100, ddcPathKey: pathKey)
                    softwareIndices.remove(candidate.index)
                case .dead:
                    forgetWriteOnlyDDCPath(pathKey)
                    break
                }
            }
        }

        if gammaBaselines.count > Self.rememberedGammaBaselines {
            gammaBaselines = gammaBaselines.filter { seenTopology.contains($0.key) }
        }
        for index in softwareIndices.sorted() {
            let id = built[index].id
            stateLock.lock()
            let remembered = rememberedLevel(for: id)
            let previousExtended = routes[id]?.extendedDimming == true
            let softwareLevel = previousExtended
                ? remembered.map { BrightnessSupport.extendedDimmingComponents(for: $0).picture }
                : remembered
            var value = BrightnessSupport.softwareDimToRestore(
                remembered: softwareLevel,
                appliedByApp: dimmedDisplays.contains(id))
            stateLock.unlock()
            captureGammaBaselineIfNeeded(id)
            guard gammaBaselines[id] != nil else { continue }
            if !previousTopology.contains(id) {
                let floored = BrightnessSupport.reconnectedDimLevel(value)
                if floored != value {
                    Self.log.log("display \(id) returned dimmed to \(value); raising to \(floored)")
                    value = floored
                }
            }
            built[index] = BrightnessDisplay(
                id: id, name: built[index].name, isBuiltIn: false,
                method: .software, isActive: true, brightness: value, readable: true,
                canChooseDimming: softwarePathKeys[id] != nil)
            newRoutes[id] = Route(method: .software, service: nil, maximum: 100,
                                  ddcPathKey: softwarePathKeys[id])
            if value < 0.999 || dimmedDisplays.contains(id) {
                _ = applySoftwareDim(id, value: value)
            }
        }
        for id in Array(dimmedDisplays) where newRoutes[id]?.method != .software
            && newRoutes[id]?.extendedDimming != true {
            _ = applySoftwareDim(id, value: 1)
        }
        var resolved: [BrightnessDisplay] = []
        var supportsBrightnessOSD = false
        let stale: Bool
        stateLock.lock()
        stale = generation != rebuildGeneration
        if !stale {
            resolved = built.compactMap { display -> BrightnessDisplay? in
                if !display.isActive || newRoutes[display.id] != nil { return display }
                guard DisplayConfigurationBridge.configureEnabled != nil else { return nil }
                var display = display
                display.method = nil
                return display
            }
            for index in resolved.indices {
                let id = resolved[index].id
                resolved[index].brightness = BrightnessSupport.brightnessAfterRebuild(
                    probed: resolved[index].brightness,
                    pending: pendingLevels[id]?.value)
            }
            supportsBrightnessOSD = resolved.contains { display in
                guard display.isActive, newRoutes[display.id] != nil else { return false }
                switch display.method {
                case .system:
                    return BrightnessBridge.setBrightness != nil
                case .ddc, .software:
                    return true
                case nil:
                    return false
                }
            }
            routes = newRoutes
            recordDiscoveredTopology(online: seenTopology, active: activeTopology,
                                     mirrorSources: topology.mirrorSources,
                                     fingerprints: fingerprints)
            rebuildingTopology = nil
            for display in resolved where display.method != nil {
                lastApplied[display.id] = RememberedLevel(
                    value: display.brightness,
                    fingerprint: Self.displayFingerprint(display.id))
            }
        }
        stateLock.unlock()
        guard !stale else { return }
        for display in resolved where display.isActive {
            let route = display.method.map { String(describing: $0) } ?? "none"
            Self.log.log("display \(display.id) [\(Self.displayFingerprint(display.id), privacy: .public)] route \(route, privacy: .public) level \(display.brightness)")
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, generation == self.rebuildGeneration else { return }
            if self.displays != resolved { self.displays = resolved }
            if self.softwareDimmingPreferred != forcedSoftwareIDs {
                self.softwareDimmingPreferred = forcedSoftwareIDs
            }
            if self.extendedDimmingPreferred != extendedDimmingIDs {
                self.extendedDimmingPreferred = extendedDimmingIDs
            }
            if self.drawableDisplays != drawableIDs { self.drawableDisplays = drawableIDs }
            if self.brightnessOSDSupported != supportsBrightnessOSD {
                self.brightnessOSDSupported = supportsBrightnessOSD
            }
            self.refreshKeyboardLight()
            self.syncKeyTap()
        }
    }

    // MARK: - Writes (work queue)

    private func drainPendingLevels() {
        while true {
            stateLock.lock()
            guard let (id, pending) = pendingLevels.first else {
                drainScheduled = false
                stateLock.unlock()
                return
            }
            pendingLevels.removeValue(forKey: id)
            let value = pending.value
            let osdLevel = pending.showOSD ? value : nil
            let route = routes[id]
            let writeGeneration = rebuildGeneration
            if route?.method == .system { systemWritesInFlight.insert(id) }
            stateLock.unlock()
            guard let route else { continue }
            var writeSucceeded = false
            switch route.method {
            case .system:
                writeSucceeded = Self.writeSystemBrightness(value, to: id, smooth: pending.smooth)
            case .ddc:
                guard let service = route.service else { continue }
                if route.extendedDimming {
                    writeSucceeded = writeExtendedBrightness(value, to: id,
                                                             route: route, service: service)
                    break
                }
                let deviceValue = BrightnessSupport.deviceValue(for: value,
                                                                maximum: route.maximum)
                let packet = BrightnessSupport.writePacket(
                    code: BrightnessSupport.luminanceCode,
                    value: deviceValue)
                writeSucceeded = ddcSend(to: id, service: service, packet: packet)
            case .software:
                writeSucceeded = applySoftwareDim(id, value: value)
            }
            Self.log.log("wrote display \(id) route \(String(describing: route.method), privacy: .public) level \(value) ok \(writeSucceeded)")
            if route.method == .ddc, !writeSucceeded, route.ddcReadable == false,
               let pathKey = route.ddcPathKey {
                forgetWriteOnlyDDCPath(pathKey)
                DispatchQueue.main.async { [weak self] in
                    self?.refresh(force: true)
                }
            }
            if route.method == .system {
                stateLock.lock()
                if pendingLevels[id] == nil { systemWritesInFlight.remove(id) }
                stateLock.unlock()
            }
            if writeSucceeded, let osdLevel {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.running,
                          UserDefaults.standard.bool(forKey: DefaultsKey.brightnessOSDEnabled) else { return }
                    self.stateLock.lock()
                    let current = self.rebuildGeneration
                    let latestWrite = self.writeSequence
                    self.stateLock.unlock()
                    guard current == writeGeneration,
                          latestWrite == pending.sequence else { return }
                    BrightnessOSD.show(displayID: id,
                                       brightness: osdLevel)
                }
            }
        }
    }

    private static func writeSystemBrightness(_ value: Double, to id: CGDirectDisplayID,
                                              smooth: Bool) -> Bool {
        var current: Float = -1
        if smooth, CGDisplayIsAsleep(id) == 0,
           let ease = BrightnessBridge.setBrightnessSmooth, let read = BrightnessBridge.getBrightness,
           read(id, &current) == 0,
           let change = BrightnessSupport.easedBrightnessChange(to: value, from: current),
           ease(id, change) == 0, read(id, &current) == 0,
           BrightnessSupport.easedBrightnessLanded(on: value, reported: current) {
            return true
        }
        return BrightnessBridge.setBrightness?(id, Float(value)) == 0
    }

    private func writeExtendedBrightness(_ value: Double, to id: CGDirectDisplayID,
                                         route: Route, service: CFTypeRef) -> Bool {
        let components = BrightnessSupport.extendedDimmingComponents(for: value)
        if components.picture >= 0.999, dimmedDisplays.contains(id),
           !applySoftwareDim(id, value: 1) { return false }

        let deviceValue = BrightnessSupport.deviceValue(for: components.hardware,
                                                        maximum: route.maximum)
        var hardwareSucceeded = true
        if route.lastDDCValue != deviceValue {
            let packet = BrightnessSupport.writePacket(code: BrightnessSupport.luminanceCode,
                                                       value: deviceValue)
            hardwareSucceeded = ddcSend(to: id, service: service, packet: packet)
            if hardwareSucceeded {
                stateLock.lock()
                if routes[id]?.ddcPathKey == route.ddcPathKey,
                   routes[id]?.extendedDimming == true {
                    routes[id]?.lastDDCValue = deviceValue
                }
                stateLock.unlock()
            }
        }
        let pictureSucceeded = components.picture >= 0.999
            || applySoftwareDim(id, value: components.picture)
        return hardwareSucceeded && pictureSucceeded
    }

    // MARK: - Software dimming (work queue)

    private func captureGammaBaselineIfNeeded(_ id: CGDirectDisplayID) {
        let fingerprint = Self.displayFingerprint(id)
        if gammaBaselines[id]?.fingerprint == fingerprint, dimmedDisplays.contains(id) { return }
        let capacity = 256
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = [CGGammaValue](repeating: 0, count: capacity)
        var blue = [CGGammaValue](repeating: 0, count: capacity)
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, UInt32(capacity), &red, &green, &blue,
                                          &sampleCount) == .success,
              sampleCount > 0 else { return }
        let count = Int(min(sampleCount, UInt32(capacity)))
        gammaBaselines[id] = GammaTable(red: Array(red.prefix(count)),
                                        green: Array(green.prefix(count)),
                                        blue: Array(blue.prefix(count)),
                                        count: UInt32(count),
                                        fingerprint: fingerprint)
        Self.log.log("captured gamma baseline for display \(id) [\(fingerprint, privacy: .public)], peak \(red[count - 1])")
    }

    @discardableResult
    private func applySoftwareDim(_ id: CGDirectDisplayID, value: Double) -> Bool {
        guard let baseline = gammaBaselines[id],
              baseline.fingerprint == Self.displayFingerprint(id) else { return false }
        if value >= 0.999 {
            let restored = CGSetDisplayTransferByTable(id, baseline.count, baseline.red,
                                                       baseline.green, baseline.blue) == .success
            if restored { dimmedDisplays.remove(id) }
            return restored
        }
        let factor = BrightnessSupport.softwareDimFactor(for: value)
        let red = BrightnessSupport.scaledGammaTable(baseline.red, factor: factor)
        let green = BrightnessSupport.scaledGammaTable(baseline.green, factor: factor)
        let blue = BrightnessSupport.scaledGammaTable(baseline.blue, factor: factor)
        let applied = CGSetDisplayTransferByTable(id, baseline.count, red, green, blue) == .success
        if applied { dimmedDisplays.insert(id) }
        return applied
    }

    // MARK: - DDC transactions (work queue)

    private func paceDDCCommand(for id: CGDirectDisplayID) {
        let now = DispatchTime.now().uptimeNanoseconds / 1_000
        let delay = BrightnessSupport.ddcCommandDelay(
            nowMicroseconds: now,
            lastCommandEndMicroseconds: ddcCommandEnds[id])
        if delay > 0 { usleep(delay) }
    }

    private func recordDDCCommandEnd(for id: CGDirectDisplayID) {
        ddcCommandEnds[id] = DispatchTime.now().uptimeNanoseconds / 1_000
    }

    private func ddcSend(to id: CGDirectDisplayID, service: CFTypeRef, packet: [UInt8]) -> Bool {
        guard let write = BrightnessBridge.writeI2C else { return false }
        paceDDCCommand(for: id)
        defer { recordDDCCommandEnd(for: id) }
        var bytes = packet
        var success = false
        for attempt in 0...BrightnessSupport.retryAttempts {
            for _ in 0..<BrightnessSupport.writeCycles {
                usleep(BrightnessSupport.writePauseMicroseconds)
                let accepted = write(service, BrightnessSupport.chipAddress,
                                     BrightnessSupport.dataAddress,
                                     &bytes, UInt32(bytes.count)) == KERN_SUCCESS
                success = accepted || success
            }
            if success { return true }
            if attempt < BrightnessSupport.retryAttempts {
                usleep(BrightnessSupport.retryPauseMicroseconds)
            }
        }
        return success
    }

    private enum DDCProbe {
        case replied(current: UInt16, maximum: UInt16)
        case writeOnly
        case dead
    }

    private func forcedSoftwarePaths() -> Set<String> {
        Set(UserDefaults.standard.stringArray(
            forKey: DefaultsKey.brightnessForcedSoftwarePaths
        ) ?? [])
    }

    private func extendedDimmingPaths() -> Set<String> {
        Set(UserDefaults.standard.stringArray(
            forKey: DefaultsKey.brightnessExtendedDimmingPaths
        ) ?? [])
    }

    func setExtendedDimmingPreferred(_ preferred: Bool, for id: CGDirectDisplayID) {
        stateLock.lock()
        let pathKey = routes[id]?.ddcPathKey
        if pathKey != nil {
            pendingLevels.removeValue(forKey: id)
        }
        if pathKey != nil && !preferred {
            lastApplied[id] = nil
            levelKnownAt[id] = nil
        }
        stateLock.unlock()
        guard let pathKey else { return }
        let defaults = UserDefaults.standard
        let stored = defaults.stringArray(forKey: DefaultsKey.brightnessExtendedDimmingPaths) ?? []
        let updated = BrightnessSupport.updatedWriteOnlyDDCPaths(
            stored, path: pathKey, isWriteOnly: preferred)
        if updated != stored {
            defaults.set(updated, forKey: DefaultsKey.brightnessExtendedDimmingPaths)
        }
        Self.log.log("display \(id) extended dimming preferred \(preferred)")
        guard !preferred else {
            refresh(force: true)
            return
        }
        workQueue.async { [weak self] in
            guard let self else { return }
            if self.dimmedDisplays.contains(id) {
                self.applySoftwareDim(id, value: 1)
            }
            DispatchQueue.main.async { [weak self] in self?.refresh(force: true) }
        }
    }

    func setSoftwareDimmingPreferred(_ preferred: Bool, for id: CGDirectDisplayID) {
        stateLock.lock()
        let pathKey = routes[id]?.ddcPathKey
        stateLock.unlock()
        guard let pathKey else { return }
        let defaults = UserDefaults.standard
        let stored = defaults.stringArray(forKey: DefaultsKey.brightnessForcedSoftwarePaths) ?? []
        let updated = BrightnessSupport.updatedWriteOnlyDDCPaths(
            stored, path: pathKey, isWriteOnly: preferred)
        if updated != stored {
            defaults.set(updated, forKey: DefaultsKey.brightnessForcedSoftwarePaths)
        }
        forgetWriteOnlyDDCPath(pathKey)
        Self.log.log("display \(id) software dimming preferred \(preferred)")
        guard !preferred else {
            refresh(force: true)
            return
        }
        stateLock.lock()
        lastApplied[id] = nil
        levelKnownAt[id] = nil
        stateLock.unlock()
        workQueue.async { [weak self] in
            guard let self else { return }
            self.applySoftwareDim(id, value: 1)
            DispatchQueue.main.async { [weak self] in self?.refresh(force: true) }
        }
    }

    private func writeOnlyDDCPaths() -> Set<String> {
        Set(UserDefaults.standard.stringArray(
            forKey: DefaultsKey.brightnessDDCWriteOnlyPaths
        ) ?? [])
    }

    private func rememberWriteOnlyDDCPath(_ path: String?) {
        guard let path else { return }
        let defaults = UserDefaults.standard
        let stored = defaults.stringArray(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths) ?? []
        let updated = BrightnessSupport.updatedWriteOnlyDDCPaths(
            stored, path: path, isWriteOnly: true)
        if updated != stored {
            defaults.set(updated, forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
        }
    }

    private func forgetWriteOnlyDDCPath(_ path: String?) {
        guard let path else { return }
        let defaults = UserDefaults.standard
        let stored = defaults.stringArray(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths) ?? []
        let updated = BrightnessSupport.updatedWriteOnlyDDCPaths(
            stored, path: path, isWriteOnly: false)
        if updated != stored {
            defaults.set(updated, forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
        }
    }

    private func ddcProbeLuminance(for id: CGDirectDisplayID,
                                   service: CFTypeRef,
                                   classifyingChannel: Bool = false) -> DDCProbe {
        guard let write = BrightnessBridge.writeI2C,
              let read = BrightnessBridge.readI2C else { return .dead }
        paceDDCCommand(for: id)
        defer { recordDDCCommandEnd(for: id) }
        var request = BrightnessSupport.readRequestPacket(code: BrightnessSupport.luminanceCode)
        var writeAccepted = false
        let attempts = BrightnessSupport.ddcProbeAttempts()
        for attempt in 0..<attempts {
            let writeCycles = BrightnessSupport.ddcProbeWriteCycles(
                classifyingChannel: classifyingChannel,
                isFinalAttempt: attempt + 1 == attempts)
            for _ in 0..<writeCycles {
                usleep(BrightnessSupport.writePauseMicroseconds)
                if write(service, BrightnessSupport.chipAddress,
                         BrightnessSupport.dataAddress,
                         &request, UInt32(request.count)) == KERN_SUCCESS {
                    writeAccepted = true
                }
            }
            usleep(BrightnessSupport.readPauseMicroseconds)
            var reply = [UInt8](repeating: 0, count: BrightnessSupport.replyLength)
            if read(service, BrightnessSupport.chipAddress, 0,
                    &reply, UInt32(reply.count)) == KERN_SUCCESS,
               let parsed = BrightnessSupport.parseReply(reply, code: BrightnessSupport.luminanceCode) {
                return .replied(current: parsed.current, maximum: parsed.maximum)
            }
            if attempt + 1 < attempts {
                usleep(BrightnessSupport.retryPauseMicroseconds)
            }
        }
        switch BrightnessSupport.channelOutcome(writeAccepted: writeAccepted, replyParsed: false) {
        case .writeOnly: return .writeOnly
        case .live, .dead: return .dead
        }
    }

    // MARK: - Display identity

    private static func displayInfoDictionary(_ id: CGDirectDisplayID) -> NSDictionary? {
        guard let create = BrightnessBridge.createInfoDictionary else { return nil }
        return create(id)?.takeRetainedValue() as NSDictionary?
    }

    private static func displayName(_ id: CGDirectDisplayID, info: NSDictionary?,
                                    screenNames: [CGDirectDisplayID: String]) -> String {
        if let name = screenNames[id] { return name }
        if let names = info?["DisplayProductName"] as? [String: String],
           let name = names["en_US"] ?? names.first?.value {
            return name
        }
        return "Display"
    }

    private static func displayIdentity(_ id: CGDirectDisplayID,
                                        info: NSDictionary?) -> BrightnessSupport.DisplayIdentity {
        var identity = BrightnessSupport.DisplayIdentity()
        guard let info else { return identity }
        identity.vendorID = (info[kDisplayVendorID] as? NSNumber)?.int64Value
        identity.productID = (info[kDisplayProductID] as? NSNumber)?.int64Value
        identity.weekOfManufacture = (info[kDisplayWeekOfManufacture] as? NSNumber)?.int64Value
        identity.yearOfManufacture = (info[kDisplayYearOfManufacture] as? NSNumber)?.int64Value
        identity.horizontalImageSize = (info[kDisplayHorizontalImageSize] as? NSNumber)?.int64Value
        identity.verticalImageSize = (info[kDisplayVerticalImageSize] as? NSNumber)?.int64Value
        identity.ioDisplayLocation = info[kIODisplayLocationKey] as? String
        if let names = info["DisplayProductName"] as? [String: String] {
            identity.productName = names["en_US"] ?? names.first?.value
        }
        identity.serialNumber = (info[kDisplaySerialNumber] as? NSNumber)?.int64Value
        return identity
    }

    // MARK: - IORegistry walk

    private struct ExternalService {
        var identity: BrightnessSupport.ServiceIdentity
        var service: CFTypeRef
    }

    private static func externalServices() -> [ExternalService] {
        guard let createWithService = BrightnessBridge.createWithService else { return [] }
        var results: [ExternalService] = []
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively),
                                            &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var pending = BrightnessSupport.ServiceIdentity()
        var ordinal = 0
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &nameBuffer) == KERN_SUCCESS else { continue }
            let name = String(cString: nameBuffer)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                ordinal += 1
                pending = BrightnessSupport.ServiceIdentity()
                pending.ordinal = ordinal
                if let uuid = Self.property(entry, "EDID UUID") as? String {
                    pending.edidUUID = uuid
                }
                var path = [CChar](repeating: 0, count: 512)
                if IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS {
                    pending.ioDisplayLocation = String(cString: path)
                }
                if let attributes = Self.property(entry, "DisplayAttributes") as? NSDictionary,
                   let product = attributes["ProductAttributes"] as? NSDictionary {
                    pending.productName = product["ProductName"] as? String ?? ""
                    pending.serialNumber = (product["SerialNumber"] as? NSNumber)?.int64Value ?? 0
                }
            } else if name == "DCPAVServiceProxy" {
                guard let location = Self.property(entry, "Location") as? String,
                      location == "External",
                      let service = createWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
                else { continue }
                results.append(ExternalService(identity: pending, service: service))
            }
        }
        return results
    }

    private static func property(_ entry: io_service_t, _ key: String) -> AnyObject? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively))?
            .takeRetainedValue()
    }
}

// MARK: - Private symbol bridge

enum BrightnessBridge {
    typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightnessFn = @convention(c) (UInt32, Float) -> Int32
    typealias CreateInfoDictionaryFn = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    typealias CreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias WriteI2CFn = @convention(c)
        (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias ReadI2CFn = @convention(c)
        (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let displayServicesHandle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let coreDisplayHandle = dlopen(
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)

    static let getBrightness: GetBrightnessFn? =
        symbol(displayServicesHandle, "DisplayServicesGetBrightness")
    static let setBrightness: SetBrightnessFn? =
        symbol(displayServicesHandle, "DisplayServicesSetBrightness")
    static let setBrightnessSmooth: SetBrightnessFn? =
        symbol(displayServicesHandle, "DisplayServicesSetBrightnessSmooth")
    static let createInfoDictionary: CreateInfoDictionaryFn? =
        symbol(coreDisplayHandle, "CoreDisplay_DisplayCreateInfoDictionary")
    static let createWithService: CreateWithServiceFn? =
        symbol(coreDisplayHandle, "IOAVServiceCreateWithService")
    static let writeI2C: WriteI2CFn? =
        symbol(coreDisplayHandle, "IOAVServiceWriteI2C")
    static let readI2C: ReadI2CFn? =
        symbol(coreDisplayHandle, "IOAVServiceReadI2C")

    static var ddcAvailable: Bool {
        createWithService != nil && writeI2C != nil && readI2C != nil
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

private final class KeyboardLightBridge {
    private typealias CopyIDsFn = @convention(c) (NSObject, Selector) -> Unmanaged<AnyObject>
    private typealias IsBuiltInFn = @convention(c) (NSObject, Selector, UInt64) -> ObjCBool
    private typealias GetBrightnessFn = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias SetBrightnessFn = @convention(c)
        (NSObject, Selector, Float, Int32, Bool, UInt64) -> ObjCBool
    private typealias SuspendIdleDimmingFn = @convention(c)
        (NSObject, Selector, Bool, UInt64) -> ObjCBool

    private let client: NSObject
    private let keyboardID: UInt64
    private let getBrightness: GetBrightnessFn
    private let setBrightnessValue: SetBrightnessFn
    private let suspendIdleDimming: SuspendIdleDimmingFn
    private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let setSelector = NSSelectorFromString(
        "setBrightness:fadeSpeed:commit:forKeyboard:")
    private let suspendSelector = NSSelectorFromString("suspendIdleDimming:forKeyboard:")

    init?() {
        guard let framework = Bundle(
            path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
              framework.load(),
              let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }

        let client = clientClass.init()
        let copySelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
        guard let copyIDs: CopyIDsFn = Self.implementation(
            client, selector: copySelector, as: CopyIDsFn.self),
              let isBuiltIn: IsBuiltInFn = Self.implementation(
                client, selector: builtInSelector, as: IsBuiltInFn.self),
              let getBrightness: GetBrightnessFn = Self.implementation(
                client, selector: getSelector, as: GetBrightnessFn.self),
              let setBrightness: SetBrightnessFn = Self.implementation(
                client, selector: setSelector, as: SetBrightnessFn.self),
              let suspendIdleDimming: SuspendIdleDimmingFn = Self.implementation(
                client, selector: suspendSelector, as: SuspendIdleDimmingFn.self),
              let ids = copyIDs(client, copySelector).takeRetainedValue() as? [NSNumber],
              let keyboardID = ids.map(\.uint64Value).first(where: {
                  isBuiltIn(client, builtInSelector, $0).boolValue
              })
        else { return nil }

        self.client = client
        self.keyboardID = keyboardID
        self.getBrightness = getBrightness
        self.setBrightnessValue = setBrightness
        self.suspendIdleDimming = suspendIdleDimming
    }

    func brightness() -> Float {
        getBrightness(client, getSelector, keyboardID)
    }

    func setBrightness(_ value: Float) -> Bool {
        _ = suspendIdleDimming(client, suspendSelector, true, keyboardID)
        defer { _ = suspendIdleDimming(client, suspendSelector, false, keyboardID) }
        return setBrightnessValue(client, setSelector, min(max(value, 0), 1), 350,
                                  true, keyboardID).boolValue
    }

    private static func implementation<Function>(
        _ object: NSObject,
        selector: Selector,
        as type: Function.Type
    ) -> Function? {
        guard let cls = object_getClass(object),
              let method = class_getInstanceMethod(cls, selector) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: type)
    }
}

private enum DisplayConfigurationBridge {
    typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef, UInt32, Bool) -> Int32

    private static let coreGraphicsHandle = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

    static let configureEnabled: ConfigureEnabledFn? = {
        guard let coreGraphicsHandle,
              let pointer = dlsym(coreGraphicsHandle, "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(pointer, to: ConfigureEnabledFn.self)
    }()
}
