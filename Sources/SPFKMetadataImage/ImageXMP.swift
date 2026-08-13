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
/// **Never set an `rdf:Alt` field at a bare path** — a tag set at `"dc:rights"` crashes the
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
                "Failed to write image metadata to \(url.path)" + (underlying.map { " — \($0.localizedDescription)" } ?? "")
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
    /// **Readable does not imply writable** — WebP reads in full and has no encoder at all, so
    /// every write to one fails. ``writeMetadata(_:clearing:url:)`` throws for exactly the files
    /// this refuses. Answered by extension rather than by opening the file, since it is asked per
    /// row and per field.
    public static func canWrite(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }

        return writableContentTypes.contains(type.identifier)
    }

    // MARK: - Keywords (dc:subject) -- unordered array

    /// Reads keywords (`dc:subject`) from an image file. An empty array covers both a file with
    /// no XMP and one with XMP but no keywords; neither is an error condition.
    public static func keywords(from url: URL) throws -> [String] {
        try readMetadata(from: url).keywords
    }

    /// Replaces the whole `dc:subject` keyword set, preserving all other existing metadata.
    public static func setKeywords(_ keywords: [String], url: URL) throws {
        try writeTags([.array(name: "subject", type: .arrayUnordered, value: keywords as CFArray)], url: url)
    }

    // MARK: - Full metadata read

    private static let iptcExtensionNamespace = "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/"
    private static let iptcExtensionPrefix = "Iptc4xmpCore"
    private static let xmpBasicNamespace = "http://ns.adobe.com/xap/1.0/"
    private static let xmpBasicPrefix = "xmp"
    private static let photoshopNamespace = "http://ns.adobe.com/photoshop/1.0/"
    private static let photoshopPrefix = "photoshop"

    /// Reads every field this package supports in one pass — one file open, one metadata copy.
    public static func readMetadata(from url: URL) throws -> XMPMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
            return XMPMetadata()
        }

        return XMPMetadata(
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
    /// the file. `[]`/`nil` means **leave the existing value alone**, not clear it — `clearing`
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

        try writeTags(writes, clearing: clearing, url: url)
    }

    // MARK: - Private

    /// Three write mechanisms, chosen per field:
    /// - `.array` hand-builds a `dc:`-namespaced tag, the only safe way found for `rdf:Bag`/
    ///   `rdf:Seq` fields.
    /// - `.scalarProperty` goes through the `CGImageMetadataSetValueMatchingImageProperty` bridge,
    ///   for any field with a classic-property crosswalk.
    /// - `.namespacedTag` builds a tag under a registered namespace, for fields with no crosswalk.
    ///   `isAlternateText` selects the `[x-default]`-indexed path `rdf:Alt` fields require.
    private enum MetadataWrite {
        case array(name: String, type: CGImageMetadataType, value: CFArray)
        case scalarProperty(dictionary: CFString, property: CFString, value: CFTypeRef)
        case namespacedTag(namespace: CFString, prefix: CFString, name: String, value: CFTypeRef, isAlternateText: Bool)
    }

    /// Handles both `rdf:Bag` and `rdf:Seq` array tags. `CGImageMetadataTagCopyValue` returns an
    /// array of *nested* `CGImageMetadataTag` objects rather than strings — a `value as? [String]`
    /// cast silently yields `[]` — and a single-element field can come back as a bare `CFString`.
    private static func arrayValue(_ metadata: CGImageMetadata, path: String) -> [String] {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
              let value = CGImageMetadataTagCopyValue(tag)
        else { return [] }

        if let tags = value as? [CGImageMetadataTag] {
            return tags.compactMap { CGImageMetadataTagCopyValue($0) as? String }
        }
        if let array = value as? [String] {
            return array
        }
        if let single = value as? String {
            return [single]
        }
        return []
    }

    /// Reads an `rdf:Alt` (language-alternative) field. Same nested-tag shape as the array fields,
    /// one entry per language; the first is `x-default`, the only language this package writes.
    private static func alternateTextValue(_ metadata: CGImageMetadata, path: String) -> String? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
              let value = CGImageMetadataTagCopyValue(tag)
        else { return nil }

        if let tags = value as? [CGImageMetadataTag] {
            return tags.compactMap { CGImageMetadataTagCopyValue($0) as? String }.first
        }
        return value as? String
    }

    /// Reads a plain (non-alternate-text) scalar string field. These come back as a bare `String`,
    /// not array-wrapped like the array or alternate-text fields.
    private static func scalarStringValue(_ metadata: CGImageMetadata, path: String) -> String? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) else { return nil }
        return CGImageMetadataTagCopyValue(tag) as? String
    }

    /// Reads a plain scalar integer field -- `xmp:Rating`.
    private static func scalarIntValue(_ metadata: CGImageMetadata, path: String) -> Int? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
              let value = CGImageMetadataTagCopyValue(tag)
        else { return nil }

        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    /// Builds a metadata object from `writes` and merges it onto the file, preserving the EXIF and
    /// XMP this package does not model. Writes to a temporary file in the same directory as `url`
    /// and atomically replaces the original, so a failure mid-write cannot corrupt it.
    private static func writeTags(
        _ writes: [MetadataWrite],
        clearing: Set<XMPField> = [],
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

        if clearing.isEmpty {
            metadata = CGImageMetadataCreateMutable()
            shouldMerge = true
        } else {
            if let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
               let mutableCopy = CGImageMetadataCreateMutableCopy(existing)
            {
                metadata = mutableCopy
            } else {
                // No XMP on the file at all — nothing to remove.
                metadata = CGImageMetadataCreateMutable()
            }

            shouldMerge = false

            for field in clearing {
                // Returns false when the tag was absent, the ordinary case for an empty field.
                CGImageMetadataRemoveTagWithPath(metadata, nil, field.path as CFString)
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

        var registeredPrefixes: Set<String> = []
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
