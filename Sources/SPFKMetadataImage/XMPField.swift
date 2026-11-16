// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO

/// One field of ``XMPMetadata``: where it lives in XMP, the shape of its value, and how ImageIO
/// writes it. Every reader, writer and store iterates `allCases`, so a field is added here and
/// nowhere else.
///
/// Also lets a caller say "empty this field" as distinct from "leave it alone", which
/// ``XMPMetadata`` alone cannot express.
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

    /// The XMP value type a field holds.
    public enum Shape: Hashable, Sendable {
        case text
        /// Text holding an integer, e.g. `xmp:Rating`.
        case integer
        /// `rdf:Alt`, read and written at `x-default` only.
        case langAlt
        /// `rdf:Bag`, unordered.
        case bag
        /// `rdf:Seq`, ordered.
        case seq
        /// `True`/`False`; absent is a third state.
        case bool
        /// One text child of a struct. Both names are local to the field's namespace.
        case `struct`(parent: String, child: String)
    }

    // MARK: - Table

    private struct Entry {
        let namespace: XMPNamespace
        let name: String
        let shape: Shape
        var crosswalk: CFString?
        var removesContainerBeforeWrite = false
    }

    private var entry: Entry {
        switch self {
        case .keywords: Entry(namespace: .dublinCore, name: "subject", shape: .bag)
        case .creators: Entry(namespace: .dublinCore, name: "creator", shape: .seq)
        case .title:
            Entry(namespace: .dublinCore, name: "title", shape: .langAlt,
                  crosswalk: kCGImagePropertyIPTCObjectName, removesContainerBeforeWrite: true)
        case .description:
            Entry(namespace: .dublinCore, name: "description", shape: .langAlt,
                  crosswalk: kCGImagePropertyIPTCCaptionAbstract, removesContainerBeforeWrite: true)
        case .copyright:
            Entry(namespace: .dublinCore, name: "rights", shape: .langAlt,
                  crosswalk: kCGImagePropertyIPTCCopyrightNotice, removesContainerBeforeWrite: true)
        case .city: Entry(namespace: .photoshop, name: "City", shape: .text, crosswalk: kCGImagePropertyIPTCCity)
        case .state: Entry(namespace: .photoshop, name: "State", shape: .text, crosswalk: kCGImagePropertyIPTCProvinceState)
        case .country:
            Entry(namespace: .photoshop, name: "Country", shape: .text, crosswalk: kCGImagePropertyIPTCCountryPrimaryLocationName)
        case .subLocation: Entry(namespace: .iptcCore, name: "Location", shape: .text, crosswalk: kCGImagePropertyIPTCSubLocation)
        case .rating: Entry(namespace: .xmpBasic, name: "Rating", shape: .integer, crosswalk: kCGImagePropertyIPTCStarRating)
        case .label: Entry(namespace: .xmpBasic, name: "Label", shape: .text)
        case .labelColor: Entry(namespace: .photoshop, name: "LabelColor", shape: .text)
        case .accessibilityAltText: Entry(namespace: .iptcCore, name: "AltTextAccessibility", shape: .langAlt)
        case .accessibilityDescription: Entry(namespace: .iptcCore, name: "ExtDescrAccessibility", shape: .langAlt)
        }
    }

    // MARK: - Description

    public var shape: Shape { entry.shape }

    /// The XMP namespace URI this field's property lives in.
    public var namespace: String { entry.namespace.uri }

    /// The prefix ImageIO addresses ``namespace`` by.
    public var prefix: String { entry.namespace.prefix }

    /// The property's local name: the child's for a struct field.
    public var localName: String {
        if case let .struct(_, child) = shape { return child }
        return entry.name
    }

    /// The XMP path ImageIO reads and removes this field at.
    ///
    /// A language alternative is given as the bare path, so removal takes the container and every
    /// language in it. Writing one uses the `[x-default]`-indexed path.
    public var path: String {
        if case let .struct(parent, child) = shape {
            return "\(prefix):\(parent).\(prefix):\(child)"
        }
        return "\(prefix):\(entry.name)"
    }

    /// The `kCGImagePropertyIPTCDictionary` key whose ImageIO bridge writes this field, if it
    /// uses one. Only `text`/`integer` fields may: the bridge writes the wrong shape for any
    /// other, unless ``removesContainerBeforeWrite`` makes it build a fresh container.
    var crosswalk: CFString? { entry.crosswalk }

    /// Whether a write must remove the existing container first. The bridge sets a string onto an
    /// existing `rdf:Alt` without changing its type, which ImageIO then writes back empty.
    public var removesContainerBeforeWrite: Bool { entry.removesContainerBeforeWrite }

    /// Whether the property is an `rdf:Bag`/`rdf:Seq` holding several values rather than one.
    public var isArray: Bool { shape == .bag || shape == .seq }

    /// Whether the array's order carries meaning, making it an `rdf:Seq` rather than an `rdf:Bag`.
    public var isOrderedArray: Bool { shape == .seq }

    /// Whether the property is an `rdf:Alt` language alternative.
    public var isLanguageAlternative: Bool { shape == .langAlt }

    public var isStructField: Bool {
        if case .struct = shape { return true }
        return false
    }
}

/// The namespaces ``XMPField`` uses, with ImageIO's own URI and prefix for each.
enum XMPNamespace {
    case dublinCore
    case photoshop
    case xmpBasic
    case xmpRights
    case iptcCore
    case iptcExtension

    var uri: String {
        switch self {
        case .dublinCore: kCGImageMetadataNamespaceDublinCore as String
        case .photoshop: kCGImageMetadataNamespacePhotoshop as String
        case .xmpBasic: kCGImageMetadataNamespaceXMPBasic as String
        case .xmpRights: kCGImageMetadataNamespaceXMPRights as String
        case .iptcCore: kCGImageMetadataNamespaceIPTCCore as String
        case .iptcExtension: kCGImageMetadataNamespaceIPTCExtension as String
        }
    }

    var prefix: String {
        switch self {
        case .dublinCore: kCGImageMetadataPrefixDublinCore as String
        case .photoshop: kCGImageMetadataPrefixPhotoshop as String
        case .xmpBasic: kCGImageMetadataPrefixXMPBasic as String
        case .xmpRights: kCGImageMetadataPrefixXMPRights as String
        case .iptcCore: kCGImageMetadataPrefixIPTCCore as String
        case .iptcExtension: kCGImageMetadataPrefixIPTCExtension as String
        }
    }
}
