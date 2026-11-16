// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageXMP {
    /// On a PNG with no XMP packet, ImageIO drops a whole `CGImageDestinationCopyImageSource` write
    /// containing any `dc:`, `photoshop:` or `Iptc4xmpCore:` property and still reports success. An
    /// `xmp:`-only write does create the packet, after which every write lands.
    static func needsPNGPacketSeed(type: CFString, url: URL) throws -> Bool {
        guard (type as String) == UTType.png.identifier else { return false }

        return try !pngHasXMPPacket(url: url)
    }

    /// Writes `xmp:MetadataDate` alone so the file gains a packet, and throws if it did not.
    static func seedPNGPacket(source: CGImageSource, type: CFString, url: URL) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try copyImageSource(
            source, type: type,
            writes: [.namespacedTag(
                namespace: XMPNamespace.xmpBasic.uri as CFString, prefix: XMPNamespace.xmpBasic.prefix as CFString,
                name: "MetadataDate", value: now as CFString, form: .scalar
            )],
            clearingPaths: [], replacingPaths: [], namespacesToRegister: [], url: url
        )

        guard try pngHasXMPPacket(url: url) else {
            throw ImageXMPError.writeFailed(url, underlying: nil)
        }
    }

    /// A PNG's XMP packet parsed on its own, `nil` for any other type or a PNG without one.
    ///
    /// ImageIO's merged metadata for a PNG holds only the first `dc:creator` however many the
    /// packet has, so the packet's own value is the one to read, and to write back on a clear.
    static func pngPacketMetadata(source: CGImageSource, url: URL) throws -> CGImageMetadata? {
        guard let type = CGImageSourceGetType(source), (type as String) == UTType.png.identifier,
              let packet = try pngXMPPacket(url: url)
        else {
            return nil
        }

        return CGImageMetadataCreateFromXMPData(Data(packet.utf8) as CFData)
    }

    /// Whether the PNG has an `iTXt` chunk keyed `XML:com.adobe.xmp`.
    ///
    /// `CGImageSourceCopyMetadataAtIndex` cannot answer this: ImageIO writes an `eXIf` chunk into
    /// every PNG it encodes, and returns that as metadata whether or not a packet exists.
    static func pngHasXMPPacket(url: URL) throws -> Bool {
        try pngXMPChunk(url: url) != nil
    }

    /// The text of the PNG's XMP packet, `nil` when it has none or the text is compressed.
    static func pngXMPPacket(url: URL) throws -> String? {
        guard let chunk = try pngXMPChunk(url: url) else { return nil }

        // After the keyword: compression flag, compression method, then a language tag and a
        // translated keyword, each NUL-terminated.
        var rest = chunk.dropFirst(xmpKeyword.count)
        guard rest.count >= 2, rest[rest.startIndex] == 0 else { return nil }
        rest = rest.dropFirst(2)

        for _ in 0 ..< 2 {
            guard let terminator = rest.firstIndex(of: 0) else { return nil }
            rest = rest[rest.index(after: terminator)...]
        }

        return String(data: Data(rest), encoding: .utf8)
    }

    private static let xmpKeyword = Data("XML:com.adobe.xmp\0".utf8)

    /// The data of the PNG's `iTXt` chunk keyed `XML:com.adobe.xmp`, keyword included.
    private static func pngXMPChunk(url: URL) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let signatureLength: UInt64 = 8
        var offset = signatureLength

        try handle.seek(toOffset: offset)

        while let header = try handle.read(upToCount: 8), header.count == 8 {
            let length = header.prefix(4).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let type = String(decoding: header.suffix(4), as: UTF8.self)

            if type == "IEND" { return nil }

            if type == "iTXt", length >= UInt64(xmpKeyword.count),
               let data = try handle.read(upToCount: Int(length)), data.prefix(xmpKeyword.count) == xmpKeyword
            {
                return data
            }

            // Length, type, data, CRC.
            offset += 12 + length
            try handle.seek(toOffset: offset)
        }

        return nil
    }
}
