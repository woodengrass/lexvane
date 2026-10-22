import ContentModel
import Foundation
import XCTest

final class IdentityRegistrationTests: XCTestCase {
    private let observedHash = CKHash.sha256Hex(of: Data("observed document".utf8))
    private let semantic = CKHash.sha256Hex(of: Data("stable semantic basis".utf8))
    private let id = "lx:word:00000000-0000-4000-8000-000000000001"
    private let secondId = "lx:word:00000000-0000-4000-8000-000000000002"

    private func ledger() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("ledger.jsonl")
    }
    private func registration(id: String? = nil, kind: IdentityKind = .word, key: String = "adoption:word:fixture",
        content: String? = nil, semantic: String? = nil, vendors: [String] = [], basis: IdentityBasis = .coordinator,
        observations: [IdentityObservation]? = nil, reason: String = "existing_identity_adoption_now",
        refs: [String] = ["fixture:registration-evidence"]) -> IdentityRegistration {
        IdentityRegistration(id: id ?? self.id,
            draft: IdentityDraft(kind: kind, issuanceKey: key, contentHash: content ?? observedHash,
                semanticHash: semantic ?? self.semantic, vendorIds: vendors, basis: basis),
            observations: observations ?? [IdentityObservation(recordId: id ?? self.id, revision: 7, contentSha256: observedHash)],
            reason: reason, evidenceRefs: refs)
    }
    private func failure(_ reason: String, _ action: () throws -> Void) {
        XCTAssertThrowsError(try action()) { XCTAssertEqual(($0 as? IdentityFailure)?.reason, reason) }
    }
    private func reseal(_ object: [String: Any]) throws -> String {
        var event = try CKIdentityJSON.decode(IdentityEvent.self,
            line: String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        event.eventHash = ""
        event.eventHash = CKHash.sha256Hex(of: Data(try CKIdentityJSON.line(event).utf8))
        return try CKIdentityJSON.line(event) + "\n"
    }
    func testAdoptionPreservesExistingIDHistoricalPrefixAndReplays() throws {
        let url = try ledger()
        let prior = try IdentityLedger.issue(IdentityDraft(kind: .sense, issuanceKey: "prior",
            contentHash: observedHash, semanticHash: semantic, vendorIds: []), at: url)
        let prefix = try Data(contentsOf: url)
        let adopted = try IdentityLedger.registerExisting(registration(), at: url)
        XCTAssertEqual(adopted.id, id); XCTAssertEqual(adopted.revision, 1)
        XCTAssertTrue(try Data(contentsOf: url).starts(with: prefix))
        let state = try IdentityLedger.audit(at: url)
        XCTAssertEqual(state.records[id], adopted); XCTAssertEqual(state.records[prior.id], prior)
        XCTAssertEqual(state.eventCount, 2)
        let event = try CKIdentityJSON.decode(IdentityEvent.self, line: XCTUnwrap(CKJSONL.readLines(at: url).last))
        XCTAssertEqual(event.operation, .registerExisting)
        XCTAssertEqual(event.observations?.first?.revision, 7)
        XCTAssertEqual(event.observations?.first?.contentSha256, observedHash)
    }
    func testExactRetryIsByteIdempotentAcrossReplay() throws {
        let url = try ledger()
        let first = try IdentityLedger.registerExisting(registration(), at: url)
        let bytes = try Data(contentsOf: url)
        _ = try IdentityLedger.audit(at: url)
        XCTAssertEqual(try IdentityLedger.registerExisting(registration(), at: url), first)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testEveryChangedRegistrationFieldConflictsWithoutAppend() throws {
        let url = try ledger()
        _ = try IdentityLedger.registerExisting(registration(), at: url)
        let bytes = try Data(contentsOf: url)
        let otherHash = CKHash.sha256Hex(of: Data("changed".utf8))
        let changes = [registration(key: "different-key"), registration(content: otherHash),
            registration(semantic: otherHash), registration(vendors: ["vendor:1"]),
            registration(observations: [IdentityObservation(recordId: id, revision: 8, contentSha256: observedHash)]),
            registration(observations: [IdentityObservation(recordId: id, revision: 7, contentSha256: otherHash)]),
            registration(reason: "different-reason"), registration(refs: ["fixture:other-evidence"])]
        for changed in changes {
            failure("registration_conflict") { _ = try IdentityLedger.registerExisting(changed, at: url) }
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }
    func testBatchValidatesAllBeforeAppendAndDeduplicatesRetries() throws {
        let url = try ledger(); try Data().write(to: url)
        failure("issuance_key_conflict") {
            _ = try IdentityLedger.registerExisting([registration(), registration(id: secondId)], at: url)
        }
        XCTAssertEqual(try Data(contentsOf: url), Data())
        let inputs = [registration(), registration(id: secondId, key: "second"), registration()]
        let records = try IdentityLedger.registerExisting(inputs, at: url)
        XCTAssertEqual(records.map(\.id), [id, secondId, id])
        XCTAssertEqual(try IdentityLedger.audit(at: url).eventCount, 2)
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(try IdentityLedger.registerExisting(Array(inputs.reversed()), at: url), Array(records.reversed()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testIssuedIdentityCannotBeRecastAsAdoption() throws {
        let url = try ledger()
        let issued = try IdentityLedger.issue(registration().draft, at: url)
        failure("registration_conflict") { _ = try IdentityLedger.registerExisting(registration(id: issued.id), at: url) }
        XCTAssertEqual(try IdentityLedger.audit(at: url).eventCount, 1)
    }
    func testRejectsKindMismatchMalformedIDAndInvalidRecord() throws {
        let url = try ledger()
        let invalid = [registration(kind: .sense), registration(id: "lx:word:not-a-uuid"), registration(id: id + ":"),
            registration(key: " \n"), registration(content: "bad"), registration(semantic: "bad"),
            registration(vendors: ["same", "same"])]
        for value in invalid {
            failure("invalid_record") { _ = try IdentityLedger.registerExisting(value, at: url) }
        }
        failure("translation_cannot_be_identity") {
            _ = try IdentityLedger.registerExisting(registration(basis: .translation), at: url)
        }
    }
    func testEveryIdentityKindCanBeAdoptedWithoutMinting() throws {
        let url = try ledger()
        for kind in IdentityKind.allCases {
            let existing = "lx:\(kind.rawValue):00000000-0000-4000-8000-000000000001"
            XCTAssertEqual(try IdentityLedger.registerExisting(registration(id: existing, kind: kind, key: kind.rawValue), at: url).id, existing)
        }
        XCTAssertEqual(try IdentityLedger.audit(at: url).records.count, IdentityKind.allCases.count)
    }
    func testEvidenceMustBeNonemptyUniqueAndRevisionBound() throws {
        let url = try ledger()
        let observation = IdentityObservation(recordId: id, revision: 7, contentSha256: observedHash)
        let invalid = [registration(observations: []), registration(reason: " "), registration(refs: []),
            registration(refs: [" "]), registration(refs: ["same", "same"]), registration(observations: [observation, observation]),
            registration(observations: [IdentityObservation(recordId: " ", revision: 7, contentSha256: observedHash)]),
            registration(observations: [IdentityObservation(recordId: id, revision: 0, contentSha256: observedHash)]),
            registration(observations: [IdentityObservation(recordId: id, revision: 7, contentSha256: "bad")])]
        for value in invalid {
            failure("invalid_registration_evidence") { _ = try IdentityLedger.registerExisting(value, at: url) }
        }
        XCTAssertEqual(try IdentityLedger.audit(at: url).eventCount, 0)
    }
    func testRetiredAdoptionCannotBeRegisteredAgain() throws {
        let url = try ledger()
        _ = try IdentityLedger.registerExisting(registration(), at: url)
        let successors = ["split-a", "split-b"].map {
            IdentityDraft(kind: .word, issuanceKey: $0, contentHash: observedHash, semanticHash: semantic, vendorIds: [])
        }
        _ = try IdentityLedger.transition(IdentityTransition(operation: .split, predecessors: [id], successors: successors,
            reason: "explicit split", evidenceRefs: ["fixture:split"]), at: url)
        failure("unknown_or_retired_identity") { _ = try IdentityLedger.registerExisting(registration(), at: url) }
    }
    func testRevisedAdoptionCannotBeRolledBackByRetry() throws {
        let url = try ledger()
        _ = try IdentityLedger.registerExisting(registration(), at: url)
        _ = try IdentityLedger.revise(IdentityRevision(id: id, contentHash: CKHash.sha256Hex(of: Data("edit".utf8)),
            semanticHash: semantic, vendorIds: []), at: url)
        failure("registration_conflict") { _ = try IdentityLedger.registerExisting(registration(), at: url) }
        XCTAssertEqual(try IdentityLedger.audit(at: url).records[id]?.revision, 2)
    }
    func testReplayRejectsResealedDuplicateInvalidEvidenceAndKind() throws {
        let url = try ledger()
        _ = try IdentityLedger.registerExisting(registration(), at: url)
        let bytes = try Data(contentsOf: url)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var duplicate = original; duplicate["sequence"] = 2; duplicate["previous_hash"] = original["event_hash"]
        try (bytes + Data(reseal(duplicate).utf8)).write(to: url)
        failure("duplicate_identity") { _ = try IdentityLedger.audit(at: url) }
        var noEvidence = original; noEvidence.removeValue(forKey: "observations")
        try Data(reseal(noEvidence).utf8).write(to: url)
        failure("invalid_registration_evidence") { _ = try IdentityLedger.audit(at: url) }
        var wrongKind = original
        var records = try XCTUnwrap(original["records"] as? [[String: Any]])
        records[0]["kind"] = "sense"; wrongKind["records"] = records
        try Data(reseal(wrongKind).utf8).write(to: url)
        failure("invalid_record") { _ = try IdentityLedger.audit(at: url) }
    }
}
