// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO
import SPFKTesting
import Testing
@testable import SPFKMetadataImage

/// Editing a WebP's whole packet, as the XMP tab does. The fixture's packet was written by exiftool,
/// so its attributes are single-quoted.
struct ImageXMPWebPPacketTests {
    private static func copyFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).webp")
        try FileManager.default.copyItem(at: TestBundleResources.shared.webp_exif_xmp, to: url)
        return url
    }

    /// `packet` with each field replaced, serialized as the XMP tab would hand it back. The field is
    /// removed first: the IPTC bridge empties an existing `rdf:Alt` rather than setting it.
    private static func editing(_ packet: String, _ fields: [XMPField: String]) throws -> String {
        let parsed = try #require(try ImageXMP.parsePacket(Data(packet.utf8)))
        let metadata = try #require(CGImageMetadataCreateMutableCopy(parsed))
        for (field, value) in fields {
            let crosswalk = try #require(field.crosswalk)
            CGImageMetadataRemoveTagWithPath(metadata, nil, field.path as CFString)
            try #require(CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyIPTCDictionary, crosswalk, value as CFString))
        }
        let data = try #require(CGImageMetadataCreateXMPData(metadata, nil) as Data?)
        return try #require(String(data: data, encoding: .utf8))
    }

    @Test func canWritePacketIsWebPOnly() {
        #expect(ImageXMP.canWritePacket(url: URL(fileURLWithPath: "/tmp/a.webp")))
        #expect(ImageXMP.canWritePacket(url: URL(fileURLWithPath: "/tmp/a.WEBP")))
        #expect(ImageXMP.canWritePacket(url: URL(fileURLWithPath: "/tmp/a.jpg")) == false)
    }

    @Test func thePacketIsTheChunkNotImageIOsView() throws {
        let packet = try #require(try ImageXMP.webPPacket(from: TestBundleResources.shared.webp_exif_xmp))

        #expect(packet.contains("Fixture title"))
        #expect(!packet.contains("EXIF description"))
        #expect(try ImageXMP.webPPacket(from: TestBundleResources.shared.webp_simple) == nil)
    }

    @Test func aSingleQuotedPacketReadsIntoFields() throws {
        let packet = try #require(try ImageXMP.webPPacket(from: TestBundleResources.shared.webp_exif_xmp))
        let fields = try #require(ImageXMP.readMetadata(fromPacket: packet))

        #expect(fields.title == "Fixture title")
        #expect(fields.keywords == ["alpha", "beta"])
    }

    /// Only what the edit changed is written: a property another app set after the baseline was
    /// read survives.
    @Test func anEditKeepsAChangeMadeSinceItsBaseline() throws {
        let url = try Self.copyFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let baseline = try #require(try ImageXMP.webPPacket(from: url))
        try ImageXMP.writeMetadata(XMPMetadata(city: "Hood River"), url: url)

        let edited = try Self.editing(baseline, [.title: "Edited title"])
        try ImageXMP.applyWebPPacketChanges(from: baseline, to: edited, url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.title == "Edited title")
        #expect(read.city == "Hood River")
        #expect(read.keywords == ["alpha", "beta"])
        #expect(read.rating == 2)
    }

    /// The EXIF's description would otherwise go on showing over the packet's.
    @Test func editingAnEXIFBackedFieldShowsTheEdit() throws {
        let url = try Self.copyFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let baseline = try #require(try ImageXMP.webPPacket(from: url))
        let edited = try Self.editing(baseline, [.description: "Packet description"])
        try ImageXMP.applyWebPPacketChanges(from: baseline, to: edited, url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.description == "Packet description")
        #expect(read.copyright == "EXIF copyright")
    }

    @Test func clearingRemovesThePacketAndKeepsUntouchedEXIF() throws {
        let url = try Self.copyFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(description: "Packet description"), url: url)

        let baseline = try ImageXMP.webPPacket(from: url)
        try ImageXMP.applyWebPPacketChanges(from: baseline, to: nil, url: url)

        #expect(try ImageXMP.webPPacket(from: url) == nil)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.title == nil)
        #expect(read.description == nil)
        #expect(read.copyright == "EXIF copyright")
    }

    @Test func anEditOnAFileWithNoPacketCreatesOne() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).webp")
        try FileManager.default.copyItem(at: TestBundleResources.shared.webp_simple, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let empty = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description rdf:about=\"\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmp:Label=\"Blue\"/></rdf:RDF></x:xmpmeta>"
        try ImageXMP.applyWebPPacketChanges(from: nil, to: empty, url: url)

        #expect(try ImageXMP.readMetadata(from: url).label == "Blue")
    }

    @Test func anUnparseableEditThrowsAndLeavesTheFile() throws {
        let url = try Self.copyFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let before = try Data(contentsOf: url)
        #expect(throws: ImageXMP.ImageXMPError.self) {
            try ImageXMP.applyWebPPacketChanges(from: nil, to: "not a packet", url: url)
        }
        #expect(try Data(contentsOf: url) == before)
    }
}
