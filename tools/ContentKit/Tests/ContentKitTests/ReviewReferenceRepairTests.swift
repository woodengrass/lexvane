import ContentModel
import Foundation
import XCTest

/// Review-reference repair for one ambiguous provenance row (no verdict chosen).
///
/// provenance/teachfix-fix1/e5348033-80df-4c28-8b4a-d40ffab03635-r2 carried two
/// stale review_refs: a singleton binding entry r1 and an ambiguous old ID
/// whose preserved candidates both bind entry r3. The provenance subject is
/// entry r5, so neither ref is an exact-current (kind/id/revision/hash) match.
/// The repair empties current review_refs (pending review, no passed claims),
/// reseals r4 -> r5, and preserves the exact old row plus all candidates in
/// content/history/review-reference-repair/.
///
/// This test uses ONLY tracked fixtures. The full 7,041-row canonical
/// collection (content/reviews/pilot-230-current/reviews-disambiguated.jsonl)
/// is a generated local artifact and is intentionally untracked (see
/// .gitignore and tools/ReviewDisambiguate/README.md). The three candidate
/// rows below are sealed copies, byte-identical to the canonical rows with
/// the same record_id, stored at
/// content/history/review-reference-repair/review-candidates.jsonl so a
/// clean checkout still audits green. No test in this file skips when a
/// file is missing: a missing tracked fixture fails loudly.
final class ReviewReferenceRepairTests: XCTestCase {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func provenanceRows(_ path: String) throws -> [ContractRecord] {
        try CKJSONL.readLines(at: Self.repoRoot.appendingPathComponent(path))
            .map { try ContractJSON.decode(Data($0.utf8)) }
    }

    func testStaleReviewRefsMigratedToPendingWithSnapshotPreserved() throws {
        let recordID = "provenance/teachfix-fix1/e5348033-80df-4c28-8b4a-d40ffab03635-r2"
        let stale0573 = "review/pilot-230/review-230-b/0573"
        let stale0464 = "review/pilot-230/review-rereview1-b/0464"

        // Current row: r5, sealed, no stale refs, subject still entry r5.
        let current = try provenanceRows("content/records/pilot-230/merged/pilot-230-provenance.jsonl")
        let matches = current.filter { $0.recordId == recordID }
        XCTAssertEqual(matches.count, 1)
        guard case .provenance(let row) = try XCTUnwrap(matches.first) else {
            return XCTFail("expected provenance row")
        }
        XCTAssertEqual(row.revision, 5)
        XCTAssertFalse(row.payload.reviewRefs.contains(stale0573))
        XCTAssertFalse(row.payload.reviewRefs.contains(stale0464))
        XCTAssertTrue(row.payload.reviewRefs.isEmpty)
        XCTAssertEqual(row.payload.subjectId, "lx:word:e5348033-80df-4c28-8b4a-d40ffab03635")
        XCTAssertEqual(row.payload.subjectKind, .entry)
        XCTAssertEqual(row.payload.subjectRevision, 5)
        XCTAssertEqual(row.payload.subjectContentSha256, "eee37a2846e85c8d8986006750e6d41f89ad84fdf6e87a0743de3f25d370f9c4")

        // Snapshot preserved: exact old r4 row with both stale refs intact.
        let snapshot = try provenanceRows("content/history/review-reference-repair/original-provenance.jsonl")
        XCTAssertEqual(snapshot.count, 1)
        guard case .provenance(let old) = try XCTUnwrap(snapshot.first) else {
            return XCTFail("expected archived provenance row")
        }
        XCTAssertEqual(old.recordId, recordID)
        XCTAssertEqual(old.revision, 4)
        XCTAssertEqual(old.contentSha256, "01a93cac6201e7b6040f87d8270421b7eeb6dbfffcc5bd1601446ce22b640fe5")
        XCTAssertEqual(old.payload.reviewRefs, [stale0573, stale0464])

        // Candidates decode: singleton binds entry r1, both 0464 variants bind
        // entry r3 -- neither matches the r5 subject, so empty is the only
        // honest binding (no candidate picked, no verdict fabricated).
        // Tracked fixture: byte-identical sealed copies of the same three
        // canonical rows (see tools/ReviewDisambiguate/README.md). The full
        // 7,041-row canonical file is untracked and must not be read here.
        let wanted: Set<String> = [
            stale0573,
            "review/pilot-230/review-rereview1-b/0464~h08c36e50d5e2",
            "review/pilot-230/review-rereview1-b/0464~hd7ec8f388e7c",
        ]
        var found: [String: Review] = [:]
        let fixtureLines = try CKJSONL.readLines(at: Self.repoRoot.appendingPathComponent(
            "content/history/review-reference-repair/review-candidates.jsonl"))
        XCTAssertEqual(fixtureLines.count, 3, "fixture must hold exactly the 3 sealed candidates")
        for line in fixtureLines
        {
            let record = try ContractJSON.decode(Data(line.utf8))
            guard case .review(let review) = record, wanted.contains(review.recordId) else {
                return XCTFail("fixture holds only the 3 wanted sealed candidates")
            }
            found[review.recordId] = review
        }
        XCTAssertEqual(Set(found.keys), wanted)
        XCTAssertEqual(found[stale0573]?.payload.subjectRevision, 1)
        for id in wanted where id != stale0573 {
            XCTAssertEqual(found[id]?.payload.subjectRevision, 3)
        }
        for review in found.values {
            XCTAssertEqual(review.payload.subjectId, "lx:word:e5348033-80df-4c28-8b4a-d40ffab03635")
            XCTAssertEqual(review.payload.subjectKind, .entry)
            XCTAssertNotEqual(review.payload.subjectContentSha256, row.payload.subjectContentSha256)
        }

        // Manifest tracks the migration with all candidates and the reason.
        let manifestURL = Self.repoRoot.appendingPathComponent(
            "content/history/review-reference-repair/migration-manifest.json")
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)) as? [String: Any])
        XCTAssertEqual(manifest["record_id"] as? String, recordID)
        XCTAssertEqual(manifest["new_revision"] as? Int, 5)
        let removed = try XCTUnwrap(manifest["removed_review_refs"] as? [[String: Any]])
        XCTAssertEqual(removed.count, 2)
        XCTAssertTrue(removed.contains { ($0["old_record_id"] as? String) == stale0573 })
        let ambiguous = try XCTUnwrap(removed.first { ($0["old_record_id"] as? String) == stale0464 })
        XCTAssertEqual((ambiguous["candidates"] as? [[String: Any]])?.count, 2)
    }
}
