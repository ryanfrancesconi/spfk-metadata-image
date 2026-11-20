// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import CoreGraphics
import Foundation
import ImageIO
import SPFKBase
import SPFKMetadataImage
import SPFKTesting
import Testing

@Suite
class ImageXMPCustomPropertyTests: BinTestCase {
    let namespace = "http://ns.example.com/image-xmp-custom-property-tests/1.0/"
    let value = #"{"version":1,"exposure":-1.5}"#

    private func makeJPEG(named name: String, customPrefix: String?) throws -> URL {
        let url = bin.appendingPathComponent("\(name).jpg")

        let context = try #require(CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = try #require(context.makeImage())

        let metadata = CGImageMetadataCreateMutable()
        let creator = try #require(CGImageMetadataTagCreate(
            "http://purl.org/dc/elements/1.1/" as CFString, "dc" as CFString, "source" as CFString,
            .string, "fixture" as CFString
        ))
        #expect(CGImageMetadataSetTagWithPath(metadata, nil, "dc:source" as CFString, creator))

        if let customPrefix {
            #expect(CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace as CFString, customPrefix as CFString, nil))
            let tag = try #require(CGImageMetadataTagCreate(
                namespace as CFString, customPrefix as CFString, "Develop" as CFString, .string, value as CFString
            ))
            #expect(CGImageMetadataSetTagWithPath(metadata, nil, "\(customPrefix):Develop" as CFString, tag))
        }

        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// The read matches on the namespace, so a prefix other than the caller's still reads.
    @Test func readsThePropertyUnderAnyPrefix() throws {
        deleteBinOnExit = true
        let url = try makeJPEG(named: "custom", customPrefix: "elsewhere")

        #expect(try ImageXMP.stringValue(namespace: namespace, name: "Develop", from: url) == value)
        #expect(try ImageXMP.stringValue(namespace: namespace, name: "Other", from: url) == nil)
    }

    @Test func absentPropertyIsNil() throws {
        deleteBinOnExit = true
        let url = try makeJPEG(named: "plain", customPrefix: nil)

        #expect(try ImageXMP.stringValue(namespace: namespace, name: "Develop", from: url) == nil)
    }

    @Test func unreadableFileThrows() throws {
        deleteBinOnExit = true
        let url = bin.appendingPathComponent("garbage.jpg")
        try Data("not an image".utf8).write(to: url)

        #expect(throws: ImageXMP.ImageXMPError.self) {
            try ImageXMP.stringValue(namespace: namespace, name: "Develop", from: url)
        }
    }
}
