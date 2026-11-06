// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class ColorSamplerService: ObservableObject {
    static let shared = ColorSamplerService()

    private var activeSampler: NSColorSampler?

    private init() {}

    func pick() {
        let asked = "everythingAskedScreenRecordingForColorPicker"
        if !Permissions.shared.screenRecording, !UserDefaults.standard.bool(forKey: asked) {
            UserDefaults.standard.set(true, forKey: asked)
            Permissions.shared.requestScreenRecording()
            return
        }
        ScreenCaptureService.shared.capture(initial: .color)
    }

    func pickNative() {
        guard activeSampler == nil else { return }
        let sampler = NSColorSampler()
        activeSampler = sampler
        sampler.show { [weak self] color in
            DispatchQueue.main.async {
                self?.activeSampler = nil
                guard let color else { return }
                self?.copy(color)
            }
        }
    }

    func receiveUnifiedColor(_ color: NSColor) {
        copy(color)
    }

    func formattedValue(_ color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let format = ColorCopyFormat.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.colorPickerFormat) ?? "hex"
        )
        return ColorValue.string(red: srgb.redComponent,
                                 green: srgb.greenComponent,
                                 blue: srgb.blueComponent,
                                 format: format,
                                 bareHex: UserDefaults.standard.bool(forKey: DefaultsKey.colorPickerBareHex))
    }

    @discardableResult
    func copyQuietly(_ color: NSColor) -> String? {
        guard let value = formattedValue(color) else { return nil }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setString(value, forType: .string)
        return value
    }

    private func copy(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB),
              let value = copyQuietly(color)
        else { return }
        QuickToolHUD.show(icon: "eyedropper", message: value, swatch: srgb)
    }
}
