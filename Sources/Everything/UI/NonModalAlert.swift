// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class NonModalAlert: NSObject {
    private static var open: [NonModalAlert] = []

    let alert: NSAlert
    private let retained: [AnyObject]
    private var completion: ((NSApplication.ModalResponse) -> Void)?

    private init(alert: NSAlert, retained: [AnyObject],
                 completion: @escaping (NSApplication.ModalResponse) -> Void) {
        self.alert = alert
        self.retained = retained
        self.completion = completion
    }

    @discardableResult
    static func present(_ alert: NSAlert,
                        retaining retained: [AnyObject] = [],
                        show: (NSWindow) -> Void = { window in
                            window.center()
                            window.makeKeyAndOrderFront(nil)
                        },
                        completion: @escaping (NSApplication.ModalResponse) -> Void) -> NonModalAlert {
        let presentation = NonModalAlert(alert: alert, retained: retained, completion: completion)
        if alert.buttons.isEmpty {
            alert.addButton(withTitle: Bundle(for: NSAlert.self)
                .localizedString(forKey: "OK", value: "OK", table: "Common"))
        }
        for button in alert.buttons {
            button.target = presentation
            button.action = #selector(respond(_:))
        }
        alert.layout()
        alert.window.level = .modalPanel
        alert.window.hidesOnDeactivate = false
        open.append(presentation)
        show(alert.window)
        return presentation
    }

    var isOpen: Bool { completion != nil }

    func dismiss(with response: NSApplication.ModalResponse) {
        guard let completion else { return }
        self.completion = nil
        alert.window.orderOut(nil)
        Self.open.removeAll { $0 === self }
        completion(response)
    }

    @objc private func respond(_ sender: NSButton) {
        guard let index = alert.buttons.firstIndex(of: sender) else { return }
        dismiss(with: NSApplication.ModalResponse(
            rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index))
    }
}
