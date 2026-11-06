// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RadialMenuSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = RadialMenuService.shared
    @AppStorage(DefaultsKey.radialMenuEnabled) private var enabled = false
    @AppStorage(DefaultsKey.radialMenuAtPointer) private var atPointer = true
    @AppStorage(DefaultsKey.radialMenuActivationMode) private var activationModeRaw =
        RadialMenuActivationMode.pressOrHold.rawValue
    @AppStorage(DefaultsKey.middleClickEnabled) private var middleClickEnabled = false
    @AppStorage(DefaultsKey.middleClickTapFingers) private var middleClickTapFingers = 0

    @State private var profiles: [RadialMenuProfile] = RadialMenuSupport.decodeProfiles(
        UserDefaults.standard.data(forKey: DefaultsKey.radialMenuProfiles))
    @State private var selectedProfileID: UUID?
    @State private var openSubmenuID: UUID?
    @State private var editing: RadialMenuItem?
    @State private var dragging: RadialMenuItem?
    @Environment(\.colorScheme) private var colorScheme

    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }

    private var selectedProfileIndex: Int {
        if let selectedProfileID, let idx = profiles.firstIndex(where: { $0.id == selectedProfileID }) {
            return idx
        }
        return 0
    }

    private var selectedProfile: RadialMenuProfile {
        if profiles.indices.contains(selectedProfileIndex) {
            return profiles[selectedProfileIndex]
        }
        return profiles.first ?? RadialMenuProfilePreset.general.createProfile()
    }

    private var currentProfileItems: [RadialMenuItem] {
        selectedProfile.items
    }

    private var level: [RadialMenuItem] {
        guard let openSubmenu else { return currentProfileItems }
        return openSubmenu.children
    }

    private var openSubmenu: RadialMenuItem? {
        guard let openSubmenuID else { return nil }
        return currentProfileItems.first { $0.id == openSubmenuID }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Radial menu")
                        Text("Five-finger tap on the trackpad")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !permissions.accessibility {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility")
                            Text("Needed to notice the five-finger tap.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Grant…") { permissions.requestAccessibility() }
                    }
                }
            }

            Section {
                RadialMenuVisualCanvas(
                    items: level,
                    profileColor: Color(red: 0.93, green: 0.92, blue: 0.9),
                    text: text,
                    openSubmenu: openSubmenu,
                    onSelect: { item in editing = item },
                    onReorder: { moved, target in swap(moved, with: target) },
                    onRemove: { item in remove(id: item.id) },
                    onOpenSubmenu: { item in openSubmenuID = item.id },
                    onBack: { openSubmenuID = nil; dragging = nil },
                    onAdd: { editing = RadialMenuItem(kind: .file) },
                    onReset: nil
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                HStack {
                    if level.count < RadialMenuSupport.maxItemsPerWheel {
                        Button {
                            editing = RadialMenuItem(kind: .file)
                        } label: {
                            Label(text.addButton, systemImage: "plus")
                        }
                    }
                    Spacer()
                    Button(text.tryButton) {
                        RadialMenuService.shared.presentPreview(for: selectedProfile)
                    }
                }
            } header: {
                Text(text.actionsHeader)
            } footer: {
                Text(level.count >= RadialMenuSupport.maxItemsPerWheel ? text.limitCaption
                     : "Click an action to edit it. Drag it to move it, or out of the wheel's frame to remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
        .onAppear {
            if selectedProfileID == nil || !profiles.contains(where: { $0.id == selectedProfileID }) {
                selectedProfileID = profiles.first?.id
            }
        }
        .onDrop(of: [UTType.text], delegate: RadialDragCleanupDelegate(dragging: $dragging))
        .sheet(item: $editing) { item in
            let isNew = !level.contains { $0.id == item.id }
            RadialItemEditor(text: text,
                             item: item,
                             isNew: isNew,
                             allowsSubmenu: openSubmenuID == nil,
                             openChildren: item.kind == .submenu ? { openSubmenuID = item.id } : nil,
                             save: { saved in
                                 upsert(saved)
                                 if isNew, saved.kind == .submenu {
                                     openSubmenuID = saved.id
                                 }
                             },
                             delete: isNew ? nil : { remove(id: item.id) })
        }
        .onChange(of: enabled) { _, on in
            RadialMenuService.shared.syncWithPreferences()
            requestAccessibilityIfNeeded(on)
        }
    }

    // MARK: - Profile Rows

    // MARK: - Mutations (every change lands in defaults right away)

    private func deleteProfile(id: UUID) {
        guard profiles.count > 1, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)
        let nextIndex = min(index, profiles.count - 1)
        selectedProfileID = profiles[nextIndex].id
        openSubmenuID = nil
        dragging = nil
        persist()
    }

    private func setLevel(_ new: [RadialMenuItem]) {
        guard profiles.indices.contains(selectedProfileIndex) else { return }
        if let openSubmenuID, let index = profiles[selectedProfileIndex].items.firstIndex(where: { $0.id == openSubmenuID }) {
            profiles[selectedProfileIndex].items[index].children = new
        } else {
            profiles[selectedProfileIndex].items = new
        }
        persist()
    }

    private func upsert(_ item: RadialMenuItem) {
        RadialMenuIconStore.invalidate(item.payload)
        var new = level
        if let index = new.firstIndex(where: { $0.id == item.id }) {
            new[index] = item
        } else {
            new.append(item)
        }
        setLevel(new)
    }

    private func remove(id: UUID) {
        setLevel(level.filter { $0.id != id })
    }

    private func move(_ moved: RadialMenuItem, before target: RadialMenuItem) {
        var new = level
        guard let from = new.firstIndex(where: { $0.id == moved.id }),
              let to = new.firstIndex(where: { $0.id == target.id }),
              from != to else { return }
        new.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        setLevel(new)
    }

    private func swap(_ first: RadialMenuItem, with second: RadialMenuItem) {
        var new = level
        guard let from = new.firstIndex(where: { $0.id == first.id }),
              let to = new.firstIndex(where: { $0.id == second.id }),
              from != to else { return }
        new.swapAt(from, to)
        setLevel(new)
    }

    private func persist() {
        UserDefaults.standard.set(RadialMenuSupport.encodeProfiles(profiles), forKey: DefaultsKey.radialMenuProfiles)
        RadialMenuService.shared.syncWithPreferences()
    }

    private func shortcutConflictTitle(_ shortcut: GlobalShortcut, excluding profileID: UUID) -> String? {
        if let other = RadialMenuSupport.profile(using: shortcut, in: profiles, excluding: profileID) {
            return other.displayName(text)
        }
        if let role = GlobalShortcutRole.conflict(for: shortcut, excluding: .radialMenu) {
            return role.title(l10n.s)
        }
        if let title = WindowLayoutService.shared.shortcutConflictTitle(shortcut) {
            return title
        }
        return nil
    }

    private func requestAccessibilityIfNeeded(_ on: Bool) {
        guard on, RadialMenuSupport.needsAccessibility(profiles), !permissions.accessibility else { return }
        permissions.requestAccessibility()
    }

}

