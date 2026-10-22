import Foundation
import XCTest
@testable import ContentModel

/// M1 Task14 acceptance gate on real pilot-230-derived fixtures.
///
/// Fixture provenance: see Fixtures/ReviewAcceptance/derivation.json. One real
/// meaning_recognition question plus its correct sense, their genuine passed
/// reviews, the real blind-230-01 solve row (kept under its new-style name),
/// the real blind input (kept under blind-inputs-r2/ only), and one flat
/// family-diverge verdict row. Baseline must pass before any mutation, so an
/// unrelated loader gap cannot make a rejection assertion succeed for the
/// wrong reason.
final class ReviewAcceptanceTests: XCTestCase {
    private let questionId = "lx:question:00630860-548e-4be4-92db-990184f95034"
    private let senseId = "lx:sense:0c80652c-118e-47bf-8752-e30cbb1418fe"

    private struct AcceptanceCopy {
        let root: URL
        var dataset: URL { root.appendingPathComponent("dataset") }
        var reviews: URL { root.appendingPathComponent("reviews") }
    }

    private func acceptanceCopy() throws -> AcceptanceCopy {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ReviewAcceptance")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("dataset"),
                                         to: root.appendingPathComponent("dataset"))
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("reviews"),
                                         to: root.appendingPathComponent("reviews"))
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let copy = AcceptanceCopy(root: root)
        let report = try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        XCTAssertTrue(report.valid)
        XCTAssertEqual(report.totalUnits, 4)
        XCTAssertEqual(report.coveredUnits, 4)
        XCTAssertEqual(report.blindSolveCount, 1)
        return copy
    }

    private func reject(_ reason: String, action: () throws -> ReviewCoverageReport) {
        XCTAssertThrowsError(try action()) { error in
            let failure = error as? ReviewCoverageFailure
            XCTAssertEqual(failure?.reason, reason, "\(error)")
            print("ReviewAcceptance mutation rejected: \(error)")
        }
    }

    func testMissingOneOfAllRecordsFails() throws {
        // Given: unchanged real question/sense rows and their genuine passed reviews.
        let copy = try acceptanceCopy()
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

    func testChangedFeedbackInvalidatesPass() throws {
        // Given: a passed real pilot-230 slice; preserve the old review verbatim.
        let copy = try acceptanceCopy()
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

    func testBlindDisagreementQuarantines() throws {
        // Given: the real blind-230-01 solve and a genuine listed but unaccepted alternative.
        let copy = try acceptanceCopy()
        guard case .question(let question) = try ContractJSON.decode(
            Data(contentsOf: copy.dataset.appendingPathComponent("question.jsonl"))) else {
            return XCTFail("Expected real question")
        }
        let alternative = try XCTUnwrap(question.payload.options.first {
            !question.payload.acceptedAnswers.contains($0.optionId)
        })
        let file = copy.reviews.appendingPathComponent("blind-230-01.jsonl")
        var solve = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        solve["chosen_option_id"] = alternative.optionId
        solve["ambiguity_notes"] = "Synthetic disagreement mutation: solver chooses another listed option."
        let data = try JSONSerialization.data(withJSONObject: solve, options: [.sortedKeys, .withoutEscapingSlashes])
        try (data + Data([10])).write(to: file, options: .atomic)
        // When / Then: disagreement against the key quarantines the question.
        reject("blind_key_mismatch:\(questionId)") {
            try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        }
    }

    func testSummaryCannotReplacePerItemEvidence() throws {
        // Given: a reviews-side summary claiming full passage plus the intact fixture.
        let copy = try acceptanceCopy()
        let claim = """
            {"covered":2,"total":2,"claim":"all pass per reviews-side summary"}
            """
        try Data(claim.utf8).write(to: copy.reviews.appendingPathComponent("claimed-coverage.json"))
        let report = try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        XCTAssertTrue(report.valid)
        XCTAssertEqual(report.totalUnits, 4)
        XCTAssertTrue(report.reviewsSelfReportedDenominatorIgnored)
        // When: one per-item review is removed beneath the summary claim.
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
        // Then: the summary cannot cover the missing per-item evidence.
        reject("missing_review:\(senseId)@1") {
            try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        }
    }
}
