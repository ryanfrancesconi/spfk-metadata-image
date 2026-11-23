// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation

/// Removes entries from the first IFD of a TIFF-structured blob, such as an EXIF payload, without
/// moving any other byte: every offset in a TIFF is absolute from its header, so sub-IFDs and maker
/// notes stay valid only if nothing they point at moves.
///
/// The edited IFD is written at the end of the blob and the header repointed at it. The old IFD and
/// each removed entry's out-of-line value are zeroed, so a removed text does not linger.
enum TIFFDirectoryEdit {
    enum ParseError: Error, Equatable {
        case notTIFF
        case outOfBounds
    }

    /// `blob` without `tags` in IFD0, or `nil` when IFD0 holds none of them. A leading `Exif\0\0`
    /// is kept.
    static func removingIFD0Entries(_ tags: Set<UInt16>, from blob: Data) throws -> Data? {
        var bytes = [UInt8](blob)
        let base = bytes.starts(with: exifPrefix) ? exifPrefix.count : 0

        guard bytes.count >= base + 8 else { throw ParseError.notTIFF }

        let bigEndian: Bool
        switch (bytes[base], bytes[base + 1]) {
        case (0x49, 0x49): bigEndian = false
        case (0x4D, 0x4D): bigEndian = true
        default: throw ParseError.notTIFF
        }

        func integer(at offset: Int, width: Int) -> Int {
            let field = bytes[offset ..< offset + width]
            return (bigEndian ? Array(field) : field.reversed()).reduce(0) { $0 << 8 | Int($1) }
        }

        func encode(_ value: Int, width: Int) -> [UInt8] {
            let field = (0 ..< width).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
            return bigEndian ? field.reversed() : field
        }

        guard integer(at: base + 2, width: 2) == 42 else { throw ParseError.notTIFF }

        let directory = base + integer(at: base + 4, width: 4)
        guard directory >= base + 8, directory + 2 <= bytes.count else { throw ParseError.outOfBounds }

        let entriesEnd = directory + 2 + 12 * integer(at: directory, width: 2)
        guard entriesEnd + 4 <= bytes.count else { throw ParseError.outOfBounds }

        let entries = stride(from: directory + 2, to: entriesEnd, by: 12)
        let removed = entries.filter { tags.contains(UInt16(integer(at: $0, width: 2))) }
        guard !removed.isEmpty else { return nil }

        let kept = entries.filter { !removed.contains($0) }

        func outOfLineValue(_ entry: Int) -> Range<Int>? {
            guard let size = typeSizes[integer(at: entry + 2, width: 2)] else { return nil }

            let length = size * integer(at: entry + 4, width: 4)
            let start = base + integer(at: entry + 8, width: 4)
            guard length > 4, start >= base + 8, start + length <= bytes.count else { return nil }

            return start ..< start + length
        }

        var replacement = encode(kept.count, width: 2)
        kept.forEach { replacement += bytes[$0 ..< $0 + 12] }
        replacement += bytes[entriesEnd ..< entriesEnd + 4]

        let keptValues = kept.compactMap(outOfLineValue)
        for value in removed.compactMap(outOfLineValue) where !keptValues.contains(where: { $0.overlaps(value) }) {
            bytes.replaceSubrange(value, with: repeatElement(0, count: value.count))
        }
        bytes.replaceSubrange(directory ..< entriesEnd + 4, with: repeatElement(0, count: entriesEnd + 4 - directory))

        // An IFD starts on a word boundary.
        if (bytes.count - base) % 2 == 1 { bytes.append(0) }

        bytes.replaceSubrange(base + 4 ..< base + 8, with: encode(bytes.count - base, width: 4))
        bytes += replacement

        return Data(bytes)
    }

    private static let exifPrefix: [UInt8] = Array("Exif\0\0".utf8)

    /// Bytes per value, by TIFF field type (BYTE through DOUBLE, then IFD).
    private static let typeSizes: [Int: Int] = [
        1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 13: 4,
    ]
}
