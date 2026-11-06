import AppKit
// SPDX-License-Identifier: GPL-3.0-or-later
// NX_SYSDEFINED: the event type media, volume and brightness keys arrive as.
enum SystemKeyEvents {
    static let systemDefinedEventTypeRawValue: UInt32 = 14
}

/// Permissions the guide overlay can point at.
enum PermissionKind {
    case accessibility
    case screenRecording
    case microphone
}

/// Case-, accent- and width-insensitive text for the island's search fields.
enum CommandBarSearch {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The island once opened system metrics in detail; EVERYTHING has none, so
/// only the type remains for the island's bookkeeping.
enum MetricDetailKind: String, Equatable, Identifiable {
    case cpu, gpu, memory, network, disk, battery, power, fan, connectedDevices
    var id: String { rawValue }
    var monitorNeeds: SystemMonitorPanelNeeds { .none }
}

/// Hints older capture and media views still set; EVERYTHING has no popover.
final class PanelInteractionState {
    static let shared = PanelInteractionState()
    var viewKeepsPopoverOpen = false
    var isPresentingPopoverModal = false
    var anchorScreen: NSScreen?
    private init() {}
}
