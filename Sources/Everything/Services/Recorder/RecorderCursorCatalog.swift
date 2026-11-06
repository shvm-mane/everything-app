// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class RecorderCursorCatalog {
    struct Shape {
        let image: CGImage
        let size: CGSize
        let hotSpot: CGPoint
    }

    private let lock = NSLock()
    private var shapes: [UInt64: Shape] = [:]
    private var order: [UInt64] = []
    private var upgraded: Set<UInt64> = []

    private(set) var systemScale: Double = 1

    let isAvailable: Bool

    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias SeedFunction = @convention(c) () -> Int32
    private typealias VisibleFunction = @convention(c) () -> Bool
    private typealias ScaleFunction = @convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SizeFunction = @convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32
    private typealias DataFunction = @convention(c) (
        Int32, UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>,
        UnsafeMutablePointer<CGRect>, UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<Int32>,
        UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

    private let seedFunction: SeedFunction?
    private let visibleFunction: VisibleFunction?
    private let sizeFunction: SizeFunction?
    private let dataFunction: DataFunction?
    private let connection: Int32

    init() {
        let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                            RTLD_LAZY)
        func symbol(_ name: String) -> UnsafeMutableRawPointer? {
            guard let handle else { return nil }
            return dlsym(handle, name)
        }
        seedFunction = symbol("CGSCurrentCursorSeed").map {
            unsafeBitCast($0, to: SeedFunction.self)
        }
        visibleFunction = symbol("CGCursorIsVisible").map {
            unsafeBitCast($0, to: VisibleFunction.self)
        }
        sizeFunction = symbol("CGSGetGlobalCursorDataSize").map {
            unsafeBitCast($0, to: SizeFunction.self)
        }
        dataFunction = symbol("CGSGetGlobalCursorData").map {
            unsafeBitCast($0, to: DataFunction.self)
        }
        connection = symbol("CGSMainConnectionID").map {
            unsafeBitCast($0, to: ConnectionFunction.self)()
        } ?? 0
        isAvailable = seedFunction != nil && sizeFunction != nil
            && dataFunction != nil && connection != 0

        if let scaleSymbol = symbol("CGSGetCursorScale") {
            var value: Float = 1
            let function = unsafeBitCast(scaleSymbol, to: ScaleFunction.self)
            if function(connection, &value) == 0, value.isFinite, value > 0 {
                systemScale = min(4, max(1, Double(value)))
            }
        }
    }

    // MARK: - Per sample

    func currentSeed() -> Int32 {
        seedFunction?() ?? 0
    }

    func isPointerVisible() -> Bool {
        visibleFunction?() ?? true
    }

    @discardableResult
    func captureCurrentShape() -> UInt64 {
        guard isAvailable,
              let sizeFunction, let dataFunction else { return 0 }
        var byteCount: Int32 = 0
        guard sizeFunction(connection, &byteCount) == 0, byteCount > 0, byteCount < 16_000_000
        else { return 0 }

        var buffer = [UInt8](repeating: 0, count: Int(byteCount))
        var capacity = byteCount
        var bytesPerRow: Int32 = 0
        var rect = CGRect.zero
        var hotSpot = CGPoint.zero
        var bitsPerPixel: Int32 = 0
        var components: Int32 = 0
        var bitsPerComponent: Int32 = 0
        let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return dataFunction(connection, base, &capacity, &bytesPerRow, &rect, &hotSpot,
                                &bitsPerPixel, &components, &bitsPerComponent)
        }
        guard status == 0, bitsPerPixel == 32, components == 4, bitsPerComponent == 8,
              rect.width >= 1, rect.height >= 1, bytesPerRow > 0
        else { return 0 }

        let identity = Self.hash(buffer, rect: rect, hotSpot: hotSpot)
        lock.lock()
        let known = shapes[identity] != nil
        lock.unlock()
        if known { return identity }

        guard let shape = Self.makeShape(buffer,
                                         bytesPerRow: Int(bytesPerRow),
                                         rect: rect,
                                         hotSpot: hotSpot)
        else { return 0 }
        lock.lock()
        if shapes[identity] == nil {
            shapes[identity] = shape
            order.append(identity)
        }
        lock.unlock()
        requestSharperImage(for: identity, rect: rect)
        return identity
    }

    // MARK: - Building

    private static func makeShape(_ buffer: [UInt8],
                                  bytesPerRow: Int,
                                  rect: CGRect,
                                  hotSpot: CGPoint) -> Shape? {
        let width = Int(rect.width)
        var height = Int(rect.height)
        guard width > 0, height > 0 else { return nil }

        if height >= width * 2, height % width == 0 {
            height = width
        }

        let needed = bytesPerRow * height
        guard needed <= buffer.count else { return nil }
        guard let provider = CGDataProvider(data: Data(buffer.prefix(needed)) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = CGImage(width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow,
                                  space: space,
                                  bitmapInfo: info,
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: true,
                                  intent: .defaultIntent)
        else { return nil }
        return Shape(image: image,
                     size: CGSize(width: width, height: height),
                     hotSpot: CGPoint(x: min(hotSpot.x, CGFloat(width)),
                                      y: min(hotSpot.y, CGFloat(height))))
    }

    private func requestSharperImage(for identity: UInt64, rect: CGRect) {
        lock.lock()
        let alreadyTried = upgraded.contains(identity)
        if !alreadyTried { upgraded.insert(identity) }
        lock.unlock()
        guard !alreadyTried, rect.width > 0, rect.height > 0 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let cursor = NSCursor.currentSystem
            else { return }
            let wanted = Int((rect.width * 2 * RecorderSupport.zoomAmountRange.upperBound)
                .rounded(.up))
            let reps = cursor.image.representations.compactMap { $0 as? NSBitmapImageRep }
            guard let rep = reps.filter({ $0.pixelsWide >= wanted })
                    .min(by: { $0.pixelsWide < $1.pixelsWide })
                    ?? reps.max(by: { $0.pixelsWide < $1.pixelsWide }),
                  rep.pixelsWide > Int(rect.width),
                  let image = rep.cgImage
            else { return }
            let repAspect = Double(rep.pixelsWide) / Double(max(1, rep.pixelsHigh))
            let cgsAspect = Double(rect.width) / Double(max(1, rect.height))
            guard abs(repAspect - cgsAspect) < 0.02 else { return }

            self.lock.lock()
            if let existing = self.shapes[identity] {
                self.shapes[identity] = Shape(image: image,
                                              size: existing.size,
                                              hotSpot: existing.hotSpot)
            }
            self.lock.unlock()
        }
    }

    private static func hash(_ buffer: [UInt8], rect: CGRect, hotSpot: CGPoint) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ byte: UInt8) {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01B3
        }
        for byte in buffer { mix(byte) }
        for component in [rect.width, rect.height, hotSpot.x, hotSpot.y] {
            withUnsafeBytes(of: Float(component).bitPattern) { $0.forEach(mix) }
        }
        return value
    }

    func collected() -> [(id: UInt64, shape: Shape)] {
        lock.lock()
        defer { lock.unlock() }
        return order.compactMap { identity in
            shapes[identity].map { (id: identity, shape: $0) }
        }
    }
}

extension RecorderPointerTrack {
    static func packing(samples: [RecorderMotion.Sample],
                        identities: [UInt64],
                        clicks: [RecorderMotion.Click],
                        catalog: [(id: UInt64, shape: RecorderCursorCatalog.Shape)],
                        systemScale: Double,
                        displayScale: Double) -> RecorderPointerTrack {
        var indexByIdentity: [UInt64: Int] = [:]
        var packed: [CursorShape] = []
        for entry in catalog {
            guard let png = pngData(entry.shape.image) else { continue }
            indexByIdentity[entry.id] = packed.count
            packed.append(CursorShape(png: png,
                                      hotSpot: entry.shape.hotSpot,
                                      pointSize: entry.shape.size))
        }
        let remapped = samples.enumerated().map { offset, sample -> RecorderMotion.Sample in
            var copy = sample
            let identity = identities.indices.contains(offset) ? identities[offset] : 0
            copy.shapeIndex = indexByIdentity[identity] ?? 0
            return copy
        }
        return RecorderPointerTrack(samples: remapped,
                                    clicks: clicks,
                                    shapes: packed,
                                    systemScale: systemScale,
                                    displayScale: displayScale)
    }
}
