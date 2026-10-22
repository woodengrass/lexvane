import ContentCLI
@testable import ContentModel
import Foundation
import XCTest

final class IdentityCoverageTests: XCTestCase {
    private let materialHash = CKHash.sha256Hex(of: Data("fixture".utf8))
    private func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private func draft(_ key: String, kind: IdentityKind = .word) -> IdentityDraft {
        IdentityDraft(kind: kind, issuanceKey: key, contentHash: materialHash, semanticHash: materialHash, vendorIds: [], basis: .coordinator)
    }
    private func failure(_ reason: String, _ action: () throws -> Void) {
        XCTAssertThrowsError(try action()) { error in
            XCTAssertEqual((error as? IdentityFailure)?.reason, reason)
        }
    }
    private func original(_ id: String, aliasOf: String? = nil) -> ExtractedItem {
        ExtractedItem(originalId: id, page: 1, line: 1, term: "fixture-\(id)", pos: "n.", level: "1", aliasOf: aliasOf)
    }
    private func header(_ items: [ExtractedItem]) -> CoverageHeader {
        CoverageHeader(recordType: "header", sourceVersion: "synthetic-v1", url: "https://www.ceec.edu.tw/fixture.pdf",
                       cutoff: "2026-10-11", inventoryRefs: ["fixture:inventory"], parseRule: "fixture-tsv-v1",
                       contentHash: materialHash, denominator: items.filter { $0.aliasOf == nil }.count,
                       extractionAudit: ExtractionAudit(contentHash: materialHash, parseRule: "fixture-tsv-v1", pageCount: 1,
                           lineCount: items.count, items: items, ignoredLines: [], fieldMapping: ["term", "pos", "level"], complete: true),
                       status: .notYetAuthored, complete: true)
    }
    private func row(_ item: ExtractedItem) -> CoverageRow {
        CoverageRow(recordType: item.aliasOf == nil ? .originalItem : .alias, sourceVersion: "synthetic-v1",
                    item: item, entryId: nil, status: .notYetAuthored, qualifiedActiveTarget: false,
                    reason: "Synthetic content unwritten", evidenceRefs: ["fixture:page-1"])
    }
    func testTranslationCannotBeIdentity() throws {
        // Given a translated label offered as an issuance basis; When issuing; Then reject.
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        var input = draft("opaque-request"); input.basis = .translation
        failure("translation_cannot_be_identity") { _ = try IdentityLedger.issue(input, at: ledger) }
    }
    func testTextEditPreservesIDAndIncrementsRevision() throws {
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        let first = try IdentityLedger.issue(draft("opaque-request"), at: ledger)
        let edited = try IdentityLedger.revise(IdentityRevision(id: first.id, contentHash: CKHash.sha256Hex(of: Data("edit".utf8)),
                                               semanticHash: materialHash, vendorIds: []), at: ledger)
        XCTAssertEqual(edited.id, first.id); XCTAssertEqual(edited.revision, 2)
        XCTAssertNotEqual(edited.contentHash, first.contentHash)
    }
    func testReorderPreservesIDAndRerunDoesNotAppend() throws {
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        let a = try IdentityLedger.issue(draft("request-a"), at: ledger)
        let b = try IdentityLedger.issue(draft("request-b"), at: ledger)
        let before = try Data(contentsOf: ledger)
        let reordered = try [IdentityLedger.issue(draft("request-b"), at: ledger), IdentityLedger.issue(draft("request-a"), at: ledger)]
        XCTAssertEqual(reordered.map(\.id), [b.id, a.id]); XCTAssertEqual(try Data(contentsOf: ledger), before)
    }
    func testMultipleVendorIDsPreserveIdentity() throws {
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        let first = try IdentityLedger.issue(draft("request"), at: ledger)
        let revised = try IdentityLedger.revise(IdentityRevision(id: first.id, contentHash: materialHash, semanticHash: materialHash,
                                                vendorIds: ["vendor-a:42", "vendor-b:99"]), at: ledger)
        XCTAssertEqual(revised.id, first.id); XCTAssertEqual(revised.vendorIds.count, 2)
    }
    func testAllKindsHaveIndependentOpaqueIDs() throws {
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        let records = try IdentityKind.allCases.map { try IdentityLedger.issue(draft("request-\($0.rawValue)", kind: $0), at: ledger) }
        XCTAssertEqual(Set(records.map(\.id)).count, IdentityKind.allCases.count)
        XCTAssertTrue(records.allSatisfy { $0.id.hasPrefix("lx:\($0.kind.rawValue):") })
    }
    func testSilentSenseSplitRejected() throws {
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        let sense = try IdentityLedger.issue(draft("sense-request", kind: .sense), at: ledger)
        failure("semantic_change_requires_mapping") {
            _ = try IdentityLedger.revise(IdentityRevision(id: sense.id, contentHash: materialHash,
                semanticHash: CKHash.sha256Hex(of: Data("two meanings".utf8)), vendorIds: []), at: ledger)
        }
    }
    func testExplicitSplitKeepsPredecessorAndIndependentSuccessors() throws {
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        let old = try IdentityLedger.issue(draft("old", kind: .sense), at: ledger)
        let before = try Data(contentsOf: ledger)
        let successors = try IdentityLedger.transition(IdentityTransition(operation: .split, predecessors: [old.id],
            successors: [draft("new-a", kind: .sense), draft("new-b", kind: .sense)], reason: "Explicit new meanings", evidenceRefs: ["fixture:decision"]), at: ledger)
        let state = try IdentityLedger.audit(at: ledger)
        XCTAssertTrue(try Data(contentsOf: ledger).starts(with: before))
        XCTAssertEqual(state.records[old.id], old); XCTAssertTrue(state.retiredIds.contains(old.id))
        XCTAssertEqual(successors.map(\.revision), [1, 1]); XCTAssertFalse(successors.map(\.id).contains(old.id))
    }
    func testExplicitMergeDoesNotRewritePredecessors() throws {
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        let old = try [IdentityLedger.issue(draft("a"), at: ledger), IdentityLedger.issue(draft("b"), at: ledger)]
        let merged = try IdentityLedger.transition(IdentityTransition(operation: .merge, predecessors: old.map(\.id),
            successors: [draft("merged")], reason: "Explicit merge", evidenceRefs: ["fixture:decision"]), at: ledger)
        let state = try IdentityLedger.audit(at: ledger)
        XCTAssertEqual(state.retiredIds, Set(old.map(\.id))); XCTAssertEqual(merged.first?.revision, 1)
    }
    func testSplitRequiresEvidenceAndMultipleSuccessors() throws {
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        let old = try IdentityLedger.issue(draft("a"), at: ledger)
        failure("invalid_transition") { _ = try IdentityLedger.transition(IdentityTransition(operation: .split,
            predecessors: [old.id], successors: [draft("b")], reason: "", evidenceRefs: []), at: ledger) }
    }
    func testTamperedLedgerRejected() throws {
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        _ = try IdentityLedger.issue(draft("a"), at: ledger)
        let raw = try String(contentsOf: ledger, encoding: .utf8)
        try Data(raw.replacingOccurrences(of: materialHash, with: String(repeating: "b", count: 64)).utf8).write(to: ledger)
        failure("broken_append_chain") { _ = try IdentityLedger.audit(at: ledger) }
    }
    func testDuplicateLedgerEventRejected() throws {
        let ledger = try workspace().appendingPathComponent("ledger.jsonl")
        _ = try IdentityLedger.issue(draft("a"), at: ledger)
        let line = try XCTUnwrap(CKJSONL.readLines(at: ledger).first)
        try CKJSONL.appendLine(line, to: ledger)
        failure("broken_append_chain") { _ = try IdentityLedger.audit(at: ledger) }
    }
    func testAliasesCannotInflateCoverage() throws {
        let items = [original("one"), original("alias", aliasOf: "one")]
        var lock = header(items); lock.denominator = 2
        failure("fabricated_denominator") { _ = try CoverageMap.audit(header: lock, rows: items.map(row), identities: .empty) }
    }
    func testAliasIsMapOnly() throws {
        let items = [original("one"), original("alias", aliasOf: "one")]
        let report = try CoverageMap.audit(header: header(items), rows: items.map(row), identities: .empty)
        XCTAssertEqual(report.denominator, 1); XCTAssertEqual(report.aliasCount, 1); XCTAssertEqual(report.mappedHeadwords, 0)
    }
    func testTruncatedWordlistFailsCoverage() throws {
        let items = [original("one"), original("two")]
        failure("truncated_or_changed_extraction") {
            _ = try CoverageMap.audit(header: header(items), rows: [row(items[0])], identities: .empty)
        }
    }
    func testPendingCannotFabricateDenominator() throws {
        var lock = header([]); lock.status = .rightsPending; lock.contentHash = nil; lock.extractionAudit = nil
        failure("pending_material_cannot_claim_counts") { _ = try CoverageMap.audit(header: lock, rows: [], identities: .empty) }
    }
    func testUnwrittenCannotHaveQualifiedActiveTarget() throws {
        let item = original("one"); var unwritten = row(item); unwritten.qualifiedActiveTarget = true
        failure("unwritten_active_target") { _ = try CoverageMap.audit(header: header([item]), rows: [unwritten], identities: .empty) }
    }
    func testMappedUnknownEntryRejected() throws {
        let item = original("one"); var mapped = row(item); mapped.status = .mapped; mapped.entryId = "lx:word:missing"
        failure("unknown_or_retired_entry") { _ = try CoverageMap.audit(header: header([item]), rows: [mapped], identities: .empty) }
    }
    func testExtractionRetainsPageLineAndFields() throws {
        let report = try PDFExtractor.parse(pages: ["Fixture heading\nalpha\tn.\t1", "beta\tv.\t2"],
            materialHash: materialHash, rule: .fixtureTSV)
        XCTAssertEqual(report.items.map(\.page), [1, 2]); XCTAssertEqual(report.items.map(\.line), [2, 1])
        XCTAssertEqual(report.items.map(\.pos), ["n.", "v."]); XCTAssertEqual(report.ignoredLines.count, 1)
        XCTAssertFalse(report.complete)
    }
    func testEmptyScanFailsExtraction() {
        XCTAssertThrowsError(try PDFExtractor.parse(pages: [""], materialHash: materialHash, rule: .fixtureTSV)) {
            XCTAssertEqual(($0 as? PDFExtractionFailure)?.reason, "empty_page")
        }
    }
    func testGarbledTextFailsExtraction() {
        XCTAssertThrowsError(try PDFExtractor.parse(pages: ["���\t??\t1"], materialHash: materialHash, rule: .fixtureTSV)) {
            XCTAssertEqual(($0 as? PDFExtractionFailure)?.reason, "garbled_page")
        }
    }
    func testInvalidPDFUsesTypedFailure() throws {
        let path = try workspace().appendingPathComponent("bad.pdf")
        try Data("not a PDF".utf8).write(to: path)
        XCTAssertThrowsError(try PDFExtractor.extract(file: path, rule: .fixtureTSV)) {
            XCTAssertEqual(($0 as? PDFExtractionFailure)?.reason, "invalid_pdf")
        }
    }
    func testLocalSyntheticPDFExtractsWithByteHash() throws {
        let path = try workspace().appendingPathComponent("synthetic.pdf")
        let stream = "BT /F1 12 Tf 40 100 Td (alpha n. 1) Tj ET"
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream"]
        var pdf = "%PDF-1.4\n"; var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count); pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 6\n0000000000 65535 f \n" + offsets.dropFirst().map { String(format: "%010d 00000 n \n", $0) }.joined()
        pdf += "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        try Data(pdf.utf8).write(to: path)
        let rule = PDFParseRule(version: "synthetic-space-v1", pattern: "^([A-Za-z]+)\\s+([a-z]+\\.)\\s+([0-9]+)$",
            termGroup: 1, posGroup: 2, levelGroup: 3, ignoredPatterns: [])
        let audit = try PDFExtractor.extract(file: path, rule: rule)
        XCTAssertEqual(audit.items.map(\.term), ["alpha"]); XCTAssertEqual(audit.contentHash, try CKHash.sha256Hex(ofFileAt: path))
        XCTAssertTrue(audit.complete)
    }
    func testCLIRejectsImplicitPaths() {
        XCTAssertEqual(IdentityCommands.run(["audit"]), 65)
    }
    func testCLIHonestPendingPassesAndPreservesInputs() throws {
        let directory = try workspace(); let ledger = directory.appendingPathComponent("ledger.jsonl")
        let coverage = directory.appendingPathComponent("coverage.jsonl"); let evidence = directory.appendingPathComponent("audit.json")
        try Data().write(to: ledger)
        var lock = header([]); lock.contentHash = nil; lock.denominator = nil; lock.extractionAudit = nil
        lock.status = .rightsPending; lock.complete = false
        let pending = CoverageRow(recordType: .sourcePending, sourceVersion: lock.sourceVersion, item: nil, entryId: nil,
            status: .rightsPending, qualifiedActiveTarget: false, reason: "No authorized bytes", evidenceRefs: ["fixture:inventory"])
        try Data((CKIdentityJSON.line(lock) + "\n" + CKIdentityJSON.line(pending) + "\n").utf8).write(to: coverage)
        let before = try Data(contentsOf: coverage)
        let code = CKCLI.run(["ids", "audit", "--ledger", ledger.path, "--coverage", coverage.path, "--evidence", evidence.path])
        XCTAssertEqual(code, 0); XCTAssertEqual(try Data(contentsOf: coverage), before)
        let report = try JSONDecoder().decode(IdentityAuditReport.self, from: Data(contentsOf: evidence))
        XCTAssertTrue(report.coverage.mappingBlocked); XCTAssertNil(report.coverage.denominator)
    }
    func testCLICannotOverwriteInput() throws {
        let directory = try workspace(); let ledger = directory.appendingPathComponent("ledger.jsonl")
        try Data().write(to: ledger)
        let code = IdentityCommands.run(["audit", "--ledger", ledger.path, "--coverage", ledger.path, "--evidence", ledger.path])
        XCTAssertEqual(code, 65); XCTAssertEqual(try Data(contentsOf: ledger), Data())
    }
}
