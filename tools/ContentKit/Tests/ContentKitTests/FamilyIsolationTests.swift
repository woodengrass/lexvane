import ContentModel
import Foundation
import XCTest
@testable import ContentCLI

final class FamilyIsolationTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ mode: String = "consistent", minimum: Int? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dataset"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("reviews"), withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/reviews/valid/dataset")
        let records = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.flatMap { file in
                try CKJSONL.readLines(at: file).map { try ContractJSON.decode(Data($0.utf8)) }
            }
        let target = try XCTUnwrap(records.compactMap { record -> Target? in
            if case .target(let t) = record, t.payload.activation == .active,
               t.payload.testedAbility != .writing { return t }; return nil
        }.sorted { $0.recordId < $1.recordId }.first)
        let owned = records.filter { record in
            switch record {
            case .question(let q): return q.payload.primaryTargetId == target.recordId
            case .teaching(let t): return t.payload.primaryTargetId == target.recordId
            default: return false
            }
        }
        let train = try XCTUnwrap(owned.compactMap { record -> Question? in
            if case .question(let q) = record, q.payload.split == .train { return q }; return nil
        }.first)
        let originalCheck = try XCTUnwrap(owned.compactMap { record -> Question? in
            if case .question(let q) = record, q.payload.split == .check { return q }; return nil
        }.first)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractJSON.bytes(originalCheck)) as? [String: Any])
        var payload = try XCTUnwrap(raw["payload"] as? [String: Any])
        payload["stem"] = mode == "renamed" ? "Daniel carried the basket home." : "A storm damaged the bridge overnight."
        raw["payload"] = payload
        let checkRecord = try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw))
        guard case .question(let check) = checkRecord else { return root }
        var selected: [ContractRecord] = [.target(target), .question(train)]
        var teachings = owned.filter { if case .teaching = $0 { return true }; return false }
        if mode == "teaching" || mode == "renamed" {
            let base = mode == "teaching" ? try XCTUnwrap(teachings.first) : ContractRecord.question(train)
            var doc = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractJSON.bytes(base)) as? [String: Any])
            var body = try XCTUnwrap(doc["payload"] as? [String: Any])
            if mode == "teaching" {
                body["examples"] = [["english": check.payload.stem, "zh_hant": "例句"]]
            } else { body["stem"] = "Maya carried the basket home." }
            doc["payload"] = body
            let changed = try ContractJSON.seal(JSONSerialization.data(withJSONObject: doc))
            if mode == "teaching" { teachings = [changed] } else { selected[1] = changed }
        }
        selected += teachings
        if mode != "short" { selected.append(checkRecord) }
        var bytes = Data()
        for record in selected { bytes.append(try ContractJSON.line(record)) }
        try bytes.write(to: root.appendingPathComponent("dataset/records.jsonl"))
        func binding(_ record: ContractRecord) -> [String: Any] {
            ["record_id": record.recordId, "revision": record.document.revision, "content_sha256": record.contentSha256]
        }
        let row: [String: Any] = ["target_id": target.recordId,
            "train_family": train.payload.familyId, "check_family": check.payload.familyId,
            "verdict": "independent", "evidence": "Compared full current questions and teaching.",
            "evaluator_session": "family-review", "finding_ids": [],
            "current_member_bindings": ["train": binding(selected[1]), "check": binding(checkRecord)],
            "current_teaching_bindings": teachings.map(binding)]
        try (JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) + Data([10]))
            .write(to: root.appendingPathComponent("reviews/family-verdicts.jsonl"))
        var profile = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repository.appendingPathComponent("content/policies/pilot-quality-v1.json"))) as? [String: Any])
        if let minimum {
            var minimums = try XCTUnwrap(profile["per_ability_minimums"] as? [String: Any])
            minimums[target.payload.testedAbility.rawValue] = ["train_families": 1, "independent_check_families": minimum]
            profile["per_ability_minimums"] = minimums
        }
        try JSONSerialization.data(withJSONObject: profile).write(to: root.appendingPathComponent("profile.json"))
        return root
    }

    private func run(_ root: URL) -> Int32 {
        CKCLI.run(["families", "audit", "--dataset", root.appendingPathComponent("dataset").path,
                   "--reviews", root.appendingPathComponent("reviews").path,
                   "--profile", root.appendingPathComponent("profile.json").path,
                   "--evidence", root.appendingPathComponent("report.json").path])
    }
    private func audit(_ root: URL) throws -> FamiliesAuditReport {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let profile = try decoder.decode(QualityProfile.self, from: Data(contentsOf: root.appendingPathComponent("profile.json")))
        return try FamiliesAudit.audit(dataset: root.appendingPathComponent("dataset"), reviews: root.appendingPathComponent("reviews"), profile: profile)
    }
    private func rejection(_ root: URL, containing reason: String) {
        XCTAssertThrowsError(try audit(root)) {
            guard let failure = $0 as? FamiliesFailure else { return XCTFail("Unexpected failure: \($0)") }
            XCTAssertTrue(failure.reason.contains(reason), failure.reason)
        }
        XCTAssertEqual(run(root), 65)
    }
    private func changeJSON(_ root: URL, path: String, _ change: (inout [String: Any]) throws -> Void) throws {
        let file = root.appendingPathComponent(path)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        try change(&raw)
        try (JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]) + Data([10])).write(to: file)
    }
    func testRenamedPersonIsNotNewFamily() throws { rejection(try fixture("renamed"), containing: "train-template:") }
    func testTeachingExampleCannotBeUnseenCheck() throws { rejection(try fixture("teaching"), containing: "teaching-example:") }
    func testInsufficientCheckStockFails() throws { rejection(try fixture("short"), containing: "check_supply_short:") }
    func testProfileMinimumIsAppliedToEachActiveTarget() throws {
        XCTAssertEqual(run(try fixture()), 0)
        XCTAssertEqual(run(try fixture(minimum: 2)), 65)
    }
    func testEveryCurrentCheckRequiresBoundVerdict() throws {
        let root = try fixture()
        try FileManager.default.removeItem(at: root.appendingPathComponent("reviews/family-verdicts.jsonl"))
        rejection(root, containing: "missing_current_family_verdict:")
    }
    func testStaleVerdictCannotCountAsSupply() throws {
        let root = try fixture()
        try changeJSON(root, path: "reviews/family-verdicts.jsonl") { row in
            var bindings = try XCTUnwrap(row["current_member_bindings"] as? [String: [String: Any]])
            bindings["check"]?["revision"] = 999
            row["current_member_bindings"] = bindings
        }
        rejection(root, containing: "missing_current_family_verdict:")
    }
    func testContaminatedVerdictReportsFindingID() throws {
        let root = try fixture()
        try changeJSON(root, path: "reviews/family-verdicts.jsonl") {
            $0["verdict"] = "contaminated"
            $0["finding_ids"] = ["finding-contamination-1"]
        }
        rejection(root, containing: "finding-contamination-1")
    }
    func testUnlistedWritingTargetStillRequiresSupply() throws {
        let root = try fixture()
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/contracts/valid/target-writing.jsonl")
        let record = try ContractJSON.decode(Data(contentsOf: source))
        try ContractJSON.line(record).write(to: root.appendingPathComponent("dataset/writing.jsonl"))
        rejection(root, containing: "check_supply_short:\(record.recordId)")
        try changeJSON(root, path: "profile.json") { $0["excluded_target_ids"] = [record.recordId] }
        XCTAssertEqual(run(root), 0)
    }
    func testNonWritingTargetCannotBeExcluded() throws {
        let root = try fixture("short")
        let rows = try CKJSONL.readLines(at: root.appendingPathComponent("dataset/records.jsonl"))
        let target = try ContractJSON.decode(Data(try XCTUnwrap(rows.first).utf8))
        try changeJSON(root, path: "profile.json") { $0["excluded_target_ids"] = [target.recordId] }
        rejection(root, containing: "only_writing_target_may_be_excluded:")
    }
    // F2-02: this formerly asserted success for unbound evidence. Strengthened
    // to rejection; historical verdict files must never be auto-migrated.
    func testFlatFrozenVerdictWithoutEmbeddedBindingsIsRejected() throws {
        let root = try fixture()
        try changeJSON(root, path: "reviews/family-verdicts.jsonl") {
            $0.removeValue(forKey: "current_member_bindings")
            $0.removeValue(forKey: "current_teaching_bindings")
            $0["batch_id"] = "pilot-230-family-test-01"
            $0["prompt_version"] = "family-review-v1"
        }
        rejection(root, containing: "missing_family_bindings:")
    }
    func testMissingMemberBindingsCannotWaiveTeachingBindings() throws {
        let root = try fixture()
        try changeJSON(root, path: "reviews/family-verdicts.jsonl") { $0.removeValue(forKey: "current_member_bindings") }
        rejection(root, containing: "missing_family_bindings:")
    }
    func testMissingTeachingBindingsCannotWaiveMemberBindings() throws {
        let root = try fixture()
        try changeJSON(root, path: "reviews/family-verdicts.jsonl") { $0.removeValue(forKey: "current_teaching_bindings") }
        rejection(root, containing: "missing_family_bindings:")
    }
    func testPartialMemberBindingsAreRejected() throws {
        let root = try fixture()
        try changeJSON(root, path: "reviews/family-verdicts.jsonl") { row in
            var members = try XCTUnwrap(row["current_member_bindings"] as? [String: Any])
            members.removeValue(forKey: "train"); row["current_member_bindings"] = members
        }
        rejection(root, containing: "missing_current_family_verdict:")
    }
    private func reviseSubject(_ root: URL, kind: String) throws {
        let file = root.appendingPathComponent("dataset/records.jsonl")
        var output = Data()
        for line in try CKJSONL.readLines(at: file) {
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            var payload = try XCTUnwrap(raw["payload"] as? [String: Any])
            if raw["kind"] as? String == kind && (kind == "teaching" || payload["split"] as? String == "check") {
                raw["revision"] = (try XCTUnwrap(raw["revision"] as? Int)) + 1
                if kind == "question" { payload["stem"] = "The satellite transmitted a signal before dawn." }
                else { payload["examples"] = [["english": "A newly authored teaching example.", "zh_hant": "新例句"]] }
                raw["payload"] = payload
                output.append(try ContractJSON.line(ContractJSON.seal(JSONSerialization.data(withJSONObject: raw))))
            } else { output.append(Data((line + "\n").utf8)) }
        }
        try output.write(to: file)
    }
    func testUnboundVerdictStillFailsAfterQuestionRevisionProbe() throws {
        let root = try fixture()
        try changeJSON(root, path: "reviews/family-verdicts.jsonl") {
            $0.removeValue(forKey: "current_member_bindings"); $0.removeValue(forKey: "current_teaching_bindings")
        }
        let file = root.appendingPathComponent("reviews/family-verdicts.jsonl")
        let before = try Data(contentsOf: file)
        try reviseSubject(root, kind: "question")
        rejection(root, containing: "missing_family_bindings:")
        XCTAssertEqual(try Data(contentsOf: file), before)
        print("UNBOUND_VERDICT_UNCHANGED_SHA256=\(CKHash.sha256Hex(of: before))")
    }
    func testQuestionRevisionCannotInheritBoundVerdict() throws {
        let root = try fixture()
        try reviseSubject(root, kind: "question")
        rejection(root, containing: "missing_current_family_verdict:")
    }
    func testTeachingRevisionCannotInheritBoundVerdict() throws {
        let root = try fixture()
        try reviseSubject(root, kind: "teaching")
        rejection(root, containing: "missing_current_family_verdict:")
    }
    func testMultiRevisionDatasetOverlaysToCurrentRevision() throws {
        let root = try fixture()
        let dataset = root.appendingPathComponent("dataset/records.jsonl")
        let lines = try CKJSONL.readLines(at: dataset)
        var raw = try XCTUnwrap(lines.compactMap { line -> [String: Any]? in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["kind"] as? String == "question",
                  (object["payload"] as? [String: Any])?["split"] as? String == "check" else { return nil }
            return object
        }.first)
        raw["revision"] = (try XCTUnwrap(raw["revision"] as? Int)) + 1
        var payload = try XCTUnwrap(raw["payload"] as? [String: Any])
        payload["stem"] = "A storm damaged the bridge overnight, revised."
        raw["payload"] = payload
        let newer = try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw))
        try (ContractJSON.line(newer)).write(to: root.appendingPathComponent("dataset/records-r2.jsonl"))
        rejection(root, containing: "missing_current_family_verdict:")
    }
}
