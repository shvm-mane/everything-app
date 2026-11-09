// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Pages

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, island, ai, scratchpad, radial, spaces, colorPicker, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .island: return "Dynamic Island"
        case .ai: return "Claude"
        case .scratchpad: return "Scratchpad"
        case .radial: return "Radial Menu"
        case .spaces: return "Spaces"
        case .colorPicker: return "Color Picker"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .island: return "capsule.tophalf.filled"
        case .ai: return "sparkles"
        case .scratchpad: return "note.text"
        case .radial: return "circle.grid.cross"
        case .spaces: return "rectangle.split.3x1"
        case .colorPicker: return "eyedropper"
        case .about: return "info.circle"
        }
    }

}

final class EverythingSettingsRouter: ObservableObject {
    static let shared = EverythingSettingsRouter()
    @Published var pane: SettingsPane = .general

    var tab: SettingsPane {
        get { pane }
        set { pane = newValue }
    }
}

// MARK: - Window content

struct EverythingSettingsView: View {
    static let minWidth: Double = 640
    static let minHeight: Double = 440

    @ObservedObject private var router = EverythingSettingsRouter.shared

    var body: some View {
        NavigationSplitView {
            EverythingSettingsSidebar()
                .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            EverythingSettingsDetail()
        }
        .frame(minWidth: Self.minWidth, minHeight: Self.minHeight)
    }
}

struct EverythingSettingsSidebar: View {
    @ObservedObject private var router = EverythingSettingsRouter.shared

    var body: some View {
        List(selection: Binding(get: { router.pane }, set: { if let pane = $0 { router.pane = pane } })) {
            ForEach(SettingsPane.allCases) { pane in
                if pane == .ai {
                    Label { Text(pane.title) } icon: {
                        Image(nsImage: ClaudeMark.templateImage(size: 15))
                    }
                    .tag(pane)
                } else {
                    Label(pane.title, systemImage: pane.symbol).tag(pane)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct EverythingSettingsDetail: View {
    @ObservedObject private var router = EverythingSettingsRouter.shared

    var body: some View {
        detail
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var detail: some View {
        switch router.pane {
        case .general: GeneralPage()
        case .island: IslandPage()
        case .ai: ClaudePage()
        case .scratchpad: ScratchpadPage()
        case .radial: RadialMenuSettings()
        case .spaces: SpacesPage()
        case .colorPicker: ColorPickerPage()
        case .about: AboutPage()
        }
    }
}

// MARK: - Shared rows

private struct RowLabel: View {
    let title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let caption {
                Text(caption).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let caption: String
    let granted: Bool?
    let open: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let granted {
                    Label(granted ? "On" : "Off", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(granted ? .green : .orange)
                        .font(.callout)
                }
                Button(granted == true ? "Open" : "Grant…", action: open)
            }
        } label: {
            RowLabel(title: title, caption: caption)
        }
    }
}

private struct KeybindField: View {
    let display: String
    let onRecord: (NSEvent) -> Bool
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            Text(recording ? "Type keybind…" : display)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
                .frame(minWidth: 110)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        onStart()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            if onRecord(event) { stop() } else { NSSound.beep() }
            return nil
        }
    }

    private func stop() {
        guard recording || monitor != nil else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onStop()
    }
}

// MARK: - General

private struct GeneralPage: View {
    @ObservedObject private var permissions = Permissions.shared
    @State private var login: LaunchAtLoginSupport.Registration =
        UserDefaults.standard.bool(forKey: DefaultsKey.launchAtLoginWanted) ? .enabled : .off
    @State private var loginPending = false
    @State private var automation: OSStatus?
    @AppStorage(PerformanceMode.key) private var performanceMode = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { login != .off }, set: setLogin)) {
                    Text("Open at login")
                }
                .disabled(loginPending)
                if login == .needsApproval {
                    LabeledContent("macOS needs your approval") {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Toggle(isOn: Binding(get: { !performanceMode }, set: { performanceMode = !$0 })) {
                    Text("Liquid glass")
                    Text("Glass, blur and extra animations. Turn off for the lightest footprint.")
                }
            }
            Section {
                PermissionRow(title: "Accessibility",
                              caption: "Keybinds, spaces, radial menu, volume keys",
                              granted: permissions.accessibility) {
                    if !permissions.accessibility { permissions.requestAccessibility() }
                    permissions.openAccessibilitySettings()
                }
                PermissionRow(title: "Automation",
                              caption: "Apple Music controls",
                              granted: automation.map { $0 == noErr }) {
                    askForAutomation()
                    permissions.openAutomationSettings()
                }
                PermissionRow(title: "Screen Recording",
                              caption: "Color picker",
                              granted: permissions.screenRecording) {
                    if !permissions.screenRecording { permissions.requestScreenRecording() }
                    permissions.openScreenRecordingSettings()
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            LaunchAtLogin.refresh { login = $0 }
            permissions.refresh()
            automation = Self.automationStatus(ask: false)
        }
    }

    private func setLogin(_ enabled: Bool) {
        login = enabled ? .enabled : .off
        loginPending = true
        LaunchAtLogin.setEnabled(enabled) { registration, _ in
            login = registration
            loginPending = false
        }
    }

    private func askForAutomation() {
        let ask = {
            DispatchQueue.global().async {
                let status = Self.automationStatus(ask: true)
                DispatchQueue.main.async { automation = status }
            }
        }
        let music = "com.apple.Music"
        guard NSRunningApplication.runningApplications(withBundleIdentifier: music).isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: music) else { return ask() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: ask)
        }
    }

