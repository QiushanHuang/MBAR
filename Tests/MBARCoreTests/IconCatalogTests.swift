import XCTest
@testable import MBARCore

final class IconCatalogTests: XCTestCase {
    func testCatalogMetadataDeduplicatesImagesAndKeepsTemplateEvidence() throws {
        let json = """
        [{"AssetStorageVersion":"test"},
         {"AssetType":"Image","Name":"StatusBarIcon","Template Mode":"template"},
         {"AssetType":"Image","Name":"StatusBarIcon","Scale":2},
         {"AssetType":"Color","Name":"statusColor"},
         {"AssetType":"Image","Name":"../outside"},
         {"AssetType":"Image","Name":"AppIcon"}]
        """
        let listing = try IconCatalog.parse(Data(json.utf8), maxNames: 20)
        XCTAssertEqual(listing.assets.map(\.name), ["AppIcon", "StatusBarIcon"])
        XCTAssertTrue(listing.assets.first(where: { $0.name == "StatusBarIcon" })!.isTemplate)
        XCTAssertFalse(listing.complete) // Invalid image names must not create a false unique match.
        XCTAssertThrowsError(try IconCatalog.parse(Data("{}".utf8), maxNames: 20))
    }
    func testCatalogMetadataLimitCannotClaimComplete() throws {
        let data = Data("[{\"AssetType\":\"Image\",\"Name\":\"a\"},{\"AssetType\":\"Image\",\"Name\":\"b\"}]".utf8)
        XCTAssertFalse(try IconCatalog.parse(data, maxNames: 1).complete)
    }
    func testToolRunnerBoundsOutputAndRuntime() throws {
        XCTAssertEqual(try BoundedToolOutput.run(executable: "/bin/echo", arguments: ["ok"], seconds: 1, maxBytes: 64), Data("ok\n".utf8))
        XCTAssertThrowsError(try BoundedToolOutput.run(executable: "/bin/echo", arguments: [String(repeating: "x", count: 200)], seconds: 1, maxBytes: 16))
        let start = Date()
        XCTAssertThrowsError(try BoundedToolOutput.run(executable: "/bin/sleep", arguments: ["3"], seconds: 0.05, maxBytes: 64))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
    func testRealCatalogCanBeSelectedAndReadBackWithoutLoadingCode() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("CatalogFixture.bundle")
        let resources = fixture.appendingPathComponent("Contents/Resources")
        let scan = IconResourceDiscovery.scan(resources: resources)
        let candidate = try XCTUnwrap(scan.candidates.first(where: { $0.locator == .catalog("StatusBarIcon") }))
        XCTAssertTrue(scan.complete, scan.issues.joined(separator: ";"))
        XCTAssertTrue(candidate.evidence.template)
        XCTAssertNotNil(IconRanker.automaticIndex(scan.candidates.map(\.evidence), complete: scan.complete, itemCount: 1))
        let readback = try XCTUnwrap(IconResourceDiscovery.read(candidate.locator, resources: resources, imports: resources))
        XCTAssertEqual(IconDigest.sha256(readback), candidate.evidence.digest)
        XCTAssertEqual(IconResourceDiscovery.sourceRevision(candidate.locator, resources: resources), candidate.sourceRevision)
        XCTAssertFalse(try XCTUnwrap(Bundle(url: fixture)).isLoaded)
    }
}
