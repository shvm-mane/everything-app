// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum QuickToggleAction: String, PanelOrderItem, Identifiable {
    case darkMode, keyboardLight, micMute, emptyTrash, quitAllApps, ejectDisks, hiddenFiles,
         desktopIcons, lockScreen, displayOff, screenSaver

    var id: String { rawValue }

    var feature: AppFeature {
        switch self {
        case .micMute: return .micMute
        case .quitAllApps: return .quitApps
        default: return .quickToggles
        }
    }
}

final class QuickTogglesService: ObservableObject {
    static let shared = QuickTogglesService()

    enum RunState: Equatable {
        case running, failed
        case needsPermission
    }

    @Published private(set) var states: [QuickToggleAction: RunState] = [:]
    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var othersShortcutRegistrationFailed = false
    @Published private(set) var quitAllExceptions: [String] = []

    private let workQueue = DispatchQueue(label: "com.vorssaint.utils.quick-toggles", qos: .userInitiated)
    private let hotkey = QuickToolHotkey(id: 63)
    private let othersHotkey = QuickToolHotkey(id: 62)

    private init() {
        hotkey.onPress = { [weak self] in self?.showQuitApps(scope: .all) }
        othersHotkey.onPress = { [weak self] in self?.showQuitApps(scope: .allExceptFront) }
        reloadQuitAllExceptions()
    }

    func state(for action: QuickToggleAction) -> RunState? {
        states[action]
    }

    func syncWithPreferences() {
        let available = quitAppsAvailable
        let defaults = UserDefaults.standard
        shortcutRegistrationFailed = !hotkey.sync(
            enabled: available && defaults.bool(forKey: DefaultsKey.quitAppsShortcutEnabled),
            shortcut: GlobalShortcut.saved(for: DefaultsKey.quitAppsShortcut,
                                           fallback: .quitAllDefault),
            storageKey: DefaultsKey.quitAppsShortcut)
        othersShortcutRegistrationFailed = !othersHotkey.sync(
            enabled: available && defaults.bool(forKey: DefaultsKey.quitAppsExceptFrontShortcutEnabled),
            shortcut: GlobalShortcut.saved(for: DefaultsKey.quitAppsExceptFrontShortcut,
                                           fallback: .quitAllExceptFrontDefault),
            storageKey: DefaultsKey.quitAppsExceptFrontShortcut)
        if !available {
            hotkey.unregister()
            othersHotkey.unregister()
            QuitAppsPanelController.shared.close()
        }
        reloadQuitAllExceptions()
    }

    // MARK: - Current system state (read on demand, never observed)

    var hiddenFilesShown: Bool {
        finderFlag(QuickTogglesSupport.showAllFilesKey, default: false)
    }

    var systemAppearanceIsDark: Bool? {
        Self.appearanceTheme?.get()
    }

    var desktopIconsShown: Bool {
        finderFlag(QuickTogglesSupport.createDesktopKey, default: true)
    }

    func ejectableVolumeCount() -> Int {
        Self.ejectableVolumeURLs().count
    }

    // MARK: - Appearance (issue #205)

    func toggleDarkMode() {
        guard available, beginRun(.darkMode) else { return }
        guard let theme = Self.appearanceTheme else {
            finishRun(.darkMode, state: .failed)
            return
        }
        theme.set(!theme.get())
        finishRun(.darkMode, state: nil)
    }

    // MARK: - Trash

    func emptyTrash() {
        guard available, states[.emptyTrash] != .running else { return }
        let strings = FeatureStrings.quickToggles(L10n.shared.language)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = strings.emptyTrashConfirmTitle
        alert.informativeText = strings.emptyTrashConfirmMessage
        alert.addButton(withTitle: strings.emptyTrashConfirmButton)
        alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
        let island = NotchService.shared.presentationWindow
        let fromIsland = island?.isVisible == true
            && (NSApp.currentEvent?.window === island || NSApp.keyWindow === island)
        guard NotchIslandAlert.run(alert, above: fromIsland ? island : nil) == .alertFirstButtonReturn else { return }
        emptyTrashConfirmed()
    }

    func emptyTrashConfirmed() {
        runAppleScript(.emptyTrash,
                       target: .finder,
                       source: QuickTogglesSupport.emptyTrashSource)
    }

    // MARK: - Quit apps (issue #855)

    func showQuitApps(scope: QuitAppsScope = .all) {
        guard quitAppsAvailable else { return }
        QuitAppsPanelController.shared.show(scope: scope, frontmostPID: frontmostAppPID())
    }

