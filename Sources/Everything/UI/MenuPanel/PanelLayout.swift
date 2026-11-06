// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

protocol PanelOrderItem: RawRepresentable, CaseIterable, Hashable where RawValue == String {}

enum PanelSectionID: String, CaseIterable, Identifiable, Hashable {
    case keepAwake, brightness, mixer, system, network, disk, power, fanControl, utilities, controls,
         toggles, wallpaper

    var id: String { rawValue }

    func title(_ s: Strings) -> String {
        switch self {
        case .keepAwake: return s.keepAwakeTitle
        case .brightness: return FeatureStrings.brightness(L10n.shared.language).pageTitle
        case .mixer: return s.mixerSection
        case .system: return s.systemSection
        case .network: return s.networkSection
        case .disk: return s.diskSection
        case .power: return s.powerSection
        case .fanControl: return FeatureStrings.fanControl(L10n.shared.language).title
        case .utilities: return s.utilitiesSection
        case .controls: return s.quickControlsSection
        case .toggles: return FeatureStrings.quickToggles(L10n.shared.language).pageTitle
        case .wallpaper: return FeatureStrings.wallpaper(L10n.shared.language).pageTitle
        }
    }

    var symbolName: String {
        switch self {
        case .keepAwake: return "moon.zzz.fill"
        case .brightness: return "display.2"
        case .mixer: return "speaker.wave.2"
        case .system: return "cpu"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        case .fanControl: return "fanblades.fill"
        case .utilities: return "wrench.and.screwdriver.fill"
        case .controls: return "switch.2"
        case .toggles: return "togglepower"
        case .wallpaper: return "photo.on.rectangle"
        }
    }

    var visibilityKey: String {
        switch self {
        case .keepAwake: return DefaultsKey.panelShowKeepAwake
        case .brightness: return DefaultsKey.panelShowBrightness
        case .mixer: return DefaultsKey.monitorShowMixer
        case .system: return DefaultsKey.monitorShowSystem
        case .network: return DefaultsKey.monitorShowNetwork
        case .disk: return DefaultsKey.monitorShowDisk
        case .power: return DefaultsKey.monitorShowPower
        case .fanControl: return DefaultsKey.panelShowFanControl
        case .utilities: return DefaultsKey.panelShowUtilities
        case .controls: return DefaultsKey.panelShowControls
        case .toggles: return DefaultsKey.panelShowToggles
        case .wallpaper: return DefaultsKey.panelShowWallpaper
        }
    }

    var shownByDefault: Bool { true }

    var featureGate: [AppFeature] {
        switch self {
        case .keepAwake: return [.keepAwake]
        case .brightness: return [.brightness]
        case .mixer: return [.mixer, .audioPriority]
        case .system: return [.monitorCPU, .monitorGPU, .monitorMemory, .connectedDevices]
        case .network: return [.monitorNetwork]
        case .disk: return [.monitorDisk]
        case .power: return [.monitorPower]
        case .fanControl: return [.fanControl]
        case .utilities: return [.quickLauncher, .cleaner, .homebrew, .appUpdates, .mediaTools,
                                 .clipboardHistory,
                                 .windowLayout, .uninstaller, .urlCleaner, .cleaningMode, .screenOCR,
                                 .colorPicker, .screenshot, .screenRecorder,
                                 .cameraPreview, .scratchpad, .commandBar, .portManager]
        case .controls: return [.scrollInverter, .linearScroll, .focusFollowsMouse, .mouseAcceleration, .mouseNavigation, .mouseButtonShortcuts, .switcher,
                                .finderCutPaste, .autoQuit,
                                .shelf, .windowMaximizer, .dockPreview, .keyboardDebounce, .dockClick, .spacesOrder,
                                .middleClick, .textSnippets, .superKey, .radialMenu, .mouseClickDebounce, .notch]
        case .toggles: return [.quickToggles, .micMute, .quitApps]
        case .wallpaper: return [.wallpaper]
        }
    }

    var isAvailable: Bool { featureGate.contains(where: \.isAvailable) }
}

enum PanelLayout {
    private static var defaults: UserDefaults { .standard }

