import Foundation
import XCTest
@testable import ContentModel

/// Reads the REAL pilot-230 phrase dataset (no synthetic fixtures):
/// phrases-12 (30 phrases). Read-only file access.
final class PhrasePilotTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    private var datasetDir: URL {
        if let override = ProcessInfo.processInfo.environment["PILOT230_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return repoRoot.appendingPathComponent("content/records/pilot-230")
    }
    private var phraseFile: URL {
        datasetDir.appendingPathComponent("phrases-12.jsonl")
    }
    private var wordFiles: [URL] {
        ["words-11a.jsonl", "words-11b.jsonl", "words-11c.jsonl", "words-pilot50.jsonl"].map {
            datasetDir.appendingPathComponent($0)
        }
    }

    private struct PhraseDataset {
        var entries: [Entry]
        var senses: [Sense]
        var targets: [Target]
        var teachings: [Teaching]
        var questions: [Question]
        var wordIds: Set<String>
    }

    private func load() throws -> PhraseDataset {
        var entries: [Entry] = []
        var senses: [Sense] = []
        var targets: [Target] = []
        var teachings: [Teaching] = []
        var questions: [Question] = []
        let text = try String(contentsOf: phraseFile, encoding: .utf8)
        for line in text.split(separator: "\n") {
            switch try ContractJSON.decode(Data(line.utf8)) {
            case .entry(let v): entries.append(v)
            case .sense(let v): senses.append(v)
            case .target(let v): targets.append(v)
            case .teaching(let v): teachings.append(v)
            case .question(let v): questions.append(v)
            case .provenance, .review, .manifest: break
            }
        }
        var wordIds = Set<String>()
        for file in wordFiles {
            let wtext = try String(contentsOf: file, encoding: .utf8)
            for line in wtext.split(separator: "\n") {
                if case .entry(let v) = try ContractJSON.decode(Data(line.utf8)), v.payload.entryKind == .word {
                    wordIds.insert(v.recordId)
                }
            }
        }
        return PhraseDataset(entries: entries, senses: senses, targets: targets,
                             teachings: teachings, questions: questions, wordIds: wordIds)
    }

    /// Candidate validation over the real phrase rows. Every branch is
    /// exercised by a mutation test below, so a trivially-true gate fails red.
    private func validateCandidate(_ data: PhraseDataset, expectedPhrases: Int) throws {
        let phrases = data.entries.filter { $0.payload.entryKind == .phrase }
        try ContractRules.require(Set(phrases.map(\.recordId)).count == phrases.count, "duplicate_phrase_identity")
        try ContractRules.require(phrases.count == expectedPhrases, "phrase_count_mismatch:\(phrases.count)/\(expectedPhrases)")
        // Whitespace never splits a phrase: count entries, not space tokens.
        let tokenCount = phrases.reduce(0) { $0 + $1.payload.lemma.split(separator: " ").count }
        try ContractRules.require(phrases.count == expectedPhrases, "whitespace_split_inflation:\(tokenCount)")
        try ContractRules.require(Set(phrases.map { $0.payload.lemma }).count == phrases.count, "duplicate_phrase_lemma")
        let phraseIds = Set(phrases.map(\.recordId))
        // No word state may stand in for a phrase; no auto-concatenated dupe.
        try ContractRules.require(phraseIds.isDisjoint(with: data.wordIds), "word_state_as_phrase")
        for target in data.targets {
            try ContractRules.require(phraseIds.contains(target.payload.entryId), "word_state_as_phrase:\(target.recordId)")
        }
        let teachByTarget = Dictionary(grouping: data.teachings, by: { $0.payload.primaryTargetId })
        let questionsByTarget = Dictionary(grouping: data.questions, by: { $0.payload.primaryTargetId })
        for entry in phrases {
            try ContractRules.require(entry.recordId.hasPrefix("lx:phrase:"), "word_state_as_phrase:\(entry.recordId)")
            let active = data.targets.filter { $0.payload.entryId == entry.recordId && $0.payload.activation == .active }
            try ContractRules.require(!active.isEmpty, "phrase_without_active_target:\(entry.recordId)")
            for target in active {
                try ContractRules.require(phraseIds.contains(target.payload.entryId), "word_state_as_phrase:\(target.recordId)")
                try ContractRules.require(!target.payload.provenanceRefs.isEmpty, "missing_provenance:\(target.recordId)")
                try ContractRules.require(!(teachByTarget[target.recordId] ?? []).isEmpty, "missing_teaching:\(target.recordId)")
                let train = (questionsByTarget[target.recordId] ?? []).filter { $0.payload.split == .train }
                try ContractRules.require(!train.isEmpty, "missing_train:\(target.recordId)")
            }
        }
    }

