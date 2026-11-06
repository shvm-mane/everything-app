// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PlainTextLineMover {
    enum Direction {
        case up
        case down
    }

    static func moving(_ direction: Direction,
                       in text: String,
                       selection: NSRange) -> (text: String, selection: NSRange)? {
        let full = text as NSString
        guard selection.location != NSNotFound, NSMaxRange(selection) <= full.length else { return nil }
        let block = full.lineRange(for: selection)
        let blockPiece = piece(full, block)
        let contentLength = (blockPiece.content as NSString).length
        let startOffset = min(selection.location - block.location, contentLength)
        let endOffset = min(NSMaxRange(selection) - block.location, contentLength)
        let selectedContentLength = endOffset - startOffset
        let selectionIncludesTerminator = NSMaxRange(selection) - block.location > contentLength

        switch direction {
        case .up:
            guard block.location > 0 else { return nil }
            let above = full.lineRange(for: NSRange(location: block.location - 1, length: 0))
            let abovePiece = piece(full, above)
            let swapped = blockPiece.content + abovePiece.terminator + abovePiece.content + blockPiece.terminator
            let newText = full.substring(to: above.location) + swapped + full.substring(from: NSMaxRange(block))
            let newStart = above.location + startOffset
            let newTerminatorLength = selectionIncludesTerminator ? (abovePiece.terminator as NSString).length : 0
            let newLength = selectedContentLength + newTerminatorLength
            return (newText, NSRange(location: newStart, length: newLength))

        case .down:
            guard NSMaxRange(block) < full.length else { return nil }
            let below = full.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            let belowPiece = piece(full, below)
            let swapped = belowPiece.content + blockPiece.terminator + blockPiece.content + belowPiece.terminator
            let newText = full.substring(to: block.location) + swapped + full.substring(from: NSMaxRange(below))
            let newStart = block.location + (belowPiece.content as NSString).length
                + (blockPiece.terminator as NSString).length + startOffset
            let newTerminatorLength = selectionIncludesTerminator ? (belowPiece.terminator as NSString).length : 0
            let newLength = selectedContentLength + newTerminatorLength
            return (newText, NSRange(location: newStart, length: newLength))
        }
    }

    private static func piece(_ full: NSString, _ range: NSRange) -> (content: String, terminator: String) {
        var end = 0
        var contentsEnd = 0
        full.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: range)
        let content = full.substring(with: NSRange(location: range.location, length: contentsEnd - range.location))
        let terminator = full.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd))
        return (content, terminator)
    }
}