// MARK: - Color Picker

// MARK: - Profile Shortcut Row

// MARK: - Row

private struct RadialDragCleanupDelegate: DropDelegate {
    @Binding var dragging: RadialMenuItem?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: - Editor sheet

private struct RadialItemEditor: View {
    let text: RadialMenuFeatureStrings
    @State var item: RadialMenuItem
    let isNew: Bool
    let allowsSubmenu: Bool
    var openChildren: (() -> Void)? = nil
    let save: (RadialMenuItem) -> Void
    let delete: (() -> Void)?

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @State private var shortcutMessage: ShortcutMessage?
    @State private var isFetchingFavicon = false
    @State private var faviconStatus: FaviconFetchStatus?

    enum FaviconFetchStatus {
        case success
        case error
    }

    enum ShortcutMessage {
        case hint(String)
        case problem(String)

        var text: String {
            switch self {
            case .hint(let text), .problem(let text): return text
            }
        }

        var isProblem: Bool {
            if case .problem = self { return true }
            return false
        }
    }

    private var availableTools: [RadialMenuTool] {
        RadialMenuTool.allCases.filter { $0 == .colorPicker && $0.isRunnable() }
    }

    private var availableQuickToggles: [RadialMenuQuickToggle] {
        RadialMenuQuickToggle.allCases.filter { $0.feature.isAvailable }
    }

    private var urlIsInvalid: Bool {
        item.kind == .url && RadialMenuSupport.normalizedURL(item.payload) == nil
    }

    private var saveDisabled: Bool {
        !RadialMenuSupport.isValidPayload(item)
    }

    @State private var choosingSymbol = false
    @State private var faviconWork: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? text.addButton : item.displayName(text))
                .font(.headline)

