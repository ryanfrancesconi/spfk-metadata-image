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

    /// The content types ImageIO can write, which is a strict subset of what it can read.
    ///
    /// Read from `CGImageDestinationCopyTypeIdentifiers()` rather than transcribed: the set is the
    /// system's and moves between OS versions. 22 writable against 62 readable on macOS 26.5.
    public static let writableContentTypes: Set<String> =
        Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    /// Whether ImageIO can write metadata back to a file with this path extension.
    ///
    /// **Readable does not imply writable** - WebP reads in full and has no encoder at all, so
    /// every write to one fails. ``writeMetadata(_:clearing:url:)`` throws for exactly the files
    /// this refuses. Answered by extension rather than by opening the file, since it is asked per
    /// row and per field.
    public static func canWrite(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }

        return writableContentTypes.contains(type.identifier)
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

        return readMetadata(from: metadata)
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

        for field in XMPField.allCases {
            let values = metadata[field]

            if field.isStructField, clearing.contains(field) || values.isNotEmpty {
                throw ImageXMPError.writeFailed(url, underlying: UnsupportedFieldShape(field: field))
            }

            guard values.isNotEmpty, !clearing.contains(field) else { continue }

            try writes.append(write(field, values: values, url: url))

            if field.removesContainerBeforeWrite {
                replacingPaths.append(field.path)
            }
        }

        try writeTags(
            writes,
            clearingPaths: XMPField.allCases.filter(clearing.contains).map(\.path),
            replacingPaths: replacingPaths,
            url: url
        )
    }

    // MARK: - Private

    /// Two write mechanisms, chosen per field by ``XMPField``:
    /// - `.scalarProperty` goes through the `CGImageMetadataSetValueMatchingImageProperty` bridge,
    ///   for a field with a crosswalk.
    /// - `.namespacedTag` builds a tag under its namespace, at the shape `form` names.
    enum MetadataWrite {
        case scalarProperty(dictionary: CFString, property: CFString, value: CFTypeRef)
        case namespacedTag(namespace: CFString, prefix: CFString, name: String, value: CFTypeRef, form: TagForm)
    }

    enum TagForm {
        case scalar
        /// Set at the `[x-default]`-indexed path. A tag at the bare path of an `rdf:Alt` crashes.
        case alternateText
        case array(CGImageMetadataType)
    }

    struct UnsupportedFieldShape: Error {
        let field: XMPField
    }

    private static func write(_ field: XMPField, values: [String], url: URL) throws -> MetadataWrite {
        let value: CFTypeRef

        if field.shape == .integer {
            guard let number = Int(values[0]) else {
                throw ImageXMPError.writeFailed(url, underlying: nil)
            }
            value = number as CFNumber
        } else if field.isArray {
            value = values as CFArray
        } else {
            value = values[0] as CFString
        }

        if let crosswalk = field.crosswalk {
            return .scalarProperty(dictionary: kCGImagePropertyIPTCDictionary, property: crosswalk, value: value)
        }

        let form: TagForm = switch field.shape {
        case .text, .integer, .bool, .struct: .scalar
        case .langAlt: .alternateText
        case .bag: .array(.arrayUnordered)
        case .seq: .array(.arrayOrdered)
        }

        return .namespacedTag(
            namespace: field.namespace as CFString, prefix: field.prefix as CFString,
            name: field.localName, value: value, form: form
        )
    }

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
        // Merging only ever adds, so an empty metadata object cannot express a removal. Clearing
        // instead works against a mutable copy of the file's own metadata and writes it back with
        // merging off; everything not explicitly removed survives.
        let metadata: CGMutableImageMetadata
        let shouldMerge: Bool
        var registeredPrefixes: Set<String> = []

        if clearingPaths.isEmpty {
            metadata = CGImageMetadataCreateMutable()
            shouldMerge = true
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

            for (namespace, prefix) in namespacesToRegister {
                var registrationError: Unmanaged<CFError>?
                guard CGImageMetadataRegisterNamespaceForPrefix(
                    metadata, namespace as CFString, prefix as CFString, &registrationError
                ) else {
                    throw ImageXMPError.writeFailed(url, underlying: registrationError?.takeUnretainedValue())
                }
                registeredPrefixes.insert(prefix)
            }

            for path in clearingPaths + replacingPaths {
                // Returns false when the tag was absent, the ordinary case for an empty field.
                CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
            }
        }

        for write in writes {
            switch write {
            case let .scalarProperty(dictionary, property, value):
                guard CGImageMetadataSetValueMatchingImageProperty(metadata, dictionary, property, value) else {
                    throw ImageXMPError.writeFailed(url, underlying: nil)
                }

            case let .namespacedTag(namespace, prefix, name, value, form):
                // The bridge already knows the namespace of any classic property; a tag does not.
                let prefixString = prefix as String
                if !registeredPrefixes.contains(prefixString) {
                    var registrationError: Unmanaged<CFError>?
                    guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, &registrationError) else {
                        throw ImageXMPError.writeFailed(url, underlying: registrationError?.takeUnretainedValue())
                    }
                    registeredPrefixes.insert(prefixString)
                }

                let type: CGImageMetadataType = if case let .array(arrayType) = form { arrayType } else { .default }

                guard let cgTag = CGImageMetadataTagCreate(namespace, prefix, name as CFString, type, value) else {
                    throw ImageXMPError.writeFailed(url, underlying: nil)
                }

                let path = if case .alternateText = form { "\(prefixString):\(name)[x-default]" } else { "\(prefixString):\(name)" }
                guard CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, cgTag) else {
                    throw ImageXMPError.writeFailed(url, underlying: nil)
                }
            }
        }

        let tempURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-\(url.lastPathComponent)")

        defer { try? FileManager.default.removeItem(at: tempURL) }

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

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            throw ImageXMPError.writeFailed(url, underlying: error)
        }
    }
}
