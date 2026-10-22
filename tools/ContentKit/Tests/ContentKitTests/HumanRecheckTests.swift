import Foundation
import XCTest
@testable import ContentCLI

final class HumanRecheckTests: XCTestCase {
    private func fixture(_ body: (URL, URL, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let dataset = root.appendingPathComponent("dataset"), reviews = root.appendingPathComponent("reviews")
        try FileManager.default.createDirectory(at: dataset, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reviews, withIntermediateDirectories: true)
        let rows: [[String: Any]] = (1...3).map { index in
            ["record_id": "q\(index)", "kind": "question", "revision": 2,
             "content_sha256": "seal\(index)", "payload": ["tested_ability": "writing", "stem": "Real stem \(index)", "accepted_answers": ["answer"]]]
        }
        try writeLines(rows, dataset.appendingPathComponent("rows.jsonl"))
        try writeLines([["kind": "review", "payload": ["subject_id": "q1", "subject_revision": 1,
            "verdict": "changes_requested", "findings": [["severity": "critical", "state": "resolved", "reason": "fixed answer error"]]]]], reviews.appendingPathComponent("review.jsonl"))
        let profile = root.appendingPathComponent("profile.json")
        try JSONSerialization.data(withJSONObject: ["human_sample_policy": ["seed": 111, "high_risk_ids": [], "strata": ["question:writing": 1]]]).write(to: profile)
        try body(dataset, reviews, profile, reviews.appendingPathComponent("OWNER-RECHECK.md"))
    }
    private func writeLines(_ rows: [[String: Any]], _ file: URL) throws {
        let lines = try rows.map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self) }
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }
    private func run(_ mode: String, _ dataset: URL, _ reviews: URL, _ profile: URL, _ out: URL) -> Int32 {
        CKCLI.run(["reports", mode, "--dataset", dataset.path, "--reviews", reviews.path, "--profile", profile.path,
                   "--seed", "111", "--out", out.path, "--evidence", out.deletingLastPathComponent().appendingPathComponent("evidence.json").path])
    }
    func testHighRiskCannotDisappearAfterFix() throws {
        try fixture { dataset, reviews, profile, out in
            XCTAssertEqual(run("human-recheck", dataset, reviews, profile, out), 0)
            let text = try String(contentsOf: reviews.appendingPathComponent("human-recheck.jsonl"), encoding: .utf8)
            XCTAssertTrue(text.contains("q1")); XCTAssertTrue(text.contains("critical")); XCTAssertTrue(text.contains("fixed"))
            XCTAssertEqual(run("audit-human-recheck", dataset, reviews, profile, out), 0)
        }
    }
    func testUnflaggedRandomSampleRequired() throws {
        try fixture { dataset, reviews, profile, out in
            XCTAssertEqual(run("human-recheck", dataset, reviews, profile, out), 0)
            let file = reviews.appendingPathComponent("human-recheck.jsonl")
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
            XCTAssertEqual(lines.count, 2)
            let retained = lines.filter { !$0.contains("stratified_random") }.joined(separator: "\n")
            try retained.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertNotEqual(run("audit-human-recheck", dataset, reviews, profile, out), 0)
        }
    }
    func testReportGenerationCannotSignForOwner() throws {
        try fixture { dataset, reviews, profile, out in
            XCTAssertEqual(run("human-recheck", dataset, reviews, profile, out), 0)
            let decisions = reviews.appendingPathComponent("human-decisions.jsonl")
            XCTAssertEqual(try Data(contentsOf: decisions).count, 0)
            try writeLines([["record_id": "q1", "revision": 2, "status": "approved", "signed_by": "agent"]], decisions)
            XCTAssertNotEqual(run("human-recheck", dataset, reviews, profile, out), 0, "Never erase existing human decisions")
            XCTAssertNotEqual(run("audit-human-recheck", dataset, reviews, profile, out), 0, "Pending packet cannot carry approval")
        }
    }
    func testRevisedContentInvalidatesHumanDecision() throws {
        try fixture { dataset, reviews, profile, out in
            XCTAssertEqual(run("human-recheck", dataset, reviews, profile, out), 0)
            let file = dataset.appendingPathComponent("rows.jsonl")
            let changed = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: "Real stem 1", with: "Changed stem")
            try changed.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertNotEqual(run("audit-human-recheck", dataset, reviews, profile, out), 0, "Content binding must catch changes even without a revision bump")
        }
    }
}
