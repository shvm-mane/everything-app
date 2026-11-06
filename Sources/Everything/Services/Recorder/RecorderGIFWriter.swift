// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class RecorderGIFWriter {
    enum Failure: Error { case invalidFrame, closed, empty }

    static let framesPerChunk = 300

    private let file: FileHandle
    private let fps: Int
    private let chunkLength: Int
    private var pending: [CGImage] = []
    private var held: (picture: Picture, image: CGImage)?
    private var canvas: (width: Int, height: Int)?
    private var globalTable: Data?
    private var headerWritten = false
    private var emitted = 0
    private var closed = false

    init(url: URL, fps: Int, framesPerChunk: Int = RecorderGIFWriter.framesPerChunk) throws {
        guard (1...100).contains(fps), framesPerChunk > 0 else { throw Failure.invalidFrame }
        self.fps = fps
        chunkLength = framesPerChunk
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        file = try FileHandle(forWritingTo: url)
    }

    deinit { try? file.close() }

    func append(_ image: CGImage) throws {
        guard !closed else { throw Failure.closed }
        if let canvas {
            guard canvas.width == image.width, canvas.height == image.height else {
                throw Failure.invalidFrame
            }
        } else {
            guard (1...0xFFFF).contains(image.width), (1...0xFFFF).contains(image.height) else {
                throw Failure.invalidFrame
            }
            canvas = (image.width, image.height)
        }
        pending.append(image)
        if pending.count >= chunkLength { try flush() }
    }

    func finish() throws {
        guard !closed else { throw Failure.closed }
        try flush()
        guard let last = held else { throw Failure.empty }
        try emit(last.picture)
        held = nil
        try file.write(contentsOf: Data([0x3B]))
        try file.synchronize()
        try file.close()
        closed = true
    }

    private func flush() throws {
        guard !pending.isEmpty, let canvas else { return }
        try autoreleasepool {
            let chunk = try Self.encode(pending)
            guard chunk.width == canvas.width, chunk.height == canvas.height,
                  chunk.frames.count == pending.count else { throw Failure.invalidFrame }
            if !headerWritten { try writeHeader(chunk) }
            if var previous = held {
                if !chunk.frames[0].covers(width: canvas.width, height: canvas.height)
                    || Self.hasTransparency(pending[0]) {
                    previous.picture = try clearingPicture(of: previous.image)
                }
                try emit(previous.picture)
            }
            for frame in chunk.frames.dropLast() { try emit(picture(for: frame, in: chunk)) }
            let last = try picture(for: chunk.frames[chunk.frames.count - 1], in: chunk)
            self.held = (last, pending[pending.count - 1])
        }
        pending.removeAll()
    }

    private func writeHeader(_ chunk: Chunk) throws {
        var header = Data("GIF89a".utf8)
        header.append(contentsOf: Self.word(chunk.width) + Self.word(chunk.height))
        header.append(chunk.screen)
        if let table = chunk.globalTable { header.append(table) }
        header.append(contentsOf: [0x21, 0xFF, 11])
        header.append(Data("NETSCAPE2.0".utf8))
        header.append(contentsOf: [3, 1, 0, 0, 0])
        try file.write(contentsOf: header)
        globalTable = chunk.globalTable
        headerWritten = true
    }

    private func picture(for frame: Frame, in chunk: Chunk) throws -> Picture {
        var block = frame.descriptor
        if let local = frame.localTable {
            block.append(local)
        } else if let table = chunk.globalTable {
            if table != globalTable {
                let flags = block[block.startIndex + 9]
                block[block.startIndex + 9] = (flags & 0x60) | 0x80 | (chunk.screen[chunk.screen.startIndex] & 7)
                block.append(table)
            }
        } else {
            throw Failure.invalidFrame
        }
        block.append(frame.pixels)
        return Picture(disposal: frame.disposal, transparency: frame.transparency,
                       transparentIndex: frame.transparentIndex, block: block)
    }

    private func clearingPicture(of image: CGImage) throws -> Picture {
        let single = try Self.encode([image])
        guard let canvas, single.frames.count == 1,
              single.frames[0].covers(width: canvas.width, height: canvas.height) else {
            throw Failure.invalidFrame
        }
        var cleared = try picture(for: single.frames[0], in: single)
        cleared.disposal = 2
        return cleared
    }

    private func emit(_ picture: Picture) throws {
        let start = (Double(emitted) * 100 / Double(fps)).rounded()
        let end = (Double(emitted + 1) * 100 / Double(fps)).rounded()
        var block = Data([0x21, 0xF9, 4, ((picture.disposal & 7) << 2) | picture.transparency])
        block.append(contentsOf: Self.word(Int(end - start)))
        block.append(contentsOf: [picture.transparentIndex, 0])
        block.append(picture.block)
        try file.write(contentsOf: block)
        emitted += 1
    }

    private static func encode(_ images: [CGImage]) throws -> Chunk {
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.gif.identifier as CFString, images.count, nil) else {
            throw Failure.invalidFrame
        }
        for image in images { CGImageDestinationAddImage(encoder, image, nil) }
        guard CGImageDestinationFinalize(encoder) else { throw Failure.invalidFrame }
        return try withExtendedLifetime(data) {
            try chunk(from: Data(bytesNoCopy: data.mutableBytes, count: data.length,
                                 deallocator: .none))
        }
    }

    private static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return true }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 255 }
    }

    private struct Picture {
        var disposal: UInt8
        let transparency: UInt8
        let transparentIndex: UInt8
        let block: Data
    }

    struct Frame {
        let disposal: UInt8
        let transparency: UInt8
        let transparentIndex: UInt8
        let left: Int
        let top: Int
        let width: Int
        let height: Int
        let descriptor: Data
        let localTable: Data?
        let pixels: Data

        func covers(width: Int, height: Int) -> Bool {
            left == 0 && top == 0 && self.width == width && self.height == height
        }
    }

    struct Chunk {
        let width: Int
        let height: Int
        let screen: Data
        let globalTable: Data?
        let frames: [Frame]
    }

    static func chunk(from data: Data) throws -> Chunk {
        let bytes = [UInt8](data)
        guard bytes.count >= 13,
              ["GIF87a", "GIF89a"].contains(String(decoding: bytes[0..<6], as: UTF8.self)) else {
            throw Failure.invalidFrame
        }
        func word(at offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        func tableLength(_ flags: UInt8) -> Int {
            flags & 0x80 == 0 ? 0 : 3 * (1 << (Int(flags & 7) + 1))
        }
        func skipBlocks(_ offset: inout Int) throws {
            while offset < bytes.count {
                let length = Int(bytes[offset])
                offset += 1
                guard length <= bytes.count - offset else { throw Failure.invalidFrame }
                offset += length
                if length == 0 { return }
            }
            throw Failure.invalidFrame
        }

        let width = word(at: 6), height = word(at: 8)
        guard width > 0, height > 0 else { throw Failure.invalidFrame }
        let globalLength = tableLength(bytes[10])
        guard globalLength <= bytes.count - 13 else { throw Failure.invalidFrame }
        let globalTable = globalLength > 0 ? Data(bytes[13..<(13 + globalLength)]) : nil
        var offset = 13 + globalLength
        var disposal: UInt8 = 0, transparency: UInt8 = 0, transparentIndex: UInt8 = 0
        var frames: [Frame] = []

        while offset < bytes.count {
            switch bytes[offset] {
            case 0x21:
                guard offset + 2 < bytes.count else { throw Failure.invalidFrame }
                let label = bytes[offset + 1]
                offset += 2
                if label == 0xF9 {
                    guard offset + 6 <= bytes.count, bytes[offset] == 4,
                          bytes[offset + 5] == 0 else { throw Failure.invalidFrame }
                    disposal = (bytes[offset + 1] >> 2) & 7
                    transparency = bytes[offset + 1] & 1
                    transparentIndex = bytes[offset + 4]
                }
                try skipBlocks(&offset)
            case 0x2C:
                guard offset + 10 <= bytes.count else { throw Failure.invalidFrame }
                let left = word(at: offset + 1), top = word(at: offset + 3)
                let frameWidth = word(at: offset + 5), frameHeight = word(at: offset + 7)
                guard frameWidth > 0, frameHeight > 0,
                      left + frameWidth <= width, top + frameHeight <= height else {
                    throw Failure.invalidFrame
                }
                let descriptor = Data(bytes[offset..<(offset + 10)])
                let localLength = tableLength(bytes[offset + 9])
                offset += 10
                guard localLength <= bytes.count - offset else { throw Failure.invalidFrame }
                let localTable = localLength > 0 ? Data(bytes[offset..<(offset + localLength)]) : nil
                offset += localLength
                let entries = (localLength > 0 ? localLength : globalLength) / 3
                guard entries > 0, transparency == 0 || Int(transparentIndex) < entries,
                      offset < bytes.count, (2...8).contains(bytes[offset]) else {
                    throw Failure.invalidFrame
                }
                let pixelsStart = offset
                offset += 1
                try skipBlocks(&offset)
                frames.append(Frame(disposal: disposal, transparency: transparency,
                                    transparentIndex: transparentIndex,
                                    left: left, top: top, width: frameWidth, height: frameHeight,
                                    descriptor: descriptor, localTable: localTable,
                                    pixels: Data(bytes[pixelsStart..<offset])))
                disposal = 0
                transparency = 0
                transparentIndex = 0
            case 0x3B:
                guard offset + 1 == bytes.count, !frames.isEmpty else { throw Failure.invalidFrame }
                return Chunk(width: width, height: height, screen: Data(bytes[10..<13]),
                             globalTable: globalTable, frames: frames)
            default:
                throw Failure.invalidFrame
            }
        }
        throw Failure.invalidFrame
    }

    private static func word(_ value: Int) -> [UInt8] {
        [UInt8(value & 255), UInt8((value >> 8) & 255)]
    }
}
