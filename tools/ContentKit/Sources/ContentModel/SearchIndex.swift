import Foundation

/// Deterministic offline pilot search index (M1 Task 17).
///
/// Lookup-key rule (fixed, versioned in ``SearchIndexDocument/normalization``):
/// NFKC compatibility mapping, then English case-insensitive lowercasing.
/// Hyphens, spaces, and whole-phrase surfaces are preserved byte-for-byte
/// after normalization: `re-sign` and `resign` are distinct keys, `form`
/// and `from` never merge, and phrases stay whole (never split on spaces).
/// Only spellings explicitly listed on entry records (lemma, aliases,
/// variants) become terms. No stemming, no fuzzy matching, no invented
/// variants. Entry counts are distinct entries; aliases never inflate them.
///
/// Resolution order: exact key match, then key-prefix match over the sorted
/// term table (binary lower-bound range). Ties always break by stable
/// entry-ID order. A key owned by several entries resolves to the full
/// sorted candidate list with `ambiguous == true`; the index never picks
/// a single winner for the caller.
///
/// Coverage: only non-quarantined entries are indexed. Check-bank answers,
/// teaching examples, and every other non-entry record are never read, so
/// they cannot leak into index bytes. `acceptanceEvaluated` stays false
/// until a Task-14 style acceptance gate exists; quarantined entries are
/// reported in `excludedQuarantinedIds`, never silently dropped.
public enum SearchIndex {
    /// Fixed normalization identifier recorded in every index document.
    public static let normalization = "NFKC+en-lowercase"

    /// Fixed lookup-key derivation: NFKC, then English lowercase.
    /// Hyphens/spaces/case-folding aside, the surface is otherwise untouched.
    public static func normalizeKey(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .lowercased(with: Locale(identifier: "en"))
    }

