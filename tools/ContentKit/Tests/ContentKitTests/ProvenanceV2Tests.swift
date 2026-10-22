import ContentModel
import Foundation
import XCTest

final class ProvenanceV2Tests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func raw(_ kind: String = "provenance") throws -> [String: Any] {
        let url = root.appendingPathComponent("content/contracts/v1/examples/valid/\(kind).jsonl")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func seal(_ raw: [String: Any]) throws -> ContractRecord {
        try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes]))
    }

    private func v2(origin: String = "unverified", method: String = "ai_generated",
                    external: [[String: Any]] = [], internalRefs: [[String: Any]] = [],
                    unverified: [[String: Any]] = [["original_source_id": "S-unknown", "operations": ["reference"],
                                                   "reason": "Historical identifier has no registry entry; origin unverified."]]) throws -> [String: Any] {
        var object = try raw()
        object["schema"] = "lexvane.provenance.v2"
        var payload = try XCTUnwrap(object["payload"] as? [String: Any])
        let original = try XCTUnwrap(payload["fields"] as? [[String: Any]])
        payload["fields"] = original.map { field in
            ["field": field["field"] as! String, "method": method, "origin": origin,
             "external_source_refs": external, "internal_evidence_refs": internalRefs,
             "unverified_refs": unverified] as [String: Any]
        }
        object["payload"] = payload
        return object
    }

    func testV1StillRequiresNonemptySourcesAndRejectsV2Fields() throws {
        for replacement: [String: Any] in [
            ["field": "lemma", "method": "ai_generated", "source_refs": []],
            ["field": "lemma", "method": "ai_generated", "source_refs": [["source_id": "S01", "operations": ["reference"]]], "origin": "generated"],
        ] {
            var object = try raw()
            var payload = try XCTUnwrap(object["payload"] as? [String: Any])
            payload["fields"] = [replacement]; object["payload"] = payload
            XCTAssertThrowsError(try seal(object))
        }
    }

    func testV2IsProvenanceOnlyAndRejectsAmbiguousLegacyKey() throws {
        for kind in ContractKind.allCases where kind != .provenance {
            var object = try raw(kind.rawValue); object["schema"] = "lexvane.provenance.v2"
            XCTAssertThrowsError(try seal(object))
        }
        var object = try raw(); object["schema"] = "lexvane.provenance.v2"
        XCTAssertThrowsError(try seal(object))
    }

    func testNoExternalRequiresExplicitGeneratedOrUnverifiedRepresentation() throws {
        let unverified = try seal(v2())
        XCTAssertEqual(try ContractJSON.line(unverified), try ContractJSON.line(ContractJSON.decode(ContractJSON.line(unverified))))
        XCTAssertThrowsError(try seal(v2(unverified: [])))
        XCTAssertThrowsError(try seal(v2(origin: "external", unverified: [])))
        XCTAssertThrowsError(try seal(v2(origin: "generated", unverified: [])))
        let work: [[String: Any]] = [["ref": "work/missing.jsonl", "availability": "unresolved", "reason": "Unavailable historical work file; not proof."]]
        _ = try seal(v2(origin: "generated", internalRefs: work, unverified: []))
        XCTAssertThrowsError(try seal(v2(origin: "generated", method: "extract", internalRefs: work, unverified: [])))
    }

    func testUnknownExternalStillFailsGraphAndUnverifiedDoesNotBecomeSource() throws {
        let external = try seal(v2(origin: "external", external: [["source_id": "unknown", "operations": ["reference"]]], unverified: []))
        let report = DatasetValidator.audit(records: [external], sources: [], reviews: [])
        XCTAssertTrue(report.defects.contains { $0.code == .danglingReference && $0.detail == "unknown" })
        let unverified = DatasetValidator.audit(records: [try seal(v2())], sources: [], reviews: [])
        XCTAssertTrue(unverified.defects.contains { $0.code == .evidenceClosure && $0.field.contains("unverified_refs") })
        XCTAssertFalse(unverified.defects.contains { $0.code == .sourcePermission || $0.detail == "S-unknown" })
    }

    func testLocalEvidenceRequiresSafeExistingRegularFileAndExactHash() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = Data("synthetic work evidence, not an execution receipt".utf8)
        try bytes.write(to: dir.appendingPathComponent("work.jsonl"))
        func provenance(ref: String, status: String = "available", hash: String? = nil) throws -> Provenance {
            var evidence: [String: Any] = ["ref": ref, "availability": status, "reason": "Synthetic local work fixture."]
            if let hash { evidence["sha256"] = hash }
            guard case .provenance(let result) = try seal(v2(origin: "generated", internalRefs: [evidence], unverified: [])) else {
                throw ContractFailure("expected_provenance")
            }
            return result
        }
        try ProvenanceValidator.validateLocalEvidence(provenance(ref: "work.jsonl", hash: CKHash.sha256Hex(of: bytes)), base: dir)
        XCTAssertThrowsError(try ProvenanceValidator.validateLocalEvidence(provenance(ref: "missing.jsonl", hash: CKHash.sha256Hex(of: bytes)), base: dir))
        XCTAssertThrowsError(try ProvenanceValidator.validateLocalEvidence(provenance(ref: "work.jsonl", hash: String(repeating: "0", count: 64)), base: dir))
        XCTAssertThrowsError(try ProvenanceValidator.validateLocalEvidence(provenance(ref: "missing.jsonl", status: "unresolved"), base: dir))
        for ref in ["../outside", "/absolute", "https://outside"] {
            XCTAssertThrowsError(try provenance(ref: ref, status: "unresolved"))
        }
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("escape").path, withDestinationPath: "/etc/hosts")
        XCTAssertThrowsError(try ProvenanceValidator.validateLocalEvidence(provenance(ref: "escape", hash: CKHash.sha256Hex(of: bytes)), base: dir))
    }

    func testMaintenanceHistoryIsHashBoundAndCannotInventOriginalRevision() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = try seal(raw())
        let bytes = try ContractJSON.line(original)
        let url = dir.appendingPathComponent("history.jsonl")
        try bytes.write(to: url)
        let cache = try ProvenanceHistory(at: url)
        var object = try v2()
        object["revision"] = original.document.revision + 1
        var payload = try XCTUnwrap(object["payload"] as? [String: Any])
        payload["migration_evidence"] = ["history_ref": "history.jsonl", "history_sha256": CKHash.sha256Hex(of: bytes),
                                         "reason": "Synthetic maintenance history; not author/reviewer execution."]
        object["payload"] = payload
        guard case .provenance(let migrated) = try seal(object) else { throw ContractFailure("expected_provenance") }
        try ProvenanceValidator.validateLocalEvidence(migrated, base: dir, history: cache)
        object["revision"] = original.document.revision + 2
        guard case .provenance(let invented) = try seal(object) else { throw ContractFailure("expected_provenance") }
        XCTAssertThrowsError(try ProvenanceValidator.validateLocalEvidence(invented, base: dir, history: cache))
        try Data("tampered".utf8).write(to: url)
        XCTAssertThrowsError(try ProvenanceValidator.validateLocalEvidence(migrated, base: dir))
    }
}
