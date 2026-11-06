// Ported from InstantSpaceSwitcher (MIT): Hotkeys/HotkeyConfiguration.swift.
// Changes: preference keys carry an "iss." prefix inside Everything's
// domain, and the nineteen published properties became one dictionary
// (same keys, same JSON encoding, same defaults).
import AppKit
import ISS
import Carbon
import Foundation

enum OptionKeyKind: String, Codable {
  case any
  case right
}

struct HotkeyCombination: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var displayKey: String
  var keyEquivalent: String
  var optionKeyKind: OptionKeyKind

  init(
    keyCode: UInt32, modifiers: UInt32, displayKey: String, keyEquivalent: String,
    optionKeyKind: OptionKeyKind = .any
  ) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.displayKey = displayKey
    self.keyEquivalent = keyEquivalent
    self.optionKeyKind = optionKeyKind
  }

  var displayString: String {
    let modifierSymbols = HotkeyCombination.symbols(for: modifiers, optionKeyKind: optionKeyKind)
    return modifierSymbols + displayKey
  }

  var cocoaModifierFlags: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
    if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
    if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
    if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
    return flags
  }

  var isValid: Bool {
    !displayKey.isEmpty
  }

  func matches(eventModifierFlags flags: UInt64) -> Bool {
    guard modifiers == HotkeyModifierState.carbonMask(fromRawFlags: flags) else {
      return false
    }

    if optionKeyKind == .right {
      return HotkeyModifierState.isRightOptionPressed(rawFlags: flags)
    }

    if modifiers & UInt32(optionKey) != 0 {
      return !HotkeyModifierState.isRightOptionPressed(rawFlags: flags)
    }

    return true
  }

  enum CodingKeys: String, CodingKey {
    case keyCode
    case modifiers
    case displayKey
    case keyEquivalent
    case optionKeyKind
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    keyCode = try container.decode(UInt32.self, forKey: .keyCode)
    modifiers = try container.decode(UInt32.self, forKey: .modifiers)
    displayKey = try container.decode(String.self, forKey: .displayKey)
    keyEquivalent = try container.decode(String.self, forKey: .keyEquivalent)
    optionKeyKind = try container.decodeIfPresent(OptionKeyKind.self, forKey: .optionKeyKind) ?? .any
  }

  static let defaultLeft = HotkeyCombination(
    keyCode: UInt32(kVK_LeftArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "←",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.leftArrow)
  )

  static let defaultRight = HotkeyCombination(
    keyCode: UInt32(kVK_RightArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "→",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.rightArrow)
  )

  static let defaultLastSpace = HotkeyCombination(
    keyCode: UInt32(kVK_ANSI_KeypadPlus),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "↩",
    keyEquivalent: "-"
  )

  static func defaultForSpace(_ number: Int) -> HotkeyCombination {
    let keyCode: UInt32
    let displayKey: String
    let keyEquivalent: String

    switch number {
    case 1...9:
      let codes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                   kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
      keyCode = UInt32(codes[number - 1])
      displayKey = "\(number)"
      keyEquivalent = "\(number)"
    case 10:
      keyCode = UInt32(kVK_ANSI_0)
      displayKey = "0"
      keyEquivalent = "0"
    case 11...16:
      let functionKey = number - 11
      let functionKeyCodes = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3),
        UInt32(kVK_F4), UInt32(kVK_F5), UInt32(kVK_F6),
      ]
      keyCode = functionKeyCodes[functionKey]
      displayKey = "F\(functionKey + 1)"
      keyEquivalent = String(Character(UnicodeScalar(NSF1FunctionKey + functionKey)!))
    default: fatalError("Invalid space number")
    }

    return HotkeyCombination(
      keyCode: keyCode,
      modifiers: defaultModifierMask,
      displayKey: displayKey,
      keyEquivalent: keyEquivalent
    )
  }

  static func from(event: NSEvent) -> HotkeyCombination? {
    let modifiers = event.modifierFlags.issCarbonMask
    let keyCode = UInt32(event.keyCode)
    let optionKeyKind = HotkeyModifierState.optionKeyKind(
      fromRawFlags: UInt64(event.modifierFlags.rawValue))

    if let special = event.specialKey, let symbol = arrowSymbol(for: special) {
      return HotkeyCombination(
        keyCode: keyCode,
        modifiers: modifiers,
        displayKey: symbol,
        keyEquivalent: arrowKeyEquivalent(special),
        optionKeyKind: optionKeyKind
      )
    }

    if let (displayKey, keyEquiv) = specialKeyInfo(for: Int(event.keyCode)) {
      return HotkeyCombination(
        keyCode: keyCode,
        modifiers: modifiers,
        displayKey: displayKey,
        keyEquivalent: keyEquiv,
        optionKeyKind: optionKeyKind
      )
    }

    guard let characters = event.charactersIgnoringModifiers, let first = characters.first,
          first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else {
      return nil
    }

    let upper = String(first).uppercased()
    return HotkeyCombination(
      keyCode: keyCode,
      modifiers: modifiers,
      displayKey: upper,
      keyEquivalent: String(first).lowercased(),
      optionKeyKind: optionKeyKind
    )
  }

  static func arrowSymbol(for specialKey: NSEvent.SpecialKey) -> String? {
    switch specialKey {
    case .leftArrow: return "←"
    case .rightArrow: return "→"
    case .upArrow: return "↑"
    case .downArrow: return "↓"
    default: return nil
    }
  }

  private static func specialKeyInfo(for keyCode: Int) -> (displayKey: String, keyEquivalent: String)? {
    func scalar(_ value: Int) -> String { String(Character(UnicodeScalar(value)!)) }
    switch keyCode {
    case kVK_Return: return ("↩", scalar(NSCarriageReturnCharacter))
    case kVK_ANSI_KeypadEnter: return ("⌅", scalar(NSEnterCharacter))
    case kVK_Tab: return ("⇥", scalar(NSTabCharacter))
    case kVK_Delete: return ("⌫", scalar(NSBackspaceCharacter))
    case kVK_ForwardDelete: return ("⌦", scalar(NSDeleteCharacter))
    case kVK_Space: return ("Space", " ")
    case kVK_F1: return ("F1", scalar(NSF1FunctionKey))
    case kVK_F2: return ("F2", scalar(NSF2FunctionKey))
    case kVK_F3: return ("F3", scalar(NSF3FunctionKey))
    case kVK_F4: return ("F4", scalar(NSF4FunctionKey))
    case kVK_F5: return ("F5", scalar(NSF5FunctionKey))
    case kVK_F6: return ("F6", scalar(NSF6FunctionKey))
    case kVK_F7: return ("F7", scalar(NSF7FunctionKey))
    case kVK_F8: return ("F8", scalar(NSF8FunctionKey))
    case kVK_F9: return ("F9", scalar(NSF9FunctionKey))
    case kVK_F10: return ("F10", scalar(NSF10FunctionKey))
    case kVK_F11: return ("F11", scalar(NSF11FunctionKey))
    case kVK_F12: return ("F12", scalar(NSF12FunctionKey))
    case kVK_Home: return ("↖", scalar(NSHomeFunctionKey))
    case kVK_End: return ("↘", scalar(NSEndFunctionKey))
    case kVK_PageUp: return ("⇞", scalar(NSPageUpFunctionKey))
    case kVK_PageDown: return ("⇟", scalar(NSPageDownFunctionKey))
    default: return nil
    }
  }

  private static func arrowKeyEquivalent(_ specialKey: NSEvent.SpecialKey) -> String {
    switch specialKey {
    case .leftArrow: return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
    case .rightArrow: return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
    case .upArrow: return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    case .downArrow: return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    default: return ""
    }
  }

  private static func symbols(for modifiers: UInt32, optionKeyKind: OptionKeyKind) -> String {
    var result = ""
    if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if modifiers & UInt32(optionKey) != 0 {
      result += optionKeyKind == .right ? "AltGr" : "⌥"
    }
    if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    return result
  }

  private static var defaultModifierMask: UInt32 {
    UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
  }
}