            Picker("", selection: kindBinding) {
                Text("File").tag(RadialMenuItem.Kind.file)
                Text("Link").tag(RadialMenuItem.Kind.url)
                if !availableTools.isEmpty {
                    Text("Color Picker").tag(RadialMenuItem.Kind.tool)
                }
                if allowsSubmenu || item.kind == .submenu {
                    Text("Submenu").tag(RadialMenuItem.Kind.submenu)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                if let target = targetRow {
                    GridRow {
                        Text(target).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        payloadEditor
                    }
                }
                GridRow {
                    Text("Name").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    TextField("", text: $item.name, prompt: Text(text.automaticLabel))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }
                GridRow {
                    Text("Icon").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    iconControl
                }
            }

            if urlIsInvalid, !item.payload.isEmpty {
                Text(text.urlInvalid).font(.caption).foregroundStyle(.orange)
            }
            if item.kind == .submenu, let openChildren {
                Button {
                    dismiss()
                    openChildren()
                } label: {
                    Label(text.editActionsButton, systemImage: "chevron.forward")
                }
            }

            HStack {
                if let delete {
                    Button(text.deleteButton, role: .destructive) {
                        delete()
                        dismiss()
                    }
                }
                Spacer()
                Button(l10n.s.uninstallerCancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(text.saveButton) {
                    var saved = item
                    saved.name = item.name.trimmingCharacters(in: .whitespaces)
                    save(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var targetRow: String? {
        switch item.kind {
        case .file: return "File"
        case .url: return "Link"
        case .tool where availableTools.count > 1: return "Tool"
        default: return nil
        }
    }

    @ViewBuilder private var iconControl: some View {
        HStack(spacing: 8) {
            Button { choosingSymbol = true } label: {
                iconPreview
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(choosingSymbol ? 0.6 : 0.25), lineWidth: 1))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white, .secondary)
                            .offset(x: 3, y: 3)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose an icon")
            .popover(isPresented: $choosingSymbol, arrowEdge: .bottom) {
                RadialSymbolPicker(text: text, item: $item)
                    .padding(12)
                    .frame(width: 300, height: 260)
            }

            if isFetchingFavicon { ProgressView().controlSize(.small) }
            if item.kind == .url {
                Button("Website Icon") {
                    item.symbolName = ""
                    fetchWebsiteFavicon()
                }
                .disabled(isFetchingFavicon || urlIsInvalid || item.payload.isEmpty)
            } else if !item.symbolName.isEmpty {
                Button("Reset") { item.symbolName = "" }
            }
        }
    }

    @ViewBuilder private var iconPreview: some View {
        if !item.symbolName.isEmpty {
            Image(systemName: item.symbolName).font(.system(size: 14, weight: .semibold))
        } else if item.kind == .file, !item.payload.isEmpty {
            Image(nsImage: RadialMenuIconStore.fileIcon(for: item.payload)).resizable().interpolation(.high)
                .frame(width: 20, height: 20)
        } else if let custom = RadialMenuIconStore.customIcon(for: item) {
            Image(nsImage: custom).resizable().interpolation(.high).frame(width: 20, height: 20)
        } else {
            Image(systemName: item.defaultSymbolName).font(.system(size: 14, weight: .semibold))
        }
    }

    private func scheduleFavicon() {
        faviconWork?.cancel()
        guard item.kind == .url, item.symbolName.isEmpty, !urlIsInvalid, !item.payload.isEmpty else { return }
        let work = DispatchWorkItem { fetchWebsiteFavicon() }
        faviconWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private var kindBinding: Binding<RadialMenuItem.Kind> {
        Binding(get: { item.kind }, set: { kind in
            guard kind != item.kind else { return }
            item.kind = kind
            shortcutMessage = nil
            faviconStatus = nil
            if kind != .url { item.customIconData = nil }
            switch kind {
            case .tool: item.payload = availableTools.first?.rawValue ?? ""
            case .quickToggle: item.payload = availableQuickToggles.first?.rawValue ?? ""
            case .windowLayout: item.payload = WindowLayoutAction.leftHalf.rawValue
            case .media: item.payload = RadialMenuMediaKey.playPause.rawValue
            default: item.payload = ""
            }
            if kind != .submenu { item.children = [] }
        })
    }

    @ViewBuilder
    private var payloadEditor: some View {
        switch item.kind {
        case .app:
            LabeledContent(text.kindApp) {
                Button(chooseTitle) { choose(applications: true) }
            }
        case .file:
            Button(chooseTitle) { choose(applications: false) }
        case .url:
            TextField("", text: $item.payload, prompt: Text(text.urlPlaceholder))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onChange(of: item.payload) { _, _ in
                    faviconStatus = nil
                    item.customIconData = nil
                    scheduleFavicon()
                }
                .onAppear { if item.customIconData == nil { scheduleFavicon() } }
        case .shortcut:
            LabeledContent(text.kindShortcut) {
                ShortcutRecorderButton(shortcut: GlobalShortcut(storageValue: item.payload) ?? .radialMenuDefault,
                                       isEnabled: true,
                                       waitingTitle: l10n.s.shortcutPressKeys,
                                       emptyTitle: item.payload.isEmpty ? l10n.s.shortcutNone : nil,
                                       clearAction: {
                                           item.payload = ""
                                           shortcutMessage = nil
                                       },
                                       notCapturedAction: {
                                           shortcutMessage = .problem(l10n.s.shortcutNotCaptured)
                                       },
                                       recordingChanged: { recording in
                                           shortcutMessage = recording
                                               ? .hint(ShortcutRecordingCaption.text(l10n.s, canClear: true))
                                               : nil
                                       },
                                       invalidAction: {
                                           shortcutMessage = .problem(l10n.s.shortcutInvalid)
                                       },
                                       captureAction: {
                                           item.payload = $0.storageValue
                                           shortcutMessage = nil
                                       })
                    .frame(width: 108)
            }
        case .tool where availableTools.count <= 1:
            EmptyView()
        case .tool:
            Picker("", selection: $item.payload) {
                ForEach(availableTools) { tool in
                    Text(tool.title)
                        .tag(tool.rawValue)
                }
            }
        case .quickToggle:
            let quickToggleText = FeatureStrings.quickToggles(l10n.language)
            Picker(quickToggleText.pageTitle, selection: $item.payload) {
                ForEach(availableQuickToggles) { action in
                    Label(action.radialTitle, systemImage: action.symbolName)
                        .tag(action.rawValue)
                }
            }
        case .windowLayout:
            let windowText = FeatureStrings.windowLayout(l10n.language)
            Picker(windowText.title, selection: $item.payload) {
                ForEach(WindowLayoutAction.allCases) { action in
                    Label(action.title(windowText), systemImage: action.symbolName)
                        .tag(action.rawValue)
                }
            }
        case .media:
            Picker(text.mediaLabel, selection: $item.payload) {
                Text(text.mediaPlayPause).tag(RadialMenuMediaKey.playPause.rawValue)
                Text(text.mediaPrevious).tag(RadialMenuMediaKey.previousTrack.rawValue)
                Text(text.mediaNext).tag(RadialMenuMediaKey.nextTrack.rawValue)
                Text(text.mediaNowPlaying).tag(RadialMenuMediaKey.nowPlaying.rawValue)
            }
        case .submenu:
            EmptyView()
        }
    }

    private var chooseTitle: String {
        if item.payload.isEmpty { return text.chooseButton }
        return RadialMenuIconStore.fileName(for: item.payload)
    }

    private func choose(applications: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = !applications
        if applications {
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.keyWindow, window.isVisible else {
            guard panel.runModal() == .OK, let url = panel.url else { return }
            applyChosen(url)
            return
        }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            applyChosen(url)
        }
    }

    private func applyChosen(_ url: URL) {
        RadialMenuIconStore.invalidate(item.payload)
        item.payload = url.path
    }

    private func fetchWebsiteFavicon() {
        guard !item.payload.isEmpty, !urlIsInvalid else { return }
        isFetchingFavicon = true
        faviconStatus = nil

        RadialMenuFaviconFetcher.fetchFavicon(for: item.payload) { result in
            isFetchingFavicon = false
            switch result {
            case .success(let data):
                item.customIconData = data
                item.symbolName = ""
                RadialMenuIconStore.invalidate(item: item)
                faviconStatus = .success
            case .failure:
                faviconStatus = .error
            }
        }
    }
}

// MARK: - Icon picker

private struct RadialSymbolPicker: View {
    let text: RadialMenuFeatureStrings
    @Binding var item: RadialMenuItem

    private static let symbols = RadialMenuSupport.symbolNames.filter {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
    }

    private let columns = [GridItem(.adaptive(minimum: 34), spacing: 6)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                iconButton(symbol: nil)
                ForEach(Self.symbols, id: \.self) { symbol in
                    iconButton(symbol: symbol)
                }
            }
        }
    }

    @ViewBuilder
    private func iconButton(symbol: String?) -> some View {
        let selected = symbol == nil ? item.symbolName.isEmpty : item.symbolName == symbol
        Button {
            item.symbolName = symbol ?? ""
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                } else if item.kind == .app || item.kind == .file, !item.payload.isEmpty {
                    Image(nsImage: RadialMenuIconStore.fileIcon(for: item.payload))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                } else if let customImage = RadialMenuIconStore.customIcon(for: item) {
                    Image(nsImage: customImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: item.defaultSymbolName)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .frame(width: 34, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.13),
                                  lineWidth: selected ? 1.2 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(symbol ?? text.automaticLabel)
    }

}
