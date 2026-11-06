// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Vision

enum BarcodeDetector {
    static let symbologies: [VNBarcodeSymbology] = [.qr, .microQR, .aztec, .dataMatrix, .pdf417]

    static func decode(_ image: CGImage) -> [QuickToolsSupport.DecodedBarcode] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = symbologies
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
            let box = observation.boundingBox
            return QuickToolsSupport.DecodedBarcode(payload: payload,
                                                    x: Double(box.minX),
                                                    y: Double(box.midY))
        }
    }

    struct Reading: Equatable {
        let payload: String
        let url: URL?
    }

    static func read(_ image: CGImage) -> Reading? {
        let codes = decode(image)
        let payload = QuickToolsSupport.joinedBarcodePayloads(codes)
        guard !payload.isEmpty else { return nil }
        let url = codes.count == 1 ? QuickToolsSupport.openableURL(from: payload) : nil
        return Reading(payload: payload, url: url)
    }
}
