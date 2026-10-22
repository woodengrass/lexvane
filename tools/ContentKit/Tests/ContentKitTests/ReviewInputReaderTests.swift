import Foundation
import XCTest
import ContentCLI
import ContentModel

final class ReviewInputReaderTests: XCTestCase {
    private func fixture() throws -> URL {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/reviews/valid")
        let scratch = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let root = scratch.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }
    private func audit(_ root: URL) throws -> ReviewCoverageReport {
        try ReviewCoverage.audit(dataset: root.appendingPathComponent("dataset"), reviews: root.appendingPathComponent("reviews"), profile: nil)
    }
    private func graph(_ root: URL) -> DatasetGraphReport {
        DatasetValidator.validate(at: root.appendingPathComponent("dataset"), sources: root.appendingPathComponent("absent-registry"),
            reviews: root.appendingPathComponent("reviews"), ledger: root.appendingPathComponent("absent-ledger"),
            profile: root.appendingPathComponent("absent-profile"))
    }
    private func packet(_ root: URL) throws {
        let file = root.appendingPathComponent("dataset/questions.jsonl")
        let line = try XCTUnwrap(String(decoding: Data(contentsOf: file), as: UTF8.self).split(separator: "\n").first)
        let subject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let row: [String: Any] = ["record_id": try XCTUnwrap(subject["record_id"]), "kind": "question",
            "revision": 1, "content_sha256": try XCTUnwrap(subject["content_sha256"]), "subject": subject,
            "human_status": "pending", "human_decision": NSNull(), "selection_reasons": ["stratified_random"]]
        try (JSONSerialization.data(withJSONObject: row) + Data([10])).write(to: root.appendingPathComponent("reviews/human-recheck.jsonl"))
    }
    func testEmptyHumanDecisionsIsValidPendingForReviewCoverage() throws {
        let root = try fixture()
        try Data().write(to: root.appendingPathComponent("reviews/human-decisions.jsonl"))
        XCTAssertEqual(try audit(root).coveredUnits, 10)
    }
    func testHumanPacketKindIsNotASealedReviewForGraphReader() throws {
        let root = try fixture()
        try packet(root)
        let report = graph(root)
        XCTAssertFalse(report.defects.contains { $0.code == .invalidRecord && $0.recordId == "human-recheck.jsonl" }, "\(report.defects)")
        XCTAssertTrue(report.humanReviewPending)
        XCTAssertFalse(report.releaseEligible)
    }
    func testEmptyPendingDecisionsDoesNotCreateGraphRecordDefect() throws {
        let root = try fixture()
        try Data().write(to: root.appendingPathComponent("reviews/human-decisions.jsonl"))
        XCTAssertFalse(graph(root).defects.contains { $0.code == .invalidRecord && $0.recordId == "human-decisions.jsonl" })
    }
    func testMixedArtifactsAndHumanPacketRetainSealedCoverage() throws {
        let root = try fixture()
        try packet(root)
        try Data().write(to: root.appendingPathComponent("reviews/human-decisions.jsonl"))
        try Data("{\"verdict\":\"independent\"}\n".utf8).write(to: root.appendingPathComponent("reviews/family-verdicts.jsonl"))
        XCTAssertEqual(try audit(root).coveredUnits, 10)
    }
    func testPacketCannotSubstituteForMissingSealedReviews() throws {
        let root = try fixture()
        try packet(root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("reviews/reviews.jsonl"))
        XCTAssertThrowsError(try audit(root)) { error in
            XCTAssertTrue(String(describing: error).contains("missing_review:"), "\(error)")
        }
    }
    func testSealedReviewUnderArtifactFilenameCannotEscapeValidation() throws {
        let root = try fixture()
        try Data("{\"schema\":\"lexvane.content.v1\",\"kind\":\"review\",\"payload\":{}}\n".utf8)
            .write(to: root.appendingPathComponent("reviews/family-hidden-review.jsonl"))
        XCTAssertThrowsError(try audit(root)) { error in
            XCTAssertTrue(String(describing: error).contains("family-hidden-review.jsonl"), "\(error)")
        }
    }
    func testNonemptyHumanDecisionsCannotBeSilentlyIgnored() throws {
        let root = try fixture()
        try Data("{\"record_id\":\"q1\",\"status\":\"approved\",\"signed_by\":\"agent\"}\n".utf8)
            .write(to: root.appendingPathComponent("reviews/human-decisions.jsonl"))
        XCTAssertThrowsError(try audit(root)) { error in
            XCTAssertTrue(String(describing: error).contains("human_decisions_require_explicit_validation"), "\(error)")
        }
        XCTAssertTrue(graph(root).defects.contains { $0.detail.contains("human_decisions_require_explicit_validation") })
    }
    func testEmptySealedReviewFileStillFailsClosed() throws {
        let root = try fixture()
        try Data().write(to: root.appendingPathComponent("reviews/reviews.jsonl"))
        XCTAssertThrowsError(try audit(root)) { error in
            XCTAssertTrue(String(describing: error).contains("invalid_jsonl:reviews.jsonl"), "\(error)")
        }
        XCTAssertTrue(graph(root).defects.contains { $0.code == .invalidRecord && $0.recordId == "reviews.jsonl" })
    }
}