enum HotkeyModifierState {
  private static let deviceRightOptionMask: UInt64 = 0x00000040

  static func optionKeyKind(fromRawFlags flags: UInt64) -> OptionKeyKind {
    isRightOptionPressed(rawFlags: flags) ? .right : .any
  }

  static func isRightOptionPressed(rawFlags flags: UInt64) -> Bool {
    flags & deviceRightOptionMask != 0
  }

  static func carbonMask(fromRawFlags flags: UInt64) -> UInt32 {
    NSEvent.ModifierFlags(rawValue: UInt(flags)).issCarbonMask
  }
}

enum HotkeyIdentifier: String, CaseIterable {
  case left
  case right
  case space1, space2, space3, space4, space5
  case space6, space7, space8, space9, space10
  case space11, space12, space13, space14, space15, space16
  case lastSpace

  var displayName: String {
    switch self {
    case .left: return "Switch to space on the left"
    case .right: return "Switch to space on the right"
    case .lastSpace: return "Switch to last used space"
    default: return "Switch to space \(HotkeyIdentifier.spaceNumber(self) ?? 0)"
    }
  }

  var defaultCombination: HotkeyCombination {
    switch self {
    case .left: return .defaultLeft
    case .right: return .defaultRight
    case .lastSpace: return .defaultLastSpace
    default: return .defaultForSpace(HotkeyIdentifier.spaceNumber(self) ?? 1)
    }
  }

