// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import CoreGraphics
import Foundation
import ImageIO
import SPFKTesting
import Testing

@testable import SPFKMetadataImage

/// Every ``XMPField`` written, read back in its shape, and cleared, on each still type ImageIO
/// writes. A field added to the table is covered here on arrival.
@Suite(.tags(.xmp))
struct XMPFieldRoundTripTests {
    enum Still: String, CaseIterable {
        case jpeg
        case heic
        case tiff
        /// Written by ImageIO with no properties, so it has no XMP packet.
        case packetlessPNG
    }

    private static func makeFile(_ still: Still) throws -> URL {
        let directory = FileManager.default.temporaryDirectory

        if still == .heic {
            let url = directory.appendingPathComponent("xmp-field-\(UUID().uuidString).heic")
            try FileManager.default.copyItem(at: TestBundleResources.shared.sharksandwich_heic, to: url)
            return url
        }

        let (type, ext) = switch still {
        case .jpeg: ("public.jpeg", "jpg")
        case .tiff: ("public.tiff", "tif")
        default: ("public.png", "png")
        }

        let url = directory.appendingPathComponent("xmp-field-\(UUID().uuidString).\(ext)")

        guard let context = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw TestError.imageCreationFailed
        }

        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)
        else {
            throw TestError.imageCreationFailed
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw TestError.imageCreationFailed
        }

        return url
    }

    private enum TestError: Error {
        case imageCreationFailed
    }

    private static func sample(for field: XMPField) -> [String] {
        switch field.shape {
        case .bag, .seq: ["\(field.rawValue) one", "\(field.rawValue) two"]
        case .integer: ["3"]
        case .bool: ["True"]
        case .text, .langAlt, .struct: ["\(field.rawValue) value"]
        }
    }

    /// Written as TorchTag saves, with every other field cleared in the same write.
    @Test(arguments: Still.allCases)
    func everyFieldWritesReadsAndClears(still: Still) throws {
        let url = try Self.makeFile(still)
        defer { try? FileManager.default.removeItem(at: url) }

        if still == .packetlessPNG {
            #expect(try !ImageXMP.pngHasXMPPacket(url: url))
        }

        for field in XMPField.allCases {
            var metadata = XMPMetadata()
            metadata[field] = Self.sample(for: field)
            let others = Set(XMPField.allCases).subtracting([field])

            try ImageXMP.writeMetadata(metadata, clearing: others, url: url)
            let written = try ImageXMP.readMetadata(from: url)[field]

            if still == .packetlessPNG, field == .creators {
                withKnownIssue("ImageIO reads only the first entry of a PNG's dc:creator, though the file holds both") {
                    #expect(written == Self.sample(for: field))
                }
            } else {
                #expect(written == Self.sample(for: field), "\(field) on \(still)")
            }

            try ImageXMP.writeMetadata(XMPMetadata(), clearing: Set(XMPField.allCases), url: url)
            let cleared = try ImageXMP.readMetadata(from: url)[field]
            #expect(cleared == [], "\(field) cleared on \(still)")
        }
    }

    /// The bridge writes Lang Alt as plain text, and empty over an existing one; Bag it writes as
    /// Seq. A crosswalk on any shape but text is only safe with the container removed first.
    @Test(arguments: XMPField.allCases.filter { $0.crosswalk != nil })
    func aCrosswalkIsOnlyUsedWhereTheBridgeWritesTheRightShape(field: XMPField) {
        switch field.shape {
        case .text, .integer: break
        case .langAlt: #expect(field.removesContainerBeforeWrite)
        default: Issue.record("\(field) is a \(field.shape) written through the bridge")
        }
    }
}
