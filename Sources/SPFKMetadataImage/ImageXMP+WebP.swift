// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO

extension ImageXMP {
    static let webPContentType = "org.webmproject.webp"

    /// IFD0 text tags ImageIO reads into these fields from a WebP's EXIF, ahead of the XMP chunk's
    /// own value. A write touching one of the fields removes its tag, so the XMP alone answers.
    static let webPEXIFCrosswalk: [(field: XMPField, tag: UInt16)] = [
        (.description, 0x010E), // ImageDescription
        (.copyright, 0x8298), // Copyright
        (.creators, 0x013B), // Artist
    ]

    /// ``copyImageSource(_:type:writes:clearingPaths:replacingPaths:namespacesToRegister:url:)`` for a
    /// WebP, which ImageIO cannot encode: the edit is applied to the file's own `XMP ` packet and
    /// spliced back as a chunk, leaving the image data untouched.
    ///
    /// Starts from the packet rather than ImageIO's view of the file, which also carries values
    /// synthesized from the EXIF chunk. A packet that does not parse throws rather than being replaced.
    static func writeWebP(
        writes: [MetadataWrite],
        clearingPaths: [String],
        replacingPaths: [String],
        namespacesToRegister: [(namespace: String, prefix: String)],
        url: URL
    ) throws {
        let container: WebPContainer
        do {
            container = try WebPContainer(data: Data(contentsOf: url, options: .mappedIfSafe))
        } catch {
            throw ImageXMPError.writeFailed(url, underlying: error)
        }

        let original = try container.xmpPacket.map { try packetMetadata($0, url: url) }

        guard let metadata = original.map({ CGImageMetadataCreateMutableCopy($0) }) ?? CGImageMetadataCreateMutable() else {
            throw ImageXMPError.writeFailed(url, underlying: nil)
        }

        var registeredPrefixes: Set<String> = []
        try registerNamespaces(namespacesToRegister, on: metadata, registeredPrefixes: &registeredPrefixes, url: url)

        let removedPaths = clearingPaths + replacingPaths
        for path in removedPaths {
            CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
        }

        try apply(writes, to: metadata, registeredPrefixes: &registeredPrefixes, url: url)

        let touchedTags = webPEXIFCrosswalk.filter { entry in
            removedPaths.contains(entry.field.path)
                || values(of: entry.field, in: metadata) != original.map { values(of: entry.field, in: $0) } ?? []
        }.map(\.tag)

        let output: Data
        do {
            var exif = container.exif
            if let current = exif, !touchedTags.isEmpty {
                exif = try TIFFDirectoryEdit.removingIFD0Entries(Set(touchedTags), from: current) ?? current
            }
            output = try container.replacing(xmp: xmpPacket(metadata, url: url), exif: exif)
        } catch let error as ImageXMPError {
            throw error
        } catch {
            throw ImageXMPError.writeFailed(url, underlying: error)
        }

        try replaceAtomically(url) { tempURL in
            try output.write(to: tempURL)
        }
    }

    /// A packet parsed on its own. `CGImageMetadataCreateFromXMPData` returns `nil` for one whose
    /// attributes are single-quoted, as exiftool writes them, though ImageIO reads the same packet
    /// from a file; such a packet is re-serialized through `XMLDocument` and parsed again.
    static func packetMetadata(_ packet: Data, url: URL) throws -> CGImageMetadata {
        if let metadata = CGImageMetadataCreateFromXMPData(packet as CFData) { return metadata }

        let root: XMLElement?
        do {
            root = try XMLDocument(data: packet, options: [.nodePreserveWhitespace]).rootElement()
        } catch {
            throw ImageXMPError.writeFailed(url, underlying: error)
        }

        guard let root,
              let metadata = CGImageMetadataCreateFromXMPData(Data(root.xmlString(options: [.nodePreserveWhitespace]).utf8) as CFData)
        else {
            throw ImageXMPError.writeFailed(url, underlying: nil)
        }

        return metadata
    }

    /// The metadata serialized inside an `<?xpacket` wrapper, as ImageIO's JPEG writer and Adobe's
    /// apps write it; `nil` when it holds no tags, which removes the chunk.
    ///
    /// A parsed packet carries a synthesized `iio:hasXMP`, which is never serialized. Without it, an
    /// emptied packet would serialize to a bare `rdf:Description` ImageIO cannot parse back.
    private static func xmpPacket(_ metadata: CGImageMetadata, url: URL) throws -> Data? {
        let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] ?? []
        guard tags.contains(where: { CGImageMetadataTagCopyPrefix($0) as String? != "iio" }) else { return nil }

        guard let body = CGImageMetadataCreateXMPData(metadata, nil) as Data? else {
            throw ImageXMPError.writeFailed(url, underlying: nil)
        }

        var packet = Data("<?xpacket begin=\"".utf8)
        packet.append(contentsOf: [0xEF, 0xBB, 0xBF]) // the byte-order mark the wrapper's `begin` requires
        packet.append(Data("\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n".utf8))
        packet.append(body)
        packet.append(Data("<?xpacket end=\"w\"?>".utf8))
        return packet
    }
}
