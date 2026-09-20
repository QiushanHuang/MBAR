import XCTest
@testable import MBARCore

final class EmbeddedIconTests: XCTestCase {
    let digest = "c3ee047ccab9d3a0382a5bc6268545cdee6e85c7cf48204bd803842a1f753112"
    func testRejectsLookalikeAndFindsVerifiedFullResource() {
        let payload = Data("ICONcomplete-payload".utf8)
        let binary = Data("prefixICONwrongxxxpadding".utf8) + payload + Data("suffix".utf8)
        XCTAssertEqual(EmbeddedIcon.extract(from: binary, prefix: Data("ICON".utf8), length: payload.count, sha256: digest), payload)
    }
    func testTruncatedResourceIsNotReturnedAsCompleteImage() {
        XCTAssertNil(EmbeddedIcon.extract(from: Data("ICONpartial".utf8), prefix: Data("ICON".utf8), length: 20, sha256: digest))
        XCTAssertNil(EmbeddedIcon.extract(from: Data("ICONcomplete-payloae".utf8), prefix: Data("ICON".utf8), length: 20, sha256: digest))
    }
}
