// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import CoreGraphics
import Foundation
import ImageIO
import SPFKTesting
@testable import SPFKMetadataImage

/// The formats the write suites run against: JPEG, written by ImageIO's encoder, and WebP, written
/// by the chunk splice.
enum TestImageFormat: String, CaseIterable {
    case jpeg, webP

    enum TestError: Error {
        case imageCreationFailed
    }

    /// A 64 x 64 image in the temporary directory whose only metadata is EXIF IFD0 `Make`
    /// `SPFKTestFixture`, the canary for metadata a write must not drop.
    func makeImage(named name: String) throws -> URL {
        switch self {
        case .jpeg: try Self.makeJPEG(named: name)
        case .webP: try Self.makeWebP(named: name)
        }
    }

    private static func makeJPEG(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).jpg")

        guard let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw TestError.imageCreationFailed
        }

        context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        else {
            throw TestError.imageCreationFailed
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "SPFKTestFixture"],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw TestError.imageCreationFailed }

        return url
    }

    private static func makeWebP(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).webp")
        let container = try WebPContainer(data: Data(contentsOf: TestBundleResources.shared.webp_simple))
        try container.replacing(xmp: nil, exif: makeEXIF).write(to: url)
        return url
    }

    /// Little-endian TIFF: header, IFD0 with one ASCII `Make` entry (0x010F), then its value.
    private static var makeEXIF: Data {
        let make = Array("SPFKTestFixture\0".utf8)
        let valueOffset: UInt32 = 8 + 2 + 12 + 4

        var bytes: [UInt8] = [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, 0x01, 0x00, 0x0F, 0x01, 0x02, 0x00]
        bytes += littleEndian(UInt32(make.count)) + littleEndian(valueOffset) + littleEndian(0)
        return Data(bytes + make)
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }
}
