// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

/// Dublin Core / IPTC / IPTC Extension / XMP Basic fields `ImageXMP` reads/writes.
///
/// - `keywords`/`creators` -- array-typed (`rdf:Bag`/`rdf:Seq`).
/// - `title`/`description`/`copyright` -- language-alternative (`rdf:Alt`, always written/read
///   as the `x-default` language), backed by a classic-property crosswalk ImageIO recognizes.
/// - `city`/`state`/`country` -- plain scalar strings (`photoshop:City`/`State`/`Country`), also
///   backed by a classic-property crosswalk.
/// - `rating` -- plain scalar number (`xmp:Rating`, 0-5), backed by a classic-property crosswalk
///   (`kCGImagePropertyIPTCStarRating`).
/// - `label` -- plain scalar string (`xmp:Label`) -- no classic-property crosswalk exists for
///   this field, so it's written directly under the `xmp:` namespace.
/// - `accessibilityAltText`/`accessibilityDescription` -- language-alternative
///   (`Iptc4xmpCore:AltTextAccessibility`/`ExtDescrAccessibility`) -- no classic-property
///   crosswalk exists for these either (they're IPTC Extension fields newer than ImageIO's
///   classic-dictionary bridge), written directly under a registered `Iptc4xmpCore:` namespace
///   using the `[x-default]` language-indexed path. See `ImageXMP`'s doc comment for the crash
///   history behind why that indexed path (not a bare path) is required for any `rdf:Alt` field.
///
/// `nil` for any optional field means the field isn't present on the file, distinct from an
/// empty string or `0`.
public struct ImageXMPMetadata: Hashable, Sendable {
    public var keywords: [String]
    public var creators: [String]
    public var title: String?
    public var description: String?
    public var copyright: String?
    public var city: String?
    public var state: String?
    public var country: String?
    public var rating: Int?
    public var label: String?
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
        rating: Int? = nil,
        label: String? = nil,
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
        self.rating = rating
        self.label = label
        self.accessibilityAltText = accessibilityAltText
        self.accessibilityDescription = accessibilityDescription
    }
}
