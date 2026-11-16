// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO
import SPFKTesting
import Testing

@testable import SPFKMetadataImage

/// `Iptc4xmpCore:CreatorContactInfo`, whose children are separate fields written as one struct.
@Suite(.tags(.xmp))
struct ImageXMPStructTests {
    typealias Still = XMPFieldRoundTripTests.Still

    private static let contactFields = XMPField.allCases.filter { $0.structName == "CreatorContactInfo" }

    private static func contact(_ url: URL) throws -> [XMPField: String] {
        let metadata = try ImageXMP.readMetadata(from: url)
        return Dictionary(uniqueKeysWithValues: contactFields.compactMap { field in
            metadata[field].first.map { (field, $0) }
        })
    }

    /// Whether ImageIO, or a PNG's own packet, still holds the struct itself.
    private static func hasStruct(_ url: URL) throws -> Bool {
        let path = "Iptc4xmpCore:CreatorContactInfo" as CFString

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }

        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
           CGImageMetadataCopyTagWithPath(metadata, nil, path) != nil
        {
            return true
        }

        guard let packet = try ImageXMP.pngPacketMetadata(source: source, url: url) else { return false }
        return CGImageMetadataCopyTagWithPath(packet, nil, path) != nil
    }

    @Test(arguments: Still.allCases)
    func childrenAreSetChangedAndClearedWithoutLeavingAnEmptyStruct(still: Still) throws {
        let url = try XMPFieldRoundTripTests.makeFile(still)
        defer { try? FileManager.default.removeItem(at: url) }

        var metadata = XMPMetadata()
        metadata[.contactEmail] = ["a@example.com"]
        metadata[.contactPhone] = ["555-0100"]
        metadata[.contactCity] = ["Portland"]

        try ImageXMP.writeMetadata(metadata, url: url)
        #expect(try Self.contact(url) == [.contactEmail: "a@example.com", .contactPhone: "555-0100", .contactCity: "Portland"])

        // A merge write naming one child keeps the others.
        var change = XMPMetadata()
        change[.contactEmail] = ["b@example.com"]
        try ImageXMP.writeMetadata(change, url: url)
        #expect(try Self.contact(url) == [.contactEmail: "b@example.com", .contactPhone: "555-0100", .contactCity: "Portland"])

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.contactPhone], url: url)
        #expect(try Self.contact(url) == [.contactEmail: "b@example.com", .contactCity: "Portland"])

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: Set(Self.contactFields), url: url)
        #expect(try Self.contact(url) == [:])
        #expect(try !Self.hasStruct(url), "\(still) kept an empty struct")
    }

    /// HEIC and TIFF report `photoshop:Headline` at `Iptc4xmpExt:Headline` too, and a write from a
    /// copy of the file's metadata stores that copy, which must follow the field.
    @Test(arguments: [Still.heic, .tiff])
    func headlineKeepsItsSecondPathInStep(still: Still) throws {
        let url = try XMPFieldRoundTripTests.makeFile(still)
        defer { try? FileManager.default.removeItem(at: url) }

        func extensionHeadline() -> String? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
                  let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "Iptc4xmpExt:Headline" as CFString)
            else { return nil }
            return CGImageMetadataTagCopyValue(tag) as? String
        }

        var metadata = XMPMetadata()
        metadata[.headline] = ["First"]
        try ImageXMP.writeMetadata(metadata, clearing: [.title], url: url)

        // Any clearing write stores ImageIO's second copy in the file.
        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.title], url: url)

        metadata[.headline] = ["Second"]
        try ImageXMP.writeMetadata(metadata, clearing: [.title], url: url)
        #expect(try ImageXMP.readMetadata(from: url)[.headline] == ["Second"])
        #expect(extensionHeadline() ?? "Second" == "Second")

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.headline], url: url)
        #expect(try ImageXMP.readMetadata(from: url)[.headline] == [])
        #expect(extensionHeadline() == nil)
    }
}
