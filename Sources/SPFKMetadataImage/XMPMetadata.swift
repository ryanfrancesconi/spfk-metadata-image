// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

/// The descriptive XMP vocabulary -- Dublin Core / IPTC / IPTC Extension / XMP Basic fields --
/// carried by an image or a video alike. Distinct from `spfk-metadata-xmp`'s `XMPDynamicMedia`,
/// which models the technical, time-based half of XMP.
///
/// Format-neutral: `ImageXMP` reads and writes it through ImageIO, `VideoXMP` (in
/// `spfk-metadata-xmp`) through the Adobe toolkit, and both address the identical ``XMPField``
/// set. Stored by field, as XMP holds it; `nil` means the field is absent from the file, distinct
/// from an empty string or `0`.
public struct XMPMetadata: Hashable, Sendable {
    private var storage: [XMPField: [String]] = [:]

    public init() {}

    /// This field's value as XMP holds it: empty when absent, one entry for a scalar, many for an
    /// array. Setting `[]` removes the field.
    public subscript(field: XMPField) -> [String] {
        get { storage[field] ?? [] }
        set { storage[field] = newValue.isEmpty ? nil : newValue }
    }

    // MARK: - Named fields

    public var keywords: [String] {
        get { self[.keywords] }
        set { self[.keywords] = newValue }
    }

    public var creators: [String] {
        get { self[.creators] }
        set { self[.creators] = newValue }
    }

    public var title: String? {
        get { scalar(.title) }
        set { setScalar(newValue, .title) }
    }

    public var description: String? {
        get { scalar(.description) }
        set { setScalar(newValue, .description) }
    }

    public var copyright: String? {
        get { scalar(.copyright) }
        set { setScalar(newValue, .copyright) }
    }

    public var city: String? {
        get { scalar(.city) }
        set { setScalar(newValue, .city) }
    }

    public var state: String? {
        get { scalar(.state) }
        set { setScalar(newValue, .state) }
    }

    public var country: String? {
        get { scalar(.country) }
        set { setScalar(newValue, .country) }
    }

    /// A finer-grained place name than `city`/`state`/`country` - a neighborhood or a landmark.
    public var subLocation: String? {
        get { scalar(.subLocation) }
        set { setScalar(newValue, .subLocation) }
    }

    /// 0-5.
    public var rating: Int? {
        get { scalar(.rating).flatMap { Int($0) } }
        set { setScalar(newValue.map(String.init), .rating) }
    }

    public var label: String? {
        get { scalar(.label) }
        set { setScalar(newValue, .label) }
    }

    /// A hex swatch, e.g. `"#F37500"` - Lightroom's Custom Color label, which sits in the same
    /// picker as its five named ones. `label` still carries the user-facing name either way.
    public var labelColor: String? {
        get { scalar(.labelColor) }
        set { setScalar(newValue, .labelColor) }
    }

    public var accessibilityAltText: String? {
        get { scalar(.accessibilityAltText) }
        set { setScalar(newValue, .accessibilityAltText) }
    }

    public var accessibilityDescription: String? {
        get { scalar(.accessibilityDescription) }
        set { setScalar(newValue, .accessibilityDescription) }
    }

    private func scalar(_ field: XMPField) -> String? {
        storage[field]?.first
    }

    private mutating func setScalar(_ value: String?, _ field: XMPField) {
        storage[field] = value.map { [$0] }
    }

    public init(
        keywords: [String] = [],
        creators: [String] = [],
        title: String? = nil,
        description: String? = nil,
        copyright: String? = nil,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        subLocation: String? = nil,
        rating: Int? = nil,
        label: String? = nil,
        labelColor: String? = nil,
        accessibilityAltText: String? = nil,
        accessibilityDescription: String? = nil
    ) {
        self.keywords = keywords
        self.creators = creators
        self.title = title
        self.description = description
        self.copyright = copyright
        self.city = city
        self.state = state
        self.country = country
        self.subLocation = subLocation
        self.rating = rating
        self.label = label
        self.labelColor = labelColor
        self.accessibilityAltText = accessibilityAltText
        self.accessibilityDescription = accessibilityDescription
    }
}
