import XCTest
@testable import MBARCore

final class ASARResourceTests: XCTestCase {
    private func archive(offset: String = "0", size: Int = 3, unpacked: Bool = false) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: ["files": ["icons": ["files": ["tray.png": ["size": size, "offset": offset, "unpacked": unpacked]]]]])
        let padding = (4 - ((json.count + 4) % 4)) % 4
        var bytes = Data()
        for n in [4, json.count + padding + 8, json.count + padding + 4, json.count] {
            var value = UInt32(n).littleEndian; withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
        }
        bytes.append(json); bytes.append(Data(repeating: 0, count: padding)); bytes.append(Data("abc".utf8))
        return bytes
    }
    func testReadsNamedResourceWithoutDependingOnArchiveOffsets() throws {
        XCTAssertEqual(ASARResource.extract(from: try archive(), path: "icons/tray.png"), Data("abc".utf8))
    }
    func testRejectsTruncationOverflowAndUnpackedRedirects() throws {
        XCTAssertNil(ASARResource.extract(from: Data([4,0,0,0]), path: "icons/tray.png"))
        XCTAssertNil(ASARResource.extract(from: try archive(offset: "18446744073709551615"), path: "icons/tray.png"))
        XCTAssertNil(ASARResource.extract(from: try archive(size: 999), path: "icons/tray.png"))
        XCTAssertNil(ASARResource.extract(from: try archive(unpacked: true), path: "icons/tray.png"))
        XCTAssertNil(ASARResource.extract(from: try archive(), path: "../icons/tray.png"))
    }
    func testListsBoundedEntriesAndMarksIncompleteArchive() throws {
        let index = try ASARResource.index(from: archive())
        XCTAssertEqual(index.paths, ["icons/tray.png"])
        XCTAssertTrue(index.complete)
        XCTAssertEqual(index.extract("icons/tray.png"), Data("abc".utf8))
        XCTAssertFalse(try ASARResource.index(from: archive(), maxEntries: 1).complete)
        XCTAssertFalse(try ASARResource.index(from: archive(unpacked: true)).complete)
        XCTAssertThrowsError(try ASARResource.index(from: Data([4, 0, 0, 0])))
    }
}
