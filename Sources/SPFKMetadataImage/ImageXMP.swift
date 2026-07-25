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

    /// Reads keywords (`dc:subject`) from an image file. Returns an empty array both when the
    /// file has no XMP at all and when it has XMP but no keywords -- these aren't distinguished
    /// since neither is an error condition for a caller that just wants "what keywords does
    /// this file have."
    public static func keywords(from url: URL) throws -> [String] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
            return []
        }

        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "dc:subject" as CFString) else {
            return []
        }

        guard let value = CGImageMetadataTagCopyValue(tag) else {
            return []
        }

        // dc:subject is an rdf:Bag (unordered array). CGImageMetadataTagCopyValue on an
        // array-typed tag returns an array of *nested* CGImageMetadataTag objects (one per
        // element), not plain strings directly -- verified via a standalone instrumented
        // script after `value as? [String]` silently failed and always returned []. Each
        // element needs its own CGImageMetadataTagCopyValue call to get the actual string.
        // A single-keyword file may come back as a bare CFString rather than a one-element
        // array, so that shape is handled too.
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

    /// Replaces the whole `dc:subject` keyword set, preserving all other existing metadata
    /// (EXIF, other XMP fields, etc.) via `kCGImageDestinationMergeMetadata` -- this is a
    /// merge, not a wholesale metadata replacement.
    ///
    /// Writes to a temporary file in the same directory as `url`, then atomically replaces the
    /// original via `FileManager.replaceItemAt` -- never partially overwrites the original file
    /// in place, so a failure or crash mid-write can't corrupt it.
    public static func setKeywords(_ keywords: [String], url: URL) throws {
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

        guard let tag = CGImageMetadataTagCreate(
            dublinCoreNamespace as CFString, dublinCorePrefix as CFString, "subject" as CFString, .arrayUnordered, keywords as CFArray
        ) else {
            throw ImageXMPError.writeFailed(url, underlying: nil)
        }

        guard CGImageMetadataSetTagWithPath(metadata, nil, "dc:subject" as CFString, tag) else {
            throw ImageXMPError.writeFailed(url, underlying: nil)
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
