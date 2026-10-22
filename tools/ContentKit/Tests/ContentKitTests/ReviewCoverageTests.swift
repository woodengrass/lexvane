import Foundation
import XCTest
import ContentCLI
@testable import ContentModel

/// Task8 review-coverage gate: the accepted denominator always comes from the
/// dataset's current revisions, never from a reviews-side self report.
/// Mutated invalid fixtures are derived per test from the static valid set.
final class ReviewCoverageTests: XCTestCase {
    private static var packageRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }
    private static var repoRoot: String {
        URL(fileURLWithPath: packageRoot)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }
    private static var validRoot: URL {
        URL(fileURLWithPath: packageRoot)
            .appendingPathComponent("Tests/ContentKitTests/Fixtures/reviews/valid")
    }
    private static var trialProfile: String {
        URL(fileURLWithPath: repoRoot)
            .appendingPathComponent("content/policies/pilot-trial-v0.json").path
    }

    private func freshCopy() throws -> (dataset: URL, reviews: URL, temp: URL) {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        let dataset = temp.appendingPathComponent("dataset")
        let reviews = temp.appendingPathComponent("reviews")
        try fm.copyItem(at: Self.validRoot.appendingPathComponent("dataset"), to: dataset)
        try fm.copyItem(at: Self.validRoot.appendingPathComponent("reviews"), to: reviews)
        return (dataset, reviews, temp)
    }
    private func lines(of file: URL) throws -> [Data] {
        let text = try String(contentsOf: file, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map { Data($0.utf8) }
    }
    private func writeLines(_ lines: [Data], to file: URL) throws {
        var out = Data()
        for line in lines { out.append(line); out.append(10) }
        try out.write(to: file, options: .atomic)
    }
    /// Raw JSON mutation followed by a real reseal, so the edited document
    /// keeps a valid envelope hash and the audit sees the semantic change.
    private func resealed(_ data: Data, mutate: (inout [String: Any]) -> Void) throws -> Data {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&raw)
        let edited = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        var sealed = try ContractJSON.line(ContractJSON.seal(edited))
        sealed.removeLast()
        return sealed
    }
    private func reviewFile(for subjectId: String, in reviews: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: reviews, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            for line in try lines(of: file) {
                guard let raw = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let payload = raw["payload"] as? [String: Any],
                      payload["subject_id"] as? String == subjectId else { continue }
                return file
            }
        }
        throw ContractFailure("no_review_for:\(subjectId)")
    }

    func testValidFixturePassesWithCurrentRevisionCoverage() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let report = try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        XCTAssertTrue(report.valid)
        XCTAssertEqual(report.denominatorSource, "dataset-current-revisions")
        XCTAssertTrue(report.reviewsSelfReportedDenominatorIgnored)
        // 1 entry + 1 sense + 1 target + 1 teaching + 2 questions +
        // 2 feedback units + 2 distractor-rationale units.
        XCTAssertEqual(report.totalUnits, 10)
        XCTAssertEqual(report.coveredUnits, 10)
        XCTAssertEqual(report.coverage, 1.0)
        XCTAssertEqual(report.subjectsByKind["question"], 2)
        XCTAssertEqual(report.blindSolveCount, 2)
        XCTAssertEqual(report.unresolvedCriticalFindings, 0)
    }

    func testMissingSenseCannotPass() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let senseId = "lx:sense:22222222-2222-2222-2222-222222222222"
        let file = try reviewFile(for: senseId, in: copy.reviews)
        let kept = try lines(of: file).filter { line in
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
            let payload = try XCTUnwrap(raw["payload"] as? [String: Any])
            return payload["subject_id"] as? String != senseId
        }
        try writeLines(kept, to: file)
        XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("missing_review"), "\(error)")
            XCTAssertTrue(String(describing: error).contains(senseId), "\(error)")
        }
    }

    func testStaleRevisionCannotPass() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let targetId = "lx:target:33333333-3333-3333-3333-333333333333"
        let file = try reviewFile(for: targetId, in: copy.reviews)
        let rewritten = try lines(of: file).map { line -> Data in
            let raw = try JSONSerialization.jsonObject(with: line) as? [String: Any]
            let subject = (raw?["payload"] as? [String: Any])?["subject_id"] as? String
            guard subject == targetId else { return line }
            return try resealed(line) { edited in
                var payload = edited["payload"] as! [String: Any]
                payload["subject_revision"] = 999
                edited["payload"] = payload
            }
        }
        try writeLines(rewritten, to: file)
        XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("stale_revision"), "\(error)")
        }
    }

    func testGeneratorSessionCannotReviewOwnBatch() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let questionId = "lx:question:55555555-5555-5555-5555-555555555555"
        let file = try reviewFile(for: questionId, in: copy.reviews)
        let rewritten = try lines(of: file).map { line -> Data in
            let raw = try JSONSerialization.jsonObject(with: line) as? [String: Any]
            let subject = (raw?["payload"] as? [String: Any])?["subject_id"] as? String
            guard subject == questionId else { return line }
            return try resealed(line) { edited in
                var payload = edited["payload"] as! [String: Any]
                payload["reviewer_session"] = "author-session-1"
                edited["payload"] = payload
            }
        }
        try writeLines(rewritten, to: file)
        XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("self_review"), "\(error)")
        }
    }

    func testBlindPayloadContainsNoKeyOrAnswerHint() throws {
        // Near-miss A: a forbidden accepted_answers key inside the blind input.
        do {
            let copy = try freshCopy()
            defer { try? FileManager.default.removeItem(at: copy.temp) }
            let inputs = copy.reviews.appendingPathComponent("blind-inputs")
            let file = try FileManager.default.contentsOfDirectory(at: inputs, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.first!
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            raw["accepted_answers"] = ["option-a"]
            try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: file)
            XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) { error in
                XCTAssertTrue(String(describing: error).contains("blind_leak"), "\(error)")
            }
        }
        // Near-miss B: the sense gloss smuggled into the free-text rules.
        do {
            let copy = try freshCopy()
            defer { try? FileManager.default.removeItem(at: copy.temp) }
            let inputs = copy.reviews.appendingPathComponent("blind-inputs")
            let files = try FileManager.default.contentsOfDirectory(at: inputs, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            // The fixture sense gloss is 合併; planting it in rules must trip the scan.
            for file in files {
                var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
                raw["rules"] = "請選出「合併」之意，答案是 form。"
                try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: file)
            }
            XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) { error in
                XCTAssertTrue(String(describing: error).contains("blind_leak"), "\(error)")
            }
        }
        // Near-miss C: an answer-derivable blind input filename.
        do {
            let copy = try freshCopy()
            defer { try? FileManager.default.removeItem(at: copy.temp) }
            let inputs = copy.reviews.appendingPathComponent("blind-inputs")
            let fm = FileManager.default
            let files = try fm.contentsOfDirectory(at: inputs, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            try fm.moveItem(at: files[0], to: inputs.appendingPathComponent("blind-answer-is-form.json"))
            XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) { error in
                XCTAssertTrue(String(describing: error).contains("blind_leak"), "\(error)")
            }
        }
    }

    func testCoverageDenominatorComesFromDatasetNotReviews() throws {
        // A reviews-side self report claiming a tiny denominator is ignored.
        do {
            let copy = try freshCopy()
            defer { try? FileManager.default.removeItem(at: copy.temp) }
            let claim = """
                {"covered":1,"total":1,"claim":"all pass per reviews-side count"}
                """
            try Data(claim.utf8).write(to: copy.reviews.appendingPathComponent("claimed-coverage.json"))
            let report = try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
            XCTAssertTrue(report.valid)
            XCTAssertEqual(report.totalUnits, 10)
            XCTAssertTrue(report.reviewsSelfReportedDenominatorIgnored)
        }
        // A review for a subject the dataset never issued cannot widen or
        // shrink the denominator; it fails closed as unknown.
        do {
            let copy = try freshCopy()
            defer { try? FileManager.default.removeItem(at: copy.temp) }
            let questionId = "lx:question:55555555-5555-5555-5555-555555555555"
            let file = try reviewFile(for: questionId, in: copy.reviews)
            var existing = try lines(of: file)
            let ghost = try resealed(existing[0]) { edited in
                var payload = edited["payload"] as! [String: Any]
                payload["subject_id"] = "lx:question:99999999-9999-9999-9999-999999999999"
                edited["record_id"] = "review/ghost-extra"
                edited["payload"] = payload
            }
            existing.append(ghost)
            try writeLines(existing, to: file)
            XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) { error in
                let text = String(describing: error)
                XCTAssertTrue(text.contains("unknown_subject") || text.contains("stale_revision"), text)
            }
        }
    }

    func testGeneratorCannotSignHumanRecheck() throws {
        // Generator-signed acceptance without a human reply is forged.
        do {
            let copy = try freshCopy()
            defer { try? FileManager.default.removeItem(at: copy.temp) }
            let human = copy.reviews.appendingPathComponent("human-recheck.jsonl")
            let rows = try lines(of: human)
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: rows[0]) as? [String: Any])
            raw["human_status"] = "accepted"
            raw["signed_by"] = "author-session-1"
            raw["human_reply_source"] = NSNull()
            let edited = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
            try writeLines([edited], to: human)
            XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) { error in
                XCTAssertTrue(String(describing: error).contains("human_signoff_forged"), "\(error)")
            }
        }
        // Even with a reply note, the generator session can never sign for the owner.
        do {
            let copy = try freshCopy()
            defer { try? FileManager.default.removeItem(at: copy.temp) }
            let human = copy.reviews.appendingPathComponent("human-recheck.jsonl")
            let rows = try lines(of: human)
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: rows[0]) as? [String: Any])
            raw["human_status"] = "accepted"
            raw["signed_by"] = "author-session-1"
            raw["human_reply_source"] = "owner reply 2026-10-12"
            let edited = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
            try writeLines([edited], to: human)
            XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) { error in
                XCTAssertTrue(String(describing: error).contains("human_signoff_forged"), "\(error)")
            }
        }
    }

    func testReviewsAuditCLI() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let evidence = copy.temp.appendingPathComponent("coverage.json")
        XCTAssertEqual(CKCLI.run(["reviews", "audit",
            "--dataset", copy.dataset.path, "--reviews", copy.reviews.path,
            "--profile", Self.trialProfile, "--evidence", evidence.path]), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: evidence.path))
        // The broken copy (sense review removed) exits non-zero with a typed reason.
        let senseId = "lx:sense:22222222-2222-2222-2222-222222222222"
        let file = try reviewFile(for: senseId, in: copy.reviews)
        let kept = try lines(of: file).filter { line in
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
            let payload = try XCTUnwrap(raw["payload"] as? [String: Any])
            return payload["subject_id"] as? String != senseId
        }
        try writeLines(kept, to: file)
        let badEvidence = copy.temp.appendingPathComponent("coverage-bad.json")
        XCTAssertNotEqual(CKCLI.run(["reviews", "audit",
            "--dataset", copy.dataset.path, "--reviews", copy.reviews.path,
            "--evidence", badEvidence.path]), 0)
    }

    private func mutateSolves(_ reviews: URL, mutate: (inout [String: Any]) -> Void) throws {
        let file = reviews.appendingPathComponent("blind-solves.jsonl")
        var rows = try lines(of: file)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: rows[0]) as? [String: Any])
        mutate(&raw)
        rows[0] = try JSONSerialization.data(withJSONObject: raw)
        try writeLines(rows, to: file)
    }

    func testSplitBlindFilesAndFamilyArtifacts() throws {
        for name in ["blind-batch-1.jsonl", "blind-check-1.jsonl", "blind-train-r3.jsonl", "blind-check-r3.jsonl"] {
            let copy = try freshCopy()
            defer { try? FileManager.default.removeItem(at: copy.temp) }
            try FileManager.default.moveItem(at: copy.reviews.appendingPathComponent("blind-solves.jsonl"),
                to: copy.reviews.appendingPathComponent(name))
            for family in ["family-verdicts.jsonl", "family-verdicts-r3.jsonl"] {
                try Data("{\"verdict\":\"independent\"}\n".utf8).write(to: copy.reviews.appendingPathComponent(family))
            }
            XCTAssertEqual(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil).blindSolveCount, 2)
        }
    }

    func testSplitAndLegacySolvesAreAllLoadedWithCurrentBinding() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let file = copy.reviews.appendingPathComponent("blind-solves.jsonl")
        try FileManager.default.copyItem(at: file, to: copy.reviews.appendingPathComponent("blind-check-r3.jsonl"))
        var stale = try XCTUnwrap(JSONSerialization.jsonObject(with: lines(of: file)[0]) as? [String: Any])
        stale["question_revision"] = 999; stale["answerable"] = false
        try writeLines([JSONSerialization.data(withJSONObject: stale)], to: copy.reviews.appendingPathComponent("blind-train-r3.jsonl"))
        XCTAssertEqual(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil).blindSolveCount, 4)
    }

    func testProvenanceExtrasPreserveDenominator() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let provenance = try ContractJSON.decode(lines(of: copy.dataset.appendingPathComponent("provenance.jsonl"))[0])
        let source = try lines(of: copy.reviews.appendingPathComponent("reviews.jsonl"))[0]
        let extra = try resealed(source) { raw in
            raw["record_id"] = "review/provenance-extra"
            var payload = raw["payload"] as! [String: Any]
            payload["subject_id"] = provenance.recordId
            payload["subject_kind"] = "provenance"
            payload["subject_revision"] = provenance.document.revision
            payload["subject_content_sha256"] = provenance.contentSha256
            raw["payload"] = payload
        }
        try writeLines([extra], to: copy.reviews.appendingPathComponent("extras.jsonl"))
        let report = try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews,
            profile: URL(fileURLWithPath: Self.trialProfile))
        XCTAssertEqual(report.totalUnits, 10)
        XCTAssertNil(report.subjectsByKind["provenance"])
    }

    func testBlindWrongKeyRejected() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let solve = try XCTUnwrap(JSONSerialization.jsonObject(with: lines(of: copy.reviews.appendingPathComponent("blind-solves.jsonl"))[0]) as? [String: Any])
        let question = try lines(of: copy.dataset.appendingPathComponent("questions.jsonl")).map { try ContractJSON.decode($0) }
            .first { $0.recordId == solve["question_id"] as? String }
        guard case .question(let q) = question else { return XCTFail("missing question") }
        let wrong = try XCTUnwrap(q.payload.options.first { !q.payload.acceptedAnswers.contains($0.optionId) })
        try mutateSolves(copy.reviews) { $0["chosen_option_id"] = wrong.optionId }
        XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) {
            XCTAssertTrue(String(describing: $0).contains("blind_key_mismatch"), "\($0)")
        }
    }

    func testBlindUnanswerableRejected() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        try mutateSolves(copy.reviews) { $0["answerable"] = false }
        XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) {
            XCTAssertTrue(String(describing: $0).contains("blind_unanswerable"), "\($0)")
        }
    }

    func testAmbiguityCountDoesNotReject() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let before = try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil).blindAmbiguityCount
        let file = copy.reviews.appendingPathComponent("blind-solves.jsonl")
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: lines(of: file)[0]) as? [String: Any])
        let hadNote = !(raw["ambiguity_notes"] as! String).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        try mutateSolves(copy.reviews) { $0["ambiguity_notes"] = "Potential alternative; disposition required in review." }
        XCTAssertEqual(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil).blindAmbiguityCount,
                       before + (hadNote ? 0 : 1))
    }

    func testWritingRequiresResponseButDoesNotMatchOptionKey() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let solve = try XCTUnwrap(JSONSerialization.jsonObject(with: lines(of: copy.reviews.appendingPathComponent("blind-solves.jsonl"))[0]) as? [String: Any])
        let id = solve["question_id"] as! String
        let qfile = copy.dataset.appendingPathComponent("questions.jsonl")
        let rewritten = try lines(of: qfile).map { data -> Data in
            let record = try ContractJSON.decode(data)
            guard record.recordId == id else { return data }
            return try resealed(data) { raw in
                var p = raw["payload"] as! [String: Any]
                p["tested_ability"] = "writing"; p["options"] = []; p["distractor_rationales"] = []
                p["accepted_answers"] = ["written response"]; raw["payload"] = p
            }
        }
        try writeLines(rewritten, to: qfile)
        let question = try XCTUnwrap(rewritten.map { try ContractJSON.decode($0) }.first { $0.recordId == id })
        let rfile = try reviewFile(for: id, in: copy.reviews)
        let updated = try lines(of: rfile).map { data -> Data in
            guard case .review(let review) = try ContractJSON.decode(data), review.payload.subjectId == id else { return data }
            return try resealed(data) { raw in
                var p = raw["payload"] as! [String: Any]
                p["subject_content_sha256"] = question.contentSha256
                var items = p["checklist"] as! [[String: Any]]
                for i in items.indices where items[i]["item"] as? String == "distractor-rationales" {
                    items[i]["result"] = "not_applicable"
                }
                p["checklist"] = items; raw["payload"] = p
            }
        }
        try writeLines(updated, to: rfile)
        let input = copy.reviews.appendingPathComponent("blind-inputs/blind-\(id.split(separator: ":").last!).json")
        var projection = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: input)) as? [String: Any])
        projection["options"] = []
        try JSONSerialization.data(withJSONObject: projection).write(to: input)
        try mutateSolves(copy.reviews) { $0["chosen_option_id"] = NSNull(); $0["response_text"] = "  " }
        XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) {
            XCTAssertTrue(String(describing: $0).contains("blind_writing_response_required"), "\($0)")
        }
        try mutateSolves(copy.reviews) { $0["response_text"] = "An independently written response" }
        XCTAssertTrue(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil).valid)
    }

    func testChecklistDumpMatchesRequiredFixtureIDs() throws {
        let file = Self.validRoot.appendingPathComponent("reviews/reviews.jsonl")
        for line in try lines(of: file) {
            guard case .review(let review) = try ContractJSON.decode(line) else { return XCTFail("not review") }
            XCTAssertEqual(Set(try XCTUnwrap(ReviewCoverage.checklistIDs[review.payload.subjectKind.rawValue])),
                           Set(review.payload.checklist.map(\.item)))
        }
        XCTAssertEqual(ReviewCoverage.checklistIDs["question"]?.count, 8)
        XCTAssertEqual(CKCLI.run(["reviews", "--dump-checklist-ids"]), 0)
    }

    func testAgentAcceptedHappyAndFailClosedCLI() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let output = copy.temp.appendingPathComponent("accepted.json")
        let args = ["--dataset", copy.dataset.path, "--stage", "agent-accepted", "--reviews", copy.reviews.path,
                    "--profile", Self.trialProfile, "--expected-words", "1", "--expected-phrases", "0", "--evidence", output.path]
        let report = try ContractDataset.validate(arguments: args)
        XCTAssertTrue(report.acceptanceEvaluated); XCTAssertFalse(report.releaseEligible)
        XCTAssertEqual(report.stage, "agent-accepted"); XCTAssertEqual(report.acceptedCount, 6)
        XCTAssertEqual(report.quarantinedCount, 0)
        XCTAssertEqual(report.expectedWords, report.actualWords)
        XCTAssertEqual(report.expectedPhrases, report.actualPhrases)
        XCTAssertEqual(CKCLI.run(["validate"] + args), 0)
        let receipt = try Data(contentsOf: output)
        var mismatch = args; mismatch[9] = "50"
        XCTAssertEqual(CKCLI.run(["validate"] + mismatch), 65)
        XCTAssertEqual(CKCLI.run(["validate"] + Array(args.dropLast(2))), 65)
        var duplicate = args; duplicate[10] = "--expected-words"
        XCTAssertEqual(CKCLI.run(["validate"] + duplicate), 65)
        var negative = args; negative[9] = "-1"
        XCTAssertEqual(CKCLI.run(["validate"] + negative), 65)
        var overlap = args; overlap[13] = copy.reviews.appendingPathComponent("reviews.jsonl").path
        XCTAssertEqual(CKCLI.run(["validate"] + overlap), 65)
        try mutateSolves(copy.reviews) { $0["answerable"] = false }
        XCTAssertEqual(CKCLI.run(["validate"] + args), 65)
        XCTAssertEqual(try Data(contentsOf: output), receipt)
    }

    func testAgentAcceptedRejectsQuarantinedContentAndCandidateReceiptIsUnchanged() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let candidate = try ContractDataset.validate(at: copy.dataset)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractJSON.bytes(candidate)) as? [String: Any])
        XCTAssertEqual(Set(raw.keys), ["valid", "stage", "record_count", "counts", "canonical_sha256", "acceptance_evaluated", "release_eligible"])
        let file = copy.dataset.appendingPathComponent("entries.jsonl")
        try writeLines([resealed(lines(of: file)[0]) { raw in
            var p = raw["payload"] as! [String: Any]; p["status"] = "quarantined"; raw["payload"] = p
        }], to: file)
        XCTAssertThrowsError(try ContractDataset.validate(arguments: ["--dataset", copy.dataset.path,
            "--stage", "agent-accepted", "--reviews", copy.reviews.path, "--profile", Self.trialProfile,
            "--expected-words", "1", "--expected-phrases", "0", "--evidence", copy.temp.appendingPathComponent("out.json").path])) {
            XCTAssertTrue(String(describing: $0).contains("quarantined_records"), "\($0)")
        }
    }
}
