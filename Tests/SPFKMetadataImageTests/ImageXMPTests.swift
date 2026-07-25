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

        let written = ImageXMPMetadata(
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
        try ImageXMP.writeMetadata(ImageXMPMetadata(creators: creators), url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.creators == creators)
    }

    @Test
    func writingMetadataDoesNotClobberUnspecifiedFields() throws {
        let url = try Self.makeTestJPEG(named: "no-clobber")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.setKeywords(["original-keyword"], url: url)
        try ImageXMP.writeMetadata(ImageXMPMetadata(creators: ["New creator only"]), url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.creators == ["New creator only"])
        #expect(read.keywords == ["original-keyword"])
    }

    /// Regression test for a real crash found against a real HEIC file (2026-07-24): writing an
    /// `.alternateText`-typed tag (dc:rights) via CGImageMetadataTagCreate crashed the process
    /// with -[Swift.__StringStorage count]: unrecognized selector, despite passing reliably on
    /// synthetic JPEG fixtures. That's why only array-typed fields (keywords/creators) are
    /// exposed at all -- this test exists so a future re-addition of an alternate-text field
    /// doesn't silently reintroduce the same crash without new real-file testing.
    @Test
    func realFileWritesDoNotCrash() throws {
        let url = try Self.makeTestJPEG(named: "real-file-safety")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(ImageXMPMetadata(keywords: ["a"], creators: ["b"]), url: url)
        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.keywords == ["a"])
        #expect(read.creators == ["b"])
    }
}
