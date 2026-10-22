import Foundation
import XCTest
import ContentModel
@testable import ContentCLI

final class PackReaderTests: XCTestCase {
    func testCorruptHashFails() throws {
        let fixture = try Task19Fixture()
        let index = fixture.pack.appendingPathComponent("index.json")
        var bytes = try Data(contentsOf: index)
        bytes[bytes.startIndex] = bytes[bytes.startIndex] == 32 ? 33 : 32
        try bytes.write(to: index)
        let before = try fixture.packBytes()
        XCTAssertThrowsError(try PackageBuilder.verify(fixture.pack)) {
            XCTAssertEqual($0 as? PackageFailure, PackageFailure(reason: "payload_hash_mismatch:index.json"))
        }
        XCTAssertEqual(try fixture.packBytes(), before)
    }

    func testTruncatedJSONFails() throws {
        let fixture = try Task19Fixture()
        // Rebind the transport hash so this reaches JSON decoding, not just hash validation.
        let path = "records/entry.jsonl"
        try fixture.replacePayload(path, bytes: Data("{\"schema\":\n".utf8))
        let before = try fixture.packBytes()
        XCTAssertThrowsError(try PackageBuilder.verify(fixture.pack)) {
            XCTAssertFalse($0 is PackageFailure, "must reach malformed-record decoding")
        }
        XCTAssertEqual(try fixture.packBytes(), before)
    }

    func testNewerSchemaFailsWithoutMutation() throws {
        let fixture = try Task19Fixture()
        try fixture.editManifest { $0["schema"] = "lexvane.private-pack.v2" }
        let before = try fixture.packBytes()
        XCTAssertThrowsError(try PackageBuilder.verify(fixture.pack)) {
            XCTAssertEqual($0 as? PackageFailure, PackageFailure(reason: "invalid_manifest_version_or_policy"))
        }
        XCTAssertEqual(try fixture.packBytes(), before)
    }
}
