// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

/// A WebP's RIFF chunk list, and a copy of the file with its `EXIF` and `XMP ` chunks replaced.
///
/// Every other chunk is carried across byte for byte, so a metadata write never touches image
/// data. Layout and VP8X flags follow libwebp's muxer (`WebPMuxSetChunk` + `WebPMuxAssemble`).
struct WebPContainer {
    enum ParseError: Error, Equatable {
        case notWebP
        case sizeMismatch
        case truncatedChunk(offset: Int)
        case missingImage
        case duplicateChunk(String)
        case unreadableBitstream
    }

    struct Chunk {
        let fourCC: String
        /// The chunk header's offset, relative to the container's start.
        let offset: Int
        let size: Int

        var payloadOffset: Int { offset + 8 }
        /// Header, payload and pad byte.
        var diskSize: Int { 8 + size + (size & 1) }
    }

    let data: Data
    let chunks: [Chunk]

    init(data: Data) throws {
        self.data = data

        guard data.count >= 12, Self.fourCC(data, at: 0) == "RIFF", Self.fourCC(data, at: 8) == "WEBP" else {
            throw ParseError.notWebP
        }

        guard Int(Self.uint32(data, at: 4)) + 8 == data.count else { throw ParseError.sizeMismatch }

        var chunks: [Chunk] = []
        var offset = 12

        while offset < data.count {
            guard offset + 8 <= data.count else { throw ParseError.truncatedChunk(offset: offset) }

            let chunk = Chunk(fourCC: Self.fourCC(data, at: offset), offset: offset, size: Int(Self.uint32(data, at: offset + 4)))
            guard offset + chunk.diskSize <= data.count else { throw ParseError.truncatedChunk(offset: offset) }

            chunks.append(chunk)
            offset += chunk.diskSize
        }

        for fourCC in [Self.exifFourCC, Self.xmpFourCC] where chunks.count(where: { $0.fourCC == fourCC }) > 1 {
            throw ParseError.duplicateChunk(fourCC)
        }

        switch chunks.first?.fourCC {
        case "VP8 ", "VP8L":
            guard chunks.count == 1 else { throw ParseError.missingImage }
        case "VP8X":
            guard chunks.count(where: { Self.imageFourCCs.contains($0.fourCC) }) > 0 else { throw ParseError.missingImage }
        default:
            throw ParseError.missingImage
        }

        self.chunks = chunks
    }

    var xmpPacket: Data? { payload(of: Self.xmpFourCC) }

    var exif: Data? { payload(of: Self.exifFourCC) }

    /// The file with `xmp` and `exif` as its metadata chunks; `nil` removes that chunk.
    func replacing(xmp: Data?, exif: Data?) throws -> Data {
        guard let first = chunks.first else { throw ParseError.missingImage }

        var parts: [Data] = []

        if first.fourCC == "VP8X" {
            parts = extendedChunks(xmp: xmp, exif: exif)
        } else if xmp == nil, exif == nil {
            return data
        } else {
            let hasAlpha = first.fourCC == "VP8L" ? try Self.losslessHasAlpha(chunkPayload(first)) : false
            let flags = (exif == nil ? 0 : Self.exifFlag) | (xmp == nil ? 0 : Self.xmpFlag) | (hasAlpha ? Self.alphaFlag : 0)
            parts = try [Self.vp8xChunk(flags: flags, canvas: Self.canvasSize(of: first, in: data)), chunkBytes(first)]
            if let exif { parts.append(Self.chunk(Self.exifFourCC, exif)) }
            if let xmp { parts.append(Self.chunk(Self.xmpFourCC, xmp)) }
        }

        var output = Data("RIFF".utf8)
        output.append(Self.littleEndian(UInt32(4 + parts.reduce(0) { $0 + $1.count })))
        output.append(Data("WEBP".utf8))
        parts.forEach { output.append($0) }
        return output
    }

    // MARK: - Extended layout

