// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SPFKMetadataImage

struct ImageXMPTests {
    /// Generates a small synthetic JPEG with a real EXIF field set (TIFF Make), so tests can
    /// verify keyword writes don't clobber other existing metadata. Pure metadata I/O doesn't
    /// need real photo content to test correctly, unlike ML-classification-style testing.
    private static func makeTestJPEG(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).jpg")

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))

        guard let cgImage = context.makeImage() else {
            throw TestError.imageCreationFailed
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw TestError.imageCreationFailed
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "SPFKTestFixture"],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw TestError.imageCreationFailed
        }

        return url
    }

    private enum TestError: Error {
        case imageCreationFailed
    }

    @Test
    func freshFileHasNoKeywords() throws {
        let url = try Self.makeTestJPEG(named: "fresh")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try ImageXMP.keywords(from: url) == [])
    }

    @Test
    func writeThenReadRoundTrips() throws {
        let url = try Self.makeTestJPEG(named: "roundtrip")
        defer { try? FileManager.default.removeItem(at: url) }

        let written = ["mountains", "california", "sunset"]
        try ImageXMP.setKeywords(written, url: url)

        let read = try ImageXMP.keywords(from: url)
        #expect(Set(read) == Set(written))
    }

    @Test
    func replacingKeywordsOverwritesRatherThanAppends() throws {
        let url = try Self.makeTestJPEG(named: "replace")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.setKeywords(["first", "second"], url: url)
        try ImageXMP.setKeywords(["third"], url: url)

        let read = try ImageXMP.keywords(from: url)
        #expect(read == ["third"])
    }

    @Test
    func writingKeywordsPreservesExistingEXIFData() throws {
        let url = try Self.makeTestJPEG(named: "preserve-exif")
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

    @Test
    func freshFileHasEmptyMetadata() throws {
        let url = try Self.makeTestJPEG(named: "fresh-metadata")
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try ImageXMP.readMetadata(from: url)
        #expect(metadata.creators == [])
    }

    @Test
    func writeAndReadFullMetadataRoundTrips() throws {
        let url = try Self.makeTestJPEG(named: "full-metadata")
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

    @Test
    func multipleCreatorsPreserveOrder() throws {
        let url = try Self.makeTestJPEG(named: "multi-creator")
        defer { try? FileManager.default.removeItem(at: url) }

        let creators = ["First Photographer", "Second Photographer", "Third Photographer"]
        try ImageXMP.writeMetadata(XMPMetadata(creators: creators), url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.creators == creators)
    }

    @Test
    func writingMetadataDoesNotClobberUnspecifiedFields() throws {
        let url = try Self.makeTestJPEG(named: "no-clobber")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.setKeywords(["original-keyword"], url: url)
        try ImageXMP.writeMetadata(XMPMetadata(creators: ["New creator only"]), url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.creators == ["New creator only"])
        #expect(read.keywords == ["original-keyword"])
    }

    /// Regression test for a real crash found against a real HEIC file (2026-07-24): writing an
    /// `.alternateText`-typed tag (dc:rights) via CGImageMetadataTagCreate crashed the process
    /// with -[Swift.__StringStorage count]: unrecognized selector, despite passing reliably on
    /// synthetic JPEG fixtures. Root cause traced (2026-07-27) to that specific call sequence --
    /// switching to CGImageMetadataSetValueMatchingImageProperty (what title/description now use)
    /// was verified crash-free against a real, metadata-rich iPhone HEIC, including for dc:rights
    /// itself. This test exists so a future change to the write path doesn't silently reintroduce
    /// the original crash without new real-file testing -- see titleAndDescriptionRoundTrip below
    /// for the same coverage on the fields actually exposed.
    @Test
    func realFileWritesDoNotCrash() throws {
        let url = try Self.makeTestJPEG(named: "real-file-safety")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(keywords: ["a"], creators: ["b"]), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.keywords == ["a"])
        #expect(read.creators == ["b"])
    }

    @Test
    func titleAndDescriptionRoundTrip() throws {
        let url = try Self.makeTestJPEG(named: "title-description")
        defer { try? FileManager.default.removeItem(at: url) }

        let written = XMPMetadata(title: "A Test Title", description: "A test description.")
        try ImageXMP.writeMetadata(written, url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.title == written.title)
        #expect(read.description == written.description)
    }

    @Test
    func freshFileHasNilTitleAndDescription() throws {
        let url = try Self.makeTestJPEG(named: "fresh-title-description")
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try ImageXMP.readMetadata(from: url)
        #expect(metadata.title == nil)
        #expect(metadata.description == nil)
    }

    @Test
    func titleAndDescriptionCoexistWithKeywordsAndCreators() throws {
        let url = try Self.makeTestJPEG(named: "coexist")
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

    @Test
    func copyrightRoundTrips() throws {
        let url = try Self.makeTestJPEG(named: "copyright")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(copyright: "© 2026 Test"), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.copyright == "© 2026 Test")
    }

    @Test
    func locationFieldsRoundTrip() throws {
        let url = try Self.makeTestJPEG(named: "location")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(city: "Hood River", state: "Oregon", country: "USA"), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.city == "Hood River")
        #expect(read.state == "Oregon")
        #expect(read.country == "USA")
    }

    @Test
    func subLocationRoundTrips() throws {
        let url = try Self.makeTestJPEG(named: "sub-location")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(city: "Hood River", subLocation: "East Fork Sand"), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.city == "Hood River")
        #expect(read.subLocation == "East Fork Sand")
    }

    @Test
    func ratingRoundTrips() throws {
        let url = try Self.makeTestJPEG(named: "rating")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(rating: 4), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.rating == 4)
    }

    @Test
    func labelRoundTrips() throws {
        let url = try Self.makeTestJPEG(named: "label")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(label: "Green"), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.label == "Green")
    }

    @Test
    func labelColorRoundTrips() throws {
        let url = try Self.makeTestJPEG(named: "label-color")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(label: "Orange", labelColor: "#F37500"), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.label == "Orange")
        #expect(read.labelColor == "#F37500")
    }

    @Test
    func accessibilityFieldsRoundTrip() throws {
        let url = try Self.makeTestJPEG(named: "accessibility")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(
            XMPMetadata(accessibilityAltText: "A cyclist on a gravel path", accessibilityDescription: "Extended accessibility description"),
            url: url
        )
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.accessibilityAltText == "A cyclist on a gravel path")
        #expect(read.accessibilityDescription == "Extended accessibility description")
    }

    @Test
    func newFieldsDoNotClobberExistingFields() throws {
        let url = try Self.makeTestJPEG(named: "new-fields-no-clobber")
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

    @Test
    func freshFileHasNilForAllNewFields() throws {
        let url = try Self.makeTestJPEG(named: "fresh-new-fields")
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
