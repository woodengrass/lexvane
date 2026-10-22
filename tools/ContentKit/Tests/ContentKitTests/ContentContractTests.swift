import Foundation
import XCTest
import ContentCLI
@testable import ContentModel

final class ContentContractTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    private var examples: URL { root.appendingPathComponent("content/contracts/v1/examples") }
    private func fixture(_ kind: String, valid: Bool = true) throws -> Data {
        try Data(contentsOf: examples.appendingPathComponent("\(valid ? "valid" : "invalid")/\(kind).jsonl"))
    }
    // Mutations are raw, unvalidated input, never a content model.
    private func changed(_ data: Data, _ mutate: (inout [String: Any]) -> Void) throws -> Data {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&raw)
        return try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private func changePayload(_ data: Data, _ mutate: (inout [String: Any]) -> Void) throws -> Data {
        try changed(data) { raw in
            var payload = raw["payload"] as! [String: Any]
            mutate(&payload); raw["payload"] = payload
        }
    }
    private func rejected(_ data: Data, reason: String? = nil) {
        XCTAssertThrowsError(try ContractJSON.decode(data)) { error in
            if let reason { XCTAssertTrue(String(describing: error).contains(reason), "\(error)") }
        }
    }
    func testEveryKindHasPositiveAndNegativeFixture() throws {
        for kind in ContractKind.allCases {
            _ = try ContractJSON.decode(fixture(kind.rawValue))
            rejected(try fixture(kind.rawValue, valid: false))
        }
    }
    func testHintFieldRejected() throws {
        for key in ["pre_answer_hint", "pre-answer-hint", "preAnswerHint", "hint"] {
            rejected(try changePayload(fixture("question")) { $0[key] = "answer leak" }, reason: "unknown_field")
        }
        rejected(try changePayload(fixture("question")) { payload in
            var feedback = payload["post_answer_feedback"] as! [String: Any]
            feedback["pre_answer_hint"] = "leak"; payload["post_answer_feedback"] = feedback
        }, reason: "unknown_field")
    }
    func testUnknownSchemaRejected() throws {
        for kind in ContractKind.allCases {
            rejected(try changed(fixture(kind.rawValue)) { $0["schema"] = "lexvane.content.v99" }, reason: "unknown_schema")
        }
    }
    func testMissingPrimaryTargetRejected() throws {
        rejected(try changePayload(fixture("question")) { $0.removeValue(forKey: "primary_target_id") })
    }
    func testFeedbackRequired() throws {
        rejected(try changePayload(fixture("question")) { $0.removeValue(forKey: "post_answer_feedback") })
        rejected(try changePayload(fixture("question")) { $0["post_answer_feedback"] = ["answer": "", "explanation": ""] })
    }
    func testCaseInsensitiveVariantDoesNotMergeDistinctWords() throws {
        let entry = try fixture("entry")
        rejected(try changePayload(entry) { payload in
            payload["variants"] = [["text": "from", "entry_id": "lx:word:00000000-0000-0000-0000-000000000002"]]
        }, reason: "variant_identity_mismatch")
        // Case collisions are legal across independent identities; never union them.
        let first = try ContractJSON.decode(entry)
        let second = try ContractJSON.seal(try changed(entry) { raw in
            raw["record_id"] = "lx:word:00000000-0000-0000-0000-000000000002"
            var payload = raw["payload"] as! [String: Any]
            payload["lemma"] = "FORM"; payload["aliases"] = []; payload["variants"] = []
            raw["payload"] = payload
        })
        XCTAssertNotEqual(first.recordId, second.recordId)
        XCTAssertEqual(try ContractDataset.validateEntries([first, second]), 2)
    }
    func testCanonicalRoundTripHashStable() throws {
        for kind in ContractKind.allCases {
            let record = try ContractJSON.decode(fixture(kind.rawValue))
            let bytes = try ContractJSON.line(record)
            XCTAssertEqual(bytes.last, 10)
            XCTAssertFalse(bytes.contains(13))
            XCTAssertEqual(bytes, try ContractJSON.line(ContractJSON.decode(bytes)))
            XCTAssertEqual(record.contentSha256, try ContractJSON.revisionHash(record))
            XCTAssertEqual(bytes, try fixture(kind.rawValue))
        }
    }
    func testChoiceMeaningWritingRemainSeparate() throws {
        let names = ["question", "question-meaning", "question-writing"]
        let abilities = try names.map { name -> TestedAbility in
            guard case .question(let document) = try ContractJSON.decode(fixture(name)) else {
                throw ContractFailure("not_question")
            }
            return document.payload.testedAbility
        }
        XCTAssertEqual(abilities, [.contextualChoice, .meaningRecognition, .writing])
        XCTAssertEqual(Set(abilities).count, 3)
    }
    func testRequiredFieldsAndEnumsForEveryKind() throws {
        for kind in ContractKind.allCases {
            let data = try fixture(kind.rawValue)
            for key in ["schema", "kind", "record_id", "revision", "content_sha256", "payload"] {
                rejected(try changed(data) { $0.removeValue(forKey: key) })
            }
            rejected(try changed(data) { $0["kind"] = "future" })
            rejected(try changed(data) { $0["revision"] = 0 })
            rejected(try changed(data) { $0["content_sha256"] = String(repeating: "0", count: 64) }, reason: "hash_mismatch")
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let payload = try XCTUnwrap(raw["payload"] as? [String: Any])
            for key in payload.keys {
                rejected(try changePayload(data) { $0.removeValue(forKey: key) })
            }
        }
        for key in ["tested_ability", "split", "status"] {
            rejected(try changePayload(fixture("question")) { $0[key] = "future" })
        }
        for key in ["family_id", "provenance_refs", "distractor_rationales"] {
            rejected(try changePayload(fixture("question")) { $0.removeValue(forKey: key) })
        }
        let enums: [String: [String]] = [
            "entry": ["entry_kind", "status"], "sense": ["pos", "priority_tier", "status"],
            "target": ["activation", "tested_ability", "priority_tier", "status"],
            "teaching": ["tested_ability", "status"], "review": ["verdict", "subject_kind"],
            "provenance": ["subject_kind"], "manifest": ["build_mode", "policy_version"],
        ]
        for (kind, keys) in enums {
            for key in keys { rejected(try changePayload(fixture(kind)) { $0[key] = "future" }) }
        }
    }
    func testNoHiddenTimeAndRevisionHashChangesWithContent() throws {
        let data = try fixture("entry")
        let a = try ContractJSON.seal(data)
        let b = try ContractJSON.seal(data)
        XCTAssertEqual(a.contentSha256, b.contentSha256)
        let c = try ContractJSON.seal(try changePayload(data) { $0["lemma"] = "forms" })
        XCTAssertNotEqual(a.contentSha256, c.contentSha256)
        rejected(try changed(data) { $0["generated_at"] = "2026-10-11T00:00:00Z" }, reason: "unknown_field")
        let manifest = try fixture("manifest")
        let original = try ContractJSON.seal(manifest)
        let later = try ContractJSON.seal(try changePayload(manifest) { $0["fixed_input_time"] = "2026-10-12T00:00:00Z" })
        XCTAssertNotEqual(original.contentSha256, later.contentSha256)
    }
    func testNestedEnumsAndChoiceConstraints() throws {
        for (kind, array, key) in [("provenance", "fields", "method"), ("review", "checklist", "result"),
                                   ("review", "findings", "severity"), ("review", "findings", "state"),
                                   ("manifest", "counts", "kind")] {
            rejected(try changePayload(fixture(kind)) { payload in
                var values = payload[array] as! [[String: Any]]
                values[0][key] = "future"; payload[array] = values
            })
        }
        rejected(try changePayload(fixture("sense")) { payload in
            var values = payload["source_refs"] as! [[String: Any]]
            values[0]["operations"] = ["future"]; payload["source_refs"] = values
        })
        rejected(try changePayload(fixture("question")) { $0["distractor_rationales"] = [] }, reason: "distractor_rationale_required")
        rejected(try changePayload(fixture("question")) { $0["accepted_answers"] = ["unknown-option"] }, reason: "choice_answers_required")
        rejected(try changePayload(fixture("question")) { $0["tested_ability"] = "writing" }, reason: "writing_not_choice")
    }
    func testTrialPolicyContainsOnlyHardGates() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("content/policies/pilot-trial-v0.json"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(raw.keys), ["schema", "profile", "active_target_gates"])
        XCTAssertEqual(raw["profile"] as? String, "pilot-trial-v0")
        let gates = try XCTUnwrap(raw["active_target_gates"] as? [String: Any])
        XCTAssertEqual(Set(gates.keys), ["minimum_train_questions", "minimum_check_families", "independent_check_family_required",
                                        "complete_review", "complete_feedback", "complete_provenance", "unresolved_critical_maximum"])
        XCTAssertEqual(gates["minimum_train_questions"] as? Int, 1)
        XCTAssertEqual(gates["minimum_check_families"] as? Int, 1)
        XCTAssertEqual(gates["unresolved_critical_maximum"] as? Int, 0)
        for key in ["independent_check_family_required", "complete_review", "complete_feedback", "complete_provenance"] {
            XCTAssertEqual(gates[key] as? Bool, true)
        }
    }
    func testCLISharedFixturesAndFailurePreserveInputs() throws {
        let directory = root.appendingPathComponent("tools/ContentKit/Tests/ContentKitTests/Fixtures/contracts/valid")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let evidence = temp.appendingPathComponent("evidence.json")
        XCTAssertEqual(CKCLI.run(["validate", "--dataset", directory.path, "--stage", "candidate", "--evidence", evidence.path]), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: evidence.path))
        let receiptBytes = try Data(contentsOf: evidence)
        let bad = temp.appendingPathComponent("bad")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        let badBytes = try fixture("question", valid: false)
        let input = bad.appendingPathComponent("questions.jsonl")
        try badBytes.write(to: input)
        XCTAssertEqual(CKCLI.run(["validate", "--dataset", bad.path, "--stage", "candidate", "--evidence", evidence.path]), 65)
        XCTAssertEqual(try Data(contentsOf: input), badBytes)
        XCTAssertEqual(try Data(contentsOf: evidence), receiptBytes)
        XCTAssertEqual(CKCLI.run(["validate", "--dataset", directory.path, "--stage", "candidate"]), 65)
        XCTAssertEqual(CKCLI.run(["validate", "--dataset", directory.path, "--stage", "approved", "--evidence", evidence.path]), 65)
        XCTAssertEqual(CKCLI.run(["validate", "--dataset", directory.path, "--stage", "candidate", "--evidence", directory.appendingPathComponent("entry.jsonl").path]), 65)
    }
    func testMalformedJSONLRejected() throws {
        rejected(Data([0xff, 10]), reason: "invalid_utf8")
        rejected(Data("{}\r\n".utf8), reason: "invalid_line")
    }
}