    private static let automationKey = "everythingMusicAutomationGranted"

    private static func automationStatus(ask: Bool) -> OSStatus? {
        let defaults = UserDefaults.standard
        let remembered: OSStatus? = defaults.object(forKey: automationKey) == nil ? nil
            : defaults.bool(forKey: automationKey) ? noErr : OSStatus(errAEEventNotPermitted)
        guard let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Music").aeDesc else { return remembered }
        let status = AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, ask)
        if status == -600 || status == -1744 { return remembered }
        defaults.set(status == noErr, forKey: automationKey)
        return status
    }
}

// MARK: - Dynamic Island

private struct IslandPage: View {
    @AppStorage(DefaultsKey.notchEnabled) private var enabled = true
    @AppStorage(DefaultsKey.notchShowPlayingMusic) private var showMusic = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    Text("Dynamic Island")
                }
                Toggle(isOn: $showMusic) {
                    Text("Show now playing beside the notch")
                }
                .disabled(!enabled)
            }
        }
        .formStyle(.grouped)
        .onChange(of: enabled) { _, _ in NotchService.shared.syncWithPreferences() }
        .onChange(of: showMusic) { _, _ in NotchService.shared.syncWithPreferences() }
    }
}

// MARK: - Claude

private struct ClaudePage: View {
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsEnabled) private var enabled = true
    @AppStorage(DefaultsKey.claudeUsageShortcutEnabled) private var keybindOn = true
    @AppStorage(DefaultsKey.claudeUsageShortcut) private var stored = GlobalShortcut.claudeUsageDefault.storageValue

    private var shortcut: GlobalShortcut { GlobalShortcut(storageValue: stored) ?? .claudeUsageDefault }

    private static let claudeHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    private var claudeFound: Bool { FileManager.default.fileExists(atPath: Self.claudeHome.path) }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    Text("Show Claude in the island")
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        KeybindField(display: shortcut.displayString) { event in
                            let modifiers = GlobalShortcutModifiers(eventFlags: event.modifierFlags)
                            guard modifiers.hasPrimaryModifier else { return false }
                            stored = GlobalShortcut(keyCode: Int64(event.keyCode), modifiers: modifiers).storageValue
                            NotchService.shared.syncWithPreferences()
                            return true
                        }
                        .disabled(!keybindOn || !enabled)
                        Toggle("", isOn: $keybindOn).labelsHidden().toggleStyle(.switch).disabled(!enabled)
                    }
                } label: {
                    Text("Keybind")
                }
                LabeledContent {
                    status(claudeFound ? (usage.snapshot.seen.contains(.claude) ? "Connected" : "Waiting for Claude Code") : "Not found",
                           ok: claudeFound)
                } label: {
                    Text("Claude Code")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: enabled) { _, _ in NotchService.shared.syncWithPreferences() }
        .onChange(of: keybindOn) { _, _ in NotchService.shared.syncWithPreferences() }
    }

    private func status(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .foregroundStyle(ok ? .green : .orange)
            .font(.callout)
    }
}

// MARK: - Scratchpad

private struct ScratchpadPage: View {
    @ObservedObject private var model = WispIsland.shared.model
    @AppStorage(DefaultsKey.scratchpadShortcutEnabled) private var keybindOn = true
    @AppStorage(DefaultsKey.scratchpadShortcut) private var stored = GlobalShortcut.scratchpadDefault.storageValue
    @State private var folderPath = StorageLocation.currentFolder.path
    @State private var folderError: String?

