// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO
import SPFKTesting
import Testing
@testable import SPFKMetadataImage

/// What the WebP route adds over the JPEG one, which `ImageXMPTests` and `ImageXMPClearingTests`
/// already run against WebP: ImageIO reads IFD0 `ImageDescription`, `Copyright` and `Artist` ahead
/// of the XMP chunk, so a write touching those fields has to remove the tag.
struct ImageXMPWebPTests {
    /// Both carry IFD0 `ImageDescription`, `Copyright` and `Artist`, plus an ExifIFD and a GPS IFD.
    enum ByteOrder: String, CaseIterable {
        case littleEndian, bigEndian

        var fixture: URL {
            switch self {
            case .littleEndian: TestBundleResources.shared.webp_exif_xmp
            case .bigEndian: TestBundleResources.shared.webp_iccp_exif_mm
            }
        }
    }

    private static func copy(_ source: URL, extension pathExtension: String = "webp") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(pathExtension)")
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    private static func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private static func exifChunk(_ url: URL) throws -> Data? {
        try WebPContainer(data: Data(contentsOf: url)).exif
    }

    @Test(arguments: ByteOrder.allCases)
    func theFixtureReadsItsEXIFText(order: ByteOrder) throws {
        let url = try Self.copy(order.fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.description == "EXIF description")
        #expect(read.copyright == "EXIF copyright")
        #expect(read.creators == ["EXIF artist"])
    }

    @Test(arguments: ByteOrder.allCases)
    func clearingAnEXIFBackedFieldStaysCleared(order: ByteOrder) throws {
        let url = try Self.copy(order.fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.description, .copyright, .creators], url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.description == nil)
        #expect(read.copyright == nil)
        #expect(read.creators.isEmpty)

        let bytes = try Data(contentsOf: url)
        for text in ["EXIF description", "EXIF copyright", "EXIF artist"] {
            #expect(bytes.range(of: Data(text.utf8)) == nil, "\(text) lingers in the file")
        }
    }

    /// ImageIO reports the EXIF value over the XMP one, so a new value only shows once the tag goes.
    @Test(arguments: ByteOrder.allCases)
    func settingAnEXIFBackedFieldShowsTheNewValue(order: ByteOrder) throws {
        let url = try Self.copy(order.fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(creators: ["New artist"], description: "New description"), url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.description == "New description")
        #expect(read.creators == ["New artist"])
        #expect(read.copyright == "EXIF copyright")
    }

    @Test(arguments: ByteOrder.allCases)
    func anUntouchedEXIFBackedFieldKeepsItsTag(order: ByteOrder) throws {
        let url = try Self.copy(order.fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        let before = try Self.exifChunk(url)
        try ImageXMP.writeMetadata(XMPMetadata(title: "New title", rating: 1), url: url)

        #expect(try Self.exifChunk(url) == before)
        #expect(try ImageXMP.readMetadata(from: url).title == "New title")
    }

    /// Everything in the EXIF except the removed tags survives, read through a different path than
    /// the one under test.
    @Test(arguments: ByteOrder.allCases)
    func theRestOfTheEXIFSurvives(order: ByteOrder) throws {
        let url = try Self.copy(order.fixture)
        defer { try? FileManager.default.removeItem(at: url) }

        let removed: Set<String> = [
            kCGImagePropertyTIFFImageDescription as String, kCGImagePropertyTIFFCopyright as String,
            kCGImagePropertyTIFFArtist as String,
        ]

        func dictionaries(_ url: URL) throws -> [String: NSDictionary] {
            let properties = try Self.properties(url)
            var result: [String: NSDictionary] = [:]
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary] {
                result[key as String] = try #require(properties[key] as? NSDictionary)
            }
            let tiff = try #require(properties[kCGImagePropertyTIFFDictionary] as? [String: Any])
            result[kCGImagePropertyTIFFDictionary as String] = tiff.filter { !removed.contains($0.key) } as NSDictionary
            return result
        }

        let before = try dictionaries(url)
        try ImageXMP.writeMetadata(XMPMetadata(), clearing: [.description, .copyright, .creators], url: url)
        let after = try dictionaries(url)

        #expect(before == after)
        #expect((after[kCGImagePropertyTIFFDictionary as String]?[kCGImagePropertyTIFFMake as String] as? String) == "SPFKTestFixture")
    }

    @Test func theRestOfThePacketSurvives() throws {
        let url = try Self.copy(TestBundleResources.shared.webp_exif_xmp)
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(city: "Hood River"), url: url)

        let read = try ImageXMP.readMetadata(from: url)
        #expect(read.city == "Hood River")
        #expect(read.title == "Fixture title")
        #expect(read.keywords == ["alpha", "beta"])
        #expect(read.rating == 2)
        #expect(read.label == "Green")

        let packet = try #require(try WebPContainer(data: Data(contentsOf: url)).xmpPacket)
        #expect(packet.starts(with: Data("<?xpacket begin=\"".utf8)))
    }

    /// Clear Metadata on a file whose packet held only modeled fields leaves no `XMP ` chunk.
    @Test func clearingEveryFieldRemovesThePacket() throws {
        let url = try Self.copy(TestBundleResources.shared.webp_exif_xmp)
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageXMP.writeMetadata(XMPMetadata(), clearing: Set(XMPField.allCases), url: url)

        let container = try WebPContainer(data: Data(contentsOf: url))
        #expect(container.xmpPacket == nil)
        #expect(container.chunks.map(\.fourCC) == ["VP8X", "VP8 ", "EXIF"])
        #expect(try ImageXMP.readMetadata(from: url).description == nil)
    }

    @Test func anUnparseablePacketThrowsAndLeavesTheFile() throws {
        let simple = try WebPContainer(data: Data(contentsOf: TestBundleResources.shared.webp_simple))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).webp")
        try simple.replacing(xmp: Data("not a packet".utf8), exif: nil).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let before = try Data(contentsOf: url)
        #expect(throws: ImageXMP.ImageXMPError.self) {
            try ImageXMP.writeMetadata(XMPMetadata(title: "Lost"), url: url)
        }
        #expect(try Data(contentsOf: url) == before)
    }

    /// Routed by content, not extension.
    @Test func aWebPNamedJPGWrites() throws {
        let url = try Self.copy(TestBundleResources.shared.webp_exif_xmp, extension: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ImageXMP.canWrite(url: url))
        try ImageXMP.writeMetadata(XMPMetadata(title: "Renamed"), url: url)

        #expect(try ImageXMP.readMetadata(from: url).title == "Renamed")
        #expect(try Data(contentsOf: url).prefix(4) == Data("RIFF".utf8))
    }

    @Test func productionFieldsWrite() throws {
        let url = try Self.copy(TestBundleResources.shared.webp_simple)
        defer { try? FileManager.default.removeItem(at: url) }

        let namespace = "http://ns.adobe.com/xmp/1.0/DynamicMedia/"
        try ImageXMP.writeScalarProperties(namespace: namespace, prefix: "xmpDM", values: ["scene": "A1"], url: url)

        let packet = try #require(try WebPContainer(data: Data(contentsOf: url)).xmpPacket)
        let metadata = try #require(CGImageMetadataCreateFromXMPData(packet as CFData))
        #expect(ImageXMP.scalarStringValue(metadata, path: "xmpDM:scene") == "A1")

        try ImageXMP.writeScalarProperties(namespace: namespace, prefix: "xmpDM", values: ["scene": nil], url: url)
        #expect(try WebPContainer(data: Data(contentsOf: url)).xmpPacket == nil)
    }
}
