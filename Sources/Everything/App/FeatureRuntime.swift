// SPDX-License-Identifier: GPL-3.0-or-later
// EVERYTHING's features and what each starts. The set is fixed
// (`AppFeature.everythingFeatures`); a feature that is off starts nothing.

import AppKit

final class FeatureRuntime: ObservableObject {
    static let shared = FeatureRuntime()

    @Published private(set) var revision = 0

    private init() {}

    func syncAtLaunch() {
        for feature in AppFeature.allCases where feature.isAvailable {
            Self.bindings[feature]?()
        }
    }

    func sync(_ features: [AppFeature]) {
        for feature in features where feature.isAvailable {
            Self.bindings[feature]?()
        }
        revision += 1
    }

    func relaunchApp() { appDelegate()?.relaunchApp() }

    func isAvailable(_ feature: AppFeature) -> Bool { feature.isAvailable }

    private static let bindings: [AppFeature: () -> Void] = [
        .notch: { NotchService.shared.syncWithPreferences() },
        .notchAgents: { NotchService.shared.syncWithPreferences() },
        .scratchpad: { ScratchpadService.shared.syncWithPreferences() },
        .radialMenu: { RadialMenuService.shared.syncWithPreferences() },
        .mixer: {
            PreciseVolumeRollerService.shared.syncWithPreferences()
            AppVolumeMixer.shared.syncWithPreferences()
            AudioInputDeviceManager.shared.syncWithPreferences()
        },
        .brightness: { BrightnessService.shared.syncWithPreferences() },
        .diskImageInstaller: { DiskImageInstallerService.shared.syncWithPreferences() },
        .colorPicker: { ScreenCaptureService.shared.syncWithPreferences() },
    ]
}

extension AppFeature {
    /// No feature EVERYTHING ships depends on hardware a Mac may lack.
    var hardwareUnsupportedReason: String? { nil }
    var isHardwareSupported: Bool { true }
    var installBlockedReason: String? { nil }
}
