import ContentCLI
import ContentModel
import Foundation
import XCTest

final class SourceRegistryTests: XCTestCase {
    private func source(_ id: String, ancestors: [SourceAncestor] = [],
                        status: PermissionStatus = .allowed) -> SourceRecord {
        SourceRecord(sourceID: id, locator: "https://example.org/\(id)", version: "v1",
                     publicationDate: nil, effectiveFrom: nil, effectiveTo: nil,
                     kind: "self_authored", examYear: nil, retrievedAt: "2026-10-11T00:00:00Z",
                     contentSHA256: nil, contentSHA256Reason: "Metadata only; no original retained",
                     attribution: "Author \(id)", licenseTextRef: "license.md",
                     permissions: Dictionary(uniqueKeysWithValues: SourceOperation.allCases.map {
                         ($0.rawValue, SourcePermission(status: status, evidence: "license.md", quote: status == .allowed ? "Fixture grants this operation" : nil))
                     }), ancestors: ancestors)
    }

    private func denied(_ record: SourceRecord, registry: [SourceRecord], purpose: SourcePurpose,
                        reason: SourceGateReason, id: String, privatePreview: Bool = false) {
        XCTAssertThrowsError(try SourcePermissionGate.authorize(sourceID: record.sourceID,
            purpose: purpose, registry: registry, privatePreview: privatePreview)) { error in
            guard let failure = error as? SourceGateFailure else { return XCTFail("Unexpected \(error)") }
            XCTAssertEqual(failure.sourceID, id)
            XCTAssertEqual(failure.purpose, purpose)
            XCTAssertEqual(failure.reason, reason)
        }
    }

    func testApprovedPrivateChainAccepted() throws {
        let root = source("root")
        let middle = source("middle", ancestors: [.init(sourceID: "root", operations: [.retain, .extract])])
        let leaf = source("leaf", ancestors: [.init(sourceID: "middle", operations: [.adapt])])
        let result = try SourcePermissionGate.authorize(sourceID: "leaf", purpose: .privatePreview,
                                                       registry: [leaf, middle, root])
        XCTAssertEqual(result.sourceID, "leaf")
        XCTAssertEqual(result.purpose, .privatePreview)
        XCTAssertEqual(result.reason, "all_required_operations_allowed")
        XCTAssertEqual(result.attributions, ["Author leaf", "Author middle", "Author root"])
    }

    func testPendingAncestorRejected() {
        let root = source("root", status: .pending)
        let middle = source("middle", ancestors: [.init(sourceID: "root", operations: [.extract])])
        let leaf = source("leaf", ancestors: [.init(sourceID: "middle", operations: [.adapt])])
        denied(leaf, registry: [leaf, middle, root], purpose: .privatePreview,
               reason: .permission(.extract, .pending), id: "root")
    }

    func testRejectedSourceRejected() {
        let leaf = source("leaf", status: .rejected)
        denied(leaf, registry: [leaf], purpose: .privatePreview,
               reason: .permission(.privatePack, .rejected), id: "leaf")
    }

    func testPrivatePermissionCannotAuthorizeDistribution() {
        var leaf = source("leaf")
        leaf.permissions[SourceOperation.distribution.rawValue] = .init(status: .pending, evidence: "license.md")
        for purpose in [SourcePurpose.distribution, .production] {
            denied(leaf, registry: [leaf], purpose: purpose,
                   reason: .permission(.distribution, .pending), id: "leaf", privatePreview: true)
        }
    }

    func testMissingAttributionRejected() {
        var leaf = source("leaf")
        leaf.attribution = " "
        denied(leaf, registry: [leaf], purpose: .privatePreview, reason: .missingAttribution, id: "leaf")
    }

