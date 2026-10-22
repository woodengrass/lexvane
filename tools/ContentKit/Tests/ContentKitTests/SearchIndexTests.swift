import Foundation
import XCTest
@testable import ContentModel

/// Deterministic offline pilot search index (M1 Task 17).
/// Red-first: references SearchIndex before it exists.
final class SearchIndexTests: XCTestCase {
    private func entryDict(recordId: String, kind: String = "word", lemma: String,
                           aliases: [String] = [], variants: [String] = [],
                           status: String = "candidate") -> [String: Any] {
        func spellings(_ texts: [String]) -> [[String: String]] {
            texts.map { ["text": $0, "entry_id": recordId] }
        }
        return [
            "schema": "lexvane.content.v1",
            "kind": "entry",
            "record_id": recordId,
            "revision": 1,
            "content_sha256": String(repeating: "0", count: 64),
            "payload": [
                "entry_kind": kind,
                "lemma": lemma,
                "aliases": spellings(aliases),
                "variants": spellings(variants),
                "sense_ids": ["lx:sense:00000000-0000-0000-0000-000000000001"],
                "provenance_refs": ["provenance/task17-test"],
                "status": status,
            ] as [String: Any],
        ]
    }

    private func questionDict(nonce: String) -> [String: Any] {
        return [
            "schema": "lexvane.content.v1",
            "kind": "question",
            "record_id": "lx:question:00000000-0000-0000-0000-000000000071",
            "revision": 1,
            "content_sha256": String(repeating: "0", count: 64),
            "payload": [
                "primary_target_id": "lx:target:00000000-0000-0000-0000-000000000071",
                "tested_ability": "meaning_recognition",
                "family_id": "lx:family:00000000-0000-0000-0000-000000000071",
                "split": "train",
                "stem": "Pick the nonce \(nonce) now.",
                "options": [
                    ["english": nonce, "option_id": "option-a"],
                    ["english": "garden", "option_id": "option-b"],
                ],
                "accepted_answers": ["option-a"],
                "correct_sense_id": "lx:sense:00000000-0000-0000-0000-000000000001",
                "correct_usage_ids": ["lx:usage:00000000-0000-0000-0000-000000000001"],
                "post_answer_feedback": ["answer": nonce, "explanation": "nonce explanation for \(nonce)."],
                "distractor_rationales": [["option_id": "option-b", "reason": "A garden is not the nonce."]],
                "provenance_refs": ["provenance/task17-test"],
                "status": "candidate",
            ] as [String: Any],
        ]
    }

    private func seal(_ dict: [String: Any]) throws -> ContractRecord {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return try ContractJSON.seal(data)
    }

