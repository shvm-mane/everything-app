// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

enum SpaceWindowBridge {
    private typealias ConnectionID = UInt32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) , name)
    }

    private static let connection: ConnectionID = {
        typealias Function = @convention(c) () -> ConnectionID
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: Function.self)()
    }()

    private typealias GetWindowTagsFunction =
        @convention(c) (ConnectionID, CGWindowID, UnsafeMutablePointer<UInt32>, Int) -> CGError
    private static let getWindowTags: GetWindowTagsFunction? = {
        guard let symbol = symbol("CGSGetWindowTags") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowTagsFunction.self)
    }()

    private typealias WindowIsOrderedInFunction =
        @convention(c) (ConnectionID, CGWindowID, UnsafeMutablePointer<UInt8>) -> CGError
    private static let windowIsOrderedIn: WindowIsOrderedInFunction? = {
        guard let symbol = symbol("CGSWindowIsOrderedIn") else { return nil }
        return unsafeBitCast(symbol, to: WindowIsOrderedInFunction.self)
    }()

    static func isWindowOrderedIn(_ windowID: CGWindowID) -> Bool? {
        guard connection != 0, let windowIsOrderedIn else { return nil }
        var ordered: UInt8 = 0
        guard windowIsOrderedIn(connection, windowID, &ordered) == .success else { return nil }
        return ordered != 0
    }

    // MARK: - Space membership

    private typealias CopySpacesFunction =
        @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let copySpacesForWindows: CopySpacesFunction? = {
        guard let symbol = symbol("CGSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(symbol, to: CopySpacesFunction.self)
    }()

    static var canResolveSpaces: Bool {
        connection != 0 && copySpacesForWindows != nil
    }

    static func spaces(of windowID: CGWindowID) -> [UInt64] {
        resolvedSpaces(of: windowID) ?? []
    }

    static func resolvedSpaces(of windowID: CGWindowID) -> [UInt64]? {
        guard connection != 0, let copySpacesForWindows else { return nil }
        let mask: Int32 = 0x7
        guard let array = copySpacesForWindows(connection, mask,
                                               [NSNumber(value: windowID)] as CFArray)?
            .takeRetainedValue() as? [NSNumber]
        else { return nil }
        return array.map(\.uint64Value)
    }

    // MARK: - Display topology

    private typealias CopyDisplaySpacesFunction = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private static let copyManagedDisplaySpaces: CopyDisplaySpacesFunction? = {
        guard let symbol = symbol("CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyDisplaySpacesFunction.self)
    }()

    struct Topology {
        struct DisplayInfo {
            let displayID: CGDirectDisplayID?
            let spaces: [UInt64]
            let fullscreenSpaces: Set<UInt64>
            let currentSpace: UInt64?
        }

        func isFullscreen(on displayID: CGDirectDisplayID, separateSpaces: Bool) -> Bool {
            let candidates = separateSpaces ? displays.filter { $0.displayID == displayID } : displays
            return candidates.contains { display in
                display.currentSpace.map { display.fullscreenSpaces.contains($0) } == true
            }
        }

        let displays: [DisplayInfo]
        var orderedSpacesPerDisplay: [[UInt64]] { displays.map(\.spaces) }
        var visibleSpaces: Set<UInt64> { Set(displays.compactMap(\.currentSpace)) }
        var fullscreenSpaces: Set<UInt64> {
            displays.reduce(into: []) { $0.formUnion($1.fullscreenSpaces) }
        }
    }

    static func displayIDsByUUID() -> [String: CGDirectDisplayID] {
        var map: [String: CGDirectDisplayID] = [:]
        for screen in NSScreen.screens {
            guard let screenNum = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(screenNum)?.takeRetainedValue(),
                  let uuidStr = CFUUIDCreateString(nil, uuid) as String?
            else { continue }
            map[uuidStr] = screenNum
        }
        return map
    }

    static func topology() -> Topology? {
        topology(displayIDsByUUID: displayIDsByUUID())
    }

    static func topology(displayIDsByUUID: [String: CGDirectDisplayID]) -> Topology? {
        guard connection != 0, let copyManagedDisplaySpaces,
              let displayDicts = copyManagedDisplaySpaces(connection)?
                .takeRetainedValue() as? [[String: Any]],
              !displayDicts.isEmpty
        else { return nil }

        var displays: [Topology.DisplayInfo] = []
        for display in displayDicts {
            let spaceDictionaries = display["Spaces"] as? [[String: Any]] ?? []
            let row = spaceDictionaries
                .compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            guard !row.isEmpty else { continue }
            let fullscreenSpaces = Set(spaceDictionaries.compactMap { space -> UInt64? in
                guard (space["type"] as? NSNumber)?.intValue == 4 else { return nil }
                return (space["id64"] as? NSNumber)?.uint64Value
            })
            let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
            let uuidStr = display["Display Identifier"] as? String
            let displayID = uuidStr.flatMap { displayIDsByUUID[$0] }
            displays.append(Topology.DisplayInfo(displayID: displayID,
                                                 spaces: row,
                                                 fullscreenSpaces: fullscreenSpaces,
                                                 currentSpace: current?.uint64Value))
        }
        guard !displays.isEmpty else { return nil }
        return Topology(displays: displays)
    }

    private typealias MoveWindowsToSpaceFunction =
        @convention(c) (ConnectionID, CFArray, UInt64) -> Void
    private static let moveWindowsToManagedSpace: MoveWindowsToSpaceFunction? = {
        guard let symbol = symbol("CGSMoveWindowsToManagedSpace") else { return nil }
        return unsafeBitCast(symbol, to: MoveWindowsToSpaceFunction.self)
    }()

    static func visibleSpace(near pointer: CGPoint) -> UInt64? {
        guard let topology = topology() else { return nil }
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        if let number = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value,
           let display = topology.displays.first(where: { $0.displayID == number }) {
            return display.currentSpace
        }
        return topology.displays.first?.currentSpace
    }

    @discardableResult
    static func moveToVisibleSpace(_ windowID: CGWindowID, near pointer: CGPoint) -> Bool {
        guard connection != 0,
              let moveWindowsToManagedSpace,
              let destination = visibleSpace(near: pointer)
        else { return false }
        guard !spaces(of: windowID).contains(destination) else { return true }
        moveWindowsToManagedSpace(connection, [NSNumber(value: windowID)] as CFArray, destination)
        return true
    }

    static func isParkedOnHiddenSpace(_ windowID: CGWindowID, visibleSpaces: Set<UInt64>? = nil) -> Bool {
        guard let visible = visibleSpaces ?? topology()?.visibleSpaces else { return false }
        return SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: spaces(of: windowID),
                                                     visibleSpaces: visible)
    }

    // MARK: - Window tags

    private typealias WindowQueryFunction =
        @convention(c) (ConnectionID, CFArray, UInt64) -> Unmanaged<CFTypeRef>?
    private typealias WindowQueryResultFunction = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias IteratorAdvanceFunction = @convention(c) (CFTypeRef) -> Bool
    private typealias IteratorWindowIDFunction = @convention(c) (CFTypeRef) -> UInt32
    private typealias IteratorTagsFunction = @convention(c) (CFTypeRef) -> UInt64

    private struct WindowQuery {
        let query: WindowQueryFunction
        let windows: WindowQueryResultFunction
        let advance: IteratorAdvanceFunction
        let windowID: IteratorWindowIDFunction
        let tags: IteratorTagsFunction
    }

    private static let windowQuery: WindowQuery? = {
        guard let query = symbol("SLSWindowQueryWindows"),
              let windows = symbol("SLSWindowQueryResultCopyWindows"),
              let advance = symbol("SLSWindowIteratorAdvance"),
              let windowID = symbol("SLSWindowIteratorGetWindowID"),
              let tags = symbol("SLSWindowIteratorGetTags")
        else { return nil }
        return WindowQuery(query: unsafeBitCast(query, to: WindowQueryFunction.self),
                           windows: unsafeBitCast(windows, to: WindowQueryResultFunction.self),
                           advance: unsafeBitCast(advance, to: IteratorAdvanceFunction.self),
                           windowID: unsafeBitCast(windowID, to: IteratorWindowIDFunction.self),
                           tags: unsafeBitCast(tags, to: IteratorTagsFunction.self))
    }()

    private static func windowTags(of windowIDs: [CGWindowID]) -> [CGWindowID: UInt64]? {
        guard connection != 0, let windowQuery else { return nil }
        guard !windowIDs.isEmpty else { return [:] }
        guard let query = windowQuery.query(connection, windowIDs.map { NSNumber(value: $0) } as CFArray,
                                            0)?.takeRetainedValue(),
              let iterator = windowQuery.windows(query)?.takeRetainedValue()
        else { return nil }
        var tags: [CGWindowID: UInt64] = [:]
        while windowQuery.advance(iterator) {
            tags[windowQuery.windowID(iterator)] = windowQuery.tags(iterator)
        }
        return tags
    }

    static func isExcludedFromWindowCycle(_ windowID: CGWindowID) -> Bool {
        if let tags = windowTags(of: [windowID])?[windowID], tags != 0 {
            return SpaceHopSupport.isExcludedFromWindowCycle(windowTags: tags)
        }
        guard connection != 0, let getWindowTags else { return false }
        var tags = [UInt32](repeating: 0, count: 2)
        return tags.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress,
                  getWindowTags(connection, windowID, base,
                                MemoryLayout<UnsafeRawPointer>.size * 8) == .success
            else { return false }
            return SpaceHopSupport.isExcludedFromWindowCycle(
                windowTags: UInt64(buffer[0]) | UInt64(buffer[1]) << 32)
        }
    }

    static func windowsHiddenWithApp(among windowIDs: [CGWindowID]) -> Set<CGWindowID>? {
        guard #available(macOS 26.0, *), let tags = windowTags(of: windowIDs) else { return nil }
        return SpaceHopSupport.windowsHiddenWithApp(windowTags: tags)
    }

    static func isMinimized(_ windowID: CGWindowID) -> Bool? {
        guard #available(macOS 26.0, *), let windows = windowTags(of: [windowID]) else { return nil }
        guard let tags = windows[windowID] else { return false }
        guard tags != 0 else { return nil }
        return SpaceHopSupport.isMinimized(windowTags: tags)
    }

    // MARK: - Child windows

    private typealias IteratorParentIDFunction = @convention(c) (CFTypeRef) -> UInt32
    private static let iteratorParentID: IteratorParentIDFunction? = {
        guard let symbol = symbol("SLSWindowIteratorGetParentID") else { return nil }
        return unsafeBitCast(symbol, to: IteratorParentIDFunction.self)
    }()

    static func parentWindowID(of windowID: CGWindowID) -> CGWindowID? {
        guard connection != 0, let windowQuery, let iteratorParentID,
              let query = windowQuery.query(connection, [NSNumber(value: windowID)] as CFArray,
                                            0)?.takeRetainedValue(),
              let iterator = windowQuery.windows(query)?.takeRetainedValue()
        else { return nil }
        while windowQuery.advance(iterator) {
            guard windowQuery.windowID(iterator) == windowID else { continue }
            let parentID = iteratorParentID(iterator)
            return parentID == kCGNullWindowID ? nil : parentID
        }
        return nil
    }

    // MARK: - Fronting a specific window

    private typealias SetFrontFunction =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private static let setFrontProcess: SetFrontFunction? = {
        guard let symbol = symbol("_SLPSSetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(symbol, to: SetFrontFunction.self)
    }()

    private typealias PostEventRecordFunction =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private static let postEventRecord: PostEventRecordFunction? = {
        guard let symbol = symbol("SLPSPostEventRecordTo") else { return nil }
        return unsafeBitCast(symbol, to: PostEventRecordFunction.self)
    }()

    private typealias ProcessForPIDFunction =
        @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private static let processForPID: ProcessForPIDFunction? = {
        guard let symbol = symbol("GetProcessForPID") else { return nil }
        return unsafeBitCast(symbol, to: ProcessForPIDFunction.self)
    }()

    @discardableResult
    static func frontWindow(_ windowID: CGWindowID, ownerPID: pid_t) -> Bool {
        guard let setFrontProcess, let processForPID else { return false }
        let app = NSRunningApplication(processIdentifier: ownerPID)
        let usesClick = SwitcherSupport.usesActivationClick(executablePath: app?.executableURL?.path,
                                                          localizedName: app?.localizedName)
        guard !usesClick || postEventRecord != nil else { return false }
        var psn = ProcessSerialNumber()
        guard processForPID(ownerPID, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        guard setFrontProcess(&psn, windowID, userGenerated) == .success else { return false }
        guard usesClick else { return true }
        guard let postEventRecord else { return false }
        var targetID = windowID
        var record = [UInt8](repeating: 0, count: 0x100)
        record[0x04] = 0xf8
        record[0x3a] = 0x10
        withUnsafeBytes(of: &targetID) { record.replaceSubrange(0x3c..<0x3c + $0.count, with: $0) }
        var farPoint = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &farPoint) { record.replaceSubrange(0x20..<0x20 + $0.count, with: $0) }
        record[0x08] = 0x01
        return postEventRecord(&psn, &record) == .success
    }

    static func focusWithoutRaise(_ windowID: CGWindowID, ownerPID: pid_t,
                                  replacing focusedWindowID: CGWindowID?,
                                  while isCurrent: @escaping () -> Bool,
                                  completion: @escaping (Bool) -> Void) {
        guard isCurrent(), setFrontProcess != nil, processForPID != nil, postEventRecord != nil else {
            completion(false)
            return
        }
        guard let focusedWindowID else {
            completion(makeKeyWithoutRaise(windowID, ownerPID: ownerPID))
            return
        }
        guard postFocusRecord(focusedWindowID, ownerPID: ownerPID, gained: false) else {
            completion(false)
            return
        }
        let restoreFocus = {
            if FocusFollowsMouseSupport.shouldRestoreFocus(
                to: focusedWindowID,
                reportedFocusedWindowID: WindowActivator.focusedWindowID(for: ownerPID),
                appIsFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == ownerPID) {
                postFocusRecord(focusedWindowID, ownerPID: ownerPID, gained: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            guard isCurrent() else {
                restoreFocus()
                completion(false)
                return
            }
            let succeeded = makeKeyWithoutRaise(windowID, ownerPID: ownerPID)
            if !succeeded { restoreFocus() }
            completion(succeeded)
        }
    }

    private static func makeKeyWithoutRaise(_ windowID: CGWindowID, ownerPID: pid_t) -> Bool {
        guard let setFrontProcess, let processForPID, postEventRecord != nil else { return false }
        var psn = ProcessSerialNumber()
        guard processForPID(ownerPID, &psn) == noErr else { return false }
        let noWindows: UInt32 = 0x400
        guard setFrontProcess(&psn, windowID, noWindows) == .success else { return false }
        return postFocusRecord(windowID, ownerPID: ownerPID, gained: true)
    }

    @discardableResult
    private static func postFocusRecord(_ windowID: CGWindowID, ownerPID: pid_t, gained: Bool) -> Bool {
        guard let processForPID, let postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard processForPID(ownerPID, &psn) == noErr else { return false }
        var targetID = windowID
        var record = [UInt8](repeating: 0, count: 0x100)
        record[0x04] = 0xf8
        record[0x08] = 0x0d
        record[0x8a] = gained ? 0x01 : 0x02
        withUnsafeBytes(of: &targetID) { record.replaceSubrange(0x3c..<0x3c + $0.count, with: $0) }
        return postEventRecord(&psn, &record) == .success
    }

    // MARK: - The user's "move a space" shortcut

    private typealias HotKeyValueFunction =
        @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError
    private static let symbolicHotKeyValue: HotKeyValueFunction? = {
        guard let symbol = symbol("CGSGetSymbolicHotKeyValue") else { return nil }
        return unsafeBitCast(symbol, to: HotKeyValueFunction.self)
    }()

    private typealias HotKeyEnabledFunction = @convention(c) (Int32) -> Bool
    private static let symbolicHotKeyEnabled: HotKeyEnabledFunction? = {
        guard let symbol = symbol("CGSIsSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(symbol, to: HotKeyEnabledFunction.self)
    }()

    enum SpaceDirection {
        case left
        case right

        fileprivate var hotKeyID: Int32 { self == .left ? 79 : 81 }
    }

    enum SpaceOverview {
        case missionControl
        case appExpose

        fileprivate var hotKeyID: Int32 { self == .missionControl ? 32 : 33 }
    }

    struct SpaceShortcut {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    static func spaceShortcut(_ direction: SpaceDirection) -> SpaceShortcut? {
        registeredShortcut(direction.hotKeyID)
    }

    static func overviewShortcut(_ overview: SpaceOverview) -> SpaceShortcut? {
        registeredShortcut(overview.hotKeyID)
    }

    private static func registeredShortcut(_ hotKeyID: Int32) -> SpaceShortcut? {
        guard let symbolicHotKeyValue, let symbolicHotKeyEnabled,
              symbolicHotKeyEnabled(hotKeyID) else { return nil }
        var options: UInt32 = 0
        var keyCode: UInt32 = 0
        var modifiers: UInt32 = 0
        guard symbolicHotKeyValue(hotKeyID, &options, &keyCode, &modifiers) == .success,
              keyCode != 0
        else { return nil }
        return SpaceShortcut(keyCode: CGKeyCode(keyCode),
                             flags: SpaceHopSupport.eventFlags(fromCarbonModifiers: modifiers))
    }

    static func pressSpaceShortcut(_ shortcut: SpaceShortcut) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: false)
        else { return }
        down.flags = shortcut.flags
        up.flags = shortcut.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
