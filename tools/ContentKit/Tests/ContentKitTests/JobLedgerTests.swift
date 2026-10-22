import ContentCLI
@testable import ContentModel
import Foundation
import XCTest

final class JobLedgerTests: XCTestCase {
    // Synthetic engineering fixtures are never production agent receipts.
    let fixtureHash = CKHash.sha256Hex(of: Data("fixture".utf8))
    func binding() -> JobBinding {
        JobBinding(jobId: "jobs/fixture", role: .author, inputHash: fixtureHash,
            model: "configured-available", modelHash: CKHash.sha256Hex(of: Data("configured-available".utf8)),
            promptRef: "author.md", promptHash: fixtureHash,
            records: [JobRecord(recordId: "lx:word:00000000-0000-0000-0000-000000000001", kind: .entry, revision: 1, contentHash: fixtureHash)])
    }
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try CKPaths.ensureDirectory(at: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    func receipt(_ b: JobBinding, session: String = "synthetic-fixture-session") -> JobReceipt {
        JobReceipt(binding: b, sessionId: session, runId: "synthetic-fixture-run", evidenceRef: "return.txt",
            evidenceHash: fixtureHash, resultRecords: b.records, findingRefs: ["findings/fixture"], tokens: "unknown", cost: "unknown", generatorSessionId: nil)
    }
    func setupRunning() throws -> (URL, URL, JobBinding) {
        let dir = try directory(), ledger = dir.appendingPathComponent("jobs.jsonl"), b = binding()
        try JobLedger.append(JobEvent(binding: b, state: .pending), to: ledger)
        try JobLedger.append(JobEvent(binding: b, state: .running), to: ledger)
        try Data("fixture".utf8).write(to: dir.appendingPathComponent("return.txt"))
        return (dir, ledger, b)
    }
    func reject(_ reason: String, _ action: () throws -> Void) {
        XCTAssertThrowsError(try action()) { XCTAssertEqual(($0 as? JobFailure)?.reason, reason) }
    }
    func testResumeAcceptsRecordedReceiptOnce() throws {
        let (dir, ledger, b) = try setupRunning()
        try JobLedger.write(receipt(b), to: dir.appendingPathComponent("receipt.json"))
        XCTAssertEqual(try JobLedger.resume(at: ledger, binding: b, receiptRef: "receipt.json"), .receiptAvailable)
        try JobLedger.append(JobEvent(binding: b, state: .received, receiptRef: "receipt.json"), to: ledger)
        try JobLedger.append(JobEvent(binding: b, state: .validated, receiptRef: "receipt.json"), to: ledger)
        let restarted = try JobLedger.audit(at: ledger)
        XCTAssertEqual(restarted.acceptedCount, 1)
        XCTAssertEqual(restarted.receipts[b.jobId]?.findingRefs, ["findings/fixture"])
        XCTAssertEqual(restarted.receipts[b.jobId]?.runId, "synthetic-fixture-run")
        XCTAssertEqual(restarted.receipts[b.jobId]?.resultRecords.first?.recordId, b.records.first?.recordId)
        XCTAssertEqual(try JobLedger.resume(at: ledger, binding: b, receiptRef: "receipt.json"), .alreadyAccepted)
    }
    func testChangedInputInvalidatesReceipt() throws {
        let (dir, ledger, b) = try setupRunning()
        var changed = b; changed.inputHash = CKHash.sha256Hex(of: Data("changed".utf8))
        try JobLedger.write(receipt(changed), to: dir.appendingPathComponent("receipt.json"))
        reject("changed_input_receipt") { try JobLedger.append(JobEvent(binding: b, state: .received, receiptRef: "receipt.json"), to: ledger) }
        reject("changed_input_receipt") { _ = try JobLedger.resume(at: ledger, binding: changed, receiptRef: nil) }
    }
    func testMissingSessionReceiptRejected() throws {
        let (dir, ledger, b) = try setupRunning()
        try JobLedger.write(receipt(b, session: ""), to: dir.appendingPathComponent("receipt.json"))
        reject("missing_session_receipt") { try JobLedger.append(JobEvent(binding: b, state: .received, receiptRef: "receipt.json"), to: ledger) }
    }
    func testDuplicateCompletionCannotCountTwice() throws {
        let (dir, ledger, b) = try setupRunning()
        try JobLedger.write(receipt(b), to: dir.appendingPathComponent("receipt.json"))
        try JobLedger.append(JobEvent(binding: b, state: .received, receiptRef: "receipt.json"), to: ledger)
        let accepted = JobEvent(binding: b, state: .validated, receiptRef: "receipt.json")
        try JobLedger.append(accepted, to: ledger)
        reject("duplicate_accept") { try JobLedger.append(accepted, to: ledger) }
        try CKJSONL.appendLine(String(decoding: JobLedger.bytes(accepted), as: UTF8.self), to: ledger)
        reject("duplicate_accept") { _ = try JobLedger.audit(at: ledger) }
        XCTAssertEqual(JobCommands.run(["audit", "--jobs", ledger.path, "--evidence", dir.appendingPathComponent("audit.json").path]), 65)
    }
    func testQuotaFailureRemainsResumable() throws {
        let (_, ledger, b) = try setupRunning()
        try JobLedger.append(JobEvent(binding: b, state: .jobFailed, failure: JobFailureDetail(reason: .quota, resumable: true)), to: ledger)
        XCTAssertEqual(try JobLedger.resume(at: ledger, binding: b, receiptRef: nil), .retryAllowed)
        try JobLedger.append(JobEvent(binding: b, state: .running), to: ledger)
        XCTAssertEqual(try JobLedger.resume(at: ledger, binding: b, receiptRef: nil), .reconcileRunning)
        reject("invalid_transition") { try JobLedger.append(JobEvent(binding: b, state: .running), to: ledger) }
    }
    func testEmptyAuditNotDispatched() throws {
        let dir = try directory(), ledger = dir.appendingPathComponent("jobs.jsonl")
        try Data().write(to: ledger)
        XCTAssertEqual(try JobLedger.audit(at: ledger).status, "not_dispatched")
        XCTAssertEqual(JobCommands.run(["audit", "--jobs", ledger.path, "--evidence", dir.appendingPathComponent("audit.json").path]), 0)
    }
    func root() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    func testPlanEmptyManifestAndMissingPrompts() throws {
        let dir = try directory()
        let empty = PilotSelection(selectionSeed: "fixture", sources: [], words: [], phrases: [], subsetWordIds: [])
        XCTAssertTrue(try JobPlanner.plan(selection: empty, subset: "pilot-50", prompts: dir).jobs.isEmpty)
        let selection = try SelectionValidator.read(at: root().appendingPathComponent("content/pilot/selection.json"))
        let plan = try JobPlanner.plan(selection: selection, subset: "pilot-50", prompts: dir)
        XCTAssertEqual(plan.maxParallel, 3)
        XCTAssertEqual(plan.jobs.filter { $0.binding.role == .author }.flatMap { $0.binding.records }.count, 50)
        XCTAssertTrue(plan.jobs.allSatisfy { $0.binding.records.count <= 25 && $0.state == .pending && $0.binding.promptHash == nil })
        XCTAssertEqual(plan.status, "blocked_prompts")
    }
    func testDanglingReceiptAndQuarantineRejected() throws {
        let (_, ledger, b) = try setupRunning()
        reject("dangling_receipt") { try JobLedger.append(JobEvent(binding: b, state: .received, receiptRef: "absent.json"), to: ledger) }
        reject("finding_refs_required") { try JobLedger.append(JobEvent(binding: b, state: .quarantined), to: ledger) }
    }
    func testReviewerCannotReuseGeneratorSession() throws {
        let (dir, _, original) = try setupRunning()
        var b = original; b.role = .languageReview
        var r = receipt(b); r.generatorSessionId = r.sessionId
        reject("reviewer_generator_session_collision") { try JobLedger.validateReceipt(r, binding: b, base: dir) }
    }
    func testReceiptCannotBeReplacedAfterReceived() throws {
        let (dir, ledger, b) = try setupRunning()
        let saved = dir.appendingPathComponent("receipt.json")
        try JobLedger.write(receipt(b), to: saved)
        try JobLedger.append(JobEvent(binding: b, state: .received, receiptRef: "receipt.json"), to: ledger)
        var changed = receipt(b); changed.runId = "another-synthetic-run"
        try JobLedger.write(changed, to: saved)
        reject("receipt_hash_mismatch") { _ = try JobLedger.audit(at: ledger) }
    }
    func testBindingsAndCurrentRevisionCannotDrift() throws {
        let (dir, ledger, b) = try setupRunning()
        try JobLedger.write(receipt(b), to: dir.appendingPathComponent("receipt.json"))
        for field in ["prompt", "model", "revision"] {
            var changed = b
            switch field {
            case "prompt": changed.promptHash = CKHash.sha256Hex(of: Data("other".utf8))
            case "model": changed.model = "other"; changed.modelHash = CKHash.sha256Hex(of: Data("other".utf8))
            default: changed.records = b.records.map { JobRecord(recordId: $0.recordId, kind: $0.kind, revision: 2, contentHash: $0.contentHash) }
            }
            reject("changed_input_receipt") { try JobLedger.append(JobEvent(binding: changed, state: .received, receiptRef: "receipt.json"), to: ledger) }
        }
    }
    func testParallelCapAndQuarantineAreExplicit() throws {
        let dir = try directory(), ledger = dir.appendingPathComponent("jobs.jsonl")
        for index in 0..<4 {
            var b = binding(); b.jobId = "jobs/fixture-\(index)"
            try JobLedger.append(JobEvent(binding: b, state: .pending), to: ledger)
            if index < 3 { try JobLedger.append(JobEvent(binding: b, state: .running), to: ledger) }
            else { reject("parallel_limit") { try JobLedger.append(JobEvent(binding: b, state: .running), to: ledger) } }
        }
        var b = binding(); b.jobId = "jobs/fixture-0"
        try JobLedger.append(JobEvent(binding: b, state: .quarantined, findingRefs: ["findings/fixture"]), to: ledger)
        XCTAssertEqual(try JobLedger.resume(at: ledger, binding: b, receiptRef: nil), .blocked)
        XCTAssertEqual(try JobLedger.audit(at: ledger).events[b.jobId]?.findingRefs, ["findings/fixture"])
    }
    func testCLIProtectsInputsAndReportsTypedFailure() throws {
        let dir = try directory(), ledger = dir.appendingPathComponent("jobs.jsonl")
        try Data().write(to: ledger)
        XCTAssertEqual(JobCommands.run(["audit", "--jobs", ledger.path, "--evidence", ledger.path]), 65)
        XCTAssertEqual(try Data(contentsOf: ledger), Data())
        XCTAssertEqual(JobCommands.run(["plan"]), 65)
        let output = dir.appendingPathComponent("manifest.json")
        XCTAssertEqual(JobCommands.run(["plan", "--selection", root().appendingPathComponent("content/pilot/selection.json").path,
            "--subset", "pilot-50", "--prompts", dir.appendingPathComponent("absent-prompts").path, "--out", output.path]), 0)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        XCTAssertEqual(json["status"] as? String, "blocked_prompts")
        XCTAssertEqual(json["max_parallel"] as? Int, 3)
    }
    func testProvenanceChainAndEmptyHumanRefs() throws {
        let dir = try directory()
        let fixture = root().appendingPathComponent("content/contracts/v1/examples/valid")
        guard case .entry(let entry) = try ContractJSON.decode(Data(contentsOf: fixture.appendingPathComponent("entry.jsonl"))),
              case .provenance(let original) = try ContractJSON.decode(Data(contentsOf: fixture.appendingPathComponent("provenance.jsonl"))) else { return XCTFail("fixture kind") }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractJSON.bytes(original)) as? [String: Any])
        var payload = try XCTUnwrap(object["payload"] as? [String: Any])
        var b = binding(); b.jobId = original.payload.workUnitRef; b.promptHash = original.payload.promptHash
        b.model = original.payload.model; b.modelHash = CKHash.sha256Hex(of: Data(b.model.utf8))
        b.records = [JobRecord(recordId: entry.recordId, kind: .entry, revision: entry.revision, contentHash: entry.contentSha256)]
        payload["subject_id"] = entry.recordId; payload["subject_revision"] = entry.revision
        payload["subject_content_sha256"] = entry.contentSha256; payload["transform_chain"] = []
        payload["review_refs"] = []; payload["human_modification_refs"] = []
        object["payload"] = payload
        guard case .provenance(let provenance) = try ContractJSON.seal(JSONSerialization.data(withJSONObject: object)) else { return XCTFail("seal") }
        try Data("fixture".utf8).write(to: dir.appendingPathComponent("return.txt"))
        let ledger = dir.appendingPathComponent("jobs.jsonl")
        let ref = provenance.payload.runReceiptRef
        let saved = try JobLedger.localURL(ref, base: dir)
        try CKPaths.ensureDirectory(at: saved.deletingLastPathComponent())
        try JobLedger.write(receipt(b), to: saved)
        try JobLedger.append(JobEvent(binding: b, state: .pending), to: ledger)
        try JobLedger.append(JobEvent(binding: b, state: .running), to: ledger)
        try JobLedger.append(JobEvent(binding: b, state: .received, receiptRef: ref), to: ledger)
        let jobs = try JobLedger.audit(at: ledger)
        let fields = Set(provenance.payload.fields.map(\.field))
        let sources = Set(provenance.payload.fields.flatMap { $0.sourceRefs.map(\.sourceId) })
        func validate(_ sourceIds: Set<String>, _ expected: Set<String>, _ snapshot: JobSnapshot) throws {
            try ProvenanceValidator.validate(provenance, subject: entry, requiredFields: expected, sourceIds: sourceIds,
                jobs: snapshot, reviews: [:], transforms: [:], humanModificationRefs: [], base: dir)
        }
        try validate(sources, fields, jobs)
        XCTAssertTrue(provenance.payload.humanModificationRefs.isEmpty)
        reject("dangling_source_ref") { try validate([], fields, jobs) }
        reject("provenance_field_coverage") { try validate(sources, [], jobs) }
        reject("missing_provenance_receipt") { try validate(sources, fields, JobSnapshot()) }
        func altered(_ changes: [String: Any]) throws -> Provenance {
            var changed = object
            var p = payload
            for (key, value) in changes { p[key] = value }
            changed["payload"] = p
            guard case .provenance(let value) = try ContractJSON.seal(JSONSerialization.data(withJSONObject: changed)) else {
                throw JobFailure("fixture_kind")
            }
            return value
        }
        func check(_ p: Provenance, subject: (any ContractDocumentInfo)? = nil,
                   transforms: [String: ProvenanceTransform] = [:]) throws {
            try ProvenanceValidator.validate(p, subject: subject ?? entry, requiredFields: fields, sourceIds: sources,
                jobs: jobs, reviews: [:], transforms: transforms, humanModificationRefs: [], base: dir)
        }
        let missingTransform = try altered(["transform_chain": ["transforms/missing"]])
        reject("dangling_transform_ref") { try check(missingTransform) }
        let missingReview = try altered(["review_refs": ["reviews/missing"]])
        reject("dangling_review_ref") { try check(missingReview) }
        let fakeHuman = try altered(["human_modification_refs": ["human/missing"]])
        reject("dangling_human_modification_ref") { try check(fakeHuman) }
        var entryObject = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractJSON.bytes(entry)) as? [String: Any])
        entryObject["revision"] = 2
        guard case .entry(let revised) = try ContractJSON.seal(JSONSerialization.data(withJSONObject: entryObject)) else { return XCTFail("revision") }
        let final = JobRecord(recordId: revised.recordId, kind: .entry, revision: 2, contentHash: revised.contentSha256)
        let transformed = try altered(["subject_revision": 2, "subject_content_sha256": revised.contentSha256,
            "transform_chain": ["transforms/fixture"]])
        let transform = ProvenanceTransform(ref: "transforms/fixture", input: b.records[0], output: final,
            method: .adapt, evidenceRef: "return.txt", evidenceHash: fixtureHash)
        try check(transformed, subject: revised, transforms: [transform.ref: transform])
        reject("provenance_subject_mismatch") { try check(transformed) }
    }
}
