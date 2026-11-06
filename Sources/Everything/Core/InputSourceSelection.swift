// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

enum InputSourceSelection {
    struct Snapshot: Equatable {
        let id: String
        let isLayout: Bool
        let isASCIICapable: Bool
    }

    // MARK: - Decisions (pure)

    static func asciiLayoutID(currentID: String?, snapshots: [Snapshot]) -> String? {
        if let currentID,
           let current = snapshots.first(where: { $0.id == currentID }),
           current.isASCIICapable, current.isLayout {
            return nil
        }
        return snapshots.first { $0.isASCIICapable && $0.isLayout }?.id
    }

    static func shortCode(languages: [String]) -> String {
        guard let base = languages.first?.split(separator: "-").first else { return "" }
        return base.uppercased()
    }

    // MARK: - TIS access

    static func currentSourceID() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return inputSourceString(current, property: kTISPropertyInputSourceID)
    }

    static func select(sourceID: String) -> Bool {
        guard let source = selectableInputSources().first(where: {
            inputSourceString($0, property: kTISPropertyInputSourceID) == sourceID
        }) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    // MARK: - Shared TIS plumbing

    static func selectableInputSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false) else { return [] }
        let values = list.takeRetainedValue() as NSArray
        return (values as! [TISInputSource]).filter {
            inputSourceString($0, property: kTISPropertyInputSourceCategory)
                == kTISCategoryKeyboardInputSource as String
                && inputSourceBool($0, property: kTISPropertyInputSourceIsSelectCapable)
        }
    }

    static func snapshots() -> [Snapshot] {
        selectableInputSources().map {
            Snapshot(id: inputSourceString($0, property: kTISPropertyInputSourceID) ?? "",
                     isLayout: inputSourceString($0, property: kTISPropertyInputSourceType)
                         == kTISTypeKeyboardLayout as String,
                     isASCIICapable: inputSourceBool($0, property: kTISPropertyInputSourceIsASCIICapable))
        }
    }

    struct Reading: Equatable {
        let id: String
        let code: String
        let name: String
    }

    static func currentReading() -> Reading? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = inputSourceString(source, property: kTISPropertyInputSourceID)
        else { return nil }
        return Reading(id: id,
                       code: shortCode(languages: languages(of: source)),
                       name: inputSourceString(source, property: kTISPropertyLocalizedName) ?? "")
    }

    static func languages(of source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
              let list = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        else { return [] }
        return list
    }

    static func inputSourceString(_ source: TISInputSource,
                                  property: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    static func inputSourceBool(_ source: TISInputSource,
                                property: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}
