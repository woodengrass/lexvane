import ContentCLI
import ContentModel
import Foundation
import XCTest

final class InventoryTests: XCTestCase {
    private let index = "https://www.ceec.edu.tw/index"

    private func row(_ id: String, year: Int? = 111, kind: String = "paper", status: String = "found", extra: [String: Any] = [:]) throws -> InventoryRow {
        var object: [String: Any] = [
            "id": id, "exam_year": year.map { $0 as Any } ?? NSNull(),
            "kind": kind, "variant": "general_pdf", "revision": "original",
            "url": "https://www.ceec.edu.tw/\(id).pdf", "index_ref": index,
            "status": status, "scope": "gsat_english", "reliability": "metadata_only",
            "original_question_numbers_reliable": false, "original_page_count_reliable": false,
            "publication_date": "2020-07-31", "effective_from": 111,
            "permissions": Dictionary(uniqueKeysWithValues: InventoryAudit.operations.map { ($0, "pending") }),
            "rights_reason": "No permission decision; metadata only."
        ]
        object.merge(extra) { _, new in new }
        return try JSONDecoder().decode(InventoryRow.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func discovery(_ rows: [InventoryRow], cutoff: Int = 111, gaps: [String] = [], extraHref: String? = nil) throws -> InventoryDiscovery {
        var hrefs = rows.compactMap(\.url)
        if let extraHref { hrefs.append(extraHref) }
        let object: [String: Any] = [
            "retrieved_at": "2026-10-11T12:00:00Z", "cutoff_date": "2026-10-11",
            "cutoff_year": cutoff, "necessary_gaps": gaps,
            "snapshots": [["url": index, "title": "官方索引", "retrieved_at": "2026-10-11T12:00:00Z",
                           "snapshot_sha256": String(repeating: "a", count: 64),
                           "hash_basis": "metadata_projection", "hrefs": hrefs]],
            "exclusions": [String: String]()
        ]
        return try JSONDecoder().decode(InventoryDiscovery.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func reasons(_ rows: [InventoryRow], cutoff: Int = 111) throws -> [String] {
        try InventoryAudit.audit(rows: rows, discovery: discovery(rows, cutoff: cutoff), from: 111).issues.map(\.code)
    }

    func testMissingYearIsNotComplete() throws {
        let rows = try [row("p"), row("a", kind: "answer_key")]
        XCTAssertTrue(try reasons(rows, cutoff: 112).contains("missing_year_kind"))
    }

    func testNotFoundCannotMeanUnpublished() throws {
        let rows = try [row("p"), row("a", kind: "answer_key", status: "not_published")]
        XCTAssertTrue(try reasons(rows).contains("unsupported_unpublished"))
        let missing = try row("a", kind: "answer_key", status: "not_found_after_search", extra: ["search_evidence": [index]])
        XCTAssertTrue(try reasons([rows[0], missing]).contains("necessary_source_missing"))
    }

    func testNewSpecificationDoesNotCreateFuturePaper() throws {
        let rows = try [row("p"), row("a", kind: "answer_key"), row("spec", year: nil, kind: "specification", extra: ["effective_from": 116])]
        let result = try InventoryAudit.audit(rows: rows, discovery: discovery(rows), from: 111)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.cutoffYear, 111)
    }

    func testOfficialIndexURLAloneCannotProveUnpublished() throws {
        let rows = try [row("p"), row("a", kind: "answer_key", status: "not_published", extra: ["official_evidence": [index]])]
        XCTAssertTrue(try reasons(rows).contains("unsupported_unpublished"))
    }

    func testAnswerSheetCannotSatisfyAnswerKey() throws {
        let rows = try [row("p"), row("sheet", kind: "answer_sheet")]
        XCTAssertTrue(try reasons(rows).contains("missing_year_kind"))
    }

    func testOlderPublicationEffective111() throws {
        let rows = try [row("p"), row("a", kind: "answer_key"), row("vocab", year: nil, kind: "vocabulary")]
        XCTAssertTrue(try InventoryAudit.audit(rows: rows, discovery: discovery(rows), from: 111).complete)
    }

    func testSameBytesMultipleLinksRequiresHashes() throws {
        let hash = String(repeating: "b", count: 64)
        let rows = try [row("p"), row("a", kind: "answer_key"),
                        row("v1", year: nil, kind: "vocabulary", extra: ["content_sha256": hash]),
                        row("v2", year: nil, kind: "vocabulary", extra: ["variant": "alternate_link", "duplicate_of": "v1", "content_sha256": hash])]
        XCTAssertTrue(try InventoryAudit.audit(rows: rows, discovery: discovery(rows), from: 111).complete)
        let pending = try row("v3", year: nil, kind: "vocabulary", extra: ["duplicate_of": "v1"])
        XCTAssertTrue(try reasons(rows + [pending]).contains("unverified_duplicate"))
    }

    func testCorrectionChainRequiresEvidenceAndNoCycle() throws {
        let rows = try [row("p"), row("a", kind: "answer_key"),
                        row("a2", kind: "answer_key", extra: ["revision": "corrected", "supersedes": ["a"], "correction_evidence": [index]])]
        XCTAssertTrue(try InventoryAudit.audit(rows: rows, discovery: discovery(rows), from: 111).complete)
        let cycle = try row("a", kind: "answer_key", extra: ["supersedes": ["a2"], "correction_evidence": [index]])
        XCTAssertTrue(try reasons([rows[0], cycle, rows[2]]).contains("correction_cycle"))
    }

    func testEveryHrefNeedsRowOrExclusion() throws {
        let rows = try [row("p"), row("a", kind: "answer_key")]
        let result = try InventoryAudit.audit(rows: rows, discovery: discovery(rows, extraHref: "https://www.ceec.edu.tw/unaccounted.pdf"), from: 111)
        XCTAssertTrue(result.issues.contains { $0.code == "unaccounted_href" })
    }

    func testOpenNecessaryGapCannotClaimComplete() throws {
        let rows = try [row("p"), row("a", kind: "answer_key")]
        XCTAssertFalse(try InventoryAudit.audit(rows: rows, discovery: discovery(rows, gaps: ["Correction search unfinished"]), from: 111).complete)
    }

    func testCLIRejectsImplicitPaths() {
        XCTAssertNotEqual(InventoryCommands.run(["--from", "111"]), 0)
    }

    func testCLIMissingYearFailsWithTypedReasonAndPreservesInputs() throws {
        let rows = try [row("p"), row("a", kind: "answer_key")]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("inventory-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let inventory = directory.appendingPathComponent("inventory.jsonl")
        let discoveryURL = directory.appendingPathComponent("discovery.json")
        let evidence = directory.appendingPathComponent("audit.json")
        let encoder = JSONEncoder()
        let jsonl = try rows.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        try Data(jsonl.utf8).write(to: inventory)
        try encoder.encode(discovery(rows, cutoff: 112)).write(to: discoveryURL)
        let inputHash = try CKHash.sha256Hex(ofFileAt: inventory)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var environment = ProcessInfo.processInfo.environment
        environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
        environment["TMPDIR"] = directory.path + "/"
        process.environment = environment
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
        process.arguments = ["xcrun", "swift", "run", "--package-path", package, "contentkit", "sources", "audit-inventory",
                             "--inventory", inventory.path, "--discovery", discoveryURL.path, "--from", "111", "--evidence", evidence.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 65, output)
        XCTAssertTrue(output.contains("InventoryError(missing_year_kind)"), output)
        XCTAssertEqual(try CKHash.sha256Hex(ofFileAt: inventory), inputHash)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: evidence)) as? [String: Any])
        XCTAssertEqual(result["complete"] as? Bool, false)
    }
}
