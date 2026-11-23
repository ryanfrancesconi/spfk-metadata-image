// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A WebP's whole packet, as distinct from the modeled fields: the file's `XMP ` chunk is ours to
/// replace, so an edited packet is written as edited rather than through the fields.
extension ImageXMP {
    /// Whether the whole packet can be written, not only the modeled fields. Answered by extension,
    /// like ``canWrite(url:)``; a file whose content is not a WebP throws on the write.
    public static func canWritePacket(url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.identifier == webPContentType
    }

    /// The text of a WebP's `XMP ` chunk, `nil` when it has none. Unlike ``packet(from:)``, it holds
    /// nothing ImageIO synthesized from the EXIF.
    public static func webPPacket(from url: URL) throws -> String? {
        let container: WebPContainer
        do {
            container = try WebPContainer(data: Data(contentsOf: url, options: .mappedIfSafe))
        } catch {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let packet = container.xmpPacket else { return nil }
        guard let text = String(data: packet, encoding: .utf8) else { throw ImageXMPError.sourceCreationFailed(url) }

        return text
    }

    /// Writes the top-level properties that differ between `baseline` and `edited` into a WebP's
    /// packet, so a property another app changed since `baseline` was read is kept unless the edit
    /// changed it too. `edited` `nil` removes the packet.
    ///
    /// - Parameter baseline: the packet the edit began from, `nil` when the file had none.
    public static func applyWebPPacketChanges(from baseline: String?, to edited: String?, url: URL) throws {
        let before = try baseline.map { try packetMetadata(Data($0.utf8), url: url) }
        let after = try edited.map { try packetMetadata(Data($0.utf8), url: url) }

        try rewriteWebPPacket(url: url) { original in
            guard let after else { return (CGImageMetadataCreateMutable(), []) }

            guard let metadata = original.map({ CGImageMetadataCreateMutableCopy($0) }) ?? CGImageMetadataCreateMutable() else {
                throw ImageXMPError.writeFailed(url, underlying: nil)
            }

            for path in Set(topLevelPaths(before) + topLevelPaths(after)).sorted()
                where serializedTag(at: path, in: before) != serializedTag(at: path, in: after)
            {
                CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)

                guard let tag = CGImageMetadataCopyTagWithPath(after, nil, path as CFString) else { continue }
                try setTag(tag, at: path, in: metadata, url: url)
            }

            return (metadata, [])
        }
    }

    /// Top-level `prefix:name` paths, without ImageIO's synthesized `iio:` tags.
    private static func topLevelPaths(_ metadata: CGImageMetadata?) -> [String] {
        guard let metadata, let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] else { return [] }

        return tags.compactMap { tag in
            guard let prefix = CGImageMetadataTagCopyPrefix(tag) as String?, prefix != "iio",
                  let name = CGImageMetadataTagCopyName(tag) as String?
            else { return nil }
            return "\(prefix):\(name)"
        }
    }

    /// The tag at `path` serialized on its own, which compares two parses where `CFEqual` cannot.
    private static func serializedTag(at path: String, in metadata: CGImageMetadata?) -> Data? {
        guard let metadata, let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) else { return nil }

        let single = CGImageMetadataCreateMutable()
        guard registerNamespace(of: tag, on: single),
              CGImageMetadataSetTagWithPath(single, nil, path as CFString, tag)
        else { return nil }

        return CGImageMetadataCreateXMPData(single, nil) as Data?
    }

    private static func setTag(_ tag: CGImageMetadataTag, at path: String, in metadata: CGMutableImageMetadata, url: URL) throws {
        guard registerNamespace(of: tag, on: metadata),
              CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag)
        else {
            throw ImageXMPError.writeFailed(url, underlying: nil)
        }
    }

    /// A tag set from another metadata object needs its namespace registered on this one.
    private static func registerNamespace(of tag: CGImageMetadataTag, on metadata: CGMutableImageMetadata) -> Bool {
        guard let namespace = CGImageMetadataTagCopyNamespace(tag), let prefix = CGImageMetadataTagCopyPrefix(tag) else {
            return false
        }
        return CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil)
    }
}
