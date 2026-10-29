import ContentModel
import Foundation
import XCTest
@testable import ContentCLI

/// Current-tree triage tests. Fixtures are sealed ContractJSON rows, so every
/// hash the report binds is verified by decode, exactly like production.
final class CurrentRecheckTests: XCTestCase {
    private struct Fixture {
        let dataset: URL
        let reviews: URL
        let out: URL
        let evidence: URL
        let root: URL
    }

    private let zeroHash = String(repeating: "0", count: 64)
    private let targetID = "lx:target:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private let familyID = "lx:family:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    private let senseID = "lx:sense:cccccccc-cccc-cccc-cccc-cccccccccccc"
    private let usageID = "lx:usage:dddddddd-dddd-dddd-dddd-dddddddddddd"

    private func makeFixture(_ build: (URL, URL) throws -> Void) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dataset = root.appendingPathComponent("dataset")
        let reviews = root.appendingPathComponent("reviews")
        try FileManager.default.createDirectory(at: dataset, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reviews, withIntermediateDirectories: true)
        try build(dataset, reviews)
        try Data().write(to: reviews.appendingPathComponent("human-decisions.jsonl"))
        let triage = reviews.appendingPathComponent("triage")
        return Fixture(dataset: dataset, reviews: reviews,
                        out: triage.appendingPathComponent("current-triage.json"),
                        evidence: root.appendingPathComponent("evidence.json"), root: root)
    }

    private func sealRecord(_ row: [String: Any]) throws -> ContractRecord {
        var mutable = row
        mutable["content_sha256"] = zeroHash
        return try ContractJSON.seal(JSONSerialization.data(withJSONObject: mutable, options: [.sortedKeys]))
    }

    @discardableResult
    private func writeSealed(_ rows: [[String: Any]], _ file: URL) throws -> [ContractRecord] {
        let sealed = try rows.map { try sealRecord($0) }
        let text = try sealed.map { String(decoding: try ContractJSON.line($0), as: UTF8.self) }.joined()
        try text.write(to: file, atomically: true, encoding: .utf8)
        return sealed
    }

    private func questionRow(_ id: String, revision: Int, status: String = "candidate", options: Int = 2) -> [String: Any] {
        let names = ["First English", "Second English", "Third English", "Fourth English"]
        let ids = ["option-a", "option-b", "option-c", "option-d"]
        let taken = Array(ids.prefix(options))
        return ["record_id": id, "kind": "question", "revision": revision, "content_sha256": zeroHash,
                "schema": "lexvane.content.v1",
                "payload": ["primary_target_id": targetID, "tested_ability": "contextual_choice",
                            "family_id": familyID, "split": "train", "stem": "Stem for \(id)",
                            "options": taken.enumerated().map { ["option_id": $0.element, "english": names[$0.offset]] },
                            "accepted_answers": ["option-a"],
                            "correct_sense_id": senseID, "correct_usage_ids": [usageID],
                            "post_answer_feedback": ["answer": "First English", "explanation": "Because first."],
                            "distractor_rationales": taken.dropFirst().map { ["option_id": $0, "reason": "\($0) is wrong."] },
                            "provenance_refs": ["prov-ref"], "status": status]]
    }

    private func reviewRow(_ id: String, subject: String, revision: Int, sha: String,
                           verdict: String, checklistPassed: Bool = true,
                           findings: [[String: Any]] = [],
                           checklist: [String] = ["subject-binding"]) -> [String: Any] {
        ["record_id": id, "kind": "review", "revision": 1, "content_sha256": zeroHash,
         "schema": "lexvane.content.v1",
         "payload": ["subject_id": subject, "subject_kind": "question",
                     "subject_revision": revision, "subject_content_sha256": sha,
                     "reviewer_session": "session-1", "reviewer_model": "model-1",
                     "input_hash": zeroHash, "prompt_hash": zeroHash,
                     "checklist": checklist.map { ["item": $0,
                                                   "result": checklistPassed ? "passed" : "failed",
                                                   "reason": "Checked \($0).",
                                                   "source_evidence": ["evidence.json"]] },
                     "verdict": verdict, "findings": findings,
                     "receipt_refs": ["receipt.json"]]]
    }

    private func findingRow(_ reason: String, severity: String = "major", state: String = "unresolved") -> [String: Any] {
        ["finding_id": UUID().uuidString, "severity": severity, "state": state, "reason": reason]
    }

    private func qid(_ tag: String) -> String { "lx:question:11111111-1111-1111-1111-111111111\(tag)" }

    private func run(_ mode: String, _ fixture: Fixture, policy: URL? = nil, qualityProfile: URL? = nil) -> Int32 {
        var args = ["reports", mode, "--dataset", fixture.dataset.path, "--reviews", fixture.reviews.path,
                    "--out", fixture.out.path, "--evidence", fixture.evidence.path]
        if let policy { args += ["--policy", policy.path] }
        if let qualityProfile { args += ["--quality-profile", qualityProfile.path] }
        return CKCLI.run(args)
    }

    private func triage(_ fixture: Fixture) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.out)) as! [String: Any]
    }

    private func issues(_ fixture: Fixture) throws -> [[String: Any]] {
        try (self.triage(fixture)["issues"] as? [[String: Any]]) ?? []
    }

    private func policyDoc(_ fixture: Fixture) throws -> [String: Any] {
        try (self.triage(fixture)["policy"] as? [String: Any]) ?? [:]
    }

    private func teardown(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.root)
    }

    /// A current-binding verdict conflict is a human issue; a stale-revision
    /// disagreement for the same subject stays historical context.
    func testCurrentVsHistoricalVerdictConflict() throws {
        let question = qid("001")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 2)], dataset.appendingPathComponent("rows.jsonl"))
            let sha = sealed[0].contentSha256
            try writeSealed([
                reviewRow("r-cur-a", subject: question, revision: 2, sha: sha, verdict: "passed"),
                reviewRow("r-cur-b", subject: question, revision: 2, sha: sha, verdict: "quarantined",
                           findings: [findingRow("distractor admits a second reading")]),
                reviewRow("r-old", subject: question, revision: 1, sha: zeroHash, verdict: "changes_requested",
                           findings: [findingRow("old stem error", state: "resolved")]),
            ], reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let rows = try issues(fixture)
        let kinds = Set(rows.map { "\($0["bucket"]!)/\($0["issue_kind"]!)" })
        XCTAssertTrue(kinds.contains("human/review-disagreement"), "current disagreement must be human: \(kinds)")
        XCTAssertTrue(kinds.contains("human/unresolved-finding"), "current unresolved finding kept: \(kinds)")
        XCTAssertTrue(kinds.contains("historical/historical-disagreement"), "stale disagreement retained as context: \(kinds)")
        XCTAssertTrue(kinds.contains("historical/historical-fixed-error"), "fixed error retained: \(kinds)")
        XCTAssertFalse(rows.contains { ($0["bucket"] as? String) == "machine" && ($0["issue_kind"] as? String) == "missing-current-review" })
        XCTAssertEqual(try Data(contentsOf: fixture.reviews.appendingPathComponent("human-decisions.jsonl")).count, 0)
        XCTAssertEqual(run("audit-current-recheck", fixture), 0)
    }

    /// Repeated identical findings collapse into one row with source refs.
    func testDuplicateCollapse() throws {
        let question = qid("002")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            let sha = sealed[0].contentSha256
            try writeSealed([
                reviewRow("r-a", subject: question, revision: 1, sha: sha, verdict: "passed"),
                reviewRow("r-b", subject: question, revision: 1, sha: sha, verdict: "quarantined",
                           findings: [findingRow("same distractor flaw"), findingRow("same distractor flaw")]),
                reviewRow("r-c", subject: question, revision: 1, sha: sha, verdict: "quarantined",
                           findings: [findingRow("same distractor flaw")]),
            ], reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let rows = try issues(fixture)
        let unresolved = rows.filter { ($0["issue_kind"] as? String) == "unresolved-finding" }
        XCTAssertEqual(unresolved.count, 1, "identical reasons must dedup, got: \(unresolved.count)")
        XCTAssertEqual(unresolved.first?["source_count"] as? Int, 3, "all contributing reviews stay linked")
        let lines = try String(contentsOf: fixture.reviews.appendingPathComponent("triage")
            .appendingPathComponent("current-human-recheck.jsonl"), encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, rows.count)
    }

    /// A quarantined current verdict with no itemized findings stays pending
    /// for independent review instead of vanishing or auto-failing.
    func testIncompleteEvidencePending() throws {
        let question = qid("003")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            let sha = sealed[0].contentSha256
            try writeSealed([reviewRow("r-a", subject: question, revision: 1, sha: sha, verdict: "quarantined")],
                            reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let rows = try issues(fixture)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["issue_kind"] as? String, "incomplete-evidence")
        XCTAssertEqual(rows.first?["action"] as? String, "independent-review-needed")
        XCTAssertEqual(rows.first?["human_status"] as? String, "pending")
    }

    /// Deterministic rerun: two generations from the same tree are identical.
    func testDeterministicRerun() throws {
        let first = qid("004"), second = qid("005")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(first, revision: 1), questionRow(second, revision: 3)],
                                         dataset.appendingPathComponent("rows.jsonl"))
            try writeSealed([reviewRow("r-a", subject: first, revision: 1, sha: sealed[0].contentSha256, verdict: "passed"),
                             reviewRow("r-b", subject: second, revision: 2, sha: zeroHash, verdict: "passed")],
                            reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let firstBytes = try Data(contentsOf: fixture.out)
        let firstLines = try Data(contentsOf: fixture.reviews.appendingPathComponent("triage")
            .appendingPathComponent("current-human-recheck.jsonl"))
        XCTAssertEqual(run("current-recheck", fixture), 0)
        XCTAssertEqual(try Data(contentsOf: fixture.out), firstBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.reviews.appendingPathComponent("triage")
            .appendingPathComponent("current-human-recheck.jsonl")), firstLines)
        let rows = try issues(fixture)
        let missing = rows.first { ($0["issue_kind"] as? String) == "missing-current-review" }
        XCTAssertNotNil(missing)
        XCTAssertEqual(missing?["subject_id"] as? String, second)
        XCTAssertEqual(missing?["priority"] as? String, "medium")
        XCTAssertEqual(missing?["action"] as? String, "independent-review-needed")
        XCTAssertTrue((missing?["reason"] as? String ?? "").contains("independent review"))
    }

    /// Generation never fabricates owner approval and never overwrites it.
    func testPreserveDecisions() throws {
        let question = qid("006")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            try writeSealed([reviewRow("r-a", subject: question, revision: 1, sha: sealed[0].contentSha256, verdict: "passed")],
                            reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let doc = try triage(fixture)
        XCTAssertEqual(doc["release_eligible"] as? Bool, false)
        XCTAssertEqual(doc["human_review_pending"] as? Bool, true)
        XCTAssertTrue(doc["approval"] is NSNull)
        let decisions = fixture.reviews.appendingPathComponent("human-decisions.jsonl")
        XCTAssertEqual(try Data(contentsOf: decisions).count, 0)
        try "x".write(to: decisions, atomically: true, encoding: .utf8)
        XCTAssertNotEqual(run("current-recheck", fixture), 0, "Never erase existing human decisions")
        XCTAssertNotEqual(run("audit-current-recheck", fixture), 0, "Pending packet cannot carry approval")
    }

    /// A malformed dataset line fails instead of producing a partial packet.
    func testMalformedDatasetLineFails() throws {
        let fixture = try makeFixture { dataset, reviews in
            try writeSealed([questionRow(qid("007"), revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            try "not json at all\n".write(to: dataset.appendingPathComponent("bad.jsonl"), atomically: true, encoding: .utf8)
            try Data().write(to: reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertNotEqual(run("current-recheck", fixture), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.out.path))
    }

    /// Same dataset identity with conflicting content is rejected, not
    /// silently overwritten.
    func testConflictingDuplicateDatasetIdentityFails() throws {
        let question = qid("008")
        let fixture = try makeFixture { dataset, reviews in
            var first = questionRow(question, revision: 1)
            var payload = first["payload"] as! [String: Any]
            payload["stem"] = "First stem"
            first["payload"] = payload
            var second = questionRow(question, revision: 1)
            payload["stem"] = "Second stem"
            second["payload"] = payload
            try writeSealed([first, second], dataset.appendingPathComponent("rows.jsonl"))
            try Data().write(to: reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertNotEqual(run("current-recheck", fixture), 0)
    }

    /// Same review id with conflicting content is rejected.
    func testConflictingDuplicateReviewIdentityFails() throws {
        let question = qid("009")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            let sha = sealed[0].contentSha256
            try writeSealed([
                reviewRow("r-dup", subject: question, revision: 1, sha: sha, verdict: "passed"),
                reviewRow("r-dup", subject: question, revision: 1, sha: sha, verdict: "quarantined",
                           findings: [findingRow("late disagreement")]),
            ], reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertNotEqual(run("current-recheck", fixture), 0)
    }

    /// Byte-identical review copies dedup into one entry keeping all locations.
    func testIdenticalReviewCopiesDedupPreservingLocations() throws {
        let question = qid("010")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            let sha = sealed[0].contentSha256
            let line = try sealRecord(reviewRow("r-copy", subject: question, revision: 1, sha: sha, verdict: "quarantined",
                                                findings: [findingRow("copied flaw")]))
            let text = String(decoding: try ContractJSON.line(line), as: UTF8.self)
            try (text + text).write(to: reviews.appendingPathComponent("reviews-disambiguated.jsonl"),
                                  atomically: true, encoding: .utf8)
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let rows = try issues(fixture)
        let unresolved = rows.filter { ($0["issue_kind"] as? String) == "unresolved-finding" }
        XCTAssertEqual(unresolved.count, 1)
        XCTAssertEqual(unresolved.first?["source_count"] as? Int, 3, "dataset ref plus both copy locations")
        let doc = try triage(fixture)
        XCTAssertEqual(doc["disambiguated_reviews"] as? Int, 1)
        XCTAssertEqual(doc["disambiguated_review_locations"] as? Int, 2)
    }

    /// No current review must not drop historical context for the subject.
    func testMissingCurrentReviewKeepsHistoricalContext() throws {
        let question = qid("011")
        let fixture = try makeFixture { dataset, reviews in
            try writeSealed([questionRow(question, revision: 2)], dataset.appendingPathComponent("rows.jsonl"))
            try writeSealed([reviewRow("r-old", subject: question, revision: 1, sha: zeroHash, verdict: "quarantined",
                                       findings: [findingRow("stale major flaw")])],
                            reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let rows = try issues(fixture)
        let kinds = Set(rows.map { "\($0["bucket"]!)/\($0["issue_kind"]!)" })
        XCTAssertTrue(kinds.contains("machine/missing-current-review"), "missing binding stays machine: \(kinds)")
        XCTAssertTrue(kinds.contains("historical/historical-unresolved-stale"), "stale context retained: \(kinds)")
    }

    /// Stale unresolved findings keep their actual severity and priority.
    func testHistoricalUnresolvedStaleRetainsSeverity() throws {
        let question = qid("012")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 2)], dataset.appendingPathComponent("rows.jsonl"))
            try writeSealed([
                reviewRow("r-cur", subject: question, revision: 2, sha: sealed[0].contentSha256, verdict: "passed"),
                reviewRow("r-old", subject: question, revision: 1, sha: zeroHash, verdict: "quarantined",
                           findings: [findingRow("critical stale flaw", severity: "critical")]),
            ], reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let rows = try issues(fixture)
        let stale = rows.filter { ($0["issue_kind"] as? String) == "historical-unresolved-stale" }
        XCTAssertEqual(stale.count, 1)
        XCTAssertEqual(stale.first?["bucket"] as? String, "historical")
        XCTAssertEqual(stale.first?["severity"] as? String, "critical")
        XCTAssertEqual(stale.first?["priority"] as? String, "high")
        XCTAssertEqual(stale.first?["historical_only"] as? Bool, true)
        XCTAssertFalse(stale.contains { ($0["bucket"] as? String) == "human" })
    }

    private func v3Profile(_ dir: URL) throws -> URL {
        let profile: [String: Any] = ["profile": "pilot-quality-v3",
            "active_abilities": ["contextual_choice"], "excluded_target_ids": [] as [String],
            "per_ability_minimums": ["contextual_choice": ["train_families": 1, "independent_check_families": 1]],
            "human_sample_policy": ["seed": 1, "denominator": 2, "high_risk_count": 2,
                                    "strata": ["question:contextual_choice": 1], "maximum": 2],
            "batch_sizes": [:] as [String: Int], "hard_reject_defects": [] as [String],
            "unresolved_critical_maximum": 0, "recommendation": "blocked-on-writing-contract",
            "question_eligibility": ["version": "question-eligibility-v3", "assessments": [] as [Any]]]
        let url = dir.appendingPathComponent("pilot-quality-v3.json")
        try JSONSerialization.data(withJSONObject: profile, options: [.sortedKeys])
            .write(to: url, options: .atomic)
        return url
    }

    private func policyFixture() throws -> (Fixture, URL, URL) {
        let good = qid("013"), structural = qid("014")
        let fixture = try makeFixture { dataset, reviews in
            try writeSealed([questionRow(good, revision: 1),
                             questionRow(structural, revision: 1, options: 3)],
                            dataset.appendingPathComponent("rows.jsonl"))
            try Data().write(to: reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
            let root = dataset.deletingLastPathComponent()
            let profileURL = try v3Profile(root)
            XCTAssertEqual(QuestionQualityAuditCommands.run(["--datasets", dataset.path, "--reviews", reviews.path,
                                                             "--profile", profileURL.path,
                                                             "--out", root.appendingPathComponent("audit.json").path]), 0)
        }
        return (fixture, fixture.root.appendingPathComponent("audit.json"),
                fixture.root.appendingPathComponent("pilot-quality-v3.json"))
    }

    /// A fresh regenerated audit verifies, and its items bind: structural
    /// author work goes machine while missing assessment goes human-medium.
    func testPolicyFreshWhenCurrentAndItemsBind() throws {
        let (fixture, auditOut, profileURL) = try policyFixture()
        defer { teardown(fixture) }
        let reviewFile = fixture.reviews.appendingPathComponent("reviews-disambiguated.jsonl")
        let goodSealed = try sealRecord(questionRow(qid("013"), revision: 1))
        let requiredChecks = ["target-ability-match", "stem-tests-sense", "options-no-leak",
                              "single-answer-or-listed", "distractor-rationales",
                              "feedback-consistency", "no-pre-answer-hint", "family-independence"]
        try writeSealed([reviewRow("r-good", subject: qid("013"), revision: 1,
                                   sha: goodSealed.contentSha256, verdict: "passed",
                                   checklist: requiredChecks)], reviewFile)
        // Regenerate the audit now that the current review exists.
        XCTAssertEqual(QuestionQualityAuditCommands.run(["--datasets", fixture.dataset.path,
                                                         "--reviews", fixture.reviews.path,
                                                         "--profile", profileURL.path,
                                                         "--out", auditOut.path]), 0)
        XCTAssertEqual(run("current-recheck", fixture, policy: auditOut, qualityProfile: profileURL), 0)
        let policy = try policyDoc(fixture)
        XCTAssertEqual(policy["policy_fresh"] as? Bool, true)
        XCTAssertEqual(policy["dataset_match"] as? Bool, true)
        XCTAssertEqual(policy["reviews_match"] as? Bool, true)
        XCTAssertEqual(policy["profile_match"] as? Bool, true)
        XCTAssertEqual(policy["quality_items_bound"] as? Int, 2)
        let rows = try issues(fixture)
        let author = rows.filter { ($0["issue_kind"] as? String) == "author-revision-needed" }
        XCTAssertEqual(author.count, 1, "structural option-count defect is machine author work")
        XCTAssertEqual(author.first?["bucket"] as? String, "machine")
        XCTAssertEqual(author.first?["action"] as? String, "author-revision-needed")
        XCTAssertEqual(author.first?["priority"] as? String, "high")
        XCTAssertEqual(author.first?["missing_work"] as? String, "requires_four_options")
        let pending = rows.filter { ($0["issue_kind"] as? String) == "assessment-pending" }
        XCTAssertEqual(pending.count, 2, "both questions lack independent semantic assessment")
        XCTAssertTrue(pending.allSatisfy { ($0["bucket"] as? String) == "human" })
        XCTAssertTrue(pending.allSatisfy { ($0["action"] as? String) == "independent-review-needed" })
        XCTAssertEqual(pending.filter { ($0["priority"] as? String) == "medium" }.count, 1,
                       "pending assessment stays medium, not automatic high")
        XCTAssertEqual(pending.filter { ($0["priority"] as? String) == "high" }.count, 1,
                       "rejected assessment escalates to high")
        XCTAssertFalse(rows.contains { ($0["missing_work"] as? String) == "current_review_missing" },
                       "binding-owned reasons must not duplicate the classifier")
        XCTAssertEqual(try Data(contentsOf: fixture.reviews.appendingPathComponent("human-decisions.jsonl")).count, 0)
        XCTAssertEqual(run("audit-current-recheck", fixture, policy: auditOut, qualityProfile: profileURL), 0)
    }

    /// Changed profile or review bytes invalidate freshness without failing.
    func testPolicyStaleOnChangedInputs() throws {
        let (fixture, auditOut, profileURL) = try policyFixture()
        defer { teardown(fixture) }
        try writeSealed([], fixture.reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        XCTAssertEqual(QuestionQualityAuditCommands.run(["--datasets", fixture.dataset.path,
                                                         "--reviews", fixture.reviews.path,
                                                         "--profile", profileURL.path,
                                                         "--out", auditOut.path]), 0)
        XCTAssertEqual(run("current-recheck", fixture, policy: auditOut, qualityProfile: profileURL), 0)
        XCTAssertEqual(try policyDoc(fixture)["policy_fresh"] as? Bool, true)
        try " ".write(to: profileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(run("current-recheck", fixture, policy: auditOut, qualityProfile: profileURL), 0)
        let afterProfile = try policyDoc(fixture)
        XCTAssertEqual(afterProfile["policy_fresh"] as? Bool, false)
        XCTAssertEqual(afterProfile["profile_match"] as? Bool, false)
        let reviewFile = fixture.reviews.appendingPathComponent("reviews-disambiguated.jsonl")
        try (String(decoding: try Data(contentsOf: reviewFile), as: UTF8.self) + "\n")
            .write(to: reviewFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(run("current-recheck", fixture, policy: auditOut, qualityProfile: profileURL), 0)
        let afterReview = try policyDoc(fixture)
        XCTAssertEqual(afterReview["policy_fresh"] as? Bool, false)
        XCTAssertEqual(afterReview["reviews_match"] as? Bool, false)
    }

    /// An explicit profile without its audit is rejected.
    func testQualityProfileRequiresPolicy() throws {
        let fixture = try makeFixture { dataset, reviews in
            try writeSealed([questionRow(qid("015"), revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            try Data().write(to: reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        let profileURL = try v3Profile(fixture.dataset)
        XCTAssertNotEqual(run("current-recheck", fixture, qualityProfile: profileURL), 0)
    }

    /// P2 red-first: a current changes_requested with a failed checklist and
    /// empty findings must not vanish (currently 0 issues).
    func testChangesRequestedFailedChecklistEmptyFindingsStaysPending() throws {
        let question = qid("016")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            let sha = sealed[0].contentSha256
            try writeSealed([reviewRow("r-a", subject: question, revision: 1, sha: sha, verdict: "changes_requested",
                                        checklistPassed: false, findings: [])],
                            reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let rows = try issues(fixture)
        XCTAssertFalse(rows.isEmpty, "changes_requested with failed checklist and empty findings must not vanish")
        XCTAssertTrue(rows.allSatisfy { ($0["human_status"] as? String) == "pending" })
        XCTAssertTrue(rows.contains { ($0["action"] as? String) == "independent-review-needed" },
                      "failed checklist reasons must stay actionable: \(rows)")
    }

    /// Both non-passed verdicts with failed checklist and empty findings stay
    /// pending instead of vanishing.
    func testBothNonPassedFailedChecklistEmptyFindingsStayPending() throws {
        for (tag, verdict) in [("017", "quarantined"), ("018", "changes_requested")] {
            let question = qid(tag)
            let fixture = try makeFixture { dataset, reviews in
                let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
                let sha = sealed[0].contentSha256
                try writeSealed([reviewRow("r-a", subject: question, revision: 1, sha: sha, verdict: verdict,
                                            checklistPassed: false, findings: [])],
                                reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
            }
            XCTAssertEqual(run("current-recheck", fixture), 0, "verdict \(verdict) must generate")
            let rows = try issues(fixture)
            XCTAssertFalse(rows.isEmpty, "\(verdict) with failed checklist and empty findings must not vanish")
            XCTAssertTrue(rows.contains { ($0["action"] as? String) == "independent-review-needed" },
                          "\(verdict) checklist failure must stay actionable: \(rows)")
            XCTAssertTrue(rows.allSatisfy { ($0["human_status"] as? String) == "pending" })
            XCTAssertFalse(rows.contains { ($0["approval"] as? String) == "approved" },
                           "\(verdict) must never fabricate approval")
            teardown(fixture)
        }
    }

    /// Both non-passed verdicts with no failed items and no findings become
    /// incomplete-evidence; a clean pass never does just because findings[].
    func testBothNonPassedBareBecomeIncompleteEvidence() throws {
        for (tag, verdict) in [("019", "quarantined"), ("020", "changes_requested")] {
            let question = qid(tag)
            let fixture = try makeFixture { dataset, reviews in
                let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
                let sha = sealed[0].contentSha256
                try writeSealed([reviewRow("r-a", subject: question, revision: 1, sha: sha, verdict: verdict,
                                            checklistPassed: true, findings: [])],
                                reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
            }
            XCTAssertEqual(run("current-recheck", fixture), 0, "verdict \(verdict) must generate")
            let rows = try issues(fixture)
            XCTAssertEqual(rows.count, 1, "\(verdict) bare must yield exactly one pending action, got: \(rows)")
            XCTAssertEqual(rows.first?["issue_kind"] as? String, "incomplete-evidence")
            XCTAssertEqual(rows.first?["action"] as? String, "independent-review-needed")
            XCTAssertEqual(rows.first?["human_status"] as? String, "pending")
            teardown(fixture)
        }
        let question = qid("021")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            let sha = sealed[0].contentSha256
            try writeSealed([reviewRow("r-a", subject: question, revision: 1, sha: sha, verdict: "passed",
                                        checklistPassed: true, findings: [])],
                            reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        XCTAssertTrue(try issues(fixture).isEmpty, "a clean pass must not become incomplete just because findings[]")
    }

    /// Repeated identical failed-checklist reasons dedup into one row keeping
    /// every review location linked.
    func testFailedChecklistDedupRetainsLocations() throws {
        let question = qid("022")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            let sha = sealed[0].contentSha256
            try writeSealed([
                reviewRow("r-a", subject: question, revision: 1, sha: sha, verdict: "changes_requested",
                          checklistPassed: false, findings: []),
                reviewRow("r-b", subject: question, revision: 1, sha: sha, verdict: "changes_requested",
                          checklistPassed: false, findings: []),
            ], reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let rows = try issues(fixture)
        let actionable = rows.filter { ($0["bucket"] as? String) == "human" && ($0["historical_only"] as? Bool != true) }
        XCTAssertEqual(actionable.count, 1, "identical checklist failures must dedup, got: \(actionable)")
        XCTAssertEqual(actionable.first?["source_count"] as? Int, 3, "dataset ref plus both review locations")
        XCTAssertEqual(actionable.first?["action"] as? String, "independent-review-needed")
    }

    /// A failed checklist repeating an already-known finding reason must not
    /// duplicate it, and stale historical context stays bound as history.
    func testChecklistMatchingAnotherReviewFindingRetainsBothLocations() throws {
        let question = qid("024")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            try writeSealed([
                reviewRow("r-finding", subject: question, revision: 1, sha: sealed[0].contentSha256,
                          verdict: "changes_requested", findings: [findingRow("Checked subject-binding.")]),
                reviewRow("r-checklist", subject: question, revision: 1, sha: sealed[0].contentSha256,
                          verdict: "changes_requested", checklistPassed: false),
            ], reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let actionable = try issues(fixture).filter { ($0["bucket"] as? String) == "human" }
        XCTAssertEqual(actionable.count, 1)
        XCTAssertEqual(actionable.first?["source_count"] as? Int, 3)
    }

    func testChecklistSameAsKnownFindingDoesNotDuplicateAndKeepsHistory() throws {
        let question = qid("023")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 2)], dataset.appendingPathComponent("rows.jsonl"))
            let sha = sealed[0].contentSha256
            try writeSealed([
                reviewRow("r-cur", subject: question, revision: 2, sha: sha, verdict: "changes_requested",
                          checklistPassed: false, findings: [findingRow("Checked subject-binding.")]),
                reviewRow("r-old", subject: question, revision: 1, sha: zeroHash, verdict: "quarantined",
                          findings: [findingRow("stale major flaw")]),
            ], reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let rows = try issues(fixture)
        let current = rows.filter { ($0["historical_only"] as? Bool != true) && ($0["bucket"] as? String) == "human" }
        XCTAssertEqual(current.count, 1, "checklist repeating a known finding must not duplicate, got: \(current)")
        XCTAssertTrue(try issues(fixture).contains { ($0["issue_kind"] as? String) == "historical-unresolved-stale" },
                      "stale historical context must be retained: \(rows)")
    }

    /// A failed-checklist-only review matching a known finding reason must
    /// join that finding's row, keeping every review location.
    func testChecklistFailureMatchingKnownFindingKeepsAllLocations() throws {
        let question = qid("024")
        let fixture = try makeFixture { dataset, reviews in
            let sealed = try writeSealed([questionRow(question, revision: 1)], dataset.appendingPathComponent("rows.jsonl"))
            let sha = sealed[0].contentSha256
            try writeSealed([
                reviewRow("r-a", subject: question, revision: 1, sha: sha, verdict: "changes_requested",
                          checklistPassed: true, findings: [findingRow("Checked subject-binding.")]),
                reviewRow("r-b", subject: question, revision: 1, sha: sha, verdict: "changes_requested",
                          checklistPassed: false, findings: []),
            ], reviews.appendingPathComponent("reviews-disambiguated.jsonl"))
        }
        defer { teardown(fixture) }
        XCTAssertEqual(run("current-recheck", fixture), 0)
        let rows = try issues(fixture)
        let current = rows.filter { ($0["historical_only"] as? Bool != true) && ($0["bucket"] as? String) == "human" }
        XCTAssertEqual(current.count, 1, "matching checklist failure must join the finding row, not duplicate: \(current)")
        XCTAssertEqual(current.first?["source_count"] as? Int, 3, "dataset plus both review locations: \(current)")
        XCTAssertEqual(current.first?["severity"] as? String, "major", "original finding severity retained: \(current)")
        XCTAssertEqual(current.first?["action"] as? String, "independent-review-needed")
    }
}
