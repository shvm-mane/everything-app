// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class ShelfSharePresenter: NSObject, NSSharingServicePickerDelegate {
    private var picker: NSSharingServicePicker?
    private var completion: ((Bool) -> Void)?

    func shareMenuItem(for urls: [URL], title: String) -> NSMenuItem {
        let item = makePicker(for: urls).standardShareMenuItem
        item.title = title
        return item
    }

    @discardableResult
    func present(for urls: [URL], from view: NSView, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard view.window != nil else { return false }
        let picker = makePicker(for: urls)
        self.completion = completion
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        return true
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              didChoose service: NSSharingService?) {
        guard sharingServicePicker === picker else { return }
        picker = nil
        let completion = self.completion
        self.completion = nil
        if service != nil { NSApp.activate(ignoringOtherApps: true) }
        completion?(service != nil)
    }

    private func makePicker(for urls: [URL]) -> NSSharingServicePicker {
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = self
        self.picker = picker
        completion = nil
        return picker
    }
}
