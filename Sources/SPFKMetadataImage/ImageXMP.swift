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
/// **Only array-typed (`rdf:Bag`/`rdf:Seq`) fields are supported** -- keywords (`dc:subject`)
/// and creators (`dc:creator`). Language-alternative (`rdf:Alt`) fields -- `dc:title`,
/// `dc:description`, `dc:rights` -- are deliberately not exposed here: investigated (2026-07-24)
/// and found unsafe. `dc:title`/`dc:description` round-tripped unreliably (correct in one
/// specific field combination tested, `nil` in every other). `dc:rights` went further --
/// writing it alone via `CGImageMetadataTagCreate(..., .alternateText, ...)` **crashed the
/// process** with `-[Swift.__StringStorage count]: unrecognized selector sent to instance` on a
/// real, untouched iPhone HEIC file, despite passing reliably against simple synthetic JPEG
/// test fixtures every time -- confirming the risk is specific to richer, real-world files, not
/// something the synthetic-fixture test suite alone would have caught. Every array-typed field
/// tested has been reliable and crash-free across both synthetic and real files; every
/// alternate-text field tested has not. Don't add another `.alternateText` field here without
/// new evidence this is fixed.
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
        try writeTags([Tag(name: "subject", type: .arrayUnordered, value: keywords as CFArray)], url: url)
    }

    // MARK: - Full metadata read

    /// Reads the array-typed Dublin Core fields this package supports in one pass (one file
    /// open, one metadata copy) -- keywords (`dc:subject`) and creators (`dc:creator`). See this
    /// type's doc comment for why language-alternative fields (title/description/rights) aren't
    /// here.
    public static func readMetadata(from url: URL) throws -> ImageXMPMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
            return ImageXMPMetadata()
        }

        return ImageXMPMetadata(
            keywords: arrayValue(metadata, path: "dc:subject"),
            creators: arrayValue(metadata, path: "dc:creator")
        )
    }

    /// Writes every non-empty field in `metadata`, preserving everything else already on the
    /// file (`[]` means "leave the existing value alone," not "clear it" -- there's no
    /// clear-a-field operation yet since nothing in TorchTag calls this today; editing is
    /// deferred until the Content store exists, see `torchtag-xmp-keywords-plan.md`). This
    /// exists for round-trip testing and package completeness, matching how `setKeywords`
    /// existed before any UI used it.
    public static func writeMetadata(_ metadata: ImageXMPMetadata, url: URL) throws {
        var tags: [Tag] = []
        if metadata.keywords.isNotEmpty {
            tags.append(Tag(name: "subject", type: .arrayUnordered, value: metadata.keywords as CFArray))
        }
        if metadata.creators.isNotEmpty {
            tags.append(Tag(name: "creator", type: .arrayOrdered, value: metadata.creators as CFArray))
        }

        try writeTags(tags, url: url)
    }

    // MARK: - Private

    private struct Tag {
        let name: String
        let type: CGImageMetadataType
        let value: CFTypeRef
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

    /// Shared write path for `setKeywords`/`writeMetadata`: builds a mutable metadata object
    /// with `tags` (all in the `dc:` namespace), then merges it onto the file via
    /// `kCGImageDestinationMergeMetadata` -- preserving all other existing metadata (EXIF,
    /// other XMP fields), not a wholesale replacement. Writes to a temporary file in the same
    /// directory as `url`, then atomically replaces the original via `FileManager.
    /// replaceItemAt` -- never partially overwrites the original in place, so a failure or
    /// crash mid-write can't corrupt it.
    private static func writeTags(_ tags: [Tag], url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let uti = CGImageSourceGetType(source) else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        let metadata = CGImageMetadataCreateMutable()

        var registrationError: Unmanaged<CFError>?
        guard CGImageMetadataRegisterNamespaceForPrefix(
            metadata, dublinCoreNamespace as CFString, dublinCorePrefix as CFString, &registrationError
        ) else {
            throw ImageXMPError.writeFailed(url, underlying: registrationError?.takeUnretainedValue())
        }

        for tag in tags {
            guard let cgTag = CGImageMetadataTagCreate(
                dublinCoreNamespace as CFString, dublinCorePrefix as CFString, tag.name as CFString, tag.type, tag.value
            ) else {
                throw ImageXMPError.writeFailed(url, underlying: nil)
            }

            guard CGImageMetadataSetTagWithPath(metadata, nil, "dc:\(tag.name)" as CFString, cgTag) else {
                throw ImageXMPError.writeFailed(url, underlying: nil)
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

/// Array-typed Dublin Core fields `ImageXMP` reads/writes -- `dc:subject` is an unordered
/// `rdf:Bag`, `dc:creator` an ordered `rdf:Seq`. See `ImageXMP`'s doc comment for why
/// language-alternative fields (title/description/rights) are deliberately not here.
public struct ImageXMPMetadata: Hashable, Sendable {
    public var keywords: [String]
    public var creators: [String]

    public init(
        keywords: [String] = [],
        creators: [String] = []
    ) {
        self.keywords = keywords
        self.creators = creators
    }
}
