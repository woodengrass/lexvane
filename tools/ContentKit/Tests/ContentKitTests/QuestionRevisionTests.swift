import ContentModel
import Foundation
import XCTest

final class QuestionRevisionTests: XCTestCase {
    func testReviewedRevisionsPreserveIdentityAndInvalidateOldEvidence() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        func records(_ path: String) throws -> [ContractRecord] {
            try CKJSONL.readLines(at: root.appendingPathComponent(path)).map { try ContractJSON.decode(Data($0.utf8)) }
        }
        let history = try records("content/history/question-quality-first-batch/original-questions.jsonl")
        let current = try records("content/records/pilot-230/merged/pilot-230-question.jsonl")
        let provenance = try records("content/records/pilot-230/merged/pilot-230-provenance.jsonl")
        XCTAssertEqual(history.count, 3)
        for old in history {
            let matches = current.filter { $0.recordId == old.recordId }
            XCTAssertEqual(matches.count, 1)
            guard case .question(let question) = try XCTUnwrap(matches.first) else {
                XCTFail("Expected current question"); continue
            }
            XCTAssertEqual(question.revision, old.document.revision + 1)
            XCTAssertNotEqual(question.contentSha256, old.contentSha256)
            XCTAssertEqual(question.payload.options.count, 4)
            XCTAssertEqual(question.payload.acceptedAnswers.count, 1)
            XCTAssertEqual(question.payload.distractorRationales.count, 3)
            XCTAssertEqual(question.payload.status, .candidate)
            let correct = try XCTUnwrap(question.payload.options.first {
                question.payload.acceptedAnswers.contains($0.optionId)
            })
            XCTAssertFalse(question.payload.stem.lowercased().contains(correct.english.lowercased()))
            for ref in question.payload.provenanceRefs {
                guard case .provenance(let p) = try XCTUnwrap(provenance.first { $0.recordId == ref }) else {
                    XCTFail("Expected bound provenance"); continue
                }
                XCTAssertEqual(p.payload.subjectId, question.recordId)
                XCTAssertEqual(p.payload.subjectRevision, question.revision)
                XCTAssertEqual(p.payload.subjectContentSha256, question.contentSha256)
                XCTAssertTrue(p.payload.reviewRefs.isEmpty)
            }
        }
    }
}
