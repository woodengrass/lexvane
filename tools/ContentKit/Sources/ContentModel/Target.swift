import Foundation

public typealias Target = ContentDocument<TargetPayload>
public enum TargetActivation: String, Codable { case active, inactive }
public struct TargetPayload: ContractPayload {
    public static let kind = ContractKind.target
    public let entryId: String
    public let senseId: String
    public let usageIds: [String]
    public let testedAbility: TestedAbility
    public let activation: TargetActivation
    public let priorityTier: PriorityTier
    public let priorityReason: String
    public let sourceRefs: [ContractSourceRef]
    public let provenanceRefs: [String]
    public let status: ContentStatus
    public func validate(recordId: String) throws {
        try ContractRules.id(recordId, [.target]); try ContractRules.id(entryId, [.word, .phrase])
        try ContractRules.id(senseId, [.sense])
        for id in usageIds { try ContractRules.id(id, [.usage]) }
        try ContractRules.sourceRefs(sourceRefs)
        try ContractRules.require(ContractRules.present(priorityReason) && ContractRules.refs(provenanceRefs), "target_required_fields")
    }
}
