// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SPFKMetadataImage

/// Clearing a field, as distinct from leaving it alone. Every test here is a full round trip --
/// set, read back, clear, read back -- because the three write mechanisms this package uses
/// (hand-built array tags, the classic-property bridge, namespaced tags) each store their value
/// differently, so a clear that works for one proves nothing about the others.
struct ImageXMPClearingTests {
    // MARK: - Array fields (hand-built dc: tags)

    @Test(arguments: TestImageFormat.allCases)
    func clearingKeywordsEmptiesThem(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-keywords")

        try ImageXMP.writeMetadata(XMPMetadata(keywords: ["beach", "sunset"]), url: url)
        #expect(try ImageXMP.readMetadata(from: url).keywords == ["beach", "sunset"])

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.keywords], url: url)
        #expect(try ImageXMP.readMetadata(from: url).keywords.isEmpty)
    }

    @Test(arguments: TestImageFormat.allCases)
    func clearingCreatorsEmptiesThem(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-creators")

        try ImageXMP.writeMetadata(XMPMetadata(creators: ["Ansel"]), url: url)
        #expect(try ImageXMP.readMetadata(from: url).creators == ["Ansel"])

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.creators], url: url)
        #expect(try ImageXMP.readMetadata(from: url).creators.isEmpty)
    }

    // MARK: - Alternate-text fields via the classic-property bridge

    @Test(arguments: TestImageFormat.allCases)
    func clearingTitleEmptiesIt(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-title")

        try ImageXMP.writeMetadata(XMPMetadata(title: "Original"), url: url)
        #expect(try ImageXMP.readMetadata(from: url).title == "Original")

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.title], url: url)
        #expect(try ImageXMP.readMetadata(from: url).title == nil)
    }

    @Test(arguments: TestImageFormat.allCases)
    func clearingDescriptionAndCopyrightEmptiesThem(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-desc")

        try ImageXMP.writeMetadata(
            XMPMetadata(description: "A description", copyright: "© 2026"),
            url: url
        )
        let written = try ImageXMP.readMetadata(from: url)
        #expect(written.description == "A description")
        #expect(written.copyright == "© 2026")

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.description, .copyright], url: url)
        let cleared = try ImageXMP.readMetadata(from: url)
        #expect(cleared.description == nil)
        #expect(cleared.copyright == nil)
    }

    // MARK: - Scalar fields

    @Test(arguments: TestImageFormat.allCases)
    func clearingLocationScalarsEmptiesThem(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-location")

        try ImageXMP.writeMetadata(
            XMPMetadata(city: "Portland", state: "Oregon", country: "USA"),
            url: url
        )
        #expect(try ImageXMP.readMetadata(from: url).city == "Portland")

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.city, .state, .country], url: url)
        let cleared = try ImageXMP.readMetadata(from: url)
        #expect(cleared.city == nil)
        #expect(cleared.state == nil)
        #expect(cleared.country == nil)
    }

    /// `xmp:Label` is written as a namespaced tag rather than through the bridge, so it exercises
    /// the third write mechanism.
    @Test(arguments: TestImageFormat.allCases)
    func clearingLabelEmptiesIt(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-label")

        try ImageXMP.writeMetadata(XMPMetadata(label: "Select"), url: url)
        #expect(try ImageXMP.readMetadata(from: url).label == "Select")

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.label], url: url)
        #expect(try ImageXMP.readMetadata(from: url).label == nil)
    }

    @Test(arguments: TestImageFormat.allCases)
    func clearingRatingEmptiesIt(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-rating")

        try ImageXMP.writeMetadata(XMPMetadata(rating: 4), url: url)
        #expect(try ImageXMP.readMetadata(from: url).rating == 4)

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.rating], url: url)
        #expect(try ImageXMP.readMetadata(from: url).rating == nil)
    }

    // MARK: - Clearing must be surgical

    /// The whole reason clearing is a parameter rather than a replace-everything write: it must
    /// not touch fields the caller did not name.
    @Test(arguments: TestImageFormat.allCases)
    func clearingOneFieldLeavesTheOthersIntact(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-surgical")

        try ImageXMP.writeMetadata(
            XMPMetadata(keywords: ["keep"], title: "Keep", city: "Portland"),
            url: url
        )

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.title], url: url)

        let result = try ImageXMP.readMetadata(from: url)
        #expect(result.title == nil)
        #expect(result.keywords == ["keep"])
        #expect(result.city == "Portland")
    }

    /// Clearing writes the file wholesale rather than merging, so non-XMP metadata has to survive
    /// that path too -- the fixture's EXIF/TIFF Make is the canary.
    @Test(arguments: TestImageFormat.allCases)
    func clearingPreservesUnrelatedNonXMPMetadata(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-preserves-exif")

        try ImageXMP.writeMetadata(XMPMetadata(keywords: ["gone"]), url: url)
        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.keywords], url: url)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let tiff = properties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        #expect(tiff?[kCGImagePropertyTIFFMake] as? String == "SPFKTestFixture")
    }

    /// Guards against the clear only *looking* like it worked. Title/description/copyright and
    /// the location scalars are written through ImageIO's classic-property bridge, so the value
    /// also exists in the file's IPTC dictionary. `readMetadata` reads XMP paths only -- if the
    /// IPTC side survived a clear, this package would report the field empty while every other
    /// tool (Lightroom, Bridge, exiftool) still showed the old value. Read back through
    /// `CGImageSourceCopyPropertiesAtIndex`, a different path than the one under test.
    @Test(arguments: TestImageFormat.allCases)
    func clearingAlsoEmptiesTheClassicIPTCValue(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-iptc-crosscheck")

        try ImageXMP.writeMetadata(
            XMPMetadata(title: "Original", description: "Caption", city: "Portland"),
            url: url
        )

        func iptcDictionary() throws -> [CFString: Any] {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            return properties?[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        }

        // Confirm the bridge really did populate the classic side, or the assertion below would
        // pass for the wrong reason.
        let written = try iptcDictionary()
        #expect(written[kCGImagePropertyIPTCObjectName] as? String == "Original")

        try ImageXMP.writeMetadata(
            XMPMetadata(),
            clearing: [.title, .description, .city],
            url: url
        )

        let cleared = try iptcDictionary()
        #expect(cleared[kCGImagePropertyIPTCObjectName] == nil)
        #expect(cleared[kCGImagePropertyIPTCCaptionAbstract] == nil)
        #expect(cleared[kCGImagePropertyIPTCCity] == nil)
    }

    @Test(arguments: TestImageFormat.allCases)
    func clearingAnAlreadyEmptyFieldIsNotAnError(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-empty")

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.title, .keywords], url: url)

        #expect(try ImageXMP.readMetadata(from: url).title == nil)
    }

    /// Clearing wins over a value supplied in the same call, so a caller cannot ask for both and
    /// get an order-dependent answer.
    @Test(arguments: TestImageFormat.allCases)
    func clearingTakesPrecedenceOverAValueInTheSameWrite(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-precedence")

        try ImageXMP.writeMetadata(XMPMetadata(title: "Original"), url: url)
        try ImageXMP.writeMetadata(XMPMetadata(title: "Ignored"), clearing: [.title], url: url)

        #expect(try ImageXMP.readMetadata(from: url).title == nil)
    }

    /// Set, clear, set again -- a cleared field has to remain writable, not be poisoned by the
    /// removal.
    @Test(arguments: TestImageFormat.allCases)
    func aClearedFieldCanBeSetAgain(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "clear-then-set")

        try ImageXMP.writeMetadata(XMPMetadata(keywords: ["first"]), url: url)
        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.keywords], url: url)
        try ImageXMP.writeMetadata(XMPMetadata(keywords: ["second"]), url: url)

        #expect(try ImageXMP.readMetadata(from: url).keywords == ["second"])
    }
}
