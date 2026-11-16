// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import CoreGraphics
import Foundation
import ImageIO
import SPFKTesting
import Testing

@testable import SPFKMetadataImage

/// Every field written to photo-sized files, as a template applied to an import saves them.
@Suite(.tags(.xmp, .slow))
struct ImageXMPMemoryTests {
    private static func makePhoto(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("photo.jpg")
        let width = 4032, height = 3024

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        // Noise, so the file is as large as a camera's rather than a few kilobytes of flat color.
        guard let pixels = context.data?.assumingMemoryBound(to: UInt32.self) else { throw CocoaError(.fileWriteUnknown) }
        var generator = SystemRandomNumberGenerator()
        for index in 0 ..< context.bytesPerRow / 4 * height {
            pixels[index] = generator.next()
        }

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }

        return url
    }

    @Test func writingEveryFieldHoldsNoMemoryPerFile() async throws {
        let bin = FileManager.default.temporaryDirectory.appendingPathComponent("xmp-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bin) }

        let photo = try Self.makePhoto(in: bin)

        var metadata = XMPMetadata()
        for field in XMPField.allCases {
            metadata[field] = switch field.shape {
            case .bag, .seq: ["\(field.rawValue) one", "\(field.rawValue) two"]
            case .integer: ["3"]
            case .bool: ["True"]
            case .text, .langAlt, .struct: ["\(field.rawValue) value"]
            }
        }
        let template = metadata

        let grown = try await retainedMemoryMB(warmUp: 8, measured: 40, width: 4) { index in
            let url = bin.appendingPathComponent("out-\(index).jpg")
            try FileManager.default.copyItem(at: photo, to: url)
            try ImageXMP.writeMetadata(template, url: url)
            try FileManager.default.removeItem(at: url)
        }

        let size = try FileManager.default.attributesOfItem(atPath: photo.path)[.size] as? Int ?? 0
        #expect(size > 5_000_000)
        #expect(grown < 50, "grew \(Int(grown)) MB over 40 files")
    }
}
