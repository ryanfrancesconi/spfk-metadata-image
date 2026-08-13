// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

/// The descriptive XMP vocabulary -- Dublin Core / IPTC / IPTC Extension / XMP Basic fields --
/// carried by an image or a video alike. Distinct from `spfk-metadata-xmp`'s `XMPDynamicMedia`,
/// which models the technical, time-based half of XMP.
///
/// Format-neutral by design: `ImageXMP` reads and writes it through ImageIO, `VideoXMP` (in
/// `spfk-metadata-xmp`) through the Adobe toolkit, and both address the identical ``XMPField``
/// set — which is what stops a video and an image from supporting different fields. `nil` means
/// the field is absent from the file, distinct from an empty string or `0`.
public struct XMPMetadata: Hashable, Sendable {
    public var keywords: [String]
    public var creators: [String]
    public var title: String?
    public var description: String?
    public var copyright: String?
    public var city: String?
    public var state: String?
    public var country: String?

    /// A finer-grained place name than `city`/`state`/`country` — a neighborhood or a landmark.
    public var subLocation: String?

    /// 0-5.
    public var rating: Int?
    public var label: String?

    /// A hex swatch, e.g. `"#F37500"` — Lightroom's Custom Color label, which sits in the same
    /// picker as its five named ones. `label` still carries the user-facing name either way.
    public var labelColor: String?
    public var accessibilityAltText: String?
    public var accessibilityDescription: String?

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
