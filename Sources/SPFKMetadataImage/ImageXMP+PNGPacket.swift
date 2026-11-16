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
                namespace: xmpBasicNamespace as CFString, prefix: xmpBasicPrefix as CFString,
                name: "MetadataDate", value: now as CFString, isAlternateText: false
            )],
            clearingPaths: [], replacingPaths: [], namespacesToRegister: [], url: url
        )

        guard try pngHasXMPPacket(url: url) else {
            throw ImageXMPError.writeFailed(url, underlying: nil)
        }
    }

    /// Whether the PNG has an `iTXt` chunk keyed `XML:com.adobe.xmp`.
    ///
    /// `CGImageSourceCopyMetadataAtIndex` cannot answer this: ImageIO writes an `eXIf` chunk into
    /// every PNG it encodes, and returns that as metadata whether or not a packet exists.
    static func pngHasXMPPacket(url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let signatureLength: UInt64 = 8
        let xmpKeyword = Data("XML:com.adobe.xmp\0".utf8)
        var offset = signatureLength

        try handle.seek(toOffset: offset)

        while let header = try handle.read(upToCount: 8), header.count == 8 {
            let length = header.prefix(4).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let type = String(decoding: header.suffix(4), as: UTF8.self)

            if type == "IEND" { return false }

            if type == "iTXt", length >= UInt64(xmpKeyword.count),
               try handle.read(upToCount: xmpKeyword.count) == xmpKeyword
            {
                return true
            }

            // Length, type, data, CRC.
            offset += 12 + length
            try handle.seek(toOffset: offset)
        }

        return false
    }
}
