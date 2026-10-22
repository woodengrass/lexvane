import Foundation

public typealias Entry = ContentDocument<EntryPayload>
public struct EntrySpelling: Codable {
    public let text: String
    public let entryId: String
}
public struct EntryPayload: ContractPayload {
    public static let kind = ContractKind.entry
    public let entryKind: IdentityKind
    public let lemma: String
    public let aliases: [EntrySpelling]
    public let variants: [EntrySpelling]
    public let senseIds: [String]
    public let provenanceRefs: [String]
    public let status: ContentStatus
    public func validate(recordId: String) throws {
        try ContractRules.require([.word, .phrase].contains(entryKind), "invalid_entry_kind")
        try ContractRules.id(recordId, [entryKind])
        try ContractRules.require(ContractRules.present(lemma) && ContractRules.refs(senseIds)
            && ContractRules.refs(provenanceRefs), "entry_required_fields")
        for id in senseIds { try ContractRules.id(id, [.sense]) }
        for spelling in aliases + variants {
            try ContractRules.require(spelling.entryId == recordId, "variant_identity_mismatch")
            try ContractRules.require(ContractRules.present(spelling.text), "empty_spelling")
        }
        try ContractRules.require(Set((aliases + variants).map(\.text)).count == aliases.count + variants.count,
                                  "duplicate_spelling")
    }
}
