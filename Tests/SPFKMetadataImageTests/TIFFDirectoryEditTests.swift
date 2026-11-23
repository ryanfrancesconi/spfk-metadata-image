// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import SPFKTesting
import Testing
@testable import SPFKMetadataImage

struct TIFFDirectoryEditTests {
    private static var exif: Data {
        get throws {
            // Rebased: a chunk payload is a slice whose indices start at its file offset.
            try Data(#require(try WebPContainer(data: Data(contentsOf: TestBundleResources.shared.webp_exif_xmp)).exif))
        }
    }

    @Test func absentTagsLeaveTheBlobAlone() throws {
        #expect(try TIFFDirectoryEdit.removingIFD0Entries([0x9999], from: Self.exif) == nil)
    }

    /// Nothing before the end of the original blob moves except zeroed bytes and the header's
    /// IFD0 offset, so every other offset stays valid.
    @Test func onlyZeroesAndTheHeaderChangeInPlace() throws {
        let original = try Self.exif
        let edited = try #require(try TIFFDirectoryEdit.removingIFD0Entries([0x010E], from: original))

        #expect(edited.count > original.count)
        for index in 8 ..< original.count where edited[index] != original[index] {
            #expect(edited[index] == 0, "byte \(index) changed to a nonzero value")
        }
        #expect(edited.range(of: Data("EXIF description".utf8)) == nil)
        #expect(edited.range(of: Data("EXIF copyright".utf8)) != nil)
    }

    @Test func anEXIFPrefixIsKept() throws {
        let prefix = Data("Exif\0\0".utf8)
        let edited = try #require(try TIFFDirectoryEdit.removingIFD0Entries([0x8298], from: prefix + Self.exif))

        #expect(edited.prefix(6) == prefix)
        #expect(edited.range(of: Data("EXIF copyright".utf8)) == nil)
        #expect(edited.range(of: Data("EXIF description".utf8)) != nil)
    }

    @Test func rejectsANonTIFFBlob() {
        #expect(throws: TIFFDirectoryEdit.ParseError.notTIFF) {
            try TIFFDirectoryEdit.removingIFD0Entries([0x010E], from: Data("not a tiff blob".utf8))
        }
    }
}
