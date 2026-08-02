// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

/// The descriptive XMP vocabulary -- Dublin Core / IPTC / IPTC Extension / XMP Basic fields --
/// carried by an image or a video alike.
///
/// Format-neutral by design: `ImageXMP` reads and writes it through ImageIO, `VideoXMP` (in
/// `spfk-metadata-xmp`) through the Adobe toolkit, and both address the identical ``XMPField``
/// set. That shared set is what stops a video and an image from supporting different fields --
/// the drift the workspace CLAUDE.md warns about for format-capability lists. It lives in this
/// package rather than `spfk-metadata-xmp` only because that package already depends on this one.
///
/// Distinct from `spfk-metadata-xmp`'s `XMPDynamicMedia`, which models the technical, time-based
/// half of XMP (markers, timecode, tracks).
///
/// - `keywords`/`creators` -- array-typed (`rdf:Bag`/`rdf:Seq`).
/// - `title`/`description`/`copyright` -- language-alternative (`rdf:Alt`, always written/read
///   as the `x-default` language), backed by a classic-property crosswalk ImageIO recognizes.
/// - `city`/`state`/`country` -- plain scalar strings (`photoshop:City`/`State`/`Country`), also
///   backed by a classic-property crosswalk.
/// - `subLocation` -- plain scalar string, a finer-grained place name than `city`/`state`/
///   `country` (e.g. a neighborhood or landmark). Backed by the classic IPTC `SubLocation`
///   crosswalk (`kCGImagePropertyIPTCSubLocation`), verified (2026-07-27) to read/write at XMP
///   path `Iptc4xmpCore:Location` -- not `photoshop:Location`, the namespace `city`/`state`/
///   `country` use, despite going through the same classic-property bridge mechanism.
/// - `rating` -- plain scalar number (`xmp:Rating`, 0-5), backed by a classic-property crosswalk
///   (`kCGImagePropertyIPTCStarRating`).
/// - `label` -- plain scalar string (`xmp:Label`) -- no classic-property crosswalk exists for
///   this field, so it's written directly under the `xmp:` namespace.
/// - `labelColor` -- plain scalar string (`photoshop:LabelColor`, a hex swatch e.g. `"#F37500"`)
///   -- Lightroom's "Custom Color" label option, which sits in the same picker as its five preset
///   named labels (Red/Yellow/Green/Blue/Purple) but additionally carries an arbitrary swatch;
///   `label` still carries the user-facing name either way. No classic-property crosswalk exists,
///   written directly under the `photoshop:` namespace like `label` is under `xmp:`.
/// - `accessibilityAltText`/`accessibilityDescription` -- language-alternative
///   (`Iptc4xmpCore:AltTextAccessibility`/`ExtDescrAccessibility`) -- no classic-property
///   crosswalk exists for these either (they're IPTC Extension fields newer than ImageIO's
///   classic-dictionary bridge), written directly under a registered `Iptc4xmpCore:` namespace
///   using the `[x-default]` language-indexed path. See `ImageXMP`'s doc comment for the crash
///   history behind why that indexed path (not a bare path) is required for any `rdf:Alt` field.
///
/// `nil` for any optional field means the field isn't present on the file, distinct from an
/// empty string or `0`.
public struct XMPMetadata: Hashable, Sendable {
    public var keywords: [String]
    public var creators: [String]
    public var title: String?
    public var description: String?
    public var copyright: String?
    public var city: String?
    public var state: String?
    public var country: String?
    public var subLocation: String?
    public var rating: Int?
    public var label: String?
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