    private func extendedChunks(xmp: Data?, exif: Data?) -> [Data] {
        var kept: [(fourCC: String, bytes: Data)] = []

        for chunk in chunks {
            switch chunk.fourCC {
            case Self.exifFourCC: if let exif { kept.append((chunk.fourCC, Self.chunk(Self.exifFourCC, exif))) }
            case Self.xmpFourCC: if let xmp { kept.append((chunk.fourCC, Self.chunk(Self.xmpFourCC, xmp))) }
            default: kept.append((chunk.fourCC, chunkBytes(chunk)))
            }
        }

        let lastImage = kept.lastIndex { Self.imageFourCCs.contains($0.fourCC) } ?? kept.count - 1

        if let exif, !kept.contains(where: { $0.fourCC == Self.exifFourCC }) {
            kept.insert((Self.exifFourCC, Self.chunk(Self.exifFourCC, exif)), at: lastImage + 1)
        }

        if let xmp, !kept.contains(where: { $0.fourCC == Self.xmpFourCC }) {
            let after = kept.firstIndex { $0.fourCC == Self.exifFourCC } ?? lastImage
            kept.insert((Self.xmpFourCC, Self.chunk(Self.xmpFourCC, xmp)), at: after + 1)
        }

        // With no flag left to carry, the muxer writes the lone bitstream in simple form.
        if kept.count == 2, ["VP8 ", "VP8L"].contains(kept[1].fourCC) {
            return [kept[1].bytes]
        }

        var vp8x = kept[0].bytes
        var flags = vp8x[vp8x.startIndex + 8] & ~(Self.exifFlag | Self.xmpFlag)
        if exif != nil { flags |= Self.exifFlag }
        if xmp != nil { flags |= Self.xmpFlag }
        vp8x[vp8x.startIndex + 8] = flags
        kept[0].bytes = vp8x

        return kept.map(\.bytes)
    }

    // MARK: - Chunks

    private static let exifFourCC = "EXIF"
    private static let xmpFourCC = "XMP "
    private static let imageFourCCs: Set<String> = ["VP8 ", "VP8L", "ALPH", "ANIM", "ANMF"]

    private static let alphaFlag: UInt8 = 0x10
    private static let exifFlag: UInt8 = 0x08
    private static let xmpFlag: UInt8 = 0x04

    private func payload(of fourCC: String) -> Data? {
        chunks.first { $0.fourCC == fourCC }.map(chunkPayload)
    }

    private func chunkPayload(_ chunk: Chunk) -> Data {
        let start = data.startIndex + chunk.payloadOffset
        return data[start ..< start + chunk.size]
    }

    private func chunkBytes(_ chunk: Chunk) -> Data {
        let start = data.startIndex + chunk.offset
        return data[start ..< start + chunk.diskSize]
    }

    private static func chunk(_ fourCC: String, _ payload: Data) -> Data {
        var bytes = Data(fourCC.utf8)
        bytes.append(littleEndian(UInt32(payload.count)))
        bytes.append(payload)
        if payload.count & 1 == 1 { bytes.append(0) }
        return bytes
    }

    private static func vp8xChunk(flags: UInt8, canvas: (width: Int, height: Int)) -> Data {
        var payload = Data([flags, 0, 0, 0])
        payload.append(littleEndian(UInt32(canvas.width - 1)).prefix(3))
        payload.append(littleEndian(UInt32(canvas.height - 1)).prefix(3))
        return chunk("VP8X", payload)
    }

    // MARK: - Bitstream headers

    /// The canvas of a simple-format file: a VP8 key frame's 14-bit dimensions, after its 3-byte
    /// frame tag and `9d 01 2a` start code; or a VP8L's, after its `0x2f` signature.
    private static func canvasSize(of chunk: Chunk, in data: Data) throws -> (width: Int, height: Int) {
        let base = data.startIndex + chunk.payloadOffset
        let bytes = { (index: Int) in Int(data[base + index]) }

        if chunk.fourCC == "VP8 " {
            guard chunk.size >= 10, bytes(0) & 1 == 0, bytes(3) == 0x9D, bytes(4) == 0x01, bytes(5) == 0x2A else {
                throw ParseError.unreadableBitstream
            }
            return ((bytes(6) | bytes(7) << 8) & 0x3FFF, (bytes(8) | bytes(9) << 8) & 0x3FFF)
        }

        let bits = try losslessHeaderBits(data[base ..< base + chunk.size])
        return (Int(bits & 0x3FFF) + 1, Int(bits >> 14 & 0x3FFF) + 1)
    }

    /// Whether a VP8L payload sets `alpha_is_used`.
    private static func losslessHasAlpha(_ payload: Data) throws -> Bool {
        try losslessHeaderBits(payload) >> 28 & 1 == 1
    }

    /// The 32 bits after a VP8L signature: width-1, height-1, alpha, then a version that must be 0.
    private static func losslessHeaderBits(_ payload: Data) throws -> UInt32 {
        guard payload.count >= 5, payload.first == 0x2F else { throw ParseError.unreadableBitstream }
        let bits = uint32(payload, at: 1)
        guard bits >> 29 == 0 else { throw ParseError.unreadableBitstream }
        return bits
    }

    // MARK: - Bytes

    private static func fourCC(_ data: Data, at offset: Int) -> String {
        let start = data.startIndex + offset
        return String(decoding: data[start ..< start + 4], as: UTF8.self)
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return (0 ..< 4).reduce(UInt32(0)) { $0 | UInt32(data[start + $1]) << (8 * $1) }
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        Data((0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }
}
