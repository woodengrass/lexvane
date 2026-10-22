import Foundation
import XCTest
import ContentModel
@testable import ContentCLI

final class PilotIntegrationTests: XCTestCase {
    func testExhaustedCheckCannotBecomeUnseenAgain() throws {
        let fixture = try Task19Fixture()
        // All presentations in one scenario form one consumption horizon. Different
        // scenarios and separate simulate() calls are independent, not persisted exposure.
        let questions = try fixture.trialQuestions()
        let target = try XCTUnwrap(questions.first { $0.payload.split == .check }?.payload.primaryTargetId)
        let pool = questions.filter { $0.payload.primaryTargetId == target }
        let checkCount = Set(pool.filter { $0.payload.split == .check }.map { $0.payload.familyId }).count
        XCTAssertGreaterThan(checkCount, 0)
        var (profile, _) = QualityProfileTests.baseline()
        profile.activeAbilities = TestedAbility.allCases
        func allocation(_ demand: Int) throws -> SupplyAllocation {
            let scenario = SupplyScenarios(targetIds: [target], scenarios: [SupplyScenario(id: "continuous-horizon",
                trainPresentationsPerTarget: 1, checkPresentationsPerTarget: demand)],
                eligibleQuestions: pool.map { SupplyBinding(questionId: $0.recordId, revision: $0.revision, contentSha256: $0.contentSha256) })
            let report = try SupplySimulation.simulate(questions: pool, request: SupplyRequest(profile: profile, scenarios: scenario, seed: 111))
            XCTAssertEqual(report.acceptedCount, 0)
            XCTAssertFalse(report.releaseEligible)
            return try XCTUnwrap(report.allocations.first)
        }
        let exhausted = try allocation(checkCount)
        XCTAssertEqual(exhausted.remainingUnseenCheckFamilies, 0)
        XCTAssertEqual(exhausted.checkShortfall, 0)
        for extra in [1, 2, 10] {
            let later = try allocation(checkCount + extra)
            XCTAssertEqual(later.consumedCheckFamilyIds, exhausted.consumedCheckFamilyIds)
            XCTAssertEqual(Set(later.consumedCheckFamilyIds).count, checkCount)
            XCTAssertEqual(later.remainingUnseenCheckFamilies, 0)
            XCTAssertEqual(later.checkShortfall, extra)
        }
    }

    func testJobResumeDoesNotDoubleAcceptAfterInterruption() throws {
        let fixture = try Task19Fixture()
        let ledger = fixture.root.appendingPathComponent("jobs.jsonl")
        let hash = CKHash.sha256Hex(of: Data("fixture receipt evidence".utf8))
        let entry = try XCTUnwrap(fixture.records.first { $0.document.kind == .entry })
        let binding = JobBinding(jobId: "jobs/task19-fixture", role: .author, inputHash: hash,
            model: "synthetic-fixture", modelHash: CKHash.sha256Hex(of: Data("synthetic-fixture".utf8)), promptRef: "fixture.md", promptHash: hash,
            records: [JobRecord(recordId: entry.recordId, kind: .entry, revision: entry.document.revision, contentHash: entry.document.contentSha256)])
        try JobLedger.append(JobEvent(binding: binding, state: .pending), to: ledger)
        try JobLedger.append(JobEvent(binding: binding, state: .running), to: ledger)
        XCTAssertEqual(try JobLedger.resume(at: ledger, binding: binding, receiptRef: nil), .reconcileRunning)
        try Data("fixture receipt evidence".utf8).write(to: fixture.root.appendingPathComponent("return.txt"))
        let receipt = JobReceipt(binding: binding, sessionId: "synthetic-task19-session", runId: "synthetic-task19-run",
            evidenceRef: "return.txt", evidenceHash: hash, resultRecords: binding.records,
            findingRefs: ["findings/synthetic-task19"], tokens: "unknown", cost: "unknown", generatorSessionId: nil)
        try JobLedger.write(receipt, to: fixture.root.appendingPathComponent("receipt.json"))
        XCTAssertEqual(try JobLedger.resume(at: ledger, binding: binding, receiptRef: "receipt.json"), .receiptAvailable)
        try JobLedger.append(JobEvent(binding: binding, state: .received, receiptRef: "receipt.json"), to: ledger)
        XCTAssertEqual(try JobLedger.audit(at: ledger).acceptedCount, 0)
        let completion = JobEvent(binding: binding, state: .validated, receiptRef: "receipt.json")
        try JobLedger.append(completion, to: ledger)
        let accepted = try Data(contentsOf: ledger)
        for _ in 0..<2 {
            XCTAssertEqual(try JobLedger.resume(at: ledger, binding: binding, receiptRef: "receipt.json"), .alreadyAccepted)
            XCTAssertThrowsError(try JobLedger.append(completion, to: ledger)) {
                XCTAssertEqual(($0 as? JobFailure)?.reason, "duplicate_accept")
            }
            XCTAssertEqual(try Data(contentsOf: ledger), accepted)
            XCTAssertEqual(try JobLedger.audit(at: ledger).acceptedCount, 1)
        }
    }

    func testVerifiedReaderToSearchChain() throws {
        let fixture = try Task19Fixture()
        let manifest = try PackageBuilder.verify(fixture.pack)
        XCTAssertFalse(manifest.releaseEligible)
        XCTAssertTrue(manifest.humanReviewPending)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let index = try decoder.decode(SearchIndexDocument.self, from: Data(contentsOf: fixture.pack.appendingPathComponent("index.json")))
        let entries = fixture.records.compactMap { record -> Entry? in
            if case .entry(let entry) = record { return entry }; return nil
        }
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(index.entryCount, entries.count)
        for entry in entries {
            XCTAssertTrue(SearchIndex.resolve(query: entry.payload.lemma.uppercased(), index: index).entryIds.contains(entry.recordId))
        }
        XCTAssertTrue(SearchIndex.resolve(query: "task19-not-a-fixture-lemma", index: index).entryIds.isEmpty)
    }
}
