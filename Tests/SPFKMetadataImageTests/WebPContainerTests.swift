// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import CoreGraphics
import Foundation
import ImageIO
import libwebp
import SPFKTesting
import Testing
@testable import SPFKMetadataImage

/// The chunk splice against libwebp's muxer, which is the reference for layout and VP8X flags.
struct WebPContainerTests {
    enum Fixture: String, CaseIterable {
        case simple, losslessAlpha, alpha, exifXMP, iccpEXIFBigEndian, animated, unknownChunk

        var url: URL {
            let resources = TestBundleResources.shared
            return switch self {
            case .simple: resources.webp_simple
            case .losslessAlpha: resources.webp_lossless_alpha
            case .alpha: resources.webp_alpha
            case .exifXMP: resources.webp_exif_xmp
            case .iccpEXIFBigEndian: resources.webp_iccp_exif_mm
            case .animated: resources.webp_animated
            case .unknownChunk: resources.webp_unknown_chunk
            }
        }

        var chunkLayout: [String] {
            switch self {
            case .simple: ["VP8 "]
            case .losslessAlpha: ["VP8L"]
            case .alpha: ["VP8X", "ALPH", "VP8 "]
            case .exifXMP: ["VP8X", "VP8 ", "EXIF", "XMP "]
            case .iccpEXIFBigEndian: ["VP8X", "ICCP", "VP8 ", "EXIF"]
            case .animated: ["VP8X", "ANIM", "ANMF", "ANMF"]
            case .unknownChunk: ["VP8X", "ALPH", "VP8 ", "SPFK"]
            }
        }
    }

    enum Operation: CaseIterable {
        case setXMP, removeXMP, setEXIF, removeEXIF, removeBoth
    }