    func quitAllApps(keepingPID: pid_t?) {
        guard quitAppsAvailable, beginRun(.quitAllApps) else { return }
        let exceptions = Set(quitAllExceptions)
        let running = NSWorkspace.shared.runningApplications
        let targets = Set(QuickTogglesSupport.batchQuitTargets(
            running.map(Self.candidate), exceptions: exceptions, keepingPID: keepingPID))
        for app in running where targets.contains(app.processIdentifier) {
            _ = app.terminate()
        }
        finishRun(.quitAllApps, state: nil)
    }

    func quitApp(pid: pid_t) -> Bool {
        guard quitAppsAvailable,
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              !QuickTogglesSupport.vorssaintBundleIdentifiers.contains(bundleID) else { return false }
        return app.terminate()
    }

    private static func candidate(_ app: NSRunningApplication) -> QuitAppsCandidate {
        QuitAppsCandidate(pid: app.processIdentifier,
                          bundleIdentifier: app.bundleIdentifier,
                          activationPolicyRawValue: app.activationPolicy.rawValue,
                          isTerminated: app.isTerminated)
    }

    func frontmostAppPID() -> pid_t? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID {
            return front.processIdentifier
        }
        return (NSApp.delegate as? AppDelegate)?.panelActivationSourcePID
    }

    func addQuitAllException(_ bundleID: String) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !quitAllExceptions.contains(bundleID) else { return }
        var list = QuickTogglesSupport.sanitizedQuitAllExceptions(quitAllExceptions)
        list.append(bundleID)
        UserDefaults.standard.set(list, forKey: DefaultsKey.quitAppsKeptApps)
        reloadQuitAllExceptions()
    }

    func removeQuitAllException(_ bundleID: String) {
        guard !isMandatoryQuitAllException(bundleID) else { return }
        let list = QuickTogglesSupport.sanitizedQuitAllExceptions(
            quitAllExceptions.filter { $0 != bundleID })
        UserDefaults.standard.set(list, forKey: DefaultsKey.quitAppsKeptApps)
        reloadQuitAllExceptions()
    }

    func isMandatoryQuitAllException(_ bundleID: String) -> Bool {
        Defaults.mandatoryAutoQuitExceptionBundleIDs.contains(bundleID)
    }

    private func reloadQuitAllExceptions() {
        let raw = UserDefaults.standard.stringArray(forKey: DefaultsKey.quitAppsKeptApps) ?? []
        let sanitized = QuickTogglesSupport.sanitizedQuitAllExceptions(raw)
        if raw != sanitized {
            UserDefaults.standard.set(sanitized, forKey: DefaultsKey.quitAppsKeptApps)
        }
        quitAllExceptions = sanitized
    }

    // MARK: - Finder flags

    func toggleHiddenFiles() {
        toggleFinderFlag(.hiddenFiles,
                         key: QuickTogglesSupport.showAllFilesKey,
                         to: !hiddenFilesShown)
    }

    func toggleDesktopIcons() {
        toggleFinderFlag(.desktopIcons,
                         key: QuickTogglesSupport.createDesktopKey,
                         to: !desktopIconsShown)
    }

    // MARK: - Disks

    func ejectAllDisks() {
        guard available, beginRun(.ejectDisks) else { return }
        workQueue.async {
            let volumes = Self.ejectableVolumeURLs()
            guard !volumes.isEmpty else {
                self.finishRun(.ejectDisks, state: nil)
                return
            }
            var failures = 0
            for url in volumes {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                } catch {
                    if Self.isMounted(url) { failures += 1 }
                }
            }
            self.finishRun(.ejectDisks, state: failures == 0 ? nil : .failed)
        }
    }

    // MARK: - Screen

    func lockScreen() {
        guard available else { return }
        if let lock = Self.lockScreenFunction {
            _ = lock()
        } else {
            startScreenSaver()
        }
    }

    func turnDisplayOff() {
        guard available, beginRun(.displayOff) else { return }
        workQueue.async {
            let result = Shell.run("/usr/bin/pmset", ["displaysleepnow"])
            self.finishRun(.displayOff, state: result.status == 0 ? nil : .failed)
        }
    }

    func startScreenSaver() {
        guard available else { return }
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url,
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Permission refresh

    func refreshPermissionStates() {
        let marked = states.filter { $0.value == .needsPermission }.map(\.key)
        guard !marked.isEmpty else { return }
        workQueue.async {
            for action in marked {
                guard let target = Self.automationTarget(for: action) else { continue }
                if Permissions.automationStatus(for: target) == .granted {
                    DispatchQueue.main.async {
                        if self.states[action] == .needsPermission {
                            self.states[action] = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - Internals

    private var available: Bool {
        AppFeature.quickToggles.isAvailable
    }

    private var quitAppsAvailable: Bool {
        AppFeature.quitApps.isAvailable
    }

    private static func automationTarget(for action: QuickToggleAction) -> Permissions.AutomationTarget? {
        switch action {
        case .emptyTrash: return .finder
        default: return nil
        }
    }

    private func runAppleScript(_ action: QuickToggleAction,
                                target: Permissions.AutomationTarget,
                                source: String) {
        guard available, beginRun(action) else { return }
        workQueue.async {
            if Permissions.automationStatus(for: target) == .denied {
                self.finishRun(action, state: .needsPermission, resets: false)
                return
            }
            let result = AppleScriptRunner.runDetailed(source)
            if result.ok {
                self.finishRun(action, state: nil)
            } else if QuickTogglesSupport.isPermissionError(result.errorNumber) {
                self.finishRun(action, state: .needsPermission, resets: false)
            } else {
                self.finishRun(action, state: .failed)
            }
        }
    }

    private func toggleFinderFlag(_ action: QuickToggleAction, key: String, to value: Bool) {
        guard available, beginRun(action) else { return }
        workQueue.async {
            CFPreferencesSetAppValue(key as CFString,
                                     value as CFBoolean,
                                     QuickTogglesSupport.finderDomain as CFString)
            CFPreferencesAppSynchronize(QuickTogglesSupport.finderDomain as CFString)
            self.finishRun(action, state: self.restartFinder() ? nil : .failed)
        }
    }

    private func restartFinder() -> Bool {
        if Permissions.automationStatus(for: .finder) == .granted,
           AppleScriptRunner.runDetailed(QuickTogglesSupport.quitFinderSource).ok,
           waitForFinderExit() {
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return true
        }
        return Shell.run("/usr/bin/killall", ["Finder"]).status == 0
    }

    private func waitForFinderExit() -> Bool {
        for _ in 0..<30 {
            if Shell.run("/usr/bin/pgrep", ["-x", "Finder"]).status != 0 {
                return true
            }
            usleep(100_000)
        }
        return false
    }

    private func beginRun(_ action: QuickToggleAction) -> Bool {
        guard states[action] != .running else { return false }
        setState(action, .running)
        return true
    }

    private func finishRun(_ action: QuickToggleAction, state: RunState?, resets: Bool = true) {
        setState(action, state)
        guard state != nil, resets else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.states[action] == state else { return }
            self.states[action] = nil
        }
    }

    private func setState(_ action: QuickToggleAction, _ state: RunState?) {
        if Thread.isMainThread {
            states[action] = state
        } else {
            DispatchQueue.main.async {
                self.states[action] = state
            }
        }
    }

    private func finderFlag(_ key: String, default defaultValue: Bool) -> Bool {
        let value = CFPreferencesCopyAppValue(key as CFString,
                                              QuickTogglesSupport.finderDomain as CFString)
        return QuickTogglesSupport.finderFlag(value, default: defaultValue)
    }

    private static func ejectableVolumeURLs() -> [URL] {
        let keys: Set<URLResourceKey> = [
            .volumeIsInternalKey, .volumeIsRemovableKey,
            .volumeIsEjectableKey, .volumeIsLocalKey,
            .volumeIsRootFileSystemKey,
            .volumeNameKey,
            .volumeLocalizedNameKey,
            .volumeUUIDStringKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]) else { return [] }
        let excludedList = UserDefaults.standard.stringArray(forKey: DefaultsKey.diskEjectExcludedVolumes) ?? []
        let excludedSet = Set(excludedList.map { $0.lowercased() })
        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return false }
            let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
            return QuickTogglesSupport.shouldOfferEject(isInternal: values.volumeIsInternal ?? false,
                                                        isRemovable: values.volumeIsRemovable ?? false,
                                                        isEjectable: values.volumeIsEjectable ?? false,
                                                        isLocal: values.volumeIsLocal ?? false,
                                                        isRootFileSystem: values.volumeIsRootFileSystem
                                                            ?? (url.path == "/"),
                                                        volumeName: name,
                                                        volumeUUID: values.volumeUUIDString,
                                                        mountPath: url.path,
                                                        excludedVolumes: excludedSet)
        }
    }

    private static func isMounted(_ url: URL) -> Bool {
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                               options: []) else { return true }
        return urls.contains { $0.path == url.path }
    }

    private static let lockScreenFunction: (@convention(c) () -> Int32)? = {
        let path = "/System/Library/PrivateFrameworks/login.framework/login"
        guard let handle = dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
    }()

    private typealias AppearanceGet = @convention(c) () -> Bool
    private typealias AppearanceSet = @convention(c) (Bool) -> Void

    private static let appearanceTheme: (get: AppearanceGet, set: AppearanceSet)? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY),
              let getSymbol = dlsym(handle, "SLSGetAppearanceThemeLegacy"),
              let setSymbol = dlsym(handle, "SLSSetAppearanceThemeLegacy") else { return nil }
        return (unsafeBitCast(getSymbol, to: AppearanceGet.self),
                unsafeBitCast(setSymbol, to: AppearanceSet.self))
    }()
}
