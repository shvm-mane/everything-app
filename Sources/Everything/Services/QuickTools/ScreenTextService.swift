// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Vision

final class ScreenTextService: ObservableObject {
    static let shared = ScreenTextService()

    private var recognitionGeneration = 0

    private init() {}

    func syncWithPreferences() {
        guard AppFeature.screenOCR.isAvailable else {
            cancelSession()
            return
        }
    }

    func suspend() {
        cancelSession()
    }

    private func cancelSession() {
        recognitionGeneration += 1
    }

    func capture() {
        ScreenCaptureService.shared.capture(initial: .text)
    }

    func receiveUnifiedCapture(_ capture: ScreenshotSelectionController.Capture) {
        recognize(capture.image,
                  detectQRCodes: UserDefaults.standard.bool(
                    forKey: DefaultsKey.screenOCRDetectQRCodes))
    }

    func copyText(from image: CGImage) {
        recognize(image, detectQRCodes: false)
    }

    enum Outcome: Equatable {
        case qr(BarcodeDetector.Reading)
        case text(String)
        case empty
    }

    private func recognize(_ image: CGImage, detectQRCodes: Bool) {
        guard AppFeature.screenOCR.isAvailable else { return }
        recognitionGeneration += 1
        let generation = recognitionGeneration
        let pasteboardChangeCount = NSPasteboard.general.changeCount
        let removeLineBreaks = UserDefaults.standard.bool(forKey: DefaultsKey.screenOCRRemoveLineBreaks)
        let fallbackLanguages = MediaSupport.recognitionLanguages(for: L10n.shared.language.rawValue)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = ScreenTextService.outcome(for: ScreenTextService.recognitionImage(image),
                                                    detectQRCodes: detectQRCodes,
                                                    removeLineBreaks: removeLineBreaks,
                                                    fallbackLanguages: fallbackLanguages)
            DispatchQueue.main.async { [weak self] in
                guard self?.recognitionGeneration == generation,
                      AppFeature.screenOCR.isAvailable,
                      NSPasteboard.general.changeCount == pasteboardChangeCount else { return }
                let strings = L10n.shared.s
                switch outcome {
                case .qr(let reading):
                    QRResultController.shared.show(reading: reading)
                case .text(let text):
                    Self.copyToPasteboard(text)
                    QuickToolHUD.show(icon: "text.viewfinder", message: strings.ocrCopied)
                case .empty:
                    QuickToolHUD.show(icon: "text.viewfinder", message: strings.ocrNoText)
                }
            }
        }
    }

    private static func recognitionImage(_ image: CGImage) -> CGImage {
        guard let size = ClipboardImageRecognition.scaledSize(width: image.width, height: image.height),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: size.width,
                                      height: size.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage() ?? image
    }

    static func outcome(for image: CGImage,
                        detectQRCodes: Bool,
                        removeLineBreaks: Bool,
                        fallbackLanguages: [String] = ["en-US"]) -> Outcome {
        if detectQRCodes, let reading = BarcodeDetector.read(image) {
            return .qr(reading)
        }

        var lines = recognizedLines(in: image,
                                    level: .accurate,
                                    automaticallyDetectLanguage: true,
                                    preferredLanguages: fallbackLanguages)
        if lines.isEmpty {
            lines = recognizedLines(in: image,
                                    level: .fast,
                                    automaticallyDetectLanguage: false,
                                    preferredLanguages: fallbackLanguages)
        }
        let text = QuickToolsSupport.joinedRecognizedText(lines,
                                                         removingLineBreaks: removeLineBreaks)
        return text.isEmpty ? .empty : .text(text)
    }

    private static func recognizedLines(
        in image: CGImage,
        level: VNRequestTextRecognitionLevel,
        automaticallyDetectLanguage: Bool,
        preferredLanguages: [String] = []
    ) -> [QuickToolsSupport.RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = automaticallyDetectLanguage
        if !preferredLanguages.isEmpty,
           let supported = try? request.supportedRecognitionLanguages() {
            let available = preferredLanguages.filter { supported.contains($0) }
            if !available.isEmpty { request.recognitionLanguages = available }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }

        return (request.results ?? []).compactMap { observation -> QuickToolsSupport.RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return QuickToolsSupport.RecognizedLine(text: candidate.string,
                                                    x: observation.boundingBox.minX,
                                                    y: observation.boundingBox.midY)
        }
    }

    static func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setString(value, forType: .string)
    }
}
