// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO
import SPFKBase

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
/// (`dc:creator`). **Language-alternative (`rdf:Alt`) fields**: title (`dc:title`) and
/// description (`dc:description`).
///
/// The `rdf:Alt` fields have a real crash history, so their write path is deliberately
/// different from the array fields' -- **never build an `rdf:Alt` tag by hand.** Original
/// investigation (2026-07-24): writing `dc:rights` via `CGImageMetadataTagCreate(...,
/// .alternateText, ...)` + `CGImageMetadataSetTagWithPath` **crashed the process** with
/// `-[Swift.__StringStorage count]: unrecognized selector sent to instance` on a real, untouched
/// iPhone HEIC file, despite passing reliably against synthetic JPEG fixtures every time --
/// `dc:title`/`dc:description` round-tripped unreliably the same way (correct in one specific
/// field combination tested, `nil` in every other). Root cause traced (2026-07-27) to that
/// specific call sequence, not to `rdf:Alt` fields being unsafe in general: switching to the
/// higher-level `CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyIPTC
/// Dictionary, kCGImagePropertyIPTCObjectName/CaptionAbstract, value)` bridge -- which builds
/// the same `rdf:Alt`/`xml:lang=x-default` structure internally -- verified crash-free and
/// round-trip-correct for title, description, *and* `dc:rights` against a real, metadata-rich
/// iPhone HEIC (existing `dc:subject`/`dc:creator`/GPS/EXIF/MakerApple all preserved across the
/// write). `dc:rights` isn't exposed in `ImageXMPMetadata` since nothing needs it yet, but the
/// finding confirms the bridge API is the safe entry point for this whole field class -- don't
/// add another `rdf:Alt` field via direct `CGImageMetadataTagCreate(..., .alternateText, ...)`
/// construction; go through the property bridge instead.
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

    /// Reads the Dublin Core fields this package supports in one pass (one file open, one
    /// metadata copy) -- keywords (`dc:subject`), creators (`dc:creator`), title (`dc:title`),
    /// and description (`dc:description`).
    public static func readMetadata(from url: URL) throws -> ImageXMPMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
            return ImageXMPMetadata()
        }

        return ImageXMPMetadata(
            keywords: arrayValue(metadata, path: "dc:subject"),
            creators: arrayValue(metadata, path: "dc:creator"),
            title: alternateTextValue(metadata, path: "dc:title"),
            description: alternateTextValue(metadata, path: "dc:description")
        )
    }

    /// Writes every non-empty/non-nil field in `metadata`, preserving everything else already on
    /// the file (`[]`/`nil` means "leave the existing value alone," not "clear it" -- there's no
    /// clear-a-field operation yet since nothing in TorchTag calls this today; editing is
    /// deferred until the Content store exists, see `torchtag-xmp-keywords-plan.md`). This
    /// exists for round-trip testing and package completeness, matching how `setKeywords`
    /// existed before any UI used it.
    public static func writeMetadata(_ metadata: ImageXMPMetadata, url: URL) throws {
        var writes: [MetadataWrite] = []
        if metadata.keywords.isNotEmpty {
            writes.append(.array(name: "subject", type: .arrayUnordered, value: metadata.keywords as CFArray))
        }
        if metadata.creators.isNotEmpty {
            writes.append(.array(name: "creator", type: .arrayOrdered, value: metadata.creators as CFArray))
        }
        if let title = metadata.title {
            writes.append(.scalarProperty(
                dictionary: kCGImagePropertyIPTCDictionary, property: kCGImagePropertyIPTCObjectName, value: title as CFString
            ))
        }
        if let description = metadata.description {
            writes.append(.scalarProperty(
                dictionary: kCGImagePropertyIPTCDictionary, property: kCGImagePropertyIPTCCaptionAbstract, value: description as CFString
            ))
        }

        try writeTags(writes, url: url)
    }

    // MARK: - Private

    /// Two different write mechanisms, not one -- `.array` builds a custom-namespaced tag by
    /// hand (`CGImageMetadataTagCreate` + `CGImageMetadataSetTagWithPath`), the only safe way
    /// found for `rdf:Bag`/`rdf:Seq` fields. `.scalarProperty` goes through the higher-level
    /// `CGImageMetadataSetValueMatchingImageProperty` bridge instead -- the only verified-safe
    /// way to write `rdf:Alt` fields, see this file's doc comment for the crash history.
    private enum MetadataWrite {
        case array(name: String, type: CGImageMetadataType, value: CFArray)
        case scalarProperty(dictionary: CFString, property: CFString, value: CFString)
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

    /// Shared write path for `setKeywords`/`writeMetadata`: builds a mutable metadata object
    /// from `writes`, then merges it onto the file via `kCGImageDestinationMergeMetadata` --
    /// preserving all other existing metadata (EXIF, other XMP fields), not a wholesale
    /// replacement. Writes to a temporary file in the same directory as `url`, then atomically
    /// replaces the original via `FileManager.replaceItemAt` -- never partially overwrites the
    /// original in place, so a failure or crash mid-write can't corrupt it.
    private static func writeTags(_ writes: [MetadataWrite], url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let uti = CGImageSourceGetType(source) else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        let metadata = CGImageMetadataCreateMutable()

        // Namespace registration is only needed for the manual `CGImageMetadataTagCreate` path
        // `.array` uses -- `.scalarProperty`'s bridge API already knows the `dc:` namespace.
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
            kCGImageDestinationMergeMetadata: true,
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

/// Dublin Core fields `ImageXMP` reads/writes -- `dc:subject`/`dc:creator` are array-typed
/// (`rdf:Bag`/`rdf:Seq`); `title`/`description` are language-alternative (`rdf:Alt`, always
/// written/read as the `x-default` language). `nil` title/description means the field isn't
/// present on the file, distinct from an empty string. See `ImageXMP`'s doc comment for the
/// crash history behind why `rdf:Alt` fields go through a different write path than the array
/// ones, and why `dc:rights` still isn't exposed here despite being verified safe too.
public struct ImageXMPMetadata: Hashable, Sendable {
    public var keywords: [String]
    public var creators: [String]
    public var title: String?
    public var description: String?

    public init(
        keywords: [String] = [],
        creators: [String] = [],
        title: String? = nil,
        description: String? = nil
    ) {
        self.keywords = keywords
        self.creators = creators
        self.title = title
        self.description = description
    }
}
