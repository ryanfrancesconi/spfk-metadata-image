// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO

extension ImageXMP {
    /// The file's XMP as ImageIO serializes it, `nil` when the file has none.
    ///
    /// The packet ImageIO builds from every metadata source it reads, so it also carries values
    /// mirrored from EXIF and TIFF.
    public static func packet(from url: URL) throws -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete
        else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let data = CGImageMetadataCreateXMPData(metadata, nil)
        else {
            return nil
        }

        return String(data: data as Data, encoding: .utf8)
    }

    /// The fields this package supports, read from XMP text rather than a file; `nil` when ImageIO
    /// cannot parse it.
    public static func readMetadata(fromPacket packet: String) -> XMPMetadata? {
        guard let data = packet.data(using: .utf8),
              let metadata = CGImageMetadataCreateFromXMPData(data as CFData)
        else {
            return nil
        }

        return readMetadata(from: metadata)
    }
}
