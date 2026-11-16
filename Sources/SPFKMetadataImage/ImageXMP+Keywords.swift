// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

extension ImageXMP {
    // MARK: - Keywords (dc:subject) -- unordered array

    /// Reads keywords (`dc:subject`) from an image file. An empty array covers both a file with
    /// no XMP and one with XMP but no keywords; neither is an error condition.
    public static func keywords(from url: URL) throws -> [String] {
        try readMetadata(from: url).keywords
    }

    /// Replaces the whole `dc:subject` keyword set, preserving all other existing metadata.
    public static func setKeywords(_ keywords: [String], url: URL) throws {
        let field = XMPField.keywords

        try writeTags([.namespacedTag(
            namespace: field.namespace as CFString, prefix: field.prefix as CFString,
            name: field.localName, value: keywords as CFArray, form: .array(.arrayUnordered)
        )], url: url)
    }
}
