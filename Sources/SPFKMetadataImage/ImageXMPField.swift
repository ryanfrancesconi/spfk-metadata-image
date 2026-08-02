// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

/// One writable field of ``ImageXMPMetadata``, identified by its XMP path.
///
/// Exists so a caller can say "empty this field" as distinct from "leave it alone", which
/// ``ImageXMPMetadata`` alone cannot express: `nil`/`[]` there means "no new value", and an editor
/// needs both meanings the moment a user can clear a text field.
///
/// `path` is the same path the corresponding read in `ImageXMP.readMetadata(from:)` uses -- kept
/// alongside the case so the two cannot drift, since a clear that targets a different path than
/// the read looks exactly like the clear silently not working.
public enum ImageXMPField: String, Sendable, CaseIterable {
    case keywords
    case creators
    case title
    case description
    case copyright
    case city
    case state
    case country
    case subLocation
    case rating
    case label
    case labelColor
    case accessibilityAltText
    case accessibilityDescription

    /// The XMP path this field lives at.
    ///
    /// Alternate-text fields (`dc:title`, `dc:description`, `dc:rights`, and the two
    /// accessibility fields) are given as the bare path here deliberately: removal takes the
    /// container, not one language entry, so clearing drops every language rather than leaving an
    /// `rdf:Alt` holding languages the user cannot see or edit. Writing those fields still uses
    /// the `[x-default]`-indexed path -- see `ImageXMP`'s doc comment for the crash history behind
    /// that distinction.
    public var path: String {
        switch self {
        case .keywords: "dc:subject"
        case .creators: "dc:creator"
        case .title: "dc:title"
        case .description: "dc:description"
        case .copyright: "dc:rights"
        case .city: "photoshop:City"
        case .state: "photoshop:State"
        case .country: "photoshop:Country"
        case .subLocation: "Iptc4xmpCore:Location"
        case .rating: "xmp:Rating"
        case .label: "xmp:Label"
        case .labelColor: "photoshop:LabelColor"
        case .accessibilityAltText: "Iptc4xmpCore:AltTextAccessibility"
        case .accessibilityDescription: "Iptc4xmpCore:ExtDescrAccessibility"
        }
    }
}
