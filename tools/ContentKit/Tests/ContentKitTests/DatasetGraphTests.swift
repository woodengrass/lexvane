import Foundation
import XCTest
import ContentCLI
@testable import ContentModel

final class DatasetGraphTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/reviews/valid/dataset")

    private func records() throws -> [ContractRecord] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .sorted { $0.path < $1.path }.flatMap { file in
                try CKJSONL.readLines(at: file).map { try ContractJSON.decode(Data($0.utf8)) }
            }
    }

    private func edited(_ record: ContractRecord, _ edit: (inout [String: Any]) -> Void) throws -> ContractRecord {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractJSON.line(record)) as? [String: Any])
        var payload = try XCTUnwrap(raw["payload"] as? [String: Any])
        edit(&payload)
        raw["payload"] = payload
        return try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw))
    }

    func testDanglingSenseRejected() throws {
        let input = try records().filter { $0.document.kind != .sense }
        let report = DatasetValidator.audit(records: input, sources: [], reviews: [])
        XCTAssertFalse(report.valid)
        XCTAssertTrue(report.defects.contains { $0.code == .danglingReference && $0.field == "payload.sense_ids[0]" })
    }

    func testWrongTargetReviewRejected() throws {
        var input = try records()
        let index = try XCTUnwrap(input.firstIndex { $0.document.kind == .question })
        input[index] = try edited(input[index]) { $0["correct_sense_id"] = "lx:sense:99999999-9999-4999-8999-999999999999" }
        let report = DatasetValidator.audit(records: input, sources: [], reviews: [])
        XCTAssertTrue(report.defects.contains { $0.code == .targetSenseMismatch && $0.recordId == input[index].recordId && $0.field == "payload.correct_sense_id" })
    }

    private func source(_ id: String, pending: Bool = false, ancestors: [SourceAncestor] = []) -> SourceRecord {
        SourceRecord(sourceID: id, locator: "local", version: "1", publicationDate: nil,
            effectiveFrom: nil, effectiveTo: nil, kind: "authored", examYear: nil,
            retrievedAt: "2026-01-01T00:00:00Z", contentSHA256: nil, contentSHA256Reason: "fixture",
            attribution: id, licenseTextRef: "license.txt", permissions: Dictionary(uniqueKeysWithValues:
                SourceOperation.allCases.map { ($0.rawValue, SourcePermission(status: pending ? .pending : .allowed,
                    evidence: "license.txt", quote: "grant")) }), ancestors: ancestors)
    }

    private func validGraph() throws -> (records: [ContractRecord], reviews: [Review]) {
        var input = try records()
        let reviewFile = root.deletingLastPathComponent().appendingPathComponent("reviews/reviews.jsonl")
        let reviews = try CKJSONL.readLines(at: reviewFile).map { line -> Review in
            guard case .review(let review) = try ContractJSON.decode(Data(line.utf8)) else { throw ContractFailure("expected_review") }
            return review
        }
        let subjects = Dictionary(uniqueKeysWithValues: input.filter { $0.document.kind != .provenance }.map { ($0.recordId, $0) })
        for index in input.indices {
            guard case .provenance(let provenance) = input[index] else { continue }
            let subject = try XCTUnwrap(subjects[provenance.payload.subjectId])
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractJSON.line(subject)) as? [String: Any])
            let payload = try XCTUnwrap(raw["payload"] as? [String: Any])
            let fields = Set(payload.keys).subtracting(["status", "provenance_refs"]).sorted()
            input[index] = try edited(input[index]) {
                $0["fields"] = fields.map { ["field": $0, "method": "ai_generated", "source_refs": [["source_id": "S01", "operations": ["reference"]]]] }
                $0["review_refs"] = reviews.filter { $0.payload.subjectId == subject.recordId }.map(\.recordId)
            }
        }
        return (input, reviews)
    }

    private func source(_ id: String, allowed: Set<SourceOperation>) -> SourceRecord {
        var row = source(id, pending: true)
        for operation in allowed {
            row.permissions[operation.rawValue] = SourcePermission(status: .allowed, evidence: "license.txt", quote: "grant")
        }
        return row
    }

    func testReferenceOnlyCitationNeedsNoPackGrant() throws {
        let graph = try validGraph()
        let report = DatasetValidator.audit(records: graph.records, sources: [source("S01", allowed: [.reference])], reviews: graph.reviews)
        XCTAssertTrue(report.valid, "\(report.defects)")
    }

    func testReferenceOnlyCitationStillNeedsReferenceGrant() throws {
        let graph = try validGraph()
        let report = DatasetValidator.audit(records: graph.records, sources: [source("S01", pending: true)], reviews: graph.reviews)
        XCTAssertTrue(report.defects.contains { $0.code == .sourcePermission && $0.detail.contains("reference") && $0.detail.contains("pending") })
    }

    func testNonReferenceCitationStillNeedsPackGrant() throws {
        var graph = try validGraph()
        for index in graph.records.indices where graph.records[index].document.kind == .provenance {
            graph.records[index] = try edited(graph.records[index]) {
                let fields = $0["fields"] as? [[String: Any]] ?? []
                $0["fields"] = fields.map { field -> [String: Any] in
                    var field = field
                    field["source_refs"] = [["source_id": "S01", "operations": ["adapt"]]]
                    return field
                }
            }
        }
        let report = DatasetValidator.audit(records: graph.records, sources: [source("S01", allowed: [.reference, .adapt])], reviews: graph.reviews)
        XCTAssertTrue(report.defects.contains { $0.code == .sourcePermission && $0.detail.contains("privatePack") })
    }

    func testCompleteInMemoryGraphPassesWithExplicitFixtureGrant() throws {
        let graph = try validGraph()
        let report = DatasetValidator.audit(records: graph.records, sources: [source("S01")], reviews: graph.reviews)
        XCTAssertTrue(report.valid, "\(report.defects)")
        XCTAssertEqual(report.activeRecordIds.count, 6)
        XCTAssertTrue(report.quarantinedRecordIds.isEmpty)
        XCTAssertFalse(report.releaseEligible)
        XCTAssertTrue(report.humanReviewPending)
    }

    func testPendingRightsPropagateToQuestionWithoutDirectSourceRefs() throws {
        let graph = try validGraph()
        let report = DatasetValidator.audit(records: graph.records, sources: [source("S01", pending: true)], reviews: graph.reviews)
        for question in graph.records where question.document.kind == .question {
            XCTAssertTrue(report.defects.contains { $0.recordId == question.recordId && $0.code == .sourcePermission && $0.field.hasPrefix("ancestors.") })
        }
    }

    func testReviewCannotAuthorizeWrongSense() throws {
        var graph = try validGraph()
        let index = try XCTUnwrap(graph.records.firstIndex { $0.document.kind == .question })
        graph.records[index] = try edited(graph.records[index]) { $0["correct_sense_id"] = "lx:sense:99999999-9999-4999-8999-999999999999" }
        let subject = graph.records[index].document
        graph.reviews = try graph.reviews.map { review in
            guard review.payload.subjectId == subject.recordId else { return review }
            guard case .review(let rewritten) = try edited(.review(review), { $0["subject_content_sha256"] = subject.contentSha256 }) else {
                throw ContractFailure("expected_review")
            }
            return rewritten
        }
        let report = DatasetValidator.audit(records: graph.records, sources: [source("S01")], reviews: graph.reviews)
        XCTAssertTrue(report.defects.contains { $0.recordId == subject.recordId && $0.code == .targetSenseMismatch })
        XCTAssertFalse(report.defects.contains { $0.recordId == subject.recordId && $0.code == .missingReview })
    }

    func testProvenanceReviewMustCoverSameSubject() throws {
        var graph = try validGraph()
        let index = try XCTUnwrap(graph.records.firstIndex { $0.document.kind == .provenance })
        guard case .provenance(let p) = graph.records[index] else { return XCTFail("expected provenance") }
        let wrong = try XCTUnwrap(graph.reviews.first { $0.payload.subjectId != p.payload.subjectId })
        graph.records[index] = try edited(graph.records[index]) { $0["review_refs"] = [wrong.recordId] }
        let report = DatasetValidator.audit(records: graph.records, sources: [source("S01")], reviews: graph.reviews)
        XCTAssertTrue(report.defects.contains { $0.recordId == p.recordId && $0.field == "payload.review_refs[0]" && $0.code == .reviewBinding })
    }

    func testQuarantineCannotSatisfyActiveDependencies() throws {
        var graph = try validGraph()
        let index = try XCTUnwrap(graph.records.firstIndex { $0.document.kind == .sense })
        graph.records[index] = try edited(graph.records[index]) { $0["status"] = "quarantined" }
        let report = DatasetValidator.audit(records: graph.records, sources: [source("S01")], reviews: graph.reviews)
        XCTAssertEqual(report.quarantinedRecordIds, [graph.records[index].recordId])
        XCTAssertFalse(report.activeRecordIds.contains(graph.records[index].recordId))
        XCTAssertTrue(report.defects.contains { $0.code == .quarantineDependency })
    }

    func testFeedbackMustBeAnAcceptedVariant() throws {
        var graph = try validGraph()
        let index = try XCTUnwrap(graph.records.firstIndex { $0.document.kind == .question })
        graph.records[index] = try edited(graph.records[index]) {
            $0["post_answer_feedback"] = ["answer": "hesitate", "explanation": "not the key"]
        }
        let report = DatasetValidator.audit(records: graph.records, sources: [source("S01")], reviews: graph.reviews)
        XCTAssertTrue(report.defects.contains { $0.recordId == graph.records[index].recordId && $0.code == .feedbackMismatch })
    }

    func testSharedTrainCheckFamilyRejected() throws {
        var graph = try validGraph()
        let questions = graph.records.indices.filter { graph.records[$0].document.kind == .question }
        guard case .question(let first) = graph.records[questions[0]] else { return XCTFail("expected question") }
        graph.records[questions[1]] = try edited(graph.records[questions[1]]) { $0["family_id"] = first.payload.familyId }
        let report = DatasetValidator.audit(records: graph.records, sources: [source("S01")], reviews: graph.reviews)
        XCTAssertTrue(report.defects.contains { $0.code == .familyMismatch && $0.field == "payload.family_id" })
    }

    func testDeclaredAliasCollisionRetainsAllValues() throws {
        var input = try records()
        let entry = try XCTUnwrap(input.first { $0.document.kind == .entry })
        let newID = "lx:word:99999999-9999-4999-8999-999999999999"
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractJSON.line(entry)) as? [String: Any])
        raw["record_id"] = newID
        input.append(try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw)))
        let declaration = ["merge": [entry.recordId, newID]]
        let report = DatasetValidator.audit(records: input, sources: [], reviews: [], aliasCollisions: declaration)
        XCTAssertEqual(Set(report.aliasIndex["merge"] ?? []), Set([entry.recordId, newID]))
        XCTAssertFalse(report.defects.contains { $0.code == .unknownAliasCollision })
    }

    func testCLIRejectsDuplicateGraphFlags() {
        XCTAssertEqual(CKCLI.run(["validate", "--dataset", "input", "--stage", "private-pack", "--sources", "registry",
                                 "--reviews", "reviews", "--ledger", "ledger", "--profile", "profile", "--dataset", "output"]), 65)
    }

    func testTransitivePendingLicenseRejected() throws {
        var input = try records()
        let index = try XCTUnwrap(input.firstIndex { $0.document.kind == .sense })
        input[index] = try edited(input[index]) { $0["source_refs"] = [["source_id": "leaf", "operations": ["reference"]]] }
        let sources = [source("leaf", ancestors: [.init(sourceID: "ancestor", operations: [.adapt])]), source("ancestor", pending: true)]
        let report = DatasetValidator.audit(records: input, sources: sources, reviews: [])
        XCTAssertTrue(report.defects.contains { $0.code == .sourcePermission && $0.recordId == input[index].recordId && $0.detail.contains("ancestor") && $0.detail.contains("pending") })
    }

    func testDuplicateIDsRejected() throws {
        let input = try records()
        let report = DatasetValidator.audit(records: input + [input[0]], sources: [], reviews: [])
        XCTAssertTrue(report.defects.contains { $0.code == .duplicateID && $0.recordId == input[0].recordId })
    }

    func testUnknownAliasCollisionRejected() throws {
        var input = try records()
        let entry = try XCTUnwrap(input.first { $0.document.kind == .entry })
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractJSON.line(entry)) as? [String: Any])
        raw["record_id"] = "lx:word:99999999-9999-4999-8999-999999999999"
        var payload = try XCTUnwrap(raw["payload"] as? [String: Any])
        payload["aliases"] = []; payload["variants"] = []
        raw["payload"] = payload
        input.append(try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw)))
        let report = DatasetValidator.audit(records: input, sources: [], reviews: [])
        XCTAssertTrue(report.defects.contains { $0.code == .unknownAliasCollision })
        XCTAssertTrue(report.aliasIndex.values.contains { $0.count == 2 })
    }
}