    static var order: [PanelSectionID] {
        let saved = (defaults.string(forKey: DefaultsKey.panelSectionOrder) ?? "")
            .split(separator: ",")
            .compactMap { PanelSectionID(rawValue: String($0)) }
        var seen = Set<PanelSectionID>()
        var result: [PanelSectionID] = []
        for id in saved where seen.insert(id).inserted { result.append(id) }
        for id in PanelSectionID.allCases where seen.insert(id).inserted {
            if id == .disk, let networkIndex = result.firstIndex(of: .network) {
                result.insert(id, at: networkIndex + 1)
            } else if id == .controls, let utilitiesIndex = result.firstIndex(of: .utilities) {
                result.insert(id, at: utilitiesIndex + 1)
            } else if id == .brightness, let keepAwakeIndex = result.firstIndex(of: .keepAwake) {
                result.insert(id, at: keepAwakeIndex + 1)
            } else {
                result.append(id)
            }
        }
        return result
    }

    static func setOrder(_ ids: [PanelSectionID]) {
        defaults.set(ids.map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.panelSectionOrder)
    }

    static func itemOrder<Item: PanelOrderItem>(_ type: Item.Type, key: String) -> [Item] {
        let defaultOrder = type.allCases.map(\.rawValue)
        let raw = defaults.string(forKey: key) ?? ""
        return Defaults.sanitizedPanelItemOrder(raw, defaultOrder: defaultOrder).compactMap(Item.init(rawValue:))
    }

    static func setItemOrder<Item: PanelOrderItem>(_ ids: [Item], key: String) {
        defaults.set(ids.map(\.rawValue).joined(separator: ","), forKey: key)
    }

    static func resetItemOrder(key: String) {
        defaults.removeObject(forKey: key)
    }

    static func isShown(_ id: PanelSectionID) -> Bool {
        defaults.object(forKey: id.visibilityKey) as? Bool ?? id.shownByDefault
    }

    static func setShown(_ shown: Bool, for id: PanelSectionID) {
        defaults.set(shown, forKey: id.visibilityKey)
    }

    static func isVisibleInPanel(_ id: PanelSectionID) -> Bool {
        guard id.isAvailable, isShown(id) else { return false }
        return id != .brightness || defaults.bool(forKey: DefaultsKey.brightnessControlEnabled)
    }

    static func isCollapsed(_ id: PanelSectionID) -> Bool {
        collapsedSet().contains(id.rawValue)
    }

    static func setCollapsed(_ collapsed: Bool, for id: PanelSectionID) {
        var set = collapsedSet()
        if collapsed { set.insert(id.rawValue) } else { set.remove(id.rawValue) }
        defaults.set(set.sorted().joined(separator: ","), forKey: DefaultsKey.panelCollapsedSections)
    }

    static func resetCollapsedSectionsOnce(for version: String) {
        guard defaults.string(forKey: DefaultsKey.panelCollapsedResetVersion) != version else { return }
        defaults.removeObject(forKey: DefaultsKey.panelCollapsedSections)
        defaults.set(version, forKey: DefaultsKey.panelCollapsedResetVersion)
    }

    private static func collapsedSet() -> Set<String> {
        Set((defaults.string(forKey: DefaultsKey.panelCollapsedSections) ?? "")
            .split(separator: ",").map(String.init))
    }
}

struct PanelReorderableItem<Item: PanelOrderItem, Content: View>: View {
    let item: Item
    var isEnabled = true
    var previewsAsCard = false
    @Binding var order: [Item]
    @Binding var dragging: Item?
    let content: () -> Content

    var body: some View {
        if isEnabled {
            draggableContent
                .onDrop(of: [UTType.text], delegate: PanelItemDropDelegate(item: item,
                                                                           order: $order,
                                                                           dragging: $dragging))
        } else {
            content()
        }
    }

    @ViewBuilder
    private var draggableContent: some View {
        if previewsAsCard {
            content()
                .onDrag(itemProvider) {
                    content()
                        .frame(minWidth: 220, alignment: .leading)
                        .panelCard(interactive: false, padded: false)
                }
        } else {
            content()
                .onDrag(itemProvider)
        }
    }

    private func itemProvider() -> NSItemProvider {
        dragging = item
        return NSItemProvider(object: item.rawValue as NSString)
    }
}

private struct PanelItemDropDelegate<Item: PanelOrderItem>: DropDelegate {
    let item: Item
    @Binding var order: [Item]
    @Binding var dragging: Item?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: item) else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

