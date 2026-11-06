// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum RecorderGIFClipboard {
    static let pasteboardType = NSPasteboard.PasteboardType(UTType.gif.identifier)

    static let inlineByteLimit = 64 * 1024 * 1024

    static func publish(fileURL: URL,
                        to pasteboard: NSPasteboard = .general,
                        inlineByteLimit: Int = inlineByteLimit) -> Bool {
        guard let bytes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier,
              CGImageSourceGetCount(source) > 0 else { return false }

        let item = NSPasteboardItem()
        if bytes <= inlineByteLimit {
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
                  item.setData(data, forType: pasteboardType) else { return false }
        }
        guard item.setString(fileURL.absoluteString, forType: .fileURL) else { return false }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return false }
        pasteboard.declareVorssaintSource()
        return true
    }
}