    func testAmbiguousAliasReturnsCandidates() throws {
        let first = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000011",
                                       lemma: "behavior", aliases: ["demeanour"]))
        let second = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000012",
                                        lemma: "conduct", aliases: ["demeanour"]))
        let index = try SearchIndex.build(records: [first, second])
        // A shared alias must return every candidate in stable-ID order, never a single pick.
        let shared = SearchIndex.resolve(query: "Demeanour", index: index)
        XCTAssertTrue(shared.ambiguous, "shared alias must be flagged ambiguous")
        XCTAssertEqual(shared.entryIds, ["lx:word:00000000-0000-0000-0000-000000000011",
                                         "lx:word:00000000-0000-0000-0000-000000000012"])
        XCTAssertEqual(shared.matchKind, .exact)
        // Exact lemmas still resolve to their single owner.
        let single = SearchIndex.resolve(query: "behavior", index: index)
        XCTAssertFalse(single.ambiguous)
        XCTAssertEqual(single.entryIds, ["lx:word:00000000-0000-0000-0000-000000000011"])
        XCTAssertEqual(single.matchKind, .exact)
    }

    func testHyphenatedDistinctWordsStayDistinct() throws {
        let resignHyphen = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000021",
                                              lemma: "re-sign"))
        let resignPlain = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000022",
                                             lemma: "resign"))
        let form = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000023",
                                      lemma: "form"))
        let from = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000024",
                                      lemma: "from"))
        let index = try SearchIndex.build(records: [resignHyphen, resignPlain, form, from])
        // Hyphens are preserved: re-sign and resign never conflate; form and from never merge.
        XCTAssertEqual(SearchIndex.resolve(query: "re-sign", index: index).entryIds,
                       ["lx:word:00000000-0000-0000-0000-000000000021"])
        XCTAssertEqual(SearchIndex.resolve(query: "resign", index: index).entryIds,
                       ["lx:word:00000000-0000-0000-0000-000000000022"])
        XCTAssertEqual(SearchIndex.resolve(query: "form", index: index).entryIds,
                       ["lx:word:00000000-0000-0000-0000-000000000023"])
        XCTAssertEqual(SearchIndex.resolve(query: "from", index: index).entryIds,
                       ["lx:word:00000000-0000-0000-0000-000000000024"])
        // English case-insensitive, hyphen still significant.
        XCTAssertEqual(SearchIndex.resolve(query: "RE-SIGN", index: index).entryIds,
                       ["lx:word:00000000-0000-0000-0000-000000000021"])
        // Prefix keeps the hyphen boundary: "re-s" matches only the hyphenated term.
        let prefix = SearchIndex.resolve(query: "re-s", index: index)
        XCTAssertEqual(prefix.matchKind, .prefix)
        XCTAssertEqual(prefix.entryIds, ["lx:word:00000000-0000-0000-0000-000000000021"])
        // Entry count is never inflated by aliases or forms.
        XCTAssertEqual(index.entryCount, 4)
    }

    func testQuarantinedEntryIsNotIndexed() throws {
        let visible = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000031",
                                         lemma: "alpaca"))
        let quarantined = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000032",
                                             lemma: "quarantine-me", status: "quarantined"))
        let index = try SearchIndex.build(records: [visible, quarantined])
        XCTAssertEqual(index.excludedQuarantinedIds, ["lx:word:00000000-0000-0000-0000-000000000032"])
        XCTAssertFalse(index.entries.map(\.entryId).contains("lx:word:00000000-0000-0000-0000-000000000032"))
        let missing = SearchIndex.resolve(query: "quarantine-me", index: index)
        XCTAssertEqual(missing.matchKind, .none)
        XCTAssertTrue(missing.entryIds.isEmpty)
        XCTAssertEqual(SearchIndex.resolve(query: "alpaca", index: index).entryIds,
                       ["lx:word:00000000-0000-0000-0000-000000000031"])
        // Acceptance is still pending at Task 17: the index says so explicitly.
        XCTAssertFalse(index.acceptanceEvaluated)
    }

    func testIndexNeverLeaksCheckAnswers() throws {
        let nonce = "zxqv-check-nonce-471"
        let form = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000041",
                                      lemma: "form"))
        let garden = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000042",
                                        lemma: "garden"))
        let check = try seal(questionDict(nonce: nonce))
        let index = try SearchIndex.build(records: [form, garden, check])
        // The serialized index must not contain check-only material.
        let serialized = String(decoding: try SearchIndex.bytes(index), as: UTF8.self)
        XCTAssertFalse(serialized.contains(nonce), "check answer leaked into index bytes")
        // Neither exact nor prefix lookup can surface the check answer.
        XCTAssertTrue(SearchIndex.resolve(query: nonce, index: index).entryIds.isEmpty)
        XCTAssertTrue(SearchIndex.resolve(query: String(nonce.prefix(6)), index: index).entryIds.isEmpty)
        // Genuine lemma lookup still works.
        XCTAssertEqual(SearchIndex.resolve(query: "form", index: index).entryIds,
                       ["lx:word:00000000-0000-0000-0000-000000000041"])
    }

    func testQueryLeadingTrailingWhitespaceMatchesExact() throws {
        let apple = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000051",
                                       lemma: "apple"))
        let index = try SearchIndex.build(records: [apple])
        let expected = ["lx:word:00000000-0000-0000-0000-000000000051"]
        let baseline = SearchIndex.resolve(query: "apple", index: index)
        XCTAssertEqual(baseline.entryIds, expected)
        XCTAssertEqual(baseline.matchKind, .exact)
        // Leading/trailing ASCII whitespace must resolve identically.
        for query in [" apple", "apple ", "  apple  ", "\tapple\n"] {
            let got = SearchIndex.resolve(query: query, index: index)
            XCTAssertEqual(got.entryIds, expected, "query \(query.debugDescription) must match apple")
            XCTAssertEqual(got.matchKind, .exact, "query \(query.debugDescription) must be exact")
            XCTAssertEqual(got.queryKey, "apple")
        }
        // Whitespace-only queries resolve to none with no IDs.
        for query in ["   ", "\t \n", "\u{00A0}", "\u{3000}"] {
            let got = SearchIndex.resolve(query: query, index: index)
            XCTAssertEqual(got.matchKind, .none, "query \(query.debugDescription) must be none")
            XCTAssertTrue(got.entryIds.isEmpty)
        }
    }

    func testQueryInternalWhitespaceCollapses() throws {
        let pie = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000052",
                                     lemma: "apple pie"))
        let fused = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000053",
                                       lemma: "applepie"))
        let index = try SearchIndex.build(records: [pie, fused])
        let pieId = "lx:word:00000000-0000-0000-0000-000000000052"
        let fusedId = "lx:word:00000000-0000-0000-0000-000000000053"
        XCTAssertEqual(SearchIndex.resolve(query: "apple pie", index: index).entryIds, [pieId])
        // Repeated spaces, tabs, newlines, NBSP, and ideographic space collapse to one ASCII space.
        for query in ["apple  pie", "apple\tpie", "apple\npie", "apple\r\npie",
                      "apple\u{00A0}pie", "apple\u{3000}pie", "  apple   pie  "] {
            let got = SearchIndex.resolve(query: query, index: index)
            XCTAssertEqual(got.entryIds, [pieId], "query \(query.debugDescription) must match apple pie")
            XCTAssertEqual(got.matchKind, .exact)
            XCTAssertEqual(got.queryKey, "apple pie")
        }
        // Fullwidth ASCII folds to ASCII via NFKC, then whitespace cleaning applies.
        XCTAssertEqual(SearchIndex.resolve(query: "ａｐｐｌｅ\u{3000}ｐｉｅ", index: index).entryIds, [pieId])
        // Phrase is never fused: no-space query stays on the fused term only.
        XCTAssertEqual(SearchIndex.resolve(query: "applepie", index: index).entryIds, [fusedId])
        XCTAssertNotEqual(SearchIndex.resolve(query: "apple pie", index: index).entryIds,
                          SearchIndex.resolve(query: "applepie", index: index).entryIds)
    }

    func testQueryWhitespaceCleaningPreservesHyphens() throws {
        let hyphen = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000054",
                                        lemma: "re-sign"))
        let plain = try seal(entryDict(recordId: "lx:word:00000000-0000-0000-0000-000000000055",
                                       lemma: "resign"))
        let index = try SearchIndex.build(records: [hyphen, plain])
        let hyphenId = "lx:word:00000000-0000-0000-0000-000000000054"
        let plainId = "lx:word:00000000-0000-0000-0000-000000000055"
        // Stored keys keep hyphen distinction; index bytes unchanged.
        XCTAssertTrue(index.terms.contains { $0.key == "re-sign" })
        XCTAssertTrue(index.terms.contains { $0.key == "resign" })
        // Fullwidth query folds to ASCII and still respects the hyphen boundary.
        XCTAssertEqual(SearchIndex.resolve(query: "ＲＥ-ＳＩＧＮ", index: index).entryIds, [hyphenId])
        // Padded hyphen queries trim but never drop the hyphen.
        XCTAssertEqual(SearchIndex.resolve(query: "  re-sign ", index: index).entryIds, [hyphenId])
        XCTAssertEqual(SearchIndex.resolve(query: "  resign ", index: index).entryIds, [plainId])
        XCTAssertNotEqual(SearchIndex.resolve(query: "re-sign", index: index).entryIds,
                          SearchIndex.resolve(query: "resign", index: index).entryIds)
    }
}
