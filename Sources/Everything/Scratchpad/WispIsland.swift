// SPDX-License-Identifier: GPL-3.0-or-later
// Hosts Wisp's editor (MIT, Scratchpad/Wisp) in the island.

import AppKit
import SwiftUI

@MainActor
final class WispIsland {
    static let shared = WispIsland()

    private(set) lazy var model = EditorModel()

    private init() {}

    func didOpen() {
        model.requestFocus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [model] in
            model.reloadFromDiskIfChanged()
            model.refreshPlaceholder()
        }
    }

    func didClose() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [model] in
            model.saveAndCheckpoint()
            MemoryRelief.soon()
        }
    }

    func prepareToExit() {
        model.flushSave()
    }

    var hotKeyDisplay: String {
        GlobalShortcut.saved(for: DefaultsKey.scratchpadShortcut, fallback: .scratchpadDefault).displayString
    }

    private func noteTextView(in window: NSWindow?) -> NSTextView? {
        guard let textView = window?.firstResponder as? NSTextView, !textView.isFieldEditor else { return nil }
        return textView
    }

    func handleKey(_ event: NSEvent, in window: NSWindow?) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.keyCode == 53 {
            if model.showFind { withAnimation(.easeInOut(duration: 0.15)) { model.closeFind() }; return true }
            if model.showHelp { model.closeHelp(); return true }
            return false
        }
        switch flags {
        case [.command, .shift]:
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

struct NotchScratchpadView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var model = WispIsland.shared.model

    var body: some View {
        EditorView(model: model, hotKeyDisplay: WispIsland.shared.hotKeyDisplay, showsHeader: false)
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
