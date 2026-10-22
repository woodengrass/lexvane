import Foundation
import XCTest
import ContentCLI
import ContentModel

final class ReviewHardeningTests: XCTestCase {
    private let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func fixture() throws -> URL {
        let scratch = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let root = scratch.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: package.appendingPathComponent("Tests/ContentKitTests/Fixtures/reviews/valid"), to: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func run(_ root: URL, evidence: URL) throws -> (code: Int32, reason: Process.TerminationReason, text: String) {
        let process = Process()
        process.executableURL = package.appendingPathComponent(".build/debug/contentkit")
        process.arguments = ["reviews", "audit", "--dataset", root.appendingPathComponent("dataset").path,
                             "--reviews", root.appendingPathComponent("reviews").path, "--evidence", evidence.path]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        print("SUBPROCESS \(process.arguments ?? []) EXIT=\(process.terminationStatus) REASON=\(process.terminationReason)\n\(text)")
        return (process.terminationStatus, process.terminationReason, text)
    }

    private func rejectOverlap(_ path: String, broken: Bool = false, alias: Bool = false) throws {
        let root = try fixture()
        if broken { try FileManager.default.removeItem(at: root.appendingPathComponent("reviews/reviews.jsonl")) }
        let victim = root.appendingPathComponent(path)
        let before = try Data(contentsOf: victim)
        let output: URL
        if alias {
            let link = root.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim.deletingLastPathComponent())
            output = link.appendingPathComponent(victim.lastPathComponent)
        } else { output = victim }
        let result = try run(root, evidence: output)
        XCTAssertEqual(result.reason, .exit)
        XCTAssertEqual(result.code, 65)
        XCTAssertTrue(result.text.contains("ReviewCoverageFailure(reason=evidence_overlaps_input)"), result.text)
        let after = try Data(contentsOf: victim)
        print("INPUT \(path) BEFORE=\(CKHash.sha256Hex(of: before)) AFTER=\(CKHash.sha256Hex(of: after))")
        XCTAssertEqual(after, before)
    }

    func testDatasetDescendantIsRejectedBeforeSuccessWrite() throws {
        try rejectOverlap("dataset/questions.jsonl")
    }
    func testReviewsDescendantIsRejectedBeforeSuccessWrite() throws {
        try rejectOverlap("reviews/reviews.jsonl")
    }
    func testDatasetDescendantIsRejectedBeforeFailureWrite() throws {
        try rejectOverlap("dataset/questions.jsonl", broken: true)
    }
    func testResolvedAliasIntoReviewsIsRejected() throws {
        try rejectOverlap("reviews/reviews.jsonl", alias: true)
    }
    func testNewDescendantIsNotCreated() throws {
        let root = try fixture()
        let output = root.appendingPathComponent("reviews/new/sub/report.json")
        let result = try run(root, evidence: output)
        XCTAssertEqual(result.code, 65)
        XCTAssertTrue(result.text.contains("evidence_overlaps_input"), result.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    private func rejectDuplicateBatch(withinRow: Bool, conflictingSession: Bool = false) throws {
        let root = try fixture()
        let batches = root.appendingPathComponent("reviews/batches.jsonl")
        let original = try Data(contentsOf: batches)
        let line = try XCTUnwrap(String(decoding: original, as: UTF8.self).split(separator: "\n").first)
        var row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let id = try XCTUnwrap((row["subject_ids"] as? [String])?.first)
        if withinRow {
            row["subject_ids"] = [id, id]
            try (JSONSerialization.data(withJSONObject: row) + Data([10])).write(to: batches)
        } else if conflictingSession {
            row["batch_id"] = "conflicting-batch"; row["generator_session"] = "different-generator"
            try (original + JSONSerialization.data(withJSONObject: row) + Data([10])).write(to: batches)
        } else { try (original + original).write(to: batches) }
        let before = try Data(contentsOf: batches)
        let output = root.appendingPathComponent("duplicate.json")
        let result = try run(root, evidence: output)
        XCTAssertEqual(result.reason, .exit, result.text)
        XCTAssertEqual(result.code, 65)
        XCTAssertTrue(result.text.contains("ReviewCoverageFailure(reason=duplicate_record:batch_subject:\(id):"), result.text)
        XCTAssertFalse(result.text.contains("Fatal error"))
        XCTAssertEqual(try Data(contentsOf: batches), before)
        if FileManager.default.fileExists(atPath: output.path) {
            let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
            XCTAssertEqual(report["valid"] as? Bool, false)
            XCTAssertTrue((report["error"] as? String ?? "").contains("duplicate_record"))
        } else { XCTFail("Typed rejection evidence was not written") }
        print("BATCH_UNCHANGED_SHA256=\(CKHash.sha256Hex(of: before))")
    }
    func testDuplicateBatchBytesRejectWithoutSignal() throws {
        try rejectDuplicateBatch(withinRow: false)
    }
    func testDuplicateSubjectWithinBatchRejectsWithoutSignal() throws {
        try rejectDuplicateBatch(withinRow: true)
    }
    func testConflictingBatchSubjectRejectsWithoutSignal() throws {
        try rejectDuplicateBatch(withinRow: false, conflictingSession: true)
    }
}
