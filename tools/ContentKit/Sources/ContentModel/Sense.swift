import Foundation

public typealias Sense = ContentDocument<SensePayload>
public struct SensePayload: ContractPayload {
    public static let kind = ContractKind.sense
    public let entryId: String
    public let pos: PartOfSpeech
    public let coreMeaningZhHant: String
    public let priorityTier: PriorityTier
    public let priorityReason: String
    public let sourceRefs: [ContractSourceRef]
    public let usageIds: [String]
    public let provenanceRefs: [String]
    public let status: ContentStatus
    public func validate(recordId: String) throws {
        try ContractRules.id(recordId, [.sense]); try ContractRules.id(entryId, [.word, .phrase])
        try ContractRules.require(ContractRules.present(coreMeaningZhHant) && ContractRules.present(priorityReason)
            && ContractRules.refs(provenanceRefs), "sense_required_fields")
        try ContractRules.sourceRefs(sourceRefs)
        for id in usageIds { try ContractRules.id(id, [.usage]) }
    }
}