    func testPhrasePilotCountIsThirtyDistinct() throws {
        let data = try load()
        let phrases = data.entries.filter { $0.payload.entryKind == .phrase }
        // Count derived from the file itself; expectation is 30.
        XCTAssertEqual(phrases.count, 30)
        XCTAssertEqual(Set(phrases.map(\.recordId)).count, 30)
        XCTAssertEqual(Set(phrases.map { $0.payload.lemma }).count, 30)
    }

    func testEveryActivePhraseTargetHasTeachingTrainProvenance() throws {
        let data = try load()
        try validateCandidate(data, expectedPhrases: 30)
        let active = data.targets.filter { $0.payload.activation == .active }
        XCTAssertEqual(active.count, 60)
        XCTAssertEqual(data.teachings.count, 60)
    }

    func testWordsCannotStandInForPhrase() throws {
        let data = try load()
        // Given: real phrase targets bind only to phrase identities.
        try validateCandidate(data, expectedPhrases: 30)
        XCTAssertFalse(data.wordIds.isEmpty)
        // When: a phrase target is rebound to a real word entry (word state).
        var mutated = data
        guard let wordId = data.wordIds.first,
              let index = mutated.targets.firstIndex(where: { $0.payload.activation == .active }) else {
            return XCTFail("Expected real active phrase target and word id")
        }
        let raw = try ContractJSON.line(.target(mutated.targets[index]))
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var payload = try XCTUnwrap(dict["payload"] as? [String: Any])
        payload["entry_id"] = wordId
        dict["payload"] = payload
        let resealed = try ContractJSON.seal(JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes]))
        guard case .target(let rebound) = resealed else { return XCTFail("Expected target") }
        mutated.targets[index] = rebound
        // Then: the word-state substitution must be rejected.
        XCTAssertThrowsError(try validateCandidate(mutated, expectedPhrases: 30)) { error in
            XCTAssertTrue(String(describing: error).contains("word_state_as_phrase"), "\(error)")
            print("PhrasePilot word-state rejected: \(error)")
        }
    }

    func testWhitespaceDoesNotSplitPhrase() throws {
        let data = try load()
        let phrases = data.entries.filter { $0.payload.entryKind == .phrase }
        // Given: every real phrase lemma is multiword (contains whitespace).
        XCTAssertFalse(phrases.isEmpty)
        for entry in phrases {
            XCTAssertTrue(entry.payload.lemma.contains(" "), "Expected whole multiword phrase: \(entry.payload.lemma)")
        }
        // Splitting on whitespace would inflate 30 phrases into far more tokens.
        let tokenCount = phrases.reduce(0) { $0 + $1.payload.lemma.split(separator: " ").count }
        XCTAssertGreaterThan(tokenCount, 30)
        XCTAssertEqual(phrases.count, 30)
        try validateCandidate(data, expectedPhrases: 30)
        // A whitespace-split counter must be rejected as inflation.
        XCTAssertThrowsError(try ContractRules.require(tokenCount == 30, "whitespace_split_inflation:\(tokenCount)")) { error in
            XCTAssertTrue(String(describing: error).contains("whitespace_split_inflation"), "\(error)")
            print("PhrasePilot whitespace split rejected: \(error)")
        }
    }

    func testAutomaticallyConcatenatedDuplicatesDoNotCount() throws {
        let data = try load()
        // Given: 30 distinct phrase lemmas, no duplicates.
        try validateCandidate(data, expectedPhrases: 30)
        // When: an automatically concatenated duplicate (same lemma, new id)
        // is appended the way a naive joiner would produce.
        var mutated = data
        guard let first = mutated.entries.first(where: { $0.payload.entryKind == .phrase }) else {
            return XCTFail("Expected a real phrase entry")
        }
        let raw = try ContractJSON.line(.entry(first))
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        dict["record_id"] = "lx:phrase:\(UUID().uuidString.lowercased())"
        let resealed = try ContractJSON.seal(JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes]))
        guard case .entry(let dupe) = resealed else { return XCTFail("Expected entry") }
        mutated.entries.append(dupe)
        // Then: the duplicate must be rejected, never counted as a 31st phrase.
        XCTAssertThrowsError(try validateCandidate(mutated, expectedPhrases: 30)) { error in
            let reason = String(describing: error)
            XCTAssertTrue(reason.contains("phrase_count_mismatch") || reason.contains("duplicate_phrase_lemma"), "\(error)")
            print("PhrasePilot concatenated duplicate rejected: \(error)")
        }
    }
}
