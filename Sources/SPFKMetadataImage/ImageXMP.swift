// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO
import SPFKBase
import UniformTypeIdentifiers

/// Reads and writes XMP metadata on image files through ImageIO's `CGImageMetadata`/
/// `CGImageDestination`, not the Adobe XMP Toolkit (`spfk-metadata-xmp`), whose HEIC handler can
/// neither write XMP into a HEIC nor read back what ImageIO wrote there. `spfk-metadata-xmp`
/// stays the right tool for JPEG, TIFF-based RAW and its audio/video Dynamic Media use case.
///
/// **Never set an `rdf:Alt` field at a bare path** - a tag set at `"dc:rights"` crashes the
/// process, where the language-indexed `"dc:rights[x-default]"` is safe. Use
/// `CGImageMetadataSetValueMatchingImageProperty` for fields ImageIO exposes a classic-property
/// crosswalk for, and the `[x-default]`-indexed path for those it does not. Bare paths are fine
/// for plain scalars.
public enum ImageXMP {
    public enum ImageXMPError: Error, CustomStringConvertible {
        case sourceCreationFailed(URL)
        case destinationCreationFailed(URL)
        case writeFailed(URL, underlying: Error?)

        public var description: String {
            switch self {
            case let .sourceCreationFailed(url):
                "Could not create an image source for \(url.path)"
            case let .destinationCreationFailed(url):
                "Could not create an image destination for \(url.path)"
            case let .writeFailed(url, underlying):
                "Failed to write image metadata to \(url.path)" + (underlying.map { " - \($0.localizedDescription)" } ?? "")
            }
        }
    }

    // MARK: - Write capability

    /// The content types ImageIO can encode, which is a strict subset of what it can read. WebP is
    /// not among them: ``canWrite(url:)`` adds it, since its metadata is written as a chunk splice.
    ///
    /// Read from `CGImageDestinationCopyTypeIdentifiers()` rather than transcribed: the set is the
    /// system's and moves between OS versions. 22 writable against 62 readable on macOS 26.5.
    public static let writableContentTypes: Set<String> =
        Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    /// Whether metadata can be written back to a file with this path extension: a type ImageIO
    /// encodes, or WebP, whose `XMP ` and `EXIF` chunks are replaced without re-encoding.
    ///
    /// ``writeMetadata(_:clearing:url:)`` throws for exactly the files this refuses. Answered by
    /// extension rather than by opening the file, since it is asked per row and per field; the
    /// write itself routes by the file's content.
    public static func canWrite(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }

