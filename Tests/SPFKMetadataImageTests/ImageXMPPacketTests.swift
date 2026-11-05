// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-metadata-image

import Foundation
import ImageIO
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKMetadataImage

/// A still's XMP as text, and the modeled fields read back from text.
@Suite(.tags(.xmp))
final class ImageXMPPacketTests: BinTestCase {
    @Test(arguments: [TestBundleResources.shared.sharksandwich, TestBundleResources.shared.sharksandwich_heic])
    func aWrittenTitleIsInThePacketAndReadsBackFromIt(fixture: URL) throws {
        deleteBinOnExit = true
        let url = try copyToBin(url: fixture)
        try ImageXMP.writeMetadata(XMPMetadata(keywords: ["shark"], title: "Sandwich"), url: url)

        let packet = try #require(try ImageXMP.packet(from: url))
        let read = try #require(ImageXMP.readMetadata(fromPacket: packet))

        #expect(read.title == "Sandwich")
        #expect(read.keywords == ["shark"])
    }

    @Test func aToolkitStylePacketWithItsWrapperParses() throws {
        let packet = """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"><xmp:Rating>4</xmp:Rating></rdf:Description>
        </rdf:RDF></x:xmpmeta>
        <?xpacket end="w"?>
        """

        #expect(ImageXMP.readMetadata(fromPacket: packet)?.rating == 4)
    }

    @Test func textThatIsNotXMPReadsAsNil() {
        #expect(ImageXMP.readMetadata(fromPacket: "<unterminated") == nil)
    }

    @Test func aScalarRemovalLeavesTheOtherScalarsAndTheTitle() throws {
        deleteBinOnExit = true
        let url = try copyToBin(url: TestBundleResources.shared.sharksandwich_heic)
        let ns = "http://ns.adobe.com/xmp/1.0/DynamicMedia/"
        try ImageXMP.writeMetadata(XMPMetadata(title: "Sandwich"), url: url)
        try ImageXMP.writeScalarProperties(namespace: ns, prefix: "xmpDM", values: ["scene": "A1", "shotLocation": "Stage 4"], url: url)

        try ImageXMP.writeScalarProperties(namespace: ns, prefix: "xmpDM", values: ["scene": nil], url: url)

        let packet = try #require(try ImageXMP.packet(from: url))
        #expect(!packet.contains("xmpDM:scene"))
        #expect(packet.contains("Stage 4"))
        #expect(try ImageXMP.readMetadata(from: url).title == "Sandwich")
    }
}
