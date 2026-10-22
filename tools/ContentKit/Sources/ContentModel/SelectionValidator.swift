import Foundation

public struct SelectionFailure: Error, CustomStringConvertible, Equatable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var description: String { "SelectionFailure(reason=\(reason))" }
}
public enum SelectionFacet: String, Codable, CaseIterable {
    case polysemy
    case secondSense = "second_sense"
    case morphology
    case collocation
    case spellingHyphen = "spelling_hyphen"
    case general
}
public struct FacetEvidence: Codable {
    public var facet: SelectionFacet
    public var pos: String
    public var senseRefs: [String]
    public var examples: [String]
    public var reason: String
    public var evidenceRefs: [String]
    public var gapNote: String?
}
public struct SelectionSource: Codable {
    public var ref: String
    public var sha256: String?
    public var unavailableReason: String?
    enum CodingKeys: String, CodingKey { case ref, sha256, unavailableReason }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(ref, forKey: .ref)
        try values.encode(sha256, forKey: .sha256)
        try values.encode(unavailableReason, forKey: .unavailableReason)
    }
}
public struct SelectionEntry: Codable {
    public var id: String
    public var term: String
    public var kind: IdentityKind
    public var aliasOf: String?
    public var variantOf: String?
    public var componentsOf: String?
    public var wholePhrase: Bool
    public var basis: String
    public var basisReason: String
    public var evidenceRefs: [String]
    public var mappingStatus: CoverageStatus?
    public var mappingReason: String?
    public var mappingRefs: [String]
    public var facets: [FacetEvidence]
}
public struct PilotSelection: Codable {
    public var selectionSeed: String
    public var sources: [SelectionSource]
    /// Array order is the frozen ordered identity list; never sort by opaque ID.
    public var words: [SelectionEntry]
    public var phrases: [SelectionEntry]
    public var subsetWordIds: [String]
}
public struct SelectionReport: Codable {
    public let structurallyValid: Bool
    public let candidateWords: Int
    public let candidatePhrases: Int
    public let subsetWords: Int
    public let mappingVerifiedWords: Int
    public let mappingBlocked: Bool
    public let acceptedContentCount: Int
    public let acceptanceBlocked: Bool
    public let blockers: [String]
    public let facetCounts: [String: Int]
}
public enum SelectionValidator {
    private static func present(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private static func refs(_ values: [String]) -> Bool { !values.isEmpty && values.allSatisfy(present) }
    public static func read(at url: URL) throws -> PilotSelection {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PilotSelection.self, from: Data(contentsOf: url))
    }
    public static func validate(_ selection: PilotSelection, identities: IdentitySnapshot,
                                words: Int, phrases: Int, subsetWords: Int) throws -> SelectionReport {
        guard words > 0, phrases > 0, subsetWords > 0, subsetWords <= words,
              selection.words.count == words, selection.phrases.count == phrases,
              selection.subsetWordIds.count == subsetWords else { throw SelectionFailure("count_mismatch") }
        guard present(selection.selectionSeed), !selection.sources.isEmpty,
              Set(selection.sources.map(\.ref)).count == selection.sources.count,
              selection.sources.allSatisfy({ present($0.ref) && ($0.sha256.map(CKIdentityJSON.hashValid) ?? ($0.unavailableReason.map(present) ?? false)) }) else {
            throw SelectionFailure("source_hash_or_reason_required")
        }
        let entries = selection.words + selection.phrases
        func canonical(_ term: String) -> String { term.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        guard Set(entries.map(\.id)).count == entries.count,
              Set(entries.map { canonical($0.term) }).count == entries.count else { throw SelectionFailure("duplicate_identity_or_term") }
        for entry in entries {
            guard entry.aliasOf == nil, entry.variantOf == nil else { throw SelectionFailure("alias_or_variant_inflation") }
            guard present(entry.term), entry.term == entry.term.trimmingCharacters(in: .whitespacesAndNewlines),
                  let record = identities.records[entry.id], record.kind == entry.kind,
                  !identities.retiredIds.contains(entry.id) else { throw SelectionFailure("unknown_or_retired_identity") }
            guard entry.basis == "own_usage", present(entry.basisReason), refs(entry.evidenceRefs) else {
                throw SelectionFailure("own_basis_required")
            }
        }
        for word in selection.words {
            guard word.kind == .word, !word.term.contains(where: { $0.isWhitespace }), word.componentsOf == nil else {
                throw SelectionFailure("word_identity_required")
            }
            // This candidate-only contract has no authorized extraction/map input.
            // A self-declared mapped status must never become a verified count.
            guard word.mappingStatus == .rightsPending, word.mappingReason.map(present) == true, refs(word.mappingRefs) else {
                throw SelectionFailure("official_mapping_unverified")
            }
        }
        for phrase in selection.phrases {
            guard phrase.kind == .phrase, phrase.wholePhrase, phrase.componentsOf == nil,
                  phrase.term.split(whereSeparator: { $0.isWhitespace }).count >= 2 else { throw SelectionFailure("whole_phrase_required") }
            guard phrase.mappingStatus == nil, phrase.mappingRefs.isEmpty else { throw SelectionFailure("phrase_ceec_link_forbidden") }
        }
        let subset = Set(selection.subsetWordIds)
        guard subset.count == subsetWords else { throw SelectionFailure("duplicate_subset_identity") }
        guard subset.isSubset(of: Set(selection.words.map(\.id))) else { throw SelectionFailure("subset_not_in_words") }
        var counts: [String: Int] = [:]
        for word in selection.words {
            guard Set(word.facets.map(\.facet)).count == word.facets.count else { throw SelectionFailure("duplicate_facet") }
            for evidence in word.facets {
                guard present(evidence.pos), present(evidence.reason), refs(evidence.senseRefs),
                      refs(evidence.examples), refs(evidence.evidenceRefs),
                      ![.polysemy, .secondSense, .morphology].contains(evidence.facet) || Set(evidence.senseRefs).count >= 2 else {
                    throw SelectionFailure("facet_evidence_missing")
                }
                if subset.contains(word.id) { counts[evidence.facet.rawValue, default: 0] += 1 }
            }
        }
        for facet in SelectionFacet.allCases where counts[facet.rawValue, default: 0] == 0 {
            throw SelectionFailure("missing_facet:\(facet.rawValue)")
        }
        return SelectionReport(structurallyValid: true, candidateWords: words, candidatePhrases: phrases,
            subsetWords: subsetWords, mappingVerifiedWords: 0, mappingBlocked: true, acceptedContentCount: 0,
            acceptanceBlocked: true, blockers: ["official_word_mapping_rights_pending:no_authorized_bytes",
                "candidate_selection_is_not_accepted_content", "external_reference_and_level_verification_pending"], facetCounts: counts)
    }
}
