// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

/// Field-keyed access to the same fourteen values the named properties expose.
///
/// Exists so a writer that addresses XMP generically -- by namespace and name, as the Adobe
/// toolkit does for video -- can map the whole set in one loop instead of restating a per-field
/// switch. A second switch is exactly how one writer ends up handling thirteen fields and the
/// other fourteen.
extension ImageXMPMetadata {
    /// This field's value as XMP holds it: zero values when absent, one for a scalar, many for an
    /// array. Empty means "no value", which a writer turns into a removal.
    public func values(for field: ImageXMPField) -> [String] {
        switch field {
        case .keywords: keywords
        case .creators: creators
        case .title: [title].compactMap(\.self)
        case .description: [description].compactMap(\.self)
        case .copyright: [copyright].compactMap(\.self)
        case .city: [city].compactMap(\.self)
        case .state: [state].compactMap(\.self)
        case .country: [country].compactMap(\.self)
        case .subLocation: [subLocation].compactMap(\.self)
        case .rating: [rating.map(String.init)].compactMap(\.self)
        case .label: [label].compactMap(\.self)
        case .labelColor: [labelColor].compactMap(\.self)
        case .accessibilityAltText: [accessibilityAltText].compactMap(\.self)
        case .accessibilityDescription: [accessibilityDescription].compactMap(\.self)
        }
    }

    /// Builds metadata from field-keyed values, the inverse of ``values(for:)``.
    ///
    /// A missing or empty entry leaves the field `nil`/empty, so a caller can pass only what it
    /// found without having to distinguish "absent" from "not looked for".
    public init(fieldValues: [ImageXMPField: [String]]) {
        func first(_ field: ImageXMPField) -> String? {
            guard let value = fieldValues[field]?.first, value.isNotEmpty else { return nil }
            return value
        }

        self.init(
            keywords: fieldValues[.keywords] ?? [],
            creators: fieldValues[.creators] ?? [],
            title: first(.title),
            description: first(.description),
            copyright: first(.copyright),
            city: first(.city),
            state: first(.state),
            country: first(.country),
            subLocation: first(.subLocation),
            rating: first(.rating).flatMap { Int($0) },
            label: first(.label),
            labelColor: first(.labelColor),
            accessibilityAltText: first(.accessibilityAltText),
            accessibilityDescription: first(.accessibilityDescription)
        )
    }
}
