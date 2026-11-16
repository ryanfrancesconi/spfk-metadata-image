// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO

extension ImageXMP {
    /// Handles both `rdf:Bag` and `rdf:Seq` array tags. `CGImageMetadataTagCopyValue` returns an
    /// array of *nested* `CGImageMetadataTag` objects rather than strings - a `value as? [String]`
    /// cast silently yields `[]` - and a single-element field can come back as a bare `CFString`.
    static func arrayValue(_ metadata: CGImageMetadata, path: String) -> [String] {
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
    static func alternateTextValue(_ metadata: CGImageMetadata, path: String) -> String? {
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
    static func scalarStringValue(_ metadata: CGImageMetadata, path: String) -> String? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) else { return nil }
        return CGImageMetadataTagCopyValue(tag) as? String
    }

    /// Reads a plain scalar integer field -- `xmp:Rating`.
    static func scalarIntValue(_ metadata: CGImageMetadata, path: String) -> Int? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
              let value = CGImageMetadataTagCopyValue(tag)
        else { return nil }

        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

extension ImageXMP {
    /// One field's value, read by its shape.
    static func values(of field: XMPField, in metadata: CGImageMetadata) -> [String] {
        let path = field.path

        switch field.shape {
        case .bag, .seq:
            return arrayValue(metadata, path: path)
        case .langAlt:
            return alternateTextValue(metadata, path: path).map { [$0] } ?? []
        case .text, .struct:
            return scalarStringValue(metadata, path: path).map { [$0] } ?? []
        case .integer:
            return scalarIntValue(metadata, path: path).map { [String($0)] } ?? []
        case .bool:
            return boolValue(metadata, path: path).map { [$0 ? "True" : "False"] } ?? []
        }
    }

    /// Reads an XMP Boolean, which ImageIO may hand back as text or as a number.
    static func boolValue(_ metadata: CGImageMetadata, path: String) -> Bool? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
              let value = CGImageMetadataTagCopyValue(tag)
        else { return nil }

        if let string = value as? String {
            switch string.lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }
        return (value as? NSNumber)?.boolValue
    }
}
