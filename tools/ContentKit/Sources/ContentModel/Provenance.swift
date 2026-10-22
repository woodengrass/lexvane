import Foundation

public typealias Provenance = ContentDocument<ProvenancePayload>
public enum DerivationMethod: String, Codable {
    case reference, extract, adapt
    case humanAuthored = "human_authored"
    case aiGenerated = "ai_generated"
}
public struct DerivedField: Codable {
    public let field: String
    public let sourceRefs: [ContractSourceRef]
    public let method: DerivationMethod
}
public struct ProvenancePayload: ContractPayload {
    public static let kind = ContractKind.provenance
    public let subjectId: String
    public let subjectKind: ContractKind
    public let subjectRevision: Int
    public let subjectContentSha256: String
    public let fields: [DerivedField]
    public let model: String
    public let promptHash: String
    public let workUnitRef: String
    public let runReceiptRef: String
    public let transformChain: [String]
    public let reviewRefs: [String]
    public let humanModificationRefs: [String]
    public func validate(recordId: String) throws {
        try ContractRules.require(ContractRules.localRef(recordId) && ContractRules.present(subjectId)
            && subjectRevision > 0 && CKIdentityJSON.hashValid(subjectContentSha256)
            && !fields.isEmpty && Set(fields.map(\.field)).count == fields.count, "provenance_required_fields")
        for field in fields {
            try ContractRules.require(ContractRules.present(field.field), "empty_derived_field")
            try ContractRules.sourceRefs(field.sourceRefs)
        }
        try ContractRules.require(ContractRules.present(model) && CKIdentityJSON.hashValid(promptHash)
            && ContractRules.localRef(workUnitRef) && ContractRules.localRef(runReceiptRef)
            && transformChain.allSatisfy(ContractRules.present)
            && reviewRefs.allSatisfy(ContractRules.localRef)
            && humanModificationRefs.allSatisfy(ContractRules.localRef), "provenance_receipts_required")
    }
}