        return writableContentTypes.contains(type.identifier) || type.identifier == webPContentType
    }

    /// The content types ImageIO can read.
    public static let readableContentTypes: Set<String> =
        Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])

    /// Whether ImageIO can read a file with this path extension. SVG, for one, it cannot.
    public static func canRead(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }

        return readableContentTypes.contains(type.identifier)
    }

    // MARK: - Full metadata read

    /// Reads every field this package supports in one pass - one file open, one metadata copy.
    public static func readMetadata(from url: URL) throws -> XMPMetadata {
        // A source is created for a file it cannot read; only its status says the read failed.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete
        else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
            return XMPMetadata()
        }

        var result = readMetadata(from: metadata)

        if let packet = try pngPacketMetadata(source: source, url: url) {
            for field in XMPField.allCases {
                let values = values(of: field, in: packet)
                if values.isNotEmpty { result[field] = values }
            }
        }

        return result
    }

    /// Every field this package supports, from metadata already in memory.
    static func readMetadata(from metadata: CGImageMetadata) -> XMPMetadata {
        var result = XMPMetadata()

        for field in XMPField.allCases {
            result[field] = values(of: field, in: metadata)
        }

        return result
    }

    /// Writes every non-empty field in `metadata`, preserving everything else already on the
    /// file. An empty field means **leave the existing value alone**, not clear it - `clearing`
    /// is what expresses the difference `XMPMetadata` cannot.
    ///
    /// - Parameter clearing: fields to remove from the file. A field listed here is **not**
    ///   written even if `metadata` carries a value for it.
    public static func writeMetadata(
        _ metadata: XMPMetadata,
        clearing: Set<XMPField> = [],
        url: URL
    ) throws {
        var writes: [MetadataWrite] = []
        var replacingPaths: [String] = []
        var structChildren: [(field: XMPField, value: String?)] = []

        for field in XMPField.allCases {
            let values = metadata[field]
            let isCleared = clearing.contains(field)
            let isTouched = isCleared || values.isNotEmpty

            // A child-path removal traps, and a merge replaces the whole struct, so children are
            // collected into one rebuilt struct below.
            if field.isStructField {
                if isTouched { structChildren.append((field, isCleared ? nil : values[0])) }
                continue
            }

            if let mirror = field.imageIOMirror, isTouched {
                writes.append(.mirroredTag(
                    namespace: mirror.namespace.uri as CFString, prefix: mirror.namespace.prefix as CFString,
                    name: mirror.name, value: isCleared ? nil : values[0] as CFString
                ))
            }

            guard values.isNotEmpty, !isCleared else { continue }

            try writes.append(write(field, values: values, url: url))

            if field.removesContainerBeforeWrite {
                replacingPaths.append(field.path)
            }
        }

        writes += structureWrites(structChildren)

        try writeTags(
            writes,
            clearingPaths: XMPField.allCases.filter { clearing.contains($0) && !$0.isStructField }.map(\.path),
            replacingPaths: replacingPaths,
            url: url
        )
    }

    // MARK: - Private

    /// Builds a metadata object from `writes` and merges it onto the file, preserving the EXIF and
    /// XMP this package does not model. Writes to a temporary file in the same directory as `url`
    /// and atomically replaces the original, so a failure mid-write cannot corrupt it.
    ///
    /// `namespacesToRegister` lets a removal address a namespace the file's own metadata object has
    /// no prefix for. `replacingPaths` are removed like `clearingPaths`, but only when something is
    /// being cleared: a merging write starts from an empty object and has nothing to remove. A PNG
    /// with no XMP packet is seeded with one first, which costs a second file write.
    static func writeTags(
        _ writes: [MetadataWrite],
        clearingPaths: [String] = [],
        replacingPaths: [String] = [],
        namespacesToRegister: [(namespace: String, prefix: String)] = [],
        url: URL
    ) throws {
        guard var source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let uti = CGImageSourceGetType(source)
        else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        if writes.isNotEmpty, try needsPNGPacketSeed(type: uti, url: url) {
            try seedPNGPacket(source: source, type: uti, url: url)

            guard let seeded = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw ImageXMPError.sourceCreationFailed(url)
            }
            source = seeded
        }

        try copyImageSource(
            source, type: uti, writes: writes, clearingPaths: clearingPaths, replacingPaths: replacingPaths,
            namespacesToRegister: namespacesToRegister, url: url
        )
    }

    /// The body of ``writeTags(_:clearingPaths:replacingPaths:namespacesToRegister:url:)``, without
    /// the PNG packet seed.
    static func copyImageSource(
        _ source: CGImageSource,
        type uti: CFString,
        writes: [MetadataWrite],
        clearingPaths: [String],
        replacingPaths: [String],
        namespacesToRegister: [(namespace: String, prefix: String)],
        url: URL
    ) throws {
        if (uti as String) == webPContentType {
            try writeWebP(
                writes: writes, clearingPaths: clearingPaths, replacingPaths: replacingPaths,
                namespacesToRegister: namespacesToRegister, url: url
            )
            return
        }

        // Merging only ever adds, so an empty metadata object cannot express a removal. Clearing
        // instead works against a mutable copy of the file's own metadata and writes it back with
        // merging off; everything not explicitly removed survives.
        let metadata: CGMutableImageMetadata
        let shouldMerge: Bool
        var registeredPrefixes: Set<String> = []

        // Both paths start from ImageIO's view of a PNG, which holds one `dc:creator`.
        let packet = try pngPacketMetadata(source: source, url: url)

        func restorePNGPacketFields(into metadata: CGMutableImageMetadata) {
            guard let packet else { return }

            for field in XMPField.allCases {
                guard let tag = CGImageMetadataCopyTagWithPath(packet, nil, field.path as CFString) else { continue }
                CGImageMetadataSetTagWithPath(metadata, nil, field.path as CFString, tag)
            }
        }

        if clearingPaths.isEmpty, !writes.contains(where: \.startsFromFileMetadata) {
            metadata = CGImageMetadataCreateMutable()
            shouldMerge = true
            restorePNGPacketFields(into: metadata)
        } else {
            if let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
               let mutableCopy = CGImageMetadataCreateMutableCopy(existing)
            {
                metadata = mutableCopy
            } else {
                // No XMP on the file at all - nothing to remove.
                metadata = CGImageMetadataCreateMutable()
            }

            shouldMerge = false

            try registerNamespaces(namespacesToRegister, on: metadata, registeredPrefixes: &registeredPrefixes, url: url)

            restorePNGPacketFields(into: metadata)

            for path in clearingPaths + replacingPaths {
                // Returns false when the tag was absent, the ordinary case for an empty field.
                CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
            }
        }

        try apply(writes, to: metadata, registeredPrefixes: &registeredPrefixes, url: url)

        try replaceAtomically(url) { tempURL in
            guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, 1, nil) else {
                throw ImageXMPError.destinationCreationFailed(url)
            }

            let options: [CFString: Any] = [
                kCGImageDestinationMetadata: metadata,
                kCGImageDestinationMergeMetadata: shouldMerge,
            ]

            var copyError: Unmanaged<CFError>?
            guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &copyError) else {
                throw ImageXMPError.writeFailed(url, underlying: copyError?.takeUnretainedValue())
            }
        }
    }

    static func registerNamespaces(
        _ namespaces: [(namespace: String, prefix: String)],
        on metadata: CGMutableImageMetadata,
        registeredPrefixes: inout Set<String>,
        url: URL
    ) throws {
        for (namespace, prefix) in namespaces {
            var registrationError: Unmanaged<CFError>?
            guard CGImageMetadataRegisterNamespaceForPrefix(
                metadata, namespace as CFString, prefix as CFString, &registrationError
            ) else {
                throw ImageXMPError.writeFailed(url, underlying: registrationError?.takeUnretainedValue())
            }
            registeredPrefixes.insert(prefix)
        }
    }

    /// Runs `write` against a temporary file beside `url`, then swaps it in, so a failure
    /// mid-write cannot corrupt the original.
    static func replaceAtomically(_ url: URL, write: (URL) throws -> Void) throws {
        let tempURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-\(url.lastPathComponent)")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        try write(tempURL)

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            throw ImageXMPError.writeFailed(url, underlying: error)
        }
    }
}