    public static func sanitizedQueryKey(_ text: String) -> String {
        normalizeKey(text).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Builds a deterministic index from decoded records. Non-entry records
    /// (questions, teaching, provenance, reviews, manifests, ...) are
    /// ignored by construction. Quarantined entries are excluded and listed.
    public static func build(records: [ContractRecord]) throws -> SearchIndexDocument {
        var seen: [String: ContractRecord] = [:]
        for record in records {
            let key = "\(record.document.kind.rawValue)|\(record.recordId)"
            if let prior = seen[key] {
                guard record.document.revision != prior.document.revision else {
                    throw ContractFailure("duplicate_record:\(record.recordId)")
                }
                if record.document.revision > prior.document.revision { seen[key] = record }
            } else {
                seen[key] = record
            }
        }
        let entries = seen.values.compactMap { record -> Entry? in
            if case .entry(let entry) = record { return entry }
            return nil
        }.sorted { $0.recordId < $1.recordId }
        var excluded: [String] = []
        var postings: [String: (term: String, ids: Set<String>)] = [:]
        var documents: [SearchIndexEntry] = []
        for entry in entries {
            guard entry.payload.status != .quarantined else {
                excluded.append(entry.recordId)
                continue
            }
            documents.append(SearchIndexEntry(
                entryId: entry.recordId,
                kind: entry.payload.entryKind.rawValue,
                lemma: entry.payload.lemma))
            var surfaces: [(display: String, key: String)] = []
            surfaces.append((entry.payload.lemma, normalizeKey(entry.payload.lemma)))
            for spelling in (entry.payload.aliases + entry.payload.variants) {
                surfaces.append((spelling.text, normalizeKey(spelling.text)))
            }
            for surface in surfaces {
                var slot = postings[surface.key] ?? (surface.display, [])
                if slot.term != surface.display {
                    slot.term = [slot.term, surface.display].sorted().first!
                }
                slot.ids.insert(entry.recordId)
                postings[surface.key] = slot
            }
        }
        let terms = postings.map { key, slot in
            SearchIndexTerm(key: key, term: slot.term, entryIds: slot.ids.sorted())
        }.sorted { left, right in
            if left.key != right.key { return left.key < right.key }
            return left.term < right.term
        }
        return SearchIndexDocument(
            schema: "lexvane.index.v1",
            normalization: normalization,
            acceptanceEvaluated: false,
            excludedQuarantinedIds: excluded.sorted(),
            entryCount: documents.count,
            termCount: terms.count,
            terms: terms,
            entries: documents)
    }

    /// Resolves a raw query: exact key match first, then binary prefix range.
    /// Never invents spellings; unknown queries resolve to `.none` with no IDs.
    public static func resolve(query: String, index: SearchIndexDocument) -> SearchResolution {
        let key = sanitizedQueryKey(query)
        guard !key.isEmpty else {
            return SearchResolution(queryKey: key, entryIds: [], ambiguous: false, matchKind: .none)
        }
        if let term = exactTerm(for: key, in: index.terms) {
            return SearchResolution(queryKey: key, entryIds: term.entryIds,
                                    ambiguous: term.entryIds.count > 1, matchKind: .exact)
        }
        let ids = prefixEntryIds(for: key, in: index.terms)
        guard !ids.isEmpty else {
            return SearchResolution(queryKey: key, entryIds: [], ambiguous: false, matchKind: .none)
        }
        return SearchResolution(queryKey: key, entryIds: ids,
                                ambiguous: ids.count > 1, matchKind: .prefix)
    }

    /// Canonical bytes for stable hashes and byte-identical rebuild checks.
    public static func bytes(_ document: SearchIndexDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> SearchIndexDocument {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let document = try decoder.decode(SearchIndexDocument.self, from: data)
            guard document.schema == "lexvane.index.v1",
                  document.normalization == normalization,
                  document.entryCount == document.entries.count,
                  document.termCount == document.terms.count,
                  document.entries.map(\.entryId).sorted() == document.entries.map(\.entryId),
                  document.terms.map(\.key).sorted() == document.terms.map(\.key) else {
                throw ContractFailure("invalid_index")
            }
            return document
        } catch let failure as ContractFailure {
            throw failure
        } catch {
            throw ContractFailure("invalid_index:\(error)")
        }
    }

    private static func exactTerm(for key: String, in terms: [SearchIndexTerm]) -> SearchIndexTerm? {
        var low = 0, high = terms.count
        while low < high {
            let mid = (low + high) / 2
            if terms[mid].key < key { low = mid + 1 } else { high = mid }
        }
        guard low < terms.count, terms[low].key == key else { return nil }
        return terms[low]
    }

    private static func prefixEntryIds(for key: String, in terms: [SearchIndexTerm]) -> [String] {
        var low = 0, high = terms.count
        while low < high {
            let mid = (low + high) / 2
            if terms[mid].key < key { low = mid + 1 } else { high = mid }
        }
        var ids = Set<String>()
        var cursor = low
        while cursor < terms.count, terms[cursor].key.hasPrefix(key) {
            ids.formUnion(terms[cursor].entryIds)
            cursor += 1
        }
        return ids.sorted()
    }
}

public enum SearchMatchKind: String, Codable {
    case exact, prefix, none
}

public struct SearchResolution {
    public let queryKey: String
    public let entryIds: [String]
    public let ambiguous: Bool
    public let matchKind: SearchMatchKind
}

public struct SearchIndexTerm: Codable {
    public let key: String
    public let term: String
    public let entryIds: [String]
    public init(key: String, term: String, entryIds: [String]) {
        self.key = key; self.term = term; self.entryIds = entryIds
    }
}

public struct SearchIndexEntry: Codable {
    public let entryId: String
    public let kind: String
    public let lemma: String
    public init(entryId: String, kind: String, lemma: String) {
        self.entryId = entryId; self.kind = kind; self.lemma = lemma
    }
}

public struct SearchIndexDocument: Codable {
    public let schema: String
    public let normalization: String
    public let acceptanceEvaluated: Bool
    public let excludedQuarantinedIds: [String]
    public let entryCount: Int
    public let termCount: Int
    public let terms: [SearchIndexTerm]
    public let entries: [SearchIndexEntry]
    public init(schema: String, normalization: String, acceptanceEvaluated: Bool,
                excludedQuarantinedIds: [String], entryCount: Int, termCount: Int,
                terms: [SearchIndexTerm], entries: [SearchIndexEntry]) {
        self.schema = schema; self.normalization = normalization
        self.acceptanceEvaluated = acceptanceEvaluated
        self.excludedQuarantinedIds = excludedQuarantinedIds
        self.entryCount = entryCount; self.termCount = termCount
        self.terms = terms; self.entries = entries
    }
}
