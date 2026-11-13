// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SPFKMetadataImage

/// Writes over an `rdf:Alt` a HEIC already holds, populated or empty. JPEG never serializes an
/// empty one, so these need a HEIC fixture.
struct ImageXMPAlternateTextRewriteTests {
    private static func makeTestHEIC(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).heic")

        guard let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw TestError.imageCreationFailed
        }

        context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))

        guard let cgImage = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.heic" as CFString, 1, nil)
        else {
            throw TestError.imageCreationFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw TestError.imageCreationFailed
        }

        return url
    }

    private enum TestError: Error {
        case imageCreationFailed
    }

    /// An empty-string write is what leaves the empty container behind.
    private static func writeEmptyAlternateText(property: CFString, url: URL) throws {
        try ImageXMP.writeTags(
            [.scalarProperty(dictionary: kCGImagePropertyIPTCDictionary, property: property, value: "" as CFString)],
            url: url
        )
    }

    @Test func aTitleIsWrittenOverAnEmptyContainer() throws {
        let url = try Self.makeTestHEIC(named: "empty-title")
        defer { try? FileManager.default.removeItem(at: url) }

        try Self.writeEmptyAlternateText(property: kCGImagePropertyIPTCObjectName, url: url)
        #expect(try ImageXMP.readMetadata(from: url).title == nil)

        // Clearing another field is what selects the non-merging write, as every app save does.
        try ImageXMP.writeMetadata(XMPMetadata(title: "Real"), clearing: [.city], url: url)
        #expect(try ImageXMP.readMetadata(from: url).title == "Real")
    }

    @Test func aDescriptionIsWrittenOverAnEmptyContainer() throws {
        let url = try Self.makeTestHEIC(named: "empty-description")
        defer { try? FileManager.default.removeItem(at: url) }

        try Self.writeEmptyAlternateText(property: kCGImagePropertyIPTCCaptionAbstract, url: url)

        try ImageXMP.writeMetadata(XMPMetadata(description: "Real"), clearing: [.city], url: url)
        #expect(try ImageXMP.readMetadata(from: url).description == "Real")
    }

    @Test func populatedFieldsSurviveBeingWrittenAgain() throws {
        let url = try Self.makeTestHEIC(named: "populated")
        defer { try? FileManager.default.removeItem(at: url) }

        var first = XMPMetadata(keywords: ["keep"], title: "Keep", description: "Caption", copyright: "Rights")
        first.accessibilityAltText = "Alt"
        first.accessibilityDescription = "Extended"
        try ImageXMP.writeMetadata(first, url: url)

        var second = first
        second.city = "Portland"
        try ImageXMP.writeMetadata(second, clearing: [.state], url: url)

        let result = try ImageXMP.readMetadata(from: url)
        #expect(result.title == "Keep")
        #expect(result.description == "Caption")
        #expect(result.copyright == "Rights")
        #expect(result.accessibilityAltText == "Alt")
        #expect(result.accessibilityDescription == "Extended")
        #expect(result.keywords == ["keep"])
        #expect(result.city == "Portland")
    }

    @Test func aTitleLeftUnsetSurvivesAWriteThatClearsAnotherField() throws {
        let url = try Self.makeTestHEIC(named: "untouched")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(title: "Keep"), url: url)
        try ImageXMP.writeMetadata(XMPMetadata(city: "Portland"), clearing: [.state], url: url)

        #expect(try ImageXMP.readMetadata(from: url).title == "Keep")
    }
}
