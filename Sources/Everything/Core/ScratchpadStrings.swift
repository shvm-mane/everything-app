// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ScratchpadFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let openButton: String
    let placeholder: String
    let copyAll: String
    let copied: String
    let exportAction: String
    let exportFailed: String
    let loadFailed: String
    let saveFailed: String
    let clearAction: String
    let retentionTitle: String
    let retentionNever: String
    let retentionDay: String
    let retentionWeek: String
    let retentionMonth: String
    let retentionCaption: String
    let closeOnClickOutside: String
    let keepOpen: String
    let backgroundOpacity: String
    let backgroundTranslucent: String
    let backgroundOpaque: String
    let newPad: String
    let padActions: String
    let renamePad: String
    let closePad: String
    let saveName: String
    let cancel: String
    let deletePadMessageFormat: String
    let padLimitFormat: String
    let previewFormatting: String
    let editText: String
    let taskDone: String
    let taskNotDone: String
    let markBold: String
    let markItalic: String
    let markStrikethrough: String
    let markHeading: String
    let markBullet: String
    let markNumbered: String
    let markQuote: String
    let markCode: String
    let markLink: String
    let formatMarks: String
    let textSize: String
}

extension FeatureStrings {
    static func scratchpad(_ language: AppLanguage) -> ScratchpadFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension ScratchpadFeatureStrings {
    static let enUS = ScratchpadFeatureStrings(
        pageTitle: "Scratchpad",
        hubDescription: "Floating pads for short-lived notes",
        panelCaption: "Quick notes in separate tabs",
        openButton: "Open scratchpad",
        placeholder: "Type anything. It saves by itself.",
        copyAll: "Copy all",
        copied: "Copied",
        exportAction: "Save as file",
        exportFailed: "The file could not be saved",
        loadFailed: "Your notes could not be opened. They were left unchanged.",
        saveFailed: "Your notes could not be saved. Copy them elsewhere before quitting.",
        clearAction: "Clear",
        retentionTitle: "Clear on its own",
        retentionNever: "Never",
        retentionDay: "After a day unused",
        retentionWeek: "After a week unused",
        retentionMonth: "After a month unused",
        retentionCaption: "The pad empties itself once the text goes that long without edits.",
        closeOnClickOutside: "Close when I click outside",
        keepOpen: "Keep open",
        backgroundOpacity: "Pad background",
        backgroundTranslucent: "Translucent",
        backgroundOpaque: "Opaque",
        newPad: "New scratchpad",
        padActions: "Scratchpad actions",
        renamePad: "Rename scratchpad",
        closePad: "Close scratchpad",
        saveName: "Save",
        cancel: "Cancel",
        deletePadMessageFormat: "Delete “%@” and everything in it?",
        padLimitFormat: "You can keep up to %d scratchpads",
        previewFormatting: "Show formatting",
        editText: "Edit text",
        taskDone: "Done",
        taskNotDone: "Not done",
        markBold: "Bold",
        markItalic: "Italic",
        markStrikethrough: "Strikethrough",
        markHeading: "Heading",
        markBullet: "Bulleted list",
        markNumbered: "Numbered list",
        markQuote: "Quote",
        markCode: "Code",
        markLink: "Link",
        formatMarks: "Formatting",
        textSize: "Text size"
    )

}

extension ScratchpadFeatureStrings {
    func label(for mark: ScratchpadMark) -> String {
        switch mark {
        case .bold: return markBold
        case .italic: return markItalic
        case .strikethrough: return markStrikethrough
        case .heading: return markHeading
        case .bullet: return markBullet
        case .numbered: return markNumbered
        case .quote: return markQuote
        case .code: return markCode
        case .link: return markLink
        }
    }
}
