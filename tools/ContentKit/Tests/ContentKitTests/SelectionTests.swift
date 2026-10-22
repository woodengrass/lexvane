import ContentCLI
@testable import ContentModel
import Foundation
import XCTest

final class SelectionTests: XCTestCase {
    private func fixture() throws -> (PilotSelection, IdentitySnapshot) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let ledger = directory.appendingPathComponent("ledger.jsonl")
        let hash = CKHash.sha256Hex(of: Data("fixture".utf8))
        let word = try IdentityLedger.issue(IdentityDraft(kind: .word, issuanceKey: "word", contentHash: hash, semanticHash: hash, vendorIds: []), at: ledger)
        let phrase = try IdentityLedger.issue(IdentityDraft(kind: .phrase, issuanceKey: "phrase", contentHash: hash, semanticHash: hash, vendorIds: []), at: ledger)
        let facets = SelectionFacet.allCases.map { FacetEvidence(facet: $0, pos: "verb", senseRefs: ["own:run/move", "own:run/manage"], examples: ["I run daily.", "I run a shop."], reason: "Independently authored illustration", evidenceRefs: ["own:fixture"], gapNote: nil) }
        let w = SelectionEntry(id: word.id, term: "run", kind: .word, aliasOf: nil, variantOf: nil, componentsOf: nil, wholePhrase: false, basis: "own_usage", basisReason: "Coordinator authored", evidenceRefs: ["own:fixture"], mappingStatus: .rightsPending, mappingReason: "No authorized original bytes", mappingRefs: ["fixture:inventory"], facets: facets)
        let p = SelectionEntry(id: phrase.id, term: "in fact", kind: .phrase, aliasOf: nil, variantOf: nil, componentsOf: nil, wholePhrase: true, basis: "own_usage", basisReason: "In fact, the shop is open. Whole discourse marker, not component entries.", evidenceRefs: ["own:fixture"], mappingStatus: nil, mappingReason: nil, mappingRefs: [], facets: [])
        return (PilotSelection(selectionSeed: "fixture-v1", sources: [SelectionSource(ref: "own:fixture", sha256: hash, unavailableReason: nil)], words: [w], phrases: [p], subsetWordIds: [w.id]), try IdentityLedger.audit(at: ledger))
    }
    private func validate(_ selection: PilotSelection, _ state: IdentitySnapshot) throws -> SelectionReport {
        try SelectionValidator.validate(selection, identities: state, words: 1, phrases: 1, subsetWords: 1)
    }
    private func reject(_ reason: String, _ mutate: (inout PilotSelection) -> Void) throws {
        var (selection, state) = try fixture(); mutate(&selection)
        XCTAssertThrowsError(try validate(selection, state)) { XCTAssertEqual(($0 as? SelectionFailure)?.reason, reason) }
    }
    func testAliasDoesNotCountAsWord() throws { try reject("alias_or_variant_inflation") { $0.words[0].aliasOf = "parent" } }
    func testPhraseCannotSplitOnSpaces() throws { try reject("whole_phrase_required") { $0.phrases[0].wholePhrase = false; $0.phrases[0].componentsOf = "in fact" } }
    func testFiftyMustBeSubsetOfTwoHundred() throws { try reject("subset_not_in_words") { $0.subsetWordIds = ["outside"] } }
    func testMissingFacetRejected() throws { try reject("missing_facet:polysemy") { $0.words[0].facets.removeAll { $0.facet == .polysemy } } }
    func testFacetEvidenceRequired() throws { try reject("facet_evidence_missing") { $0.words[0].facets[0].examples = [] } }
    func testGeneralWordPresenceRequired() throws { try reject("missing_facet:general") { $0.words[0].facets.removeAll { $0.facet == .general } } }
    func testCandidatesAreNotAccepted() throws {
        let (selection, state) = try fixture(); let report = try validate(selection, state)
        XCTAssertTrue(report.structurallyValid); XCTAssertTrue(report.mappingBlocked)
        XCTAssertEqual(report.candidateWords, 1); XCTAssertEqual(report.mappingVerifiedWords, 0); XCTAssertEqual(report.acceptedContentCount, 0)
    }
    func testDuplicateIdentityRejected() throws { try reject("duplicate_identity_or_term") { $0.phrases[0].id = $0.words[0].id } }
    func testUnverifiedMappingCannotClaimVerified() throws { try reject("official_mapping_unverified") { $0.words[0].mappingStatus = .mapped } }
    func testCountMismatchRejected() throws { try reject("count_mismatch") { $0.words = [] } }
    func testGapDoesNotSubstituteCheckableFacet() throws { try reject("facet_evidence_missing") { $0.words[0].facets[0].senseRefs = []; $0.words[0].facets[0].gapNote = "Dictionary not fetched" } }
    func testPhraseCEECLinkRejected() throws { try reject("phrase_ceec_link_forbidden") { $0.phrases[0].mappingRefs = ["ceec:invented"] } }
    func testDuplicateSubsetRejected() throws {
        var (selection, state) = try fixture()
        var second = selection.words[0]; second.id = "lx:word:\(UUID().uuidString.lowercased())"; second.term = "school"
        let hash = CKHash.sha256Hex(of: Data("second fixture".utf8))
        state.records[second.id] = IdentityRecord(id: second.id, kind: .word, issuanceKey: "second", revision: 1,
            contentHash: hash, semanticHash: hash, vendorIds: [])
        selection.words.append(second); selection.subsetWordIds = [selection.words[0].id, selection.words[0].id]
        XCTAssertThrowsError(try SelectionValidator.validate(selection, identities: state, words: 2, phrases: 1, subsetWords: 2)) {
            XCTAssertEqual(($0 as? SelectionFailure)?.reason, "duplicate_subset_identity")
        }
    }
    func testSourceHashOrGapRequired() throws { try reject("source_hash_or_reason_required") { $0.sources[0].sha256 = nil } }
    func testCLIRequiresExplicitFlags() {
        XCTAssertEqual(CKCLI.run(["selection", "validate"]), 65)
        XCTAssertEqual(CKCLI.run(["selection", "validate", "--selection", "missing"]), 65)
    }
    func testCLIProtectsInputFromEvidenceOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("selection.json")
        let original = Data("preserve me".utf8); try original.write(to: file)
        XCTAssertEqual(CKCLI.run(["selection", "validate", "--selection", file.path, "--ledger", file.path,
            "--words", "200", "--phrases", "30", "--subset-words", "50", "--evidence", file.path]), 65)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