    private static let newYorkAvailable =
        NSFont.systemFont(ofSize: 14).fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 14) } != nil

    private var shortcut: GlobalShortcut { GlobalShortcut(storageValue: stored) ?? .scratchpadDefault }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        KeybindField(display: shortcut.displayString) { event in
                            let modifiers = GlobalShortcutModifiers(eventFlags: event.modifierFlags)
                            guard modifiers.hasPrimaryModifier else { return false }
                            stored = GlobalShortcut(keyCode: Int64(event.keyCode), modifiers: modifiers).storageValue
                            ScratchpadService.shared.syncWithPreferences()
                            return true
                        }
                        .disabled(!keybindOn)
                        Toggle("", isOn: $keybindOn).labelsHidden().toggleStyle(.switch)
                    }
                } label: {
                    Text("Keybind")
                }
                if Self.newYorkAvailable {
                    Picker(selection: Binding(
                        get: { model.fontFace == .newYork ? .newYork : FontFace.sanFrancisco },
                        set: { model.fontFace = $0 })) {
                        Text("SF Pro").tag(FontFace.sanFrancisco)
                        Text("New York").tag(FontFace.newYork)
                    } label: {
                        Text("Font")
                    }
                    .pickerStyle(.segmented)
                }
            }
            Section {
                LabeledContent {
                    HStack {
                        Button("Choose…") { chooseFolder() }
                        if StorageLocation.isCustom { Button("Use Default") { resetFolder() } }
                    }
                } label: {
                    RowLabel(title: "Folder", caption: (folderPath as NSString).abbreviatingWithTildeInPath)
                }
                if let folderError {
                    Text(folderError).font(.callout).foregroundStyle(.orange)
                }
                LabeledContent("Open") {
                    HStack {
                        Button("Note") {
                            let url = StorageLocation.currentURL
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [FileManager.default.fileExists(atPath: url.path) ? url : StorageLocation.currentFolder])
                        }
                        Button("History") { Snapshots.revealInFinder() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: keybindOn) { _, _ in ScratchpadService.shared.syncWithPreferences() }
        .onAppear {
            if model.fontFace != .sanFrancisco && (model.fontFace != .newYork || !Self.newYorkAvailable) {
                model.fontFace = .sanFrancisco
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Pick a folder for scratchpad.md. An iCloud Drive or Dropbox folder keeps it in sync."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let result = try StorageLocation.setFolder(folder, currentText: model.text)
            model.adoptLoadedText(result.loadedExisting ? result.newText : model.text)
            folderError = result.backupURL.map { "Your previous note was kept as \($0.lastPathComponent)." }
        } catch {
            folderError = error.localizedDescription
        }
        folderPath = StorageLocation.currentFolder.path
    }

    private func resetFolder() {
        do {
            try StorageLocation.resetToDefault(currentText: model.text)
            model.adoptLoadedText(model.text)
            folderError = nil
        } catch {
            folderError = error.localizedDescription
        }
        folderPath = StorageLocation.currentFolder.path
    }
}

// MARK: - Spaces

private struct SpacesPage: View {
    @AppStorage(SpacesDefaults.enabled) private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    Text("Instant space switching")
                }
            }
            Section {
                SpaceKeybindRow(identifier: .left, title: "Previous space")
                SpaceKeybindRow(identifier: .right, title: "Next space")
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
        .onChange(of: enabled) { _, _ in sync() }
    }

    private func sync() { MainActor.assumeIsolated { SpaceSwitcher.shared.syncWithPreferences() } }
}

private struct SpaceKeybindRow: View {
    let identifier: HotkeyIdentifier
    let title: String
    @ObservedObject private var store = HotkeyStore.shared

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                KeybindField(display: store.combination(for: identifier).displayString, onRecord: { event in
                    let isFunctionKey = (0x7A...0x7F).contains(Int(event.keyCode))
                        || [0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x67, 0x6D, 0x6F].contains(Int(event.keyCode))
                    guard let combo = HotkeyCombination.from(event: event), combo.modifiers != 0 || isFunctionKey else { return false }
                    store.update(combo, for: identifier)
                    if !store.isEnabled(identifier) { store.setEnabled(true, for: identifier) }
                    return true
                }, onStart: {
                    HotKeyManager.shared.unregisterAll()
                }, onStop: {
                    MainActor.assumeIsolated { SpaceSwitcher.shared.reregisterAllHotkeys() }
                })
                .disabled(!store.isEnabled(identifier))
                Toggle("", isOn: Binding(get: { store.isEnabled(identifier) },
                                         set: { store.setEnabled($0, for: identifier) }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

// MARK: - Color Picker

private struct ColorPickerPage: View {
    @AppStorage(DefaultsKey.colorPickerFormat) private var format = "hex"
    @AppStorage(DefaultsKey.colorPickerBareHex) private var bareHex = false
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        Form {
            Section {
                if !permissions.screenRecording {
                    PermissionRow(title: "Screen Recording",
                                  caption: "Needed for the magnifier",
                                  granted: false) {
                        permissions.requestScreenRecording()
                        permissions.openScreenRecordingSettings()
                    }
                }
            }
            Section {
                Picker("Copy as", selection: $format) {
                    ForEach(ColorCopyFormat.allCases) { format in
                        Text(format.label).tag(format.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                if format == ColorCopyFormat.hex.rawValue {
                    Toggle("Leave out the #", isOn: $bareHex)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutPage: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: AppInfo.version)
                LabeledContent("Built on", value: "Vorssaint · Wisp · InstantSpaceSwitcher")
                LabeledContent("License", value: "GPL-3.0")
            }
        }
        .formStyle(.grouped)
    }
}
