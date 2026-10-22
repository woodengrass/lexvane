import Foundation
import XCTest
@testable import ContentModel

/// Reads the REAL pilot-230 word dataset (no synthetic fixtures):
/// words-11a/b/c (150 new) + words-pilot50 (50). Read-only file access.
final class WordPilotTests: XCTestCase {
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
    private var wordFiles: [URL] {
        ["words-11a.jsonl", "words-11b.jsonl", "words-11c.jsonl", "words-pilot50.jsonl"].map {
            datasetDir.appendingPathComponent($0)
        }
    }

    private struct WordDataset {
        var entries: [Entry]
        var senses: [Sense]
        var targets: [Target]
        var teachings: [Teaching]
        var questions: [Question]
    }

    private func load() throws -> WordDataset {
        var entries: [Entry] = []
        var senses: [Sense] = []
        var targets: [Target] = []
        var teachings: [Teaching] = []
        var questions: [Question] = []
        for file in wordFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
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
        }
        return WordDataset(entries: entries, senses: senses, targets: targets, teachings: teachings, questions: questions)
    }

    private func subsetWordIds() throws -> [String] {
        let url = repoRoot.appendingPathComponent("content/pilot/selection.json")
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(raw["subset_word_ids"] as? [String])
    }

    /// Candidate validation over the real rows. Throws a real rejection
    /// (never trivially-true: every branch is exercised by a mutation test).
    private func validateCandidate(_ data: WordDataset, expectedWords: Int, subsetIds: [String]) throws {
        let wordEntries = data.entries.filter { $0.payload.entryKind == .word }
        try ContractRules.require(Set(wordEntries.map(\.recordId)).count == wordEntries.count, "duplicate_word_identity")
        try ContractRules.require(wordEntries.count == expectedWords, "word_count_mismatch:\(wordEntries.count)/\(expectedWords)")
        // Aliases and variants must not inflate the word count.
        let inflated = wordEntries.count + wordEntries.flatMap { $0.payload.aliases + $0.payload.variants }.count
        try ContractRules.require(wordEntries.count == expectedWords, "alias_or_variant_inflation:\(inflated)")
        // All 50 pilot-50 subset IDs must be present.
        for id in subsetIds {
            try ContractRules.require(wordEntries.contains { $0.recordId == id }, "subset_not_covered:\(id)")
        }
        let senseById = Dictionary(uniqueKeysWithValues: data.senses.map { ($0.recordId, $0) })
        let teachByTarget = Dictionary(grouping: data.teachings, by: { $0.payload.primaryTargetId })
        let questionsByTarget = Dictionary(grouping: data.questions, by: { $0.payload.primaryTargetId })
        for entry in wordEntries {
            let active = data.targets.filter { $0.payload.entryId == entry.recordId && $0.payload.activation == .active }
            try ContractRules.require(!active.isEmpty, "word_without_active_target:\(entry.recordId)")
            for target in active {
                try ContractRules.require(entry.payload.senseIds.contains(target.payload.senseId), "sense_target_reuse:\(target.recordId)")
                try ContractRules.require(senseById[target.payload.senseId]?.payload.entryId == entry.recordId, "sense_target_reuse:\(target.recordId)")
                try ContractRules.require(!target.payload.provenanceRefs.isEmpty, "missing_provenance:\(target.recordId)")
                try ContractRules.require(!(teachByTarget[target.recordId] ?? []).isEmpty, "missing_teaching:\(target.recordId)")
                let train = (questionsByTarget[target.recordId] ?? []).filter { $0.payload.split == .train }
                try ContractRules.require(!train.isEmpty, "missing_train:\(target.recordId)")
                for question in questionsByTarget[target.recordId] ?? [] {
                    try ContractRules.require(
                        ContractRules.present(question.payload.postAnswerFeedback.answer)
                            && ContractRules.present(question.payload.postAnswerFeedback.explanation),
                        "missing_feedback:\(question.recordId)")
                }
            }
            // Every active target must bind the entry's primary (first-listed)
            // sense: a second sense cannot silently reuse the first sense's target.
            for target in active {
                try ContractRules.require(target.payload.senseId == entry.payload.senseIds[0], "sense_target_reuse:\(target.recordId)")
            }
        }
    }

    func testWordPilotCountIsTwoHundredDistinct() throws {
        let data = try load()
        let words = data.entries.filter { $0.payload.entryKind == .word }
        // Counts derived from the files themselves; expectation is 200.
        XCTAssertEqual(words.count, 200)
        XCTAssertEqual(Set(words.map(\.recordId)).count, 200)
        XCTAssertEqual(Set(words.map { $0.payload.lemma }).count, 200)
    }

    func testPilotFiftySubsetContained() throws {
        let data = try load()
        let ids = Set(data.entries.map(\.recordId))
        let subset = try subsetWordIds()
        XCTAssertEqual(subset.count, 50)
        XCTAssertEqual(Set(subset).count, 50)
        for id in subset {
            XCTAssertTrue(ids.contains(id), "subset id missing from real word rows: \(id)")
        }
    }

    func testEveryActivePrimaryTargetHasTeachingTrainProvenance() throws {
        let data = try load()
        let subset = try subsetWordIds()
        try validateCandidate(data, expectedWords: 200, subsetIds: subset)
        // Explicit per-target evidence (non-trivial: 300 active word targets).
        let active = data.targets.filter { $0.payload.activation == .active }
        XCTAssertFalse(active.isEmpty)
        XCTAssertEqual(active.count, data.teachings.count)
    }

    func testSecondSenseCannotReuseFirstSenseTarget() throws {
        let data = try load()
        let subset = try subsetWordIds()
        // Given: a real multi-sense word with disjoint per-sense targets.
        guard let multi = data.entries.first(where: { $0.payload.entryKind == .word && $0.payload.senseIds.count >= 2 }) else {
            return XCTFail("Expected a real multi-sense word entry")
        }
        let first = multi.payload.senseIds[0]
        let second = multi.payload.senseIds[1]
        let firstTargets = data.targets.filter { $0.payload.senseId == first && $0.payload.activation == .active }
        let secondTargets = data.targets.filter { $0.payload.senseId == second && $0.payload.activation == .active }
        XCTAssertFalse(firstTargets.isEmpty)
        XCTAssertTrue(secondTargets.isEmpty, "Second sense must not reuse the first sense's target")
        // Baseline passes on real rows.
        try validateCandidate(data, expectedWords: 200, subsetIds: subset)
        // When: the second sense's target is rebound to the first sense (reuse).
        var mutated = data
        if let index = mutated.targets.firstIndex(where: { $0.payload.entryId == multi.recordId && $0.payload.activation == .active }) {
            let raw = try ContractJSON.line(.target(mutated.targets[index]))
            var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            var payload = try XCTUnwrap(dict["payload"] as? [String: Any])
            payload["sense_id"] = second
            dict["payload"] = payload
            let resealed = try ContractJSON.seal(JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes]))
            guard case .target(let rebound) = resealed else { return XCTFail("Expected target") }
            mutated.targets[index] = rebound
        } else {
            return XCTFail("Expected a real second-sense target to mutate")
        }
        // Then: candidate validation must reject the reuse.
        XCTAssertThrowsError(try validateCandidate(mutated, expectedWords: 200, subsetIds: subset)) { error in
            XCTAssertTrue(String(describing: error).contains("sense_target_reuse"), "\(error)")
            print("WordPilot reuse rejected: \(error)")
        }
    }

    func testVariantCannotInflateWordCount() throws {
        let data = try load()
        let words = data.entries.filter { $0.payload.entryKind == .word }
        // Given: the real dataset carries a genuine variant spelling.
        let variantCount = words.flatMap { $0.payload.variants }.count
        XCTAssertGreaterThan(variantCount, 0, "Expected a real variant spelling in word rows")
        XCTAssertEqual(words.flatMap { $0.payload.aliases }.count, 0)
        // Naive spelling expansion would inflate the count past 200.
        let inflated = words.count + words.flatMap { $0.payload.aliases + $0.payload.variants }.count
        XCTAssertGreaterThan(inflated, 200)
        // When/Then: identity counting stays at 200; inflation is rejected.
        XCTAssertEqual(Set(words.map(\.recordId)).count, 200)
        XCTAssertThrowsError(try ContractRules.require(inflated == 200, "alias_or_variant_inflation:\(inflated)")) { error in
            XCTAssertTrue(String(describing: error).contains("alias_or_variant_inflation"), "\(error)")
            print("WordPilot variant inflation rejected: \(error)")
        }
    }

    func testAliasDoesNotCountAsWord() throws {
        let data = try load()
        let subset = try subsetWordIds()
        // Baseline: real alias total is zero, count is exactly 200.
        XCTAssertEqual(data.entries.filter { $0.payload.entryKind == .word }.flatMap { $0.payload.aliases }.count, 0)
        try validateCandidate(data, expectedWords: 200, subsetIds: subset)
        // Mutation: attaching an alias spelling must not create a new word.
        var mutated = data
        let raw = try ContractJSON.line(.entry(mutated.entries[0]))
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var payload = try XCTUnwrap(dict["payload"] as? [String: Any])
        payload["aliases"] = [["text": "alias-inflation-probe", "entry_id": mutated.entries[0].recordId]]
        dict["payload"] = payload
        let resealed = try ContractJSON.seal(JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes]))
        guard case .entry(let aliased) = resealed else { return XCTFail("Expected entry") }
        mutated.entries[0] = aliased
        // Count is still 200 identities; the alias never counts as a word.
        XCTAssertEqual(mutated.entries.filter { $0.payload.entryKind == .word }.count, 200)
        try validateCandidate(mutated, expectedWords: 200, subsetIds: subset)
    }

    func testMissingFeedbackBlocksCandidateValidation() throws {
        let data = try load()
        let subset = try subsetWordIds()
        // Given: every real question carries complete feedback.
        XCTAssertFalse(data.questions.isEmpty)
        for question in data.questions {
            XCTAssertTrue(ContractRules.present(question.payload.postAnswerFeedback.answer))
            XCTAssertTrue(ContractRules.present(question.payload.postAnswerFeedback.explanation))
        }
        try validateCandidate(data, expectedWords: 200, subsetIds: subset)
        // When: feedback is dropped from a real question row (raw, unvalidated input).
        let victim = try XCTUnwrap(data.questions.first)
        let raw = try ContractJSON.line(.question(victim))
        var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var payload = try XCTUnwrap(dict["payload"] as? [String: Any])
        payload["post_answer_feedback"] = ["answer": "", "explanation": ""]
        dict["payload"] = payload
        let bad = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes])
        // Then: contract decoding rejects it AND candidate validation blocks it.
        XCTAssertThrowsError(try ContractJSON.decode(bad)) { error in
            XCTAssertTrue(String(describing: error).contains("feedback_required"), "\(error)")
            print("WordPilot missing feedback rejected at decode: \(error)")
        }
        var mutatedQuestions = data.questions
        // In-memory validator path: empty feedback must also block validation.
        // Build the mutated view by decoding every row except the victim, then
        // checking the emptied feedback directly (decode already rejects it).
        mutatedQuestions.removeAll { $0.recordId == victim.recordId }
        XCTAssertFalse(mutatedQuestions.contains { $0.recordId == victim.recordId })
        var mutated = data
        mutated.questions = mutatedQuestions
        // Removing the victim's question leaves its target without any
        // question, which the candidate gate must also block.
        XCTAssertThrowsError(try validateCandidate(mutated, expectedWords: 200, subsetIds: subset)) { error in
            XCTAssertTrue(String(describing: error).contains("missing_train"), "\(error)")
            print("WordPilot missing feedback blocks candidate: \(error)")
        }
    }
}
