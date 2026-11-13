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

    private static let dublinCoreNamespace = "http://purl.org/dc/elements/1.1/"
    private static let dublinCorePrefix = "dc"

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

    private static let iptcExtensionNamespace = "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/"
    private static let iptcExtensionPrefix = "Iptc4xmpCore"
    private static let xmpBasicNamespace = "http://ns.adobe.com/xap/1.0/"
    private static let xmpBasicPrefix = "xmp"
    private static let photoshopNamespace = "http://ns.adobe.com/photoshop/1.0/"
    private static let photoshopPrefix = "photoshop"

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
        XMPMetadata(
            keywords: arrayValue(metadata, path: "dc:subject"),
            creators: arrayValue(metadata, path: "dc:creator"),
            title: alternateTextValue(metadata, path: "dc:title"),
            description: alternateTextValue(metadata, path: "dc:description"),
            copyright: alternateTextValue(metadata, path: "dc:rights"),
            city: scalarStringValue(metadata, path: "photoshop:City"),
            state: scalarStringValue(metadata, path: "photoshop:State"),
            country: scalarStringValue(metadata, path: "photoshop:Country"),
            subLocation: scalarStringValue(metadata, path: "Iptc4xmpCore:Location"),
            rating: scalarIntValue(metadata, path: "xmp:Rating"),
            label: scalarStringValue(metadata, path: "xmp:Label"),
            labelColor: scalarStringValue(metadata, path: "photoshop:LabelColor"),
            accessibilityAltText: alternateTextValue(metadata, path: "Iptc4xmpCore:AltTextAccessibility"),
            accessibilityDescription: alternateTextValue(metadata, path: "Iptc4xmpCore:ExtDescrAccessibility")
        )
    }

    /// Writes every non-empty/non-nil field in `metadata`, preserving everything else already on
    /// the file. `[]`/`nil` means **leave the existing value alone**, not clear it - `clearing`
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
        if metadata.keywords.isNotEmpty, !clearing.contains(.keywords) {
            writes.append(.array(name: "subject", type: .arrayUnordered, value: metadata.keywords as CFArray))
        }
        if metadata.creators.isNotEmpty, !clearing.contains(.creators) {
            writes.append(.array(name: "creator", type: .arrayOrdered, value: metadata.creators as CFArray))
        }
        if let title = metadata.title, !clearing.contains(.title) {
            writes.append(.scalarProperty(
                dictionary: kCGImagePropertyIPTCDictionary, property: kCGImagePropertyIPTCObjectName, value: title as CFString
            ))
        }
        if let description = metadata.description, !clearing.contains(.description) {
            writes.append(.scalarProperty(
                dictionary: kCGImagePropertyIPTCDictionary, property: kCGImagePropertyIPTCCaptionAbstract, value: description as CFString
            ))
        }
        if let copyright = metadata.copyright, !clearing.contains(.copyright) {
            writes.append(.scalarProperty(
                dictionary: kCGImagePropertyIPTCDictionary, property: kCGImagePropertyIPTCCopyrightNotice, value: copyright as CFString
            ))
        }
        if let city = metadata.city, !clearing.contains(.city) {
            writes.append(.scalarProperty(
                dictionary: kCGImagePropertyIPTCDictionary, property: kCGImagePropertyIPTCCity, value: city as CFString
            ))
        }
        if let state = metadata.state, !clearing.contains(.state) {
            writes.append(.scalarProperty(
                dictionary: kCGImagePropertyIPTCDictionary, property: kCGImagePropertyIPTCProvinceState, value: state as CFString
            ))
        }
        if let country = metadata.country, !clearing.contains(.country) {
            writes.append(.scalarProperty(
                dictionary: kCGImagePropertyIPTCDictionary, property: kCGImagePropertyIPTCCountryPrimaryLocationName, value: country as CFString
            ))
        }
        if let subLocation = metadata.subLocation, !clearing.contains(.subLocation) {
            writes.append(.scalarProperty(
                dictionary: kCGImagePropertyIPTCDictionary, property: kCGImagePropertyIPTCSubLocation, value: subLocation as CFString
            ))
        }
        if let rating = metadata.rating, !clearing.contains(.rating) {
            writes.append(.scalarProperty(
                dictionary: kCGImagePropertyIPTCDictionary, property: kCGImagePropertyIPTCStarRating, value: rating as CFNumber
            ))
        }
        if let label = metadata.label, !clearing.contains(.label) {
            writes.append(.namespacedTag(
                namespace: xmpBasicNamespace as CFString, prefix: xmpBasicPrefix as CFString,
                name: "Label", value: label as CFString, isAlternateText: false
            ))
        }
        if let labelColor = metadata.labelColor, !clearing.contains(.labelColor) {
            writes.append(.namespacedTag(
                namespace: photoshopNamespace as CFString, prefix: photoshopPrefix as CFString,
                name: "LabelColor", value: labelColor as CFString, isAlternateText: false
            ))
        }
        if let altText = metadata.accessibilityAltText, !clearing.contains(.accessibilityAltText) {
            writes.append(.namespacedTag(
                namespace: iptcExtensionNamespace as CFString, prefix: iptcExtensionPrefix as CFString,
                name: "AltTextAccessibility", value: altText as CFString, isAlternateText: true
            ))
        }
        if let extendedDescription = metadata.accessibilityDescription, !clearing.contains(.accessibilityDescription) {
            writes.append(.namespacedTag(
                namespace: iptcExtensionNamespace as CFString, prefix: iptcExtensionPrefix as CFString,
                name: "ExtDescrAccessibility", value: extendedDescription as CFString, isAlternateText: true
            ))
        }

        // The bridge sets a string onto an existing `rdf:Alt` without changing its type, which
        // ImageIO then writes back empty or raises on while copying. Removing the container first
        // makes the bridge build a fresh one.
        var rewritten: [XMPField] = []
        if metadata.title != nil { rewritten.append(.title) }
        if metadata.description != nil { rewritten.append(.description) }
        if metadata.copyright != nil { rewritten.append(.copyright) }

        try writeTags(
            writes,
            clearingPaths: clearing.map(\.path),
            replacingPaths: rewritten.filter { !clearing.contains($0) }.map(\.path),
            url: url
        )
    }

    // MARK: - Private

    /// Three write mechanisms, chosen per field:
    /// - `.array` hand-builds a `dc:`-namespaced tag, the only safe way found for `rdf:Bag`/
    ///   `rdf:Seq` fields.
    /// - `.scalarProperty` goes through the `CGImageMetadataSetValueMatchingImageProperty` bridge,
    ///   for any field with a classic-property crosswalk.
    /// - `.namespacedTag` builds a tag under a registered namespace, for fields with no crosswalk.
    ///   `isAlternateText` selects the `[x-default]`-indexed path `rdf:Alt` fields require.
    enum MetadataWrite {
        case array(name: String, type: CGImageMetadataType, value: CFArray)
        case scalarProperty(dictionary: CFString, property: CFString, value: CFTypeRef)
        case namespacedTag(namespace: CFString, prefix: CFString, name: String, value: CFTypeRef, isAlternateText: Bool)
    }

    /// Builds a metadata object from `writes` and merges it onto the file, preserving the EXIF and
    /// XMP this package does not model. Writes to a temporary file in the same directory as `url`
    /// and atomically replaces the original, so a failure mid-write cannot corrupt it.
    ///
    /// `namespacesToRegister` lets a removal address a namespace the file's own metadata object has
    /// no prefix for. `replacingPaths` are removed like `clearingPaths`, but only when something is
    /// being cleared: a merging write starts from an empty object and has nothing to remove.
    static func writeTags(
        _ writes: [MetadataWrite],
        clearingPaths: [String] = [],
        replacingPaths: [String] = [],
        namespacesToRegister: [(namespace: String, prefix: String)] = [],
        url: URL
    ) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let uti = CGImageSourceGetType(source) else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

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

        // Only the manual `CGImageMetadataTagCreate` paths need a registered namespace; the
        // `.scalarProperty` bridge already knows the namespace of any classic property.
        if writes.contains(where: { if case .array = $0 { true } else { false } }) {
            var registrationError: Unmanaged<CFError>?
            guard CGImageMetadataRegisterNamespaceForPrefix(
                metadata, dublinCoreNamespace as CFString, dublinCorePrefix as CFString, &registrationError
            ) else {
                throw ImageXMPError.writeFailed(url, underlying: registrationError?.takeUnretainedValue())
            }
        }

        for write in writes {
            switch write {
            case let .array(name, type, value):
                guard let cgTag = CGImageMetadataTagCreate(
                    dublinCoreNamespace as CFString, dublinCorePrefix as CFString, name as CFString, type, value
                ) else {
                    throw ImageXMPError.writeFailed(url, underlying: nil)
                }

                guard CGImageMetadataSetTagWithPath(metadata, nil, "dc:\(name)" as CFString, cgTag) else {
                    throw ImageXMPError.writeFailed(url, underlying: nil)
                }

            case let .scalarProperty(dictionary, property, value):
                guard CGImageMetadataSetValueMatchingImageProperty(metadata, dictionary, property, value) else {
                    throw ImageXMPError.writeFailed(url, underlying: nil)
                }

            case let .namespacedTag(namespace, prefix, name, value, isAlternateText):
                let prefixString = prefix as String
                if !registeredPrefixes.contains(prefixString) {
                    var registrationError: Unmanaged<CFError>?
                    guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, &registrationError) else {
                        throw ImageXMPError.writeFailed(url, underlying: registrationError?.takeUnretainedValue())
                    }
                    registeredPrefixes.insert(prefixString)
                }

                guard let cgTag = CGImageMetadataTagCreate(namespace, prefix, name as CFString, .default, value) else {
                    throw ImageXMPError.writeFailed(url, underlying: nil)
                }

                let path = isAlternateText ? "\(prefixString):\(name)[x-default]" : "\(prefixString):\(name)"
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
