// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO

extension ImageXMP {
    /// A top-level simple property's string value in any namespace, `nil` when the file has none.
    ///
    /// Matched by namespace URI and name, so the prefix the file declares for it does not matter.
    public static func stringValue(namespace: String, name: String, from url: URL) throws -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete
        else {
            throw ImageXMPError.sourceCreationFailed(url)
        }

        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]
        else {
            return nil
        }

        for tag in tags {
            guard CGImageMetadataTagCopyNamespace(tag) as String? == namespace,
                  CGImageMetadataTagCopyName(tag) as String? == name
            else { continue }

            return CGImageMetadataTagCopyValue(tag) as? String
        }

        return nil
    }
}
