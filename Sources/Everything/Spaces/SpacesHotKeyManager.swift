// Ported from InstantSpaceSwitcher (MIT): Hotkeys/HotKeyManager.swift.
// Change: the key-down event tap is installed only while at least one
// hotkey is registered, so a disabled switcher costs nothing.
import AppKit
import ISS
import Carbon

final class HotKeyManager {
  static let shared = HotKeyManager()

  private struct Entry {
    let identifier: HotkeyIdentifier
    let combination: HotkeyCombination
    let handler: () -> Void
  }

  private var entries: [HotkeyIdentifier: Entry] = [:]
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var retryScheduled = false

  private init() {}

  func register(
    identifier: HotkeyIdentifier, combination: HotkeyCombination, handler: @escaping () -> Void
  ) {
    entries[identifier] = Entry(identifier: identifier, combination: combination, handler: handler)
    installEventTap()
  }

  func unregister(identifier: HotkeyIdentifier) {
    entries.removeValue(forKey: identifier)
    if entries.isEmpty { removeEventTap() }
  }

  func unregisterAll() {
    entries.removeAll()
    removeEventTap()
  }

  private func removeEventTap() {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    eventTap = nil
    runLoopSource = nil
  }

  private func installEventTap() {
    guard !entries.isEmpty else { return }
    if let eventTap {
      if CFMachPortIsValid(eventTap) {
        return
      }
      self.eventTap = nil
      runLoopSource = nil
    }

    let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: { _, type, event, userInfo in
          guard let userInfo else { return Unmanaged.passUnretained(event) }
          let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()

          if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = manager.eventTap {
              CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
          }

          guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
          }

          if manager.dispatch(event: event) {
            return nil
          }
          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      scheduleEventTapRetry()
      return
    }

    retryScheduled = false
    self.eventTap = eventTap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    if let runLoopSource {
      CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  /// Without Accessibility the tap cannot be created; try again until it is granted.
  private func scheduleEventTapRetry() {
    guard !retryScheduled else { return }
    retryScheduled = true

    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
      guard let self else { return }
      self.retryScheduled = false
      self.installEventTap()
    }
  }

  private func dispatch(event: CGEvent) -> Bool {
    let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
    let rawFlags = event.flags.rawValue
    let selectedEntry = Self.preferredEntry(from: Array(entries.values), keyCode: keyCode, flags: rawFlags)

    if let selectedEntry {
      DispatchQueue.main.async {
        selectedEntry.handler()
      }
      return true
    }

    return false
  }

  private static func preferredEntry(
    from entries: [Entry], keyCode: UInt32, flags: UInt64
  ) -> Entry? {
    entries.filter {
      $0.combination.keyCode == keyCode && $0.combination.matches(eventModifierFlags: flags)
    }.max {
      priority(for: $0.combination) < priority(for: $1.combination)
    }
  }

  private static func priority(for combination: HotkeyCombination) -> Int {
    combination.optionKeyKind == .right ? 1 : 0
  }
}
