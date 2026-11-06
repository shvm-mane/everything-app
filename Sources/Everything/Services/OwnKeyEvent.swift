// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin

enum OwnKeyEvent {
    static let quitProtectionMarker: Int64 = 0x5652535341494E54
    static let textSnippetMarker: Int64 = 0x564F5253

    private static let ownProcessID = Int64(getpid())

    static func isPosted(sourceProcessID: Int64, userData: Int64, ownProcessID: Int64) -> Bool {
        sourceProcessID == ownProcessID
            || userData == quitProtectionMarker
            || userData == textSnippetMarker
    }

    static func isPosted(_ event: CGEvent) -> Bool {
        isPosted(sourceProcessID: event.getIntegerValueField(.eventSourceUnixProcessID),
                 userData: event.getIntegerValueField(.eventSourceUserData),
                 ownProcessID: ownProcessID)
    }
}
