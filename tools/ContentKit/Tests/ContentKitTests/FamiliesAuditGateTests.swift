import Foundation
import XCTest
@testable import ContentModel
@testable import ContentCLI

/// Family-boundary tests use call-local empty graph reports, not full evidence
/// closure: the fixture's ledger is intentionally invalid and receipts are
/// incomplete. FamiliesAudit and pack assembly still use real disk-backed data.
/// Separate non-injected regressions ensure production rejects this graph.
final class FamiliesAuditGateTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/contracts/valid")
    }

    private struct GateFixture {
        let root: URL
        var dataset: URL { root.appendingPathComponent("dataset") }
        var reviews: URL { root.appendingPathComponent("reviews") }
        var profile: URL { root.appendingPathComponent("profile.json") }
        var sources: URL { root.appendingPathComponent("sources/registry.jsonl") }
        var ledger: URL { root.appendingPathComponent("content/ledger/ledger.json") }
        var contentRoot: URL { root.appendingPathComponent("content") }
        var evidence: URL { root.appendingPathComponent("evidence.json") }
        var out: URL { root.appendingPathComponent("pack") }
    }

    private func question(count: Int = 4, split: String = "check", revision: Int = 1,
                          keys: [String] = ["option-a"], texts: [String]? = nil) throws -> Question {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("question.jsonl"))) as? [String: Any])
        var p = try XCTUnwrap(raw["payload"] as? [String: Any])
        let words = texts ?? Array(["form", "receipt", "menu", "ticket"].prefix(count))
        let ids = ["option-a", "option-b", "option-c", "option-d"]
        p["options"] = words.enumerated().map { ["option_id": ids[$0.offset], "english": $0.element] }
        p["accepted_answers"] = keys
        let rationales = ["An application form collects new details; a receipt records a completed payment.",
            "A menu lists food choices rather than personal application details.",
            "A ticket grants admission or travel rather than collecting a job application."]
        p["distractor_rationales"] = words.enumerated().filter { !keys.contains(ids[$0.offset]) }
            .map { ["option_id": ids[$0.offset], "reason": rationales[max(0, $0.offset - 1)]] }
        p["tested_ability"] = "contextual_choice"
        p["split"] = split
        p["stem"] = split == "train"
            ? "For the job application, fill in each blank on this ___ with your name and address."
            : "At the passport office, enter your personal details in the boxes on this application ___."
        p["post_answer_feedback"] = ["answer": "form", "explanation": "A form has fields for entering requested information."]
        if split == "check" {
            raw["record_id"] = "lx:question:00000000-0000-0000-0000-000000000002"
            p["family_id"] = "lx:family:00000000-0000-0000-0000-000000000002"
        }
        raw["revision"] = revision; raw["payload"] = p
        guard case .question(let q) = try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw)) else {
            throw QualityFailure(reason: "fixture_not_question")
        }
        return q
    }

    private func evidence(_ reason: String) -> QualityEvidence {
        QualityEvidence(passed: true, reason: reason, evidence: ["synthetic-fixture:full-question-and-all-options"])
    }

    private func assessment(_ q: Question) -> QuestionQualityAssessment {
        QuestionQualityAssessment(questionId: q.recordId, revision: q.revision, contentSha256: q.contentSha256,
            authorSession: "fixture-author", evaluatorSession: "fixture-independent-reviewer",
            distractors: q.payload.distractorRationales.map { DistractorAssessment(optionId: $0.optionId,
                plausibility: evidence("Printed everyday documents are plausible to confuse, but: \($0.reason)")) },
            uniqueAnswer: evidence("Only form conventionally completes application form and supplies blank personal-detail fields."),
            noLeakage: evidence("Neither stem spells form nor embeds it in a longer word; feedback is post-answer, and options are parallel document nouns."),
            binaryContrast: nil)
    }

    private func review(_ q: Question) throws -> Review {
        let hash = String(repeating: "a", count: 64)
        let checks = ReviewCoverage.checklistIDs["question"] ?? []
        let raw: [String: Any] = ["schema": "lexvane.content.v1", "kind": "review", "record_id": "reviews/\(q.recordId.split(separator: ":").last!)/passed",
            "revision": 1, "content_sha256": "", "payload": [
                "subject_id": q.recordId, "subject_kind": "question", "subject_revision": q.revision,
                "subject_content_sha256": q.contentSha256, "reviewer_session": "fixture-independent-reviewer",
                "reviewer_model": "fixture", "input_hash": hash, "prompt_hash": hash,
                "checklist": checks.map { ["item": $0, "result": "passed", "reason": "Reviewed full fixture", "source_evidence": ["fixture/question"]] as [String: Any] },
                "verdict": "passed", "findings": [],
                "receipt_refs": ["fixture/review-receipt"]]]
        guard case .review(let r) = try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw)) else {
            throw QualityFailure(reason: "fixture_not_review")
        }
        return r
    }

    private func binding(_ record: ContractRecord) -> [String: Any] {
        ["record_id": record.recordId, "revision": record.document.revision, "content_sha256": record.contentSha256]
    }

    private func source(_ id: String) -> SourceRecord {
        SourceRecord(sourceID: id, locator: "https://example.org/\(id)", version: "v1",
            publicationDate: nil, effectiveFrom: nil, effectiveTo: nil,
            kind: "self_authored", examYear: nil, retrievedAt: "2026-10-11T00:00:00Z",
            contentSHA256: nil, contentSHA256Reason: "Metadata only; no original retained",
            attribution: "Author \(id)", licenseTextRef: "license.md",
            permissions: Dictionary(uniqueKeysWithValues: SourceOperation.allCases.map {
                ($0.rawValue, SourcePermission(status: .allowed, evidence: "license.md", quote: "Fixture grants this operation"))
            }), ancestors: [])
    }

    private func makeFixture(v3Assessed: Bool, familyEvidence: Bool, legacyV1: Bool = false) throws -> GateFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dataset"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("reviews"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("content/ledger"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("content/derived/pilot-v1"), withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let train = try question(split: "train"), check = try question()
        let teaching = try ContractJSON.decode(Data(contentsOf: fixtures.appendingPathComponent("teaching.jsonl")))
        var bytes = Data()
        for name in ["entry.jsonl", "sense.jsonl", "target.jsonl", "teaching.jsonl", "provenance.jsonl"] {
            bytes.append(try Data(contentsOf: fixtures.appendingPathComponent(name)))
        }
        bytes.append(try ContractJSON.line(.question(train)))
        bytes.append(try ContractJSON.line(.question(check)))
        let fixture = GateFixture(root: root)
        try bytes.write(to: fixture.dataset.appendingPathComponent("records.jsonl"))
        let qualityReviews = try [review(train), review(check)]
        try (ContractJSON.line(.review(qualityReviews[0])) + ContractJSON.line(.review(qualityReviews[1])))
            .write(to: fixture.reviews.appendingPathComponent("reviews.jsonl"))
        if familyEvidence, !legacyV1 {
            let row: [String: Any] = ["target_id": train.payload.primaryTargetId,
                "train_family": train.payload.familyId, "check_family": check.payload.familyId,
                "verdict": "independent", "evidence": "Job application instruction versus passport-office request, compared full fixture prompts and all options.",
                "evaluator_session": "fixture-family-reviewer", "finding_ids": [],
                "current_member_bindings": ["train": binding(.question(train)), "check": binding(.question(check))],
                "current_teaching_bindings": [binding(teaching)]]
            try (JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) + Data([10]))
                .write(to: fixture.reviews.appendingPathComponent("family-bound.jsonl"))
        }
        if legacyV1 {
            let row: [String: Any] = ["target_id": train.payload.primaryTargetId,
                "train_family": train.payload.familyId, "check_family": check.payload.familyId,
                "verdict": "independent", "evidence": "Compared full current questions and teaching.",
                "evaluator_session": "family-review", "finding_ids": [],
                "current_member_bindings": ["train": binding(.question(train)), "check": binding(.question(check))],
                "current_teaching_bindings": [binding(teaching)]]
            try (JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) + Data([10]))
                .write(to: fixture.reviews.appendingPathComponent("family-verdicts.jsonl"))
        }
        var (profile, _) = QualityProfileTests.baseline()
        if !legacyV1 {
            profile.profile = "pilot-quality-v3"
            profile.questionEligibility = QuestionEligibilityPolicy(version: "question-eligibility-v3",
                assessments: v3Assessed ? [assessment(train), assessment(check)] : [])
        }
        try ContractJSON.bytes(profile).write(to: fixture.profile)
        try Data("Fixture grants this operation; not a grant for pilot content.\n".utf8)
            .write(to: root.appendingPathComponent("sources/license.md"))
        try (JSONEncoder().encode(source("S01")) + Data([10])).write(to: fixture.sources)
        try Data("{}\n".utf8).write(to: fixture.ledger)
        let loaded = try IndexBuild.loadRecords(at: fixture.dataset)
        try SearchIndex.bytes(SearchIndex.build(records: loaded.records))
            .write(to: root.appendingPathComponent("content/derived/pilot-v1/index.json"))
        return fixture
    }

    private func evidenceJSON(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func defectCodes(in report: [String: Any]) -> [String: Int] {
        (report["defect_counts"] as? [String: Int]) ?? [:]
    }

    private func defectDetails(in report: [String: Any]) -> [String] {
        ((report["defects"] as? [[String: Any]]) ?? []).compactMap { $0["detail"] as? String }
    }

    private func isolatedGraph() -> (URL, URL, URL, URL, URL) -> DatasetGraphReport {
        { _, _, _, _, _ in
            DatasetGraphReport(recordCount: 0, activeRecordIds: [], quarantinedRecordIds: [],
                aliasIndex: [:], defects: [])
        }
    }

    private func validateArgs(_ fixture: GateFixture, evidence: URL) -> [String] {
        ["--dataset", fixture.dataset.path, "--stage", "private-pack",
            "--sources", fixture.sources.path, "--reviews", fixture.reviews.path,
            "--ledger", fixture.ledger.path, "--profile", fixture.profile.path,
            "--evidence", evidence.path]
    }

    func testValidateDatasetRejectsV3ShortageWithRetainedShortages() throws {
        let fixture = try makeFixture(v3Assessed: true, familyEvidence: false)
        let code = JobCommands.validateDataset(validateArgs(fixture, evidence: fixture.evidence),
            graphAudit: isolatedGraph())
        XCTAssertEqual(code, 65)
        let report = try evidenceJSON(at: fixture.evidence)
        XCTAssertEqual(report["valid"] as? Bool, false)
        XCTAssertEqual(defectCodes(in: report)["family_mismatch"], 2)
        let details = defectDetails(in: report).joined(separator: "\n")
        XCTAssertTrue(details.contains("family_supply_short:"), details)
        XCTAssertTrue(details.contains("family_missing_work:"), details)
        XCTAssertTrue(details.contains("lx:target:00000000-0000-0000-0000-000000000001"), details)
    }

    func testValidateDatasetHappyV3StillWorks() throws {
        let fixture = try makeFixture(v3Assessed: true, familyEvidence: true)
        let code = JobCommands.validateDataset(validateArgs(fixture, evidence: fixture.evidence),
            graphAudit: isolatedGraph())
        XCTAssertEqual(code, 0)
        let report = try evidenceJSON(at: fixture.evidence)
        XCTAssertEqual(report["valid"] as? Bool, true)
        XCTAssertTrue(defectDetails(in: report).isEmpty)
    }

    func testValidateDatasetLegacyV1StillWorks() throws {
        let fixture = try makeFixture(v3Assessed: false, familyEvidence: false, legacyV1: true)
        let code = JobCommands.validateDataset(validateArgs(fixture, evidence: fixture.evidence),
            graphAudit: isolatedGraph())
        XCTAssertEqual(code, 0)
        XCTAssertEqual(try evidenceJSON(at: fixture.evidence)["valid"] as? Bool, true)
    }

    func testValidateDatasetFamilyThrowStillBecomesDefect() throws {
        let fixture = try makeFixture(v3Assessed: false, familyEvidence: false, legacyV1: true)
        try FileManager.default.removeItem(at: fixture.reviews.appendingPathComponent("family-verdicts.jsonl"))
        let code = JobCommands.validateDataset(validateArgs(fixture, evidence: fixture.evidence),
            graphAudit: isolatedGraph())
        XCTAssertEqual(code, 65)
        let report = try evidenceJSON(at: fixture.evidence)
        XCTAssertEqual(report["valid"] as? Bool, false)
        XCTAssertTrue(defectDetails(in: report).joined(separator: "\n").contains("missing_current_family_verdict:"), "throw path must keep typed failure detail")
    }

    func testPublicValidateDatasetDoesNotInheritIsolatedGraph() throws {
        let fixture = try makeFixture(v3Assessed: true, familyEvidence: true)
        let happy = JobCommands.validateDataset(validateArgs(fixture, evidence: fixture.evidence),
            graphAudit: isolatedGraph())
        XCTAssertEqual(happy, 0)
        let bad = JobCommands.validateDataset(validateArgs(fixture, evidence: fixture.evidence))
        XCTAssertEqual(bad, 65)
        let report = try evidenceJSON(at: fixture.evidence)
        XCTAssertEqual(report["valid"] as? Bool, false)
        XCTAssertGreaterThan(defectCodes(in: report)["identity_binding"] ?? 0, 0)
        XCTAssertTrue(((report["defects"] as? [[String: Any]]) ?? []).contains {
            $0["code"] as? String == "identity_binding" && $0["field"] as? String == "ledger"
        })
        let againEvidence = fixture.root.appendingPathComponent("evidence-again.json")
        let again = JobCommands.validateDataset(validateArgs(fixture, evidence: againEvidence),
            graphAudit: isolatedGraph())
        XCTAssertEqual(again, 0)
    }

    func testPackageBuildRejectsV3ShortageWithNoOutput() throws {
        let fixture = try makeFixture(v3Assessed: true, familyEvidence: false)
        XCTAssertThrowsError(try PackageBuilder.build(dataset: fixture.dataset, sources: fixture.sources,
            reviews: fixture.reviews, ledger: fixture.ledger, profile: fixture.profile,
            mode: "private-preview", out: fixture.out, graphAudit: isolatedGraph())) {
            guard let failure = $0 as? PackageFailure else { return XCTFail("Unexpected \($0)") }
            XCTAssertTrue(failure.reason.hasPrefix("family_supply_short:"), failure.reason)
            XCTAssertTrue(failure.reason.contains("lx:target:00000000-0000-0000-0000-000000000001"), failure.reason)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.out.path))
    }

    func testPackageBuildHappyV3StillBuildsVerifiablePack() throws {
        let fixture = try makeFixture(v3Assessed: true, familyEvidence: true)
        try PackageBuilder.build(dataset: fixture.dataset, sources: fixture.sources,
            reviews: fixture.reviews, ledger: fixture.ledger, profile: fixture.profile,
            mode: "private-preview", out: fixture.out, graphAudit: isolatedGraph())
        let manifest = try PackageBuilder.verify(fixture.out)
        XCTAssertEqual(manifest.buildMode, "private-preview")
        XCTAssertFalse(manifest.releaseEligible)
        XCTAssertTrue(manifest.humanReviewPending)
    }

    func testPackageBuildFamilyThrowWrappedAsTypedFailureWithNoOutput() throws {
        let fixture = try makeFixture(v3Assessed: false, familyEvidence: false, legacyV1: true)
        try FileManager.default.removeItem(at: fixture.reviews.appendingPathComponent("family-verdicts.jsonl"))
        XCTAssertThrowsError(try PackageBuilder.build(dataset: fixture.dataset, sources: fixture.sources,
            reviews: fixture.reviews, ledger: fixture.ledger, profile: fixture.profile,
            mode: "private-preview", out: fixture.out, graphAudit: isolatedGraph())) {
            guard let failure = $0 as? PackageFailure else { return XCTFail("Unexpected \($0)") }
            XCTAssertTrue(failure.reason.hasPrefix("family_audit_failed:"), failure.reason)
            XCTAssertTrue(failure.reason.contains("missing_current_family_verdict:"), failure.reason)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.out.path))
    }

    func testDefaultPackageBuildDoesNotInheritIsolatedGraph() throws {
        let fixture = try makeFixture(v3Assessed: true, familyEvidence: true)
        let isolatedOut = fixture.root.appendingPathComponent("isolated-pack")
        try PackageBuilder.build(dataset: fixture.dataset, sources: fixture.sources,
            reviews: fixture.reviews, ledger: fixture.ledger, profile: fixture.profile,
            mode: "private-preview", out: isolatedOut, graphAudit: isolatedGraph())
        _ = try PackageBuilder.verify(isolatedOut)

        XCTAssertThrowsError(try PackageBuilder.build(dataset: fixture.dataset, sources: fixture.sources,
            reviews: fixture.reviews, ledger: fixture.ledger, profile: fixture.profile,
            mode: "private-preview", out: fixture.out)) {
            guard let failure = $0 as? PackageFailure else { return XCTFail("Unexpected \($0)") }
            XCTAssertTrue(failure.reason.hasPrefix("private_pack_validation_failed:"), failure.reason)
            XCTAssertTrue(failure.reason.contains("identity_binding="), failure.reason)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.out.path))
    }
}
