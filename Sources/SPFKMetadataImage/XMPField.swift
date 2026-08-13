// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

/// One writable field of ``XMPMetadata``, identified by its XMP path.
///
/// Lets a caller say "empty this field" as distinct from "leave it alone", which ``XMPMetadata``
/// alone cannot express — `nil`/`[]` there means "no new value". `path` must stay the path
/// `ImageXMP.readMetadata(from:)` reads from: a clear targeting a different one looks exactly
/// like the clear silently not working.
public enum XMPField: String, Sendable, CaseIterable {
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

    /// The XMP namespace URI this field's property lives in.
    ///
    /// Alongside `path` because the two writers need the same vocabulary in different shapes:
    /// ImageIO addresses a property by prefixed path, the Adobe toolkit by namespace URI and
    /// local name.
    public var namespace: String {
        switch self {
        case .keywords, .creators, .title, .description, .copyright:
            "http://purl.org/dc/elements/1.1/"
        case .city, .state, .country, .labelColor:
            "http://ns.adobe.com/photoshop/1.0/"
        case .rating, .label:
            "http://ns.adobe.com/xap/1.0/"
        case .subLocation, .accessibilityAltText, .accessibilityDescription:
            "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/"
        }
    }

    /// The property's local name, i.e. `path` without its namespace prefix.
    public var localName: String {
        guard let separator = path.firstIndex(of: ":") else { return path }
        return String(path[path.index(after: separator)...])
    }

    /// Whether the property is an `rdf:Bag`/`rdf:Seq` holding several values rather than one.
    public var isArray: Bool {
        switch self {
        case .keywords, .creators: true
        default: false
        }
    }

    /// The XMP path this field lives at.
    ///
    /// Alternate-text fields are given as the bare path deliberately: removal takes the container
    /// rather than one language entry, so clearing drops every language instead of leaving an
    /// `rdf:Alt` holding ones the user cannot see. Writing them still uses the `[x-default]`-
    /// indexed path — see ``ImageXMP``.
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
        // `Iptc4xmpCore:`, not the `photoshop:` namespace the other place fields use, despite
        // going through the same classic-property bridge.
        case .subLocation: "Iptc4xmpCore:Location"
        case .rating: "xmp:Rating"
        case .label: "xmp:Label"
        case .labelColor: "photoshop:LabelColor"
        case .accessibilityAltText: "Iptc4xmpCore:AltTextAccessibility"
        case .accessibilityDescription: "Iptc4xmpCore:ExtDescrAccessibility"
        }
    }
}
