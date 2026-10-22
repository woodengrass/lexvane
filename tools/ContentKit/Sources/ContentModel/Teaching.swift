import Foundation

public typealias Teaching = ContentDocument<TeachingPayload>
public struct TeachingExample: Codable {
    public let english: String
    public let zhHant: String
}
public struct TeachingPayload: ContractPayload {
    public static let kind = ContractKind.teaching
    public let primaryTargetId: String
    public let testedAbility: TestedAbility
    public let explanationZhHant: String
    public let usage: String
    public let examples: [TeachingExample]
    public let pronunciationText: String
    public let sourceRefs: [ContractSourceRef]
    public let provenanceRefs: [String]
    public let status: ContentStatus
    public func validate(recordId: String) throws {
        try ContractRules.id(recordId, [.usage]); try ContractRules.id(primaryTargetId, [.target])
        try ContractRules.sourceRefs(sourceRefs)
        try ContractRules.require(ContractRules.present(explanationZhHant) && ContractRules.present(usage)
            && ContractRules.present(pronunciationText) && !examples.isEmpty
            && examples.allSatisfy { ContractRules.present($0.english) && ContractRules.present($0.zhHant) }
            && ContractRules.refs(provenanceRefs), "teaching_required_fields")
    }
}
