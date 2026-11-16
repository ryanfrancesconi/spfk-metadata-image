// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

/// Keyed by each field's raw value: an array for a `bag`/`seq`, an `Int` for an `integer`, a
/// `String` otherwise. An absent scalar is omitted.
extension XMPMetadata: Codable {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(_ field: XMPField) { stringValue = field.rawValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.init()

        for field in XMPField.allCases {
            let key = Key(field)

            switch field.shape {
            case .bag, .seq:
                self[field] = try container.decodeIfPresent([String].self, forKey: key) ?? []
            case .integer:
                self[field] = try container.decodeIfPresent(Int.self, forKey: key).map { [String($0)] } ?? []
            case .text, .langAlt, .bool, .struct:
                self[field] = try container.decodeIfPresent(String.self, forKey: key).map { [$0] } ?? []
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)

        for field in XMPField.allCases {
            let key = Key(field)
            let values = self[field]

            switch field.shape {
            case .bag, .seq:
                try container.encode(values, forKey: key)
            case .integer:
                try container.encodeIfPresent(values.first.flatMap { Int($0) }, forKey: key)
            case .text, .langAlt, .bool, .struct:
                try container.encodeIfPresent(values.first, forKey: key)
            }
        }
    }
}
