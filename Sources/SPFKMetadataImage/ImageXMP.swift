// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO
import SPFKBase
import UniformTypeIdentifiers

/// Reads and writes XMP metadata on image files via ImageIO's native `CGImageMetadata`/
/// `CGImageDestination` APIs -- not the Adobe XMP Toolkit (`spfk-metadata-xmp`).
///
/// This exists because the vendored Adobe SDK's HEIC format handler is broken in both
/// directions: verified directly (2026-07-24) against a real iPhone HEIC file with no
/// pre-existing XMP -- `spfk-metadata-xmp`'s `XMP.setArrayProperty` fails with "Cannot put XMP
/// into file", and even XMP written by ImageIO into that same HEIC can't be read back through
/// the Adobe SDK's parser ("Failed to find an XMP chunk"). ImageIO handles this correctly and
/// uniformly across JPEG/HEIC/PNG/TIFF/DNG -- one code path, no vendored binary dependency.
/// `spfk-metadata-xmp` remains the right tool for formats its Adobe SDK format handlers do
/// support well (JPEG, TIFF-based RAW, and its original audio/video Dynamic Media use case).
///
/// **Array-typed (`rdf:Bag`/`rdf:Seq`) fields**: keywords (`dc:subject`) and creators
/// (`dc:creator`). **Language-alternative (`rdf:Alt`) fields**: title (`dc:title`), description
/// (`dc:description`), copyright (`dc:rights`), and the accessibility fields
/// (`Iptc4xmpCore:AltTextAccessibility`/`ExtDescrAccessibility`). **Plain scalar fields**: city/
/// state/country (`photoshop:City`/`State`/`Country`), rating (`xmp:Rating`), label
/// (`xmp:Label`), and label color (`photoshop:LabelColor`).
///
/// The `rdf:Alt` fields have a real crash history -- **never build an `rdf:Alt` tag with a bare
/// path.** Original investigation (2026-07-24): writing `dc:rights` via
/// `CGImageMetadataTagCreate(..., .alternateText, ...)` + `CGImageMetadataSetTagWithPath(...,
/// "dc:rights", ...)` (a bare path, no language index) **crashed the process** with
/// `-[Swift.__StringStorage count]: unrecognized selector sent to instance` on a real, untouched
/// iPhone HEIC file, despite passing reliably against synthetic JPEG fixtures every time --
/// `dc:title`/`dc:description` round-tripped unreliably the same way (correct in one specific
/// field combination tested, `nil` in every other).
///
/// **Root cause found (2026-07-27), and it's the bare path, not the `.alternateText` type or
/// hand-building in general:** ImageIO's `CGImageMetadataCopyTagWithPath` documentation
/// describes alternate-text array elements as accessed by RFC 3066 language code in brackets --
/// e.g. `"dc:description[x-default]"` -- the same way array elements use `[0]`. Setting a tag at
/// the *bare* path (`"dc:rights"`) instead of the language-indexed path
/// (`"dc:rights[x-default]"`) is what crashed; setting the identical `.default`-type tag at the
/// `[x-default]`-indexed path works correctly and safely, verified (2026-07-27) against the
/// exact same real HEIC that reproduced the original crash, for `dc:rights` *and* a brand-new
/// custom namespace (`Iptc4xmpCore:AltTextAccessibility`) with no classic-property crosswalk at
/// all -- both wrote, read back correctly, and preserved existing `dc:subject`/`dc:creator`.
///
/// Two safe write mechanisms follow from this, used depending on whether ImageIO recognizes a
/// classic-property crosswalk for the field:
/// - **Classic-property bridge** (`CGImageMetadataSetValueMatchingImageProperty`) for fields
///   ImageIO's `CGImageProperties.h` exposes a classic IPTC dictionary key for: title,
///   description, copyright (`kCGImagePropertyIPTCObjectName`/`CaptionAbstract`/
///   `CopyrightNotice`), city/state/country (`kCGImagePropertyIPTCCity`/`ProvinceState`/
///   `CountryPrimaryLocationName`), and rating (`kCGImagePropertyIPTCStarRating`). This bridge
///   builds whichever internal structure is correct (`rdf:Alt` or a plain scalar) automatically.
/// - **`[x-default]`-indexed path** for fields with no classic-property crosswalk at all --
///   `Iptc4xmpCore:AltTextAccessibility`/`ExtDescrAccessibility` (IPTC Extension fields newer
///   than ImageIO's classic-dictionary bridge, confirmed absent from `CGImageProperties.h` by
///   direct header inspection) and `xmp:Label` (a plain scalar, no `rdf:Alt` involved, so no
///   indexed path needed there -- just a namespaced tag at a bare path, which is safe for
///   non-alternate-text fields; the crash was specific to bare-path *alternate-text* tags).
///
/// Don't add another `rdf:Alt` field via a bare-path `CGImageMetadataSetTagWithPath` call --
/// always use the bridge if a classic-property crosswalk exists, or the `[x-default]`-indexed
/// path if it doesn't.
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
    /// **Readable does not imply writable.** WebP is the case users meet: it reads in full —
    /// EXIF, XMP rating, IPTC keywords, GPS — and has no encoder here at all, so every write to
    /// one fails. ``writeMetadata(_:clearing:url:)`` throws for exactly the files this refuses,
    /// and asking first is what keeps work from being queued that can never be saved.
    ///
    /// By extension rather than by opening the file: this is asked per row and per field.
    public static func canWrite(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }

        return writableContentTypes.contains(type.identifier)
    }

    // MARK: - Keywords (dc:subject) -- unordered array

    /// Reads keywords (`dc:subject`) from an image file. Returns an empty array both when the
    /// file has no XMP at all and when it has XMP but no keywords -- these aren't distinguished
    /// since neither is an error condition for a caller that just wants "what keywords does
    /// this file have."
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

    /// Reads every field this package supports in one pass (one file open, one metadata copy).
    /// See this type's doc comment for the write-side story behind each field's mechanism.
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
    /// the file. `[]`/`nil` means **"leave the existing value alone"**, not "clear it" -- use
    /// `clearing` for that.
    ///
    /// The two are separate because `XMPMetadata` cannot express the difference: an editor
    /// needs "the user did not touch this" and "the user emptied this" to mean different things
    /// the moment a text field is editable. A sentinel value would collide with real content, and
    /// a replace-everything write would destroy the fields this package does not model.
    ///
    /// - Parameter clearing: fields to remove from the file. A field listed here is **not**
    ///   written even if `metadata` carries a value for it -- clearing wins, so a caller cannot
    ///   accidentally ask for both.
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

    /// Three write mechanisms, chosen per-field -- see this file's doc comment for why each one
    /// exists and the crash history behind the distinction:
    /// - `.array` builds a `dc:`-namespaced tag by hand, the only safe way found for
    ///   `rdf:Bag`/`rdf:Seq` fields (keywords/creators).
    /// - `.scalarProperty` goes through the `CGImageMetadataSetValueMatchingImageProperty`
    ///   bridge, for any field with a classic-property crosswalk (title/description/copyright/
    ///   city/state/country/rating).
    /// - `.namespacedTag` builds a tag directly under a registered namespace, for fields with no
    ///   classic-property crosswalk at all (label, label color, accessibility alt-text/description).
    ///   `isAlternateText: true` sets it at the `[x-default]`-indexed path (required for
    ///   `rdf:Alt` fields, verified crash-safe); `false` sets it at a bare path (fine for plain
    ///   scalars, since the crash was specific to bare-path *alternate-text* tags).
    private enum MetadataWrite {
        case array(name: String, type: CGImageMetadataType, value: CFArray)
        case scalarProperty(dictionary: CFString, property: CFString, value: CFTypeRef)
        case namespacedTag(namespace: CFString, prefix: CFString, name: String, value: CFTypeRef, isAlternateText: Bool)
    }

    /// Handles both `rdf:Bag` (unordered, e.g. `dc:subject`) and `rdf:Seq` (ordered, e.g.
    /// `dc:creator`) array tags -- both come back from `CGImageMetadataTagCopyValue` as an
    /// array of *nested* `CGImageMetadataTag` objects, not plain strings directly (verified via
    /// a standalone instrumented script -- a naive `value as? [String]` cast silently fails and
    /// always returns `[]`). A single-element file may come back as a bare `CFString` rather
    /// than a one-element array, so that shape is handled too.
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

    /// Reads an `rdf:Alt` (language-alternative) field -- `dc:title`/`dc:description`. Comes
    /// back from `CGImageMetadataTagCopyValue` the same shape as the array fields (an array of
    /// nested `CGImageMetadataTag` objects, one per language, verified via this package's real-
    /// file spike), so the first entry (the `x-default` language, the only one this package
    /// ever writes) is what a caller wants.
    private static func alternateTextValue(_ metadata: CGImageMetadata, path: String) -> String? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
              let value = CGImageMetadataTagCopyValue(tag)
        else { return nil }

        if let tags = value as? [CGImageMetadataTag] {
            return tags.compactMap { CGImageMetadataTagCopyValue($0) as? String }.first
        }
        return value as? String
    }

    /// Reads a plain (non-alternate-text) scalar string field -- `photoshop:City`/`State`/
    /// `Country`, `xmp:Label`. These come back as a bare `String`, not array-wrapped like the
    /// array or alternate-text fields.
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

    /// Shared write path for `setKeywords`/`writeMetadata`: builds a mutable metadata object
    /// from `writes`, then merges it onto the file via `kCGImageDestinationMergeMetadata` --
    /// preserving all other existing metadata (EXIF, other XMP fields), not a wholesale
    /// replacement. Writes to a temporary file in the same directory as `url`, then atomically
    /// replaces the original via `FileManager.replaceItemAt` -- never partially overwrites the
    /// original in place, so a failure or crash mid-write can't corrupt it.
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

        // Removal needs a fundamentally different write mode, not just an extra call. The
        // additive path below builds an *empty* metadata object and hands it to ImageIO with
        // `kCGImageDestinationMergeMetadata`, which only ever adds -- there is nothing present in
        // it to remove, and merging cannot express absence. So clearing works against a mutable
        // copy of what the file already has, removes from that, and writes it back with merging
        // off, replacing the metadata wholesale. Since the object started as a full copy of the
        // file's own metadata, everything not explicitly removed survives.
        //
        // The additive path is kept for the no-clearing case rather than routing everything
        // through the copy: it is the path with the crash history documented on this type and the
        // existing round-trip coverage, and there is no reason to disturb it.
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
                // No XMP on the file at all: nothing to remove, and an empty object replacing
                // nothing is equivalent to the additive path.
                metadata = CGImageMetadataCreateMutable()
            }

            shouldMerge = false

            for field in clearing {
                // Returns false when the tag was not present, which is the ordinary case of
                // clearing an already-empty field -- not an error.
                CGImageMetadataRemoveTagWithPath(metadata, nil, field.path as CFString)
            }
        }

        // Namespace registration is only needed for the manual `CGImageMetadataTagCreate` path
        // `.array`/`.namespacedTag` use -- `.scalarProperty`'s bridge API already knows the
        // namespace for any classic property it recognizes. Each unique (namespace, prefix) is
        // only registered once, even if used by multiple `.namespacedTag` writes.
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
