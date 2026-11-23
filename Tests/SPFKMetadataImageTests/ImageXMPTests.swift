// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SPFKMetadataImage

struct ImageXMPTests {
    /// WebP is writable without being encodable: `writableContentTypes` also decides re-encodes,
    /// which a WebP cannot take. SVG is a `public.image` ImageIO has no reader for.
    @Test func readabilityIsSeparateFromWritability() {
        let webP = URL(fileURLWithPath: "/tmp/a.webp")
        let svg = URL(fileURLWithPath: "/tmp/a.svg")

        #expect(ImageXMP.canRead(url: URL(fileURLWithPath: "/tmp/a.JPG")))
        #expect(ImageXMP.canRead(url: webP))
        #expect(ImageXMP.canWrite(url: webP))
        #expect(ImageXMP.writableContentTypes.contains("org.webmproject.webp") == false)
        #expect(ImageXMP.canRead(url: svg) == false)
    }

    /// A file that can't be read is not a file without metadata: a caller writes every field it
    /// read back as empty, removing them.
    @Test(arguments: TestImageFormat.allCases)
    func anUnreadableFileThrowsRatherThanReadingEmpty(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "unreadable")
        defer { try? FileManager.default.removeItem(at: url) }

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        #expect(throws: (any Error).self) {
            try ImageXMP.readMetadata(from: url)
        }
    }

    @Test(arguments: TestImageFormat.allCases)
    func freshFileHasNoKeywords(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "fresh")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try ImageXMP.keywords(from: url) == [])
    }

    @Test(arguments: TestImageFormat.allCases)
    func writeThenReadRoundTrips(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "roundtrip")
        defer { try? FileManager.default.removeItem(at: url) }

        let written = ["mountains", "california", "sunset"]
        try ImageXMP.setKeywords(written, url: url)

        let read = try ImageXMP.keywords(from: url)
        #expect(Set(read) == Set(written))
    }

    @Test(arguments: TestImageFormat.allCases)
    func replacingKeywordsOverwritesRatherThanAppends(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "replace")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.setKeywords(["first", "second"], url: url)
        try ImageXMP.setKeywords(["third"], url: url)

        let read = try ImageXMP.keywords(from: url)
        #expect(read == ["third"])
    }

    @Test(arguments: TestImageFormat.allCases)
    func writingKeywordsPreservesExistingEXIFData(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "preserve-exif")
        defer { try? FileManager.default.removeItem(at: url) }

        guard let sourceBefore = CGImageSourceCreateWithURL(url as CFURL, nil),
              let propsBefore = CGImageSourceCopyPropertiesAtIndex(sourceBefore, 0, nil) as? [CFString: Any],
              let tiffBefore = propsBefore[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        else {
            Issue.record("Fixture didn't have expected TIFF properties before write")
            return
        }
        #expect(tiffBefore[kCGImagePropertyTIFFMake] as? String == "SPFKTestFixture")

        try ImageXMP.setKeywords(["test"], url: url)

        guard let sourceAfter = CGImageSourceCreateWithURL(url as CFURL, nil),
              let propsAfter = CGImageSourceCopyPropertiesAtIndex(sourceAfter, 0, nil) as? [CFString: Any],
              let tiffAfter = propsAfter[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        else {
            Issue.record("TIFF properties missing after keyword write -- merge dropped existing metadata")
            return
        }
        #expect(tiffAfter[kCGImagePropertyTIFFMake] as? String == "SPFKTestFixture")
    }

    @Test
    func invalidURLThrows() throws {
        let url = URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString).jpg")
        #expect(throws: ImageXMP.ImageXMPError.self) {
            try ImageXMP.keywords(from: url)
        }
    }

    @Test(arguments: TestImageFormat.allCases)
    func freshFileHasEmptyMetadata(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "fresh-metadata")
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try ImageXMP.readMetadata(from: url)
        #expect(metadata.creators == [])
    }

    @Test(arguments: TestImageFormat.allCases)
    func writeAndReadFullMetadataRoundTrips(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "full-metadata")
        defer { try? FileManager.default.removeItem(at: url) }

        let written = XMPMetadata(
            keywords: ["mountains", "california"],
            creators: ["Ryan Francesconi"]
        )
        try ImageXMP.writeMetadata(written, url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(Set(read.keywords) == Set(written.keywords))
        #expect(read.creators == written.creators)
    }

    @Test(arguments: TestImageFormat.allCases)
    func multipleCreatorsPreserveOrder(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "multi-creator")
        defer { try? FileManager.default.removeItem(at: url) }

        let creators = ["First Photographer", "Second Photographer", "Third Photographer"]
        try ImageXMP.writeMetadata(XMPMetadata(creators: creators), url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.creators == creators)
    }

    @Test(arguments: TestImageFormat.allCases)
    func writingMetadataDoesNotClobberUnspecifiedFields(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "no-clobber")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.setKeywords(["original-keyword"], url: url)
        try ImageXMP.writeMetadata(XMPMetadata(creators: ["New creator only"]), url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.creators == ["New creator only"])
        #expect(read.keywords == ["original-keyword"])
    }

    /// Writing an `.alternateText` tag (dc:rights) through `CGImageMetadataTagCreate` crashes on a
    /// real HEIC (`-[Swift.__StringStorage count]: unrecognized selector`) while passing on
    /// synthetic JPEGs; the write path uses `CGImageMetadataSetValueMatchingImageProperty` instead.
    /// See `titleAndDescriptionRoundTrip` for the fields actually exposed.
    @Test(arguments: TestImageFormat.allCases)
    func realFileWritesDoNotCrash(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "real-file-safety")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(keywords: ["a"], creators: ["b"]), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.keywords == ["a"])
        #expect(read.creators == ["b"])
    }

    @Test(arguments: TestImageFormat.allCases)
    func titleAndDescriptionRoundTrip(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "title-description")
        defer { try? FileManager.default.removeItem(at: url) }

        let written = XMPMetadata(title: "A Test Title", description: "A test description.")
        try ImageXMP.writeMetadata(written, url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.title == written.title)
        #expect(read.description == written.description)
    }

    @Test(arguments: TestImageFormat.allCases)
    func freshFileHasNilTitleAndDescription(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "fresh-title-description")
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try ImageXMP.readMetadata(from: url)
        #expect(metadata.title == nil)
        #expect(metadata.description == nil)
    }

    @Test(arguments: TestImageFormat.allCases)
    func titleAndDescriptionCoexistWithKeywordsAndCreators(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "coexist")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.setKeywords(["mountains"], url: url)
        try ImageXMP.writeMetadata(
            XMPMetadata(creators: ["Ryan Francesconi"], title: "A Title", description: "A Description"),
            url: url
        )

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.keywords == ["mountains"])
        #expect(read.creators == ["Ryan Francesconi"])
        #expect(read.title == "A Title")
        #expect(read.description == "A Description")
    }

    @Test(arguments: TestImageFormat.allCases)
    func copyrightRoundTrips(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "copyright")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(copyright: "© 2026 Test"), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.copyright == "© 2026 Test")
    }

    @Test(arguments: TestImageFormat.allCases)
    func locationFieldsRoundTrip(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "location")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(city: "Hood River", state: "Oregon", country: "USA"), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.city == "Hood River")
        #expect(read.state == "Oregon")
        #expect(read.country == "USA")
    }

    @Test(arguments: TestImageFormat.allCases)
    func subLocationRoundTrips(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "sub-location")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(city: "Hood River", subLocation: "East Fork Sand"), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.city == "Hood River")
        #expect(read.subLocation == "East Fork Sand")
    }

    @Test(arguments: TestImageFormat.allCases)
    func ratingRoundTrips(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "rating")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(rating: 4), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.rating == 4)
    }

    @Test(arguments: TestImageFormat.allCases)
    func labelRoundTrips(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "label")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(label: "Green"), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.label == "Green")
    }

    @Test(arguments: TestImageFormat.allCases)
    func labelColorRoundTrips(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "label-color")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(label: "Orange", labelColor: "#F37500"), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.label == "Orange")
        #expect(read.labelColor == "#F37500")
    }

    @Test(arguments: TestImageFormat.allCases)
    func accessibilityFieldsRoundTrip(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "accessibility")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(
            XMPMetadata(accessibilityAltText: "A cyclist on a gravel path", accessibilityDescription: "Extended accessibility description"),
            url: url
        )
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.accessibilityAltText == "A cyclist on a gravel path")
        #expect(read.accessibilityDescription == "Extended accessibility description")
    }

    @Test(arguments: TestImageFormat.allCases)
    func newFieldsDoNotClobberExistingFields(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "new-fields-no-clobber")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(
            XMPMetadata(keywords: ["bike"], creators: ["Ryan"], title: "T", description: "D"),
            url: url
        )
        try ImageXMP.writeMetadata(
            XMPMetadata(copyright: "© 2026", city: "Hood River", rating: 5, label: "Red"),
            url: url
        )

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.keywords == ["bike"])
        #expect(read.creators == ["Ryan"])
        #expect(read.title == "T")
        #expect(read.description == "D")
        #expect(read.copyright == "© 2026")
        #expect(read.city == "Hood River")
        #expect(read.rating == 5)
        #expect(read.label == "Red")
    }

    @Test(arguments: TestImageFormat.allCases)
    func freshFileHasNilForAllNewFields(format: TestImageFormat) throws {
        let url = try format.makeImage(named: "fresh-new-fields")
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try ImageXMP.readMetadata(from: url)
        #expect(metadata.copyright == nil)
        #expect(metadata.city == nil)
        #expect(metadata.state == nil)
        #expect(metadata.country == nil)
        #expect(metadata.rating == nil)
        #expect(metadata.label == nil)
        #expect(metadata.labelColor == nil)
        #expect(metadata.accessibilityAltText == nil)
        #expect(metadata.accessibilityDescription == nil)
    }
}