  /// "iss.hotkey.left" etc. — ISS's own key names under an "iss." prefix.
  var storageKey: String { "iss.hotkey.\(rawValue)" }
  var enabledKey: String { "iss.enabled.\(rawValue)" }
}

final class HotkeyStore: ObservableObject {
  static let shared = HotkeyStore()

  @Published private(set) var combinations: [HotkeyIdentifier: HotkeyCombination] = [:]
  @Published private(set) var enabledStates: [HotkeyIdentifier: Bool] = [:]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    reload()
  }

  /// Re-reads everything from defaults (after an import).
  func reload() {
    var combos: [HotkeyIdentifier: HotkeyCombination] = [:]
    var enabled: [HotkeyIdentifier: Bool] = [:]
    for identifier in HotkeyIdentifier.allCases {
      combos[identifier] = defaults.issHotkey(forKey: identifier.storageKey) ?? identifier.defaultCombination
      enabled[identifier] = defaults.object(forKey: identifier.enabledKey) as? Bool ?? true
    }
    combinations = combos
    enabledStates = enabled
  }

  func update(_ combination: HotkeyCombination, for identifier: HotkeyIdentifier) {
    guard combination != combinations[identifier] else { return }
    combinations[identifier] = combination
    defaults.setIssHotkey(combination, forKey: identifier.storageKey)
  }

  func resetToDefaults() {
    for identifier in HotkeyIdentifier.allCases {
      combinations[identifier] = identifier.defaultCombination
      defaults.setIssHotkey(identifier.defaultCombination, forKey: identifier.storageKey)
    }
  }

  func combination(for identifier: HotkeyIdentifier) -> HotkeyCombination {
    combinations[identifier] ?? identifier.defaultCombination
  }

  func isEnabled(_ identifier: HotkeyIdentifier) -> Bool {
    enabledStates[identifier] ?? true
  }

  func setEnabled(_ enabled: Bool, for identifier: HotkeyIdentifier) {
    enabledStates[identifier] = enabled
    defaults.set(enabled, forKey: identifier.enabledKey)
  }
}

extension UserDefaults {
  fileprivate func issHotkey(forKey key: String) -> HotkeyCombination? {
    guard let data = data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(HotkeyCombination.self, from: data)
  }

  fileprivate func setIssHotkey(_ hotkey: HotkeyCombination, forKey key: String) {
    if let data = try? JSONEncoder().encode(hotkey) {
      set(data, forKey: key)
    }
  }
}

extension NSEvent.ModifierFlags {
  var issCarbonMask: UInt32 {
    var mask: UInt32 = 0
    if contains(.command) { mask |= UInt32(cmdKey) }
    if contains(.option) { mask |= UInt32(optionKey) }
    if contains(.control) { mask |= UInt32(controlKey) }
    if contains(.shift) { mask |= UInt32(shiftKey) }
    return mask
  }
}
