// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SuperKeyStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let modifierKeysNote: String
    let sourceKey: String
    let capsLockKey: String
    let rightKeyFormat: String
    let holdHint: String
    let soloSection: String
    let soloCaption: String
    let soloNothing: String
    let soloCapsLock: String
    let soloEscape: String
    let activeNow: String
    let panelCaptionFormat: String
    let manageButton: String
    let soloInputSource: String
    let mappingForeignMapping: String
    let mappingSystemRefused: String
    let keyboardTapRefused: String

    func mappingFailure(_ failure: SuperKeyMappingFailure) -> String {
        switch failure {
        case .foreignMapping: return mappingForeignMapping
        case .systemRefused: return mappingSystemRefused
        case .keyboardTapRefused: return keyboardTapRefused
        }
    }
}

extension FeatureStrings {
    static func superKey(_ language: AppLanguage) -> SuperKeyStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension SuperKeyStrings {
    func sourceLabel(_ source: SuperKeySource) -> String {
        guard let symbol = source.symbol else { return capsLockKey }
        return String(format: rightKeyFormat, symbol)
    }

    static let enUS = SuperKeyStrings(
        pageTitle: "Super key",
        hubDescription: "Turns one key into the modifier combination you choose.",
        enableToggle: "Use this key as the super key",
        enableCaption: "Hold it and press any key. Choose one or more modifiers below.",
        modifierKeysNote: "Keep this key set to its default action in System Settings › Keyboard › Modifier Keys.",
        sourceKey: "Key to hold",
        capsLockKey: "Caps Lock",
        rightKeyFormat: "Right %@",
        holdHint: "Hold",
        soloSection: "A tap on its own",
        soloCaption: "What a quick tap does when no other key is pressed.",
        soloNothing: "Nothing",
        soloCapsLock: "Turn capitals on and off",
        soloEscape: "Press Escape",
        activeNow: "Working now",
        panelCaptionFormat: "%1$@ holds %2$@.",
        manageButton: "Set up…",
        soloInputSource: "Switch input source; hold for Caps Lock",
        mappingForeignMapping: "Another app’s key mapping uses the selected key. Remove it in that app: quitting it is not enough.",
        mappingSystemRefused: "macOS refused the key mapping. Reconnect the keyboard or restart the Mac, then switch this on again.",
        keyboardTapRefused: "macOS would not let EVERYTHING watch the keyboard. Turn EVERYTHING off and on in System Settings › Privacy & Security › Accessibility, then switch this on again."
    )

}
