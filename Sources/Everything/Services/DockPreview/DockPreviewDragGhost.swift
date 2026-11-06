// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class DockPreviewDragGhost {
    static let shared = DockPreviewDragGhost()

    private var window: NSWindow?
    private var size: CGSize = .zero

    private static let scale: CGFloat = 0.22
    private static let opacity: CGFloat = 0.55

    private init() {}

    func begin(image: CGImage, at pointer: CGPoint) {
        end()

        let size = CGSize(width: CGFloat(image.width) * Self.scale,
                          height: CGFloat(image.height) * Self.scale)
        guard size.width >= 1, size.height >= 1 else { return }
        self.size = size

        let ghost = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
        ghost.backgroundColor = .clear
        ghost.isOpaque = false
        ghost.hasShadow = true
        ghost.level = .popUpMenu
        ghost.ignoresMouseEvents = true
        ghost.animationBehavior = .none
        ghost.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let view = NSImageView(frame: CGRect(origin: .zero, size: size))
        view.image = NSImage(cgImage: image, size: size)
        view.imageScaling = .scaleAxesIndependently
        view.alphaValue = Self.opacity
        ghost.contentView = view

        window = ghost
        move(to: pointer)
        ghost.orderFrontRegardless()
    }

    func move(to pointer: CGPoint) {
        guard let window else { return }
        window.setFrame(CGRect(origin: CGPoint(x: pointer.x, y: pointer.y - size.height),
                               size: size),
                        display: true)
    }

    func end() {
        window?.orderOut(nil)
        window = nil
        size = .zero
    }
}
