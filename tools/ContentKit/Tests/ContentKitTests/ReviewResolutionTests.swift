import Foundation
import XCTest
@testable import ContentModel

/// Review resolution: all-current aggregate over kind/id/revision/hash.
///
/// Regression for the first-match acceptance bug: a single passed review must
/// never accept a subject when another exact-current review is non-passed,
/// regardless of file order. Same record_ids with differing content fail
/// closed; byte-identical copies dedup; historical passes never approve.
final class ReviewResolutionTests: XCTestCase {
    private static var packageRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }
    private static var validRoot: URL {
        URL(fileURLWithPath: packageRoot)
            .appendingPathComponent("Tests/ContentKitTests/Fixtures/reviews/valid")
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
    private func resealed(_ data: Data, mutate: (inout [String: Any]) -> Void) throws -> Data {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&raw)
        let edited = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        var sealed = try ContractJSON.line(ContractJSON.seal(edited))
        sealed.removeLast()
        return sealed
    }
    private func reviewLines(for subjectId: String, in reviews: URL) throws -> (file: URL, matching: [Data], others: [Data]) {
        let files = try FileManager.default.contentsOfDirectory(at: reviews, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            let all = try lines(of: file)
            var matching: [Data] = []
            var others: [Data] = []
            var found = false
            for line in all {
                guard let raw = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let payload = raw["payload"] as? [String: Any] else { others.append(line); continue }
                if payload["subject_id"] as? String == subjectId {
                    matching.append(line); found = true
                } else {
                    others.append(line)
                }
            }
            if found { return (file, matching, others) }
        }
        throw ContractFailure("no_review_for:\(subjectId)")
    }

    private func conflictingExtra(from original: Data, recordId: String) throws -> Data {
        try resealed(original) { edited in
            edited["record_id"] = recordId
            var payload = edited["payload"] as! [String: Any]
            payload["verdict"] = "changes_requested"
            edited["payload"] = payload
        }
    }

    private func reject(_ text: String, action: () throws -> ReviewCoverageReport) {
        XCTAssertThrowsError(try action()) { error in
            XCTAssertTrue(String(describing: error).contains(text), "\(error)")
        }
    }

    func testOppositeVerdictsRejectWhenPassComesFirst() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let senseId = "lx:sense:22222222-2222-2222-2222-222222222222"
        let (file, matching, others) = try reviewLines(for: senseId, in: copy.reviews)
        let extra = try conflictingExtra(from: matching[0], recordId: "review/sense-extra-resolution")
        try writeLines(others + matching + [extra], to: file)
        reject("review_not_passed:\(senseId)") {
            try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        }
    }

    func testOppositeVerdictsRejectWhenFailComesFirst() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let senseId = "lx:sense:22222222-2222-2222-2222-222222222222"
        let (file, matching, others) = try reviewLines(for: senseId, in: copy.reviews)
        let extra = try conflictingExtra(from: matching[0], recordId: "review/sense-extra-resolution")
        try writeLines(others + [extra] + matching, to: file)
        reject("review_not_passed:\(senseId)") {
            try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        }
    }

    func testConflictingSameIDsReject() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let senseId = "lx:sense:22222222-2222-2222-2222-222222222222"
        let (file, matching, others) = try reviewLines(for: senseId, in: copy.reviews)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: matching[0]) as? [String: Any])
        let recordId = try XCTUnwrap(raw["record_id"] as? String)
        let conflict = try resealed(matching[0]) { edited in
            var payload = edited["payload"] as! [String: Any]
            payload["verdict"] = "changes_requested"
            edited["payload"] = payload
        }
        try writeLines(others + matching + [conflict], to: file)
        reject("duplicate_review:\(recordId)") {
            try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        }
    }

    func testIdenticalCopiesDedup() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let senseId = "lx:sense:22222222-2222-2222-2222-222222222222"
        let (file, matching, others) = try reviewLines(for: senseId, in: copy.reviews)
        try writeLines(others + matching + matching, to: file)
        let report = try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        XCTAssertTrue(report.valid)
        XCTAssertEqual(report.totalUnits, 10)
    }

    func testHistoricalPassCannotRescueCurrentRejection() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let senseId = "lx:sense:22222222-2222-2222-2222-222222222222"
        let (file, matching, others) = try reviewLines(for: senseId, in: copy.reviews)
        let stalePass = try resealed(matching[0]) { edited in
            edited["record_id"] = "review/sense-historical-pass"
            var payload = edited["payload"] as! [String: Any]
            payload["subject_revision"] = 999
            edited["payload"] = payload
        }
        let currentFail = try conflictingExtra(from: matching[0], recordId: "review/sense-current-fail")
        try writeLines(others + matching + [stalePass, currentFail], to: file)
        reject("review_not_passed:\(senseId)") {
            try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)
        }
    }

    func testKindMismatchDoesNotCountAsCurrent() throws {
        let copy = try freshCopy()
        defer { try? FileManager.default.removeItem(at: copy.temp) }
        let senseId = "lx:sense:22222222-2222-2222-2222-222222222222"
        let (file, matching, others) = try reviewLines(for: senseId, in: copy.reviews)
        let wrongKind = try resealed(matching[0]) { edited in
            edited["record_id"] = "review/sense-wrong-kind"
            var payload = edited["payload"] as! [String: Any]
            payload["subject_kind"] = "question"
            edited["payload"] = payload
        }
        try writeLines(others + [wrongKind], to: file)
        XCTAssertThrowsError(try ReviewCoverage.audit(dataset: copy.dataset, reviews: copy.reviews, profile: nil)) { error in
            let text = String(describing: error)
            XCTAssertTrue(text.contains("stale_revision:\(senseId)") || text.contains("unknown_subject"), text)
        }
    }
}
