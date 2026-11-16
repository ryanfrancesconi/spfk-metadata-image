// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

extension XMPMetadata {
    /// This field's value as XMP holds it; the same as `self[field]`.
    public func values(for field: XMPField) -> [String] {
        self[field]
    }

    /// Builds metadata from field-keyed values, keeping only what each field's shape can hold.
    ///
    /// An empty scalar, and an `integer` field that does not parse, read as absent. A scalar keeps
    /// its first value only.
    public init(fieldValues: [XMPField: [String]]) {
        self.init()

        for (field, values) in fieldValues {
            switch field.shape {
            case .bag, .seq:
                self[field] = values
            case .integer:
                self[field] = values.first.flatMap { Int($0) }.map { [String($0)] } ?? []
            case .text, .langAlt, .bool, .struct:
                self[field] = values.first.flatMap { $0.isEmpty ? nil : [$0] } ?? []
            }
        }
    }
}
