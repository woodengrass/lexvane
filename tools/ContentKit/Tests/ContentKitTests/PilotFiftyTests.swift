import Foundation
import XCTest
@testable import ContentModel

final class PilotFiftyTests: XCTestCase {
    private let questionId = "lx:question:03dd6afe-5dfe-4035-b57f-59ebe06961d6"
    private let senseId = "lx:sense:004d2ed5-8b48-4711-aa03-5194a37b6e66"

    private struct TrialCopy {
        let root: URL
        var dataset: URL { root.appendingPathComponent("dataset") }
        var reviews: URL { root.appendingPathComponent("reviews") }
    }

    private func trialCopy() throws -> TrialCopy {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/PilotFifty")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixtures, to: root)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let copy = TrialCopy(root: root)
        // Baseline must pass before any mutation, so unrelated quarantine cannot
        // make a rejection assertion succeed for the wrong reason.
        let report = try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        XCTAssertTrue(report.valid)
        XCTAssertEqual(report.blindSolveCount, 1)
        return copy
    }

    private func writeJSON(_ value: [String: Any], to file: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(10)
        try data.write(to: file)
    }

    private func reject(_ reason: String, action: () throws -> ReviewCoverageReport) {
        XCTAssertThrowsError(try action()) { error in
            let failure = error as? ReviewCoverageFailure
            XCTAssertEqual(failure?.reason, reason, "\(error)")
            print("PilotFifty mutation rejected: \(error)")
        }
    }

    func testDroppedRealSenseReviewFails() throws {
        // Given: unchanged real question/sense rows and their genuine passed reviews.
        let copy = try trialCopy()
        let file = copy.reviews.appendingPathComponent("reviews.jsonl")
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        var retained = Data()
        for line in lines {
            guard case .review(let review) = try ContractJSON.decode(Data(line.utf8)) else {
                return XCTFail("Expected real review")
            }
            if review.payload.subjectId != senseId {
                retained.append(contentsOf: line.utf8)
                retained.append(10)
            }
        }
        try retained.write(to: file)
        // When / Then: the one removed sense review must fail its own coverage invariant.
        reject("missing_review:\(senseId)@1") {
            try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        }
    }

    func testChangedRealFeedbackCannotReuseOldPass() throws {
        // Given: a passed real trial slice; preserve the old review verbatim.
        let copy = try trialCopy()
        let file = copy.dataset.appendingPathComponent("question.jsonl")
        var row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let revision = try XCTUnwrap(row["revision"] as? Int)
        var payload = try XCTUnwrap(row["payload"] as? [String: Any])
        var feedback = try XCTUnwrap(payload["post_answer_feedback"] as? [String: Any])
        feedback["explanation"] = "Synthetic failure mutation: feedback changed after review."
        payload["post_answer_feedback"] = feedback
        row["payload"] = payload
        row["revision"] = revision + 1
        let revised = try ContractJSON.seal(JSONSerialization.data(withJSONObject: row))
        try ContractJSON.line(revised).write(to: file)
        // When / Then: valid resealing cannot rescue the old review binding.
        reject("stale_revision:\(questionId)") {
            try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        }
    }

    func testAlternativeRealBlindOptionFailsKeyMatch() throws {
        // Given: the real r3 solve and a genuine listed but unaccepted alternative.
        let copy = try trialCopy()
        guard case .question(let question) = try ContractJSON.decode(
            Data(contentsOf: copy.dataset.appendingPathComponent("question.jsonl"))) else {
            return XCTFail("Expected real question")
        }
        let alternative = try XCTUnwrap(question.payload.options.first {
            !question.payload.acceptedAnswers.contains($0.optionId)
        })
        let file = copy.reviews.appendingPathComponent("blind-solves.jsonl")
        var solve = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        solve["chosen_option_id"] = alternative.optionId
        solve["ambiguity_notes"] = "Synthetic multi-answer mutation: solver chooses another listed option."
        try writeJSON(solve, to: file)
        // When / Then: notes alone are not the invariant; the wrong listed key is.
        reject("blind_key_mismatch:\(questionId)") {
            try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        }
    }

    func testQuotaInterruptedRealQuestionJobCannotBecomeAccepted() throws {
        // Given: a job bound to the real question's revision/hash, interrupted by quota.
        let copy = try trialCopy()
        guard case .question(let question) = try ContractJSON.decode(
            Data(contentsOf: copy.dataset.appendingPathComponent("question.jsonl"))) else {
            return XCTFail("Expected real question")
        }
        let model = "openai/gpt-6.1-sol"
        let promptHash = CKHash.sha256Hex(of: Data("synthetic-quota-mutation-prompt".utf8))
        let binding = JobBinding(jobId: "jobs/pilot-fifty-quota-mutation", role: .blindSolve,
            inputHash: question.contentSha256, model: model,
            modelHash: CKHash.sha256Hex(of: Data(model.utf8)),
            promptRef: "synthetic-quota-mutation", promptHash: promptHash,
            records: [JobRecord(recordId: question.recordId, kind: .question,
                                revision: question.revision, contentHash: question.contentSha256)])
        let ledger = copy.root.appendingPathComponent("quota-jobs.jsonl")
        try JobLedger.append(JobEvent(binding: binding, state: .pending), to: ledger)
        try JobLedger.append(JobEvent(binding: binding, state: .running), to: ledger)
        try JobLedger.append(JobEvent(binding: binding, state: .jobFailed,
            failure: JobFailureDetail(reason: .quota, resumable: true)), to: ledger)
        // When / Then: jobs own interruption semantics; coverage has no job-state input.
        XCTAssertThrowsError(try JobLedger.append(JobEvent(binding: binding, state: .validated), to: ledger)) { error in
            XCTAssertEqual((error as? JobFailure)?.reason, "invalid_transition", "\(error)")
            print("PilotFifty quota mutation rejected: \(error); source=\(self.questionId)")
        }
        XCTAssertEqual(try JobLedger.audit(at: ledger).acceptedCount, 0)
        XCTAssertEqual(try JobLedger.resume(at: ledger, binding: binding, receiptRef: nil), .retryAllowed)
    }
}
