import Foundation
import XCTest
import ContentModel
@testable import ContentCLI

final class PackageBuilderTests: XCTestCase {
    private func temporary(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func fixture(_ root: URL, attribution: String = "Fixture author") throws -> PackageSnapshot {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/reviews/valid/dataset")
        let records = try IndexBuild.loadRecords(at: directory).records
        let license = root.appendingPathComponent("license.txt")
        try Data("Fixture grant; not a grant for pilot content.\n".utf8).write(to: license)
        return PackageSnapshot(records: records, sources: [PackageSource(sourceId: "S01",
            sourceVersion: String(repeating: "a", count: 64), attribution: attribution,
            license: try Data(contentsOf: license))], lineage: ["fixture": String(repeating: "b", count: 64)],
            humanReviewPending: true)
    }

    func testMissingAttributionRejectsBuild() throws {
        try temporary { root in
            XCTAssertThrowsError(try PackageBuilder.assemble(fixture(root, attribution: " "),
                mode: "private-preview", out: root.appendingPathComponent("pack"))) {
                XCTAssertEqual($0 as? PackageFailure, PackageFailure(reason: "missing_attribution"))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("pack").path))
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.contains("staging") })
        }
    }

    func testPendingHumanDoesNotBecomeReleaseEligible() throws {
        try temporary { root in
            let pack = root.appendingPathComponent("pack")
            try PackageBuilder.assemble(fixture(root), mode: "private-preview", out: pack)
            let manifest = try PackageBuilder.verify(pack)
            XCTAssertEqual(manifest.buildMode, "private-preview")
            XCTAssertFalse(manifest.releaseEligible)
            XCTAssertTrue(manifest.humanReviewPending)
        }
    }

    func testProductionModeRejected() throws {
        try temporary { root in
            XCTAssertThrowsError(try PackageBuilder.assemble(fixture(root), mode: "production",
                out: root.appendingPathComponent("pack"))) {
                XCTAssertEqual($0 as? PackageFailure, PackageFailure(reason: "production_mode_not_supported"))
            }
        }
    }

    func testExistingOutputRemainsUnchangedOnFailure() throws {
        try temporary { root in
            let pack = root.appendingPathComponent("pack")
            try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: false)
            let sentinel = pack.appendingPathComponent("sentinel")
            let bytes = Data("existing output\n".utf8)
            try bytes.write(to: sentinel)
            XCTAssertThrowsError(try PackageBuilder.assemble(fixture(root), mode: "private-preview", out: pack))
            XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: pack.path), ["sentinel"])
        }
    }

    func testReproducibleAndCorruptionRejectedOffline() throws {
        try temporary { root in
            let snapshot = try fixture(root)
            let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
            try PackageBuilder.assemble(snapshot, mode: "private-preview", out: a)
            try PackageBuilder.assemble(snapshot, mode: "private-preview", out: b)
            try PackageBuilder.compare(a, b)
            try Data("corrupt".utf8).write(to: b.appendingPathComponent("index.json"))
            XCTAssertThrowsError(try PackageBuilder.verify(b))
            XCTAssertThrowsError(try PackageBuilder.compare(a, b))
        }
    }
}
