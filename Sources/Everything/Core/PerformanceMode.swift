import AppKit

/// Liquid glass off: drops glass, blur and decorative motion.
enum PerformanceMode {
    static let key = "performanceMode"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static let motionSpeed: Double = 2
    static var reduceTransparency: Bool { isOn || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
}