    /// Odd lengths, so both exercise the pad byte.
    static let newXMP = Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"></x:xmpmeta>\n!".utf8)
    static let newEXIF = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

    @Test(arguments: Fixture.allCases)
    func parsesEveryLayout(fixture: Fixture) throws {
        let container = try WebPContainer(data: Data(contentsOf: fixture.url))
        #expect(container.chunks.map(\.fourCC) == fixture.chunkLayout)
    }

    @Test(arguments: Fixture.allCases, Operation.allCases)
    func matchesTheMuxer(fixture: Fixture, operation: Operation) throws {
        let input = try Data(contentsOf: fixture.url)
        let container = try WebPContainer(data: input)

        let (xmp, exif): (Data?, Data?) = switch operation {
        case .setXMP: (Self.newXMP, container.exif)
        case .removeXMP: (nil, container.exif)
        case .setEXIF: (container.xmpPacket, Self.newEXIF)
        case .removeEXIF: (container.xmpPacket, nil)
        case .removeBoth: (nil, nil)
        }

        let ours = try container.replacing(xmp: xmp, exif: exif)
        let muxed = try Self.mux(input, xmp: xmp, exif: exif)

        #expect(ours == muxed)
        #expect(try WebPContainer(data: ours).xmpPacket == xmp)
        #expect(try WebPContainer(data: ours).exif == exif)
    }

    @Test(arguments: Fixture.allCases)
    func imageDataIsUntouched(fixture: Fixture) throws {
        let input = try Data(contentsOf: fixture.url)
        let output = try WebPContainer(data: input).replacing(xmp: Self.newXMP, exif: Self.newEXIF)

        let imageChunks: Set<String> = ["VP8 ", "VP8L", "ALPH", "ANIM", "ANMF", "ICCP", "SPFK"]
        let before = try Self.chunkBytes(input).filter { imageChunks.contains($0.fourCC) }
        let after = try Self.chunkBytes(output).filter { imageChunks.contains($0.fourCC) }
        #expect(before.map(\.bytes) == after.map(\.bytes))

        #expect(try Self.pixels(input) == Self.pixels(output))
    }

    @Test func removingTheLastMetadataChunkReturnsToSimpleForm() throws {
        let container = try WebPContainer(data: Data(contentsOf: TestBundleResources.shared.webp_exif_xmp))
        let output = try container.replacing(xmp: nil, exif: nil)

        #expect(try WebPContainer(data: output).chunks.map(\.fourCC) == ["VP8 "])
    }

    @Test func synthesizedVP8XCarriesLosslessAlpha() throws {
        let container = try WebPContainer(data: Data(contentsOf: TestBundleResources.shared.webp_lossless_alpha))
        let output = try container.replacing(xmp: Self.newXMP, exif: nil)

        // Flags byte, then reserved bytes, then canvas width-1 and height-1 (24-bit little endian).
        #expect(Array(output[20 ..< 30]) == [0x14, 0, 0, 0, 63, 0, 0, 63, 0, 0])
    }

    @Test func rejectsMalformedContainers() throws {
        let valid = try Data(contentsOf: TestBundleResources.shared.webp_exif_xmp)

        #expect(throws: WebPContainer.ParseError.notWebP) { try WebPContainer(data: Data("RIFF".utf8)) }
        #expect(throws: WebPContainer.ParseError.sizeMismatch) { try WebPContainer(data: valid.dropLast(2)) }

        var truncated = Data(valid.dropLast(2))
        Self.setRIFFSize(&truncated)
        #expect(throws: WebPContainer.ParseError.truncatedChunk(offset: 596)) { try WebPContainer(data: truncated) }

        // A VP8X header and its EXIF, with the image chunk cut out.
        let chunks = try Self.chunkBytes(valid)
        var imageless = Data("RIFF\0\0\0\0WEBP".utf8)
        chunks.filter { $0.fourCC != "VP8 " }.forEach { imageless.append($0.bytes) }
        Self.setRIFFSize(&imageless)
        #expect(throws: WebPContainer.ParseError.missingImage) { try WebPContainer(data: imageless) }
    }

    // MARK: - Helpers

    private static func setRIFFSize(_ data: inout Data) {
        let size = UInt32(data.count - 8)
        for index in 0 ..< 4 { data[data.startIndex + 4 + index] = UInt8(truncatingIfNeeded: size >> (8 * index)) }
    }

    private static func chunkBytes(_ data: Data) throws -> [(fourCC: String, bytes: Data)] {
        let container = try WebPContainer(data: data)
        return container.chunks.map { ($0.fourCC, Data(data[$0.offset ..< $0.offset + $0.diskSize])) }
    }

    private static func pixels(_ data: Data) throws -> Data {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data)
        return Data(bytes: bytes, count: image.height * image.width * 4)
    }

    private struct MuxFailure: Error { let step: String }

    /// `WebPMuxCreate`, then `WebPMuxSetChunk` or `WebPMuxDeleteChunk` per chunk, then `WebPMuxAssemble`.
    private static func mux(_ input: Data, xmp: Data?, exif: Data?) throws -> Data {
        try input.withUnsafeBytes { raw in
            var webP = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: raw.count)
            guard let mux = WebPMuxCreate(&webP, 1) else { throw MuxFailure(step: "create") }
            defer { WebPMuxDelete(mux) }

            for (fourCC, payload) in [("EXIF", exif), ("XMP ", xmp)] {
                if let payload {
                    let error = payload.withUnsafeBytes { bytes in
                        var chunk = WebPData(bytes: bytes.bindMemory(to: UInt8.self).baseAddress, size: bytes.count)
                        return WebPMuxSetChunk(mux, fourCC, &chunk, 1)
                    }
                    guard error == WEBP_MUX_OK else { throw MuxFailure(step: "set \(fourCC)") }
                } else {
                    let error = WebPMuxDeleteChunk(mux, fourCC)
                    guard error == WEBP_MUX_OK || error == WEBP_MUX_NOT_FOUND else { throw MuxFailure(step: "delete \(fourCC)") }
                }
            }

            var output = WebPData()
            guard WebPMuxAssemble(mux, &output) == WEBP_MUX_OK, let bytes = output.bytes else { throw MuxFailure(step: "assemble") }
            defer { WebPDataClear(&output) }
            return Data(bytes: bytes, count: output.size)
        }
    }
}
