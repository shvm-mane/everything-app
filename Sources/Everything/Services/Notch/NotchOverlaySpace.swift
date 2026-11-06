// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class NotchOverlaySpace {
    private typealias ConnectionID = UInt32
    private typealias CreateFunction = @convention(c) (ConnectionID, Int32, CFDictionary?) -> UInt64
    private typealias SpacesFunction = @convention(c) (ConnectionID, CFArray) -> Int32
    private typealias WindowsFunction = @convention(c) (ConnectionID, CFArray, CFArray) -> Void
    private typealias DestroyFunction = @convention(c) (ConnectionID, UInt64) -> Void
    private typealias LevelFunction = @convention(c) (ConnectionID, UInt64, Int32) -> Int32

    private struct Bridge {
        let connection: ConnectionID
        let create: CreateFunction
        let show: SpacesFunction
        let hide: SpacesFunction
        let add: WindowsFunction
        let remove: WindowsFunction
        let destroy: DestroyFunction
        let setLevel: LevelFunction?
    }

    private static let bridge: Bridge? = {
        func symbol(_ name: String) -> UnsafeMutableRawPointer? {
            dlsym(UnsafeMutableRawPointer(bitPattern: -2) , name)
        }
        guard let main = symbol("CGSMainConnectionID"), let create = symbol("CGSSpaceCreate"),
              let show = symbol("CGSShowSpaces"), let hide = symbol("CGSHideSpaces"),
              let add = symbol("CGSAddWindowsToSpaces"), let remove = symbol("CGSRemoveWindowsFromSpaces"),
              let destroy = symbol("CGSSpaceDestroy") else { return nil }
        let connection = unsafeBitCast(main, to: (@convention(c) () -> ConnectionID).self)()
        guard connection != 0 else { return nil }
        return Bridge(connection: connection,
                      create: unsafeBitCast(create, to: CreateFunction.self),
                      show: unsafeBitCast(show, to: SpacesFunction.self),
                      hide: unsafeBitCast(hide, to: SpacesFunction.self),
                      add: unsafeBitCast(add, to: WindowsFunction.self),
                      remove: unsafeBitCast(remove, to: WindowsFunction.self),
                      destroy: unsafeBitCast(destroy, to: DestroyFunction.self),
                      setLevel: symbol("CGSSpaceSetAbsoluteLevel").map { unsafeBitCast($0, to: LevelFunction.self) })
    }()

    private let bridge: Bridge
    private let space: UInt64
    private var windows = Set<Int>()
    private var closed = false

    init?(absoluteLevel: Int32? = nil) {
        guard let bridge = Self.bridge else { return nil }
        let space = bridge.create(bridge.connection, 1, nil)
        guard space != 0 else { return nil }
        if let absoluteLevel {
            guard let setLevel = bridge.setLevel, setLevel(bridge.connection, space, absoluteLevel) == 0 else {
                bridge.destroy(bridge.connection, space)
                return nil
            }
        }
        self.bridge = bridge
        self.space = space
        _ = bridge.show(bridge.connection, [NSNumber(value: space)] as CFArray)
    }

    deinit { close() }

    func add(_ window: NSWindow) {
        guard !closed, window.windowNumber > 0, windows.insert(window.windowNumber).inserted else { return }
        bridge.add(bridge.connection, [NSNumber(value: window.windowNumber)] as CFArray,
                   [NSNumber(value: space)] as CFArray)
    }

#if VORSSAINT_DEVELOPMENT
    func probeHolds(_ window: NSWindow) -> Bool {
        typealias CopyFunction = @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSCopySpacesForWindows") else { return false }
        let copy = unsafeBitCast(symbol, to: CopyFunction.self)
        func spaces(_ mask: Int32) -> Set<UInt64> {
            Set((copy(bridge.connection, mask, [NSNumber(value: window.windowNumber)] as CFArray)?
                .takeRetainedValue() as? [NSNumber])?.map(\.uint64Value) ?? [])
        }
        return spaces(0xF) == [space] && spaces(0x7).isEmpty
    }
#endif

    func close() {
        guard !closed else { return }
        closed = true
        if !windows.isEmpty {
            bridge.remove(bridge.connection, windows.map { NSNumber(value: $0) } as CFArray,
                          [NSNumber(value: space)] as CFArray)
            windows.removeAll()
        }
        _ = bridge.hide(bridge.connection, [NSNumber(value: space)] as CFArray)
        bridge.destroy(bridge.connection, space)
    }
}
