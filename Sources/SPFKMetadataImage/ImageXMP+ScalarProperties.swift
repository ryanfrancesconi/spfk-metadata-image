// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

extension ImageXMP {
    /// Sets each plain scalar property in one namespace that has a value and removes each that is
    /// `nil`, preserving everything else on the file.
    ///
    /// - Parameter values: local name to value, e.g. `["scene": "A1", "shotDate": nil]`.
    public static func writeScalarProperties(
        namespace: String,
        prefix: String,
        values: [String: String?],
        url: URL
    ) throws {
        var writes: [MetadataWrite] = []
        var clearingPaths: [String] = []

        for (name, value) in values.sorted(by: { $0.key < $1.key }) {
            if let value {
                writes.append(.namespacedTag(
                    namespace: namespace as CFString, prefix: prefix as CFString,
                    name: name, value: value as CFString, isAlternateText: false
                ))
            } else {
                clearingPaths.append("\(prefix):\(name)")
            }
        }

        try writeTags(writes, clearingPaths: clearingPaths, namespacesToRegister: [(namespace, prefix)], url: url)
    }
}
