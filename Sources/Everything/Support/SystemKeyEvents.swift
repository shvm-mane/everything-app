import AppKit
enum SystemKeyEvents {
    static let systemDefinedEventTypeRawValue: UInt32 = 14
}

enum PermissionKind {
    case accessibility
    case screenRecording
    case microphone
}

enum CommandBarSearch {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum MetricDetailKind: String, Equatable, Identifiable {
    case cpu, gpu, memory, network, disk, battery, power, fan, connectedDevices
    var id: String { rawValue }
    var monitorNeeds: SystemMonitorPanelNeeds { .none }
}

final class PanelInteractionState {
    static let shared = PanelInteractionState()
    var viewKeepsPopoverOpen = false
    var isPresentingPopoverModal = false
    var anchorScreen: NSScreen?
    private init() {}
}
