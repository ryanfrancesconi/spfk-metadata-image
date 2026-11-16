// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SPFKMetadataImage

/// Writes to a PNG that has no XMP packet yet. ImageIO drops a whole write containing any `dc:`,
/// `photoshop:` or `Iptc4xmpCore:` property on such a file and still reports success.
struct ImageXMPPNGTests {
    private static func makePacketlessPNG(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).png")

        guard let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.imageCreationFailed
        }

        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))

        guard let cgImage = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
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

    @Test func fixtureHasNoPacket() throws {
        let url = try Self.makePacketlessPNG(named: "png-fixture")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try !ImageXMP.pngHasXMPPacket(url: url))
    }

    @Test func mergeWriteToPacketlessPNGKeepsEveryField() throws {
        let url = try Self.makePacketlessPNG(named: "png-merge")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(
            XMPMetadata(keywords: ["beach", "sunset"], title: "Title", city: "Lisbon", label: "Select"),
            url: url
        )

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.keywords == ["beach", "sunset"])
        #expect(read.title == "Title")
        #expect(read.city == "Lisbon")
        #expect(read.label == "Select")
    }

    @Test func clearingWriteToPacketlessPNGKeepsTheSetField() throws {
        let url = try Self.makePacketlessPNG(named: "png-clear")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(
            XMPMetadata(keywords: ["beach"], city: "Lisbon"),
            clearing: [.title],
            url: url
        )

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.keywords == ["beach"])
        #expect(read.city == "Lisbon")
        #expect(read.title == nil)
    }

    @Test func scalarPropertiesWriteToPacketlessPNG() throws {
        let url = try Self.makePacketlessPNG(named: "png-scalar")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeScalarProperties(
            namespace: "http://ns.adobe.com/photoshop/1.0/", prefix: "photoshop",
            values: ["City": "Porto"], url: url
        )

        #expect(try ImageXMP.readMetadata(from: url).city == "Porto")
    }

    /// The seed must not cost a second write once the packet exists, and a later write still lands.
    @Test func secondWriteAfterSeedingKeepsBothFields() throws {
        let url = try Self.makePacketlessPNG(named: "png-second")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(city: "Lisbon"), url: url)
        #expect(try ImageXMP.pngHasXMPPacket(url: url))
        try ImageXMP.writeMetadata(XMPMetadata(keywords: ["tram"]), url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.city == "Lisbon")
        #expect(read.keywords == ["tram"])
    }
}