    func testUnknownAndMissingOperationsRemainPending() throws {
        var leaf = source("leaf")
        leaf.permissions.removeValue(forKey: "private_pack")
        denied(leaf, registry: [leaf], purpose: .privatePreview,
               reason: .permission(.privatePack, .pending), id: "leaf")
        let permission = try JSONDecoder().decode(SourcePermission.self,
            from: Data(#"{"status":"unrecognized","evidence":"license.md"}"#.utf8))
        XCTAssertEqual(permission.status, .pending)
    }

    func testMissingAncestorAndCycleRejected() {
        let missing = source("leaf", ancestors: [.init(sourceID: "absent", operations: [.adapt])])
        denied(missing, registry: [missing], purpose: .privatePreview, reason: .missingSource, id: "absent")
        let cycle = source("leaf", ancestors: [.init(sourceID: "leaf", operations: [.adapt])])
        denied(cycle, registry: [cycle], purpose: .privatePreview, reason: .cycle, id: "leaf")
    }

    func testDistributionChecksAncestorDistributionToo() {
        var root = source("root")
        root.permissions["distribution"] = .init(status: .rejected, evidence: "license.md")
        let leaf = source("leaf", ancestors: [.init(sourceID: "root", operations: [.adapt])])
        denied(leaf, registry: [leaf, root], purpose: .distribution,
               reason: .permission(.distribution, .rejected), id: "root")
    }

    func testSourceFieldsAndVersionHash() throws {
        var leaf = source("leaf")
        let original = try leaf.sourceVersionHash()
        let data = try JSONEncoder().encode(leaf)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["source_id", "locator", "version", "publication_date", "effective_from", "effective_to",
                    "kind", "exam_year", "retrieved_at", "content_sha256", "content_sha256_reason",
                    "attribution", "license_text_ref", "permissions", "source_version"] {
            XCTAssertNotNil(object[key], key)
        }
        XCTAssertEqual(try JSONDecoder().decode(SourceRecord.self, from: data).sourceVersionHash(), original)
        leaf.retrievedAt = "2026-10-12T00:00:00Z"
        XCTAssertEqual(try leaf.sourceVersionHash(), original, "Retrieval time is not source identity")
        leaf.version = "v2"
        XCTAssertNotEqual(try leaf.sourceVersionHash(), original)
        leaf.contentSHA256 = CKHash.sha256Hex(of: Data("abc".utf8))
        XCTAssertEqual(leaf.contentSHA256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testRegistryEvidenceAndStructureFailures() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("Fixture grants this operation".utf8).write(to: directory.appendingPathComponent("license.md"))
        let registry = directory.appendingPathComponent("registry.jsonl")
        func write(_ record: SourceRecord) throws {
            var data = try JSONEncoder().encode(record); data.append(10); try data.write(to: registry)
        }
        try write(source("leaf", status: .pending))
        let report = try SourceRegistry.validate(at: registry)
        XCTAssertEqual(report.rowCount, 1)
        XCTAssertEqual(report.privatePackAllowedCount, 0)
        XCTAssertFalse(report.allSourcesUsable)
        var bad = source("leaf")
        bad.contentSHA256Reason = nil
        try write(bad)
        XCTAssertThrowsError(try SourceRegistry.validate(at: registry))
        bad = source("leaf"); bad.permissions["adapt"] = .init(status: .allowed, evidence: "license.md")
        try write(bad)
        XCTAssertThrowsError(try SourceRegistry.validate(at: registry))
        bad = source("leaf"); bad.licenseTextRef = "missing.md"
        try write(bad)
        XCTAssertThrowsError(try SourceRegistry.validate(at: registry))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source("leaf"))) as? [String: Any])
        object["source_version"] = String(repeating: "0", count: 64)
        try JSONSerialization.data(withJSONObject: object).write(to: registry)
        XCTAssertThrowsError(try SourceRegistry.validate(at: registry))
    }

    func testCLIValidationSuccessAndTypedFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let inputs = directory.appendingPathComponent("inputs")
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        let registry = inputs.appendingPathComponent("registry.jsonl")
        try Data("Fixture license".utf8).write(to: inputs.appendingPathComponent("license.md"))
        try JSONEncoder().encode(source("leaf", status: .pending)).write(to: registry)
        let evidence = directory.appendingPathComponent("report.json")
        func run() throws -> (Int32, String) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            var environment = ProcessInfo.processInfo.environment
            environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
            environment["TMPDIR"] = directory.path + "/"
            process.environment = environment
            process.arguments = ["xcrun", "swift", "run", "--package-path", package.path, "contentkit",
                                 "sources", "validate", "--registry", registry.path, "--evidence", evidence.path]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (process.terminationStatus, String(decoding: output, as: UTF8.self))
        }
        let success = try run(); XCTAssertEqual(success.0, 0, success.1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: evidence.path))
        let malformed = Data("{}\n".utf8); try malformed.write(to: registry)
        let failure = try run(); XCTAssertNotEqual(failure.0, 0)
        XCTAssertTrue(failure.1.contains("SourceRegistryFailure"), failure.1)
        XCTAssertEqual(try Data(contentsOf: registry), malformed)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: evidence)) as? [String: Any])
        XCTAssertEqual(report["valid"] as? Bool, false)
    }
}
