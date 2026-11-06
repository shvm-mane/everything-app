// SPDX-License-Identifier: GPL-3.0-or-later
// Wisp's scratchpad, hosted in the Dynamic Island's scratchpad page.
// The editor (Scratchpad/Wisp) is Wisp's own code, MIT licensed; this file
// replaces Wisp's floating panel, menu bar and main menu with the island.

import AppKit
import SwiftUI

/// Owns the one Wisp editor model and plays the part of Wisp's
/// PanelController + main menu: open/dismiss bookkeeping and the menu's
/// key equivalents, which an accessory app has no menu bar to carry.
@MainActor
final class WispIsland {
    static let shared = WispIsland()

    /// Created on first use so nothing is read from disk until the
    /// scratchpad is actually opened.
    private(set) lazy var model = EditorModel()

    private init() {}

    /// Wisp's "panel opened" sequence.
    func didOpen() {
        model.requestFocus()
        // Everything: the disk read and restyling wait until the island has
        // finished moving, so they never cost a frame of the page change.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [model] in
            model.reloadFromDiskIfChanged()
            model.refreshPlaceholder()
        }
    }

    /// Wisp's "panel dismissed" sequence: flush the save and checkpoint.
    func didClose() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [model] in
            model.saveAndCheckpoint()
            MemoryRelief.soon()
        }
    }

    /// Flush before the app quits.
    func prepareToExit() {
        model.editor?.finishEditing()
        model.flushSave()
    }

    var hotKeyDisplay: String {
        GlobalShortcut.saved(for: DefaultsKey.scratchpadShortcut, fallback: .scratchpadDefault).displayString
    }

    /// The scratchpad's text view, or nil when focus is elsewhere (the find
    /// field is an NSTextView too, so field editors are excluded).
    private func noteTextView(in window: NSWindow?) -> NSTextView? {
        guard let textView = window?.firstResponder as? NSTextView, !textView.isFieldEditor else { return nil }
        return textView
    }

    /// Wisp's main-menu shortcuts. Returns true when the event was used.
    func handleKey(_ event: NSEvent, in window: NSWindow?) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.keyCode == 53 {
            // Esc closes find or help first, as in Wisp; otherwise the island handles it.
            if model.showFind { withAnimation(.easeInOut(duration: 0.15)) { model.closeFind() }; return true }
            if model.showHelp { model.closeHelp(); return true }
            return false
        }
        switch flags {
        case [.command, .shift]:
            if event.keyCode == 36 || event.keyCode == 76 { _ = model.archiveToInbox(); return true }
            if key == "d", let tv = noteTextView(in: window) {
                tv.insertText(LineEditing.dateStamp(), replacementRange: tv.selectedRange())
                return true
            }
        case [.command]:
            switch key {
            case "f": model.openFind(); return true
            case "b":
                if let tv = noteTextView(in: window) { MarkdownWrap.toggle(in: tv, marker: "**"); return true }
            case "i":
                if let tv = noteTextView(in: window) { MarkdownWrap.toggle(in: tv, marker: "*"); return true }
            case "l":
                if let tv = noteTextView(in: window) {
                    LineEditing.apply(LineEditing.toggleTask(in: tv.string, selection: tv.selectedRange()), to: tv)
                    return true
                }
            case "g":
                if model.showFind { model.findNext(); return true }
            default: break
            }
        default: break
        }
        return false
    }
}

/// The island's scratchpad page: Wisp's editor, always on its dark palette
/// since the island is dark glass whatever the system appearance.
struct NotchScratchpadView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var model = WispIsland.shared.model

    var body: some View {
        EditorView(model: model, hotKeyDisplay: WispIsland.shared.hotKeyDisplay, showsHeader: false)
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Everything: the count and the History/Saved folders sit right
            // of the camera; the headings run along the bottom of the page.
            // Everything: the count top left, the folder button top right.
            .notchBand(leading: {
                ScratchpadWordCount(model: model).padding(.leading, 6)
            }, trailing: {
                QuietButton(action: { NSWorkspace.shared.open(StorageLocation.currentFolder) },
                            help: "Open the scratchpad folder") {
                    Image(systemName: "folder").font(.system(size: 12, weight: .medium))
                }
                .environment(\.colorScheme, .dark)
                .padding(.trailing, 4)
            })
            .onAppear { WispIsland.shared.didOpen() }
            .onDisappear { WispIsland.shared.didClose() }
    }
}

/// The word count (or a brief notice) in the island's top row.
private struct ScratchpadWordCount: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        Group {
            if model.saveFailed {
                Text("couldn't save").foregroundStyle(.orange)
            } else if let notice = model.notice {
                Text(notice).foregroundStyle(.secondary)
            } else if model.wordCount > 0 {
                Text(model.wordCount == 1 ? "1 word" : "\(model.wordCount) words").monospacedDigit()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .animation(.easeOut(duration: 0.2), value: model.notice)
        .environment(\.colorScheme, .dark)
    }
}
