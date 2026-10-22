import Foundation

public typealias Provenance = ContentDocument<ProvenancePayload>
public enum DerivationMethod: String, Codable {
    case reference, extract, adapt
    case humanAuthored = "human_authored"
    case aiGenerated = "ai_generated"
}
public struct DerivedField: Codable {
    public let field: String
    // v1 bytes and meaning stay frozen; v2 cannot use the ambiguous old key.
    private let legacySourceRefs: [ContractSourceRef]?
    public let externalSourceRefs: [ContractSourceRef]?
    public let internalEvidenceRefs: [InternalEvidenceRef]?
    public let unverifiedRefs: [UnverifiedOriginRef]?
    public let origin: ProvenanceOrigin?
    public let method: DerivationMethod
    public var sourceRefs: [ContractSourceRef] { legacySourceRefs ?? externalSourceRefs ?? [] }
    enum CodingKeys: String, CodingKey {
        case field, legacySourceRefs = "sourceRefs", externalSourceRefs, internalEvidenceRefs, unverifiedRefs, origin, method
    }
    func validate(schema: String) throws {
        if schema == "lexvane.content.v1" {
            try ContractRules.require(legacySourceRefs != nil && externalSourceRefs == nil
                && internalEvidenceRefs == nil && unverifiedRefs == nil && origin == nil, "v1_provenance_fields")
            try ContractRules.sourceRefs(sourceRefs)
            return
        }
        guard legacySourceRefs == nil, let externalSourceRefs, let internalEvidenceRefs,
              let unverifiedRefs, let origin else { throw ContractFailure("v2_provenance_fields") }
        if !externalSourceRefs.isEmpty { try ContractRules.sourceRefs(externalSourceRefs) }
        for evidence in internalEvidenceRefs {
            try ContractRules.require(ContractRules.localRef(evidence.ref) && !evidence.ref.contains("#")
                && evidence.line.map({ $0 > 0 }) != false && ContractRules.present(evidence.reason), "invalid_internal_evidence")
            switch evidence.availability {
            case .available:
                try ContractRules.require(evidence.sha256.map(CKIdentityJSON.hashValid) == true, "internal_evidence_hash_required")
            case .unresolved:
                try ContractRules.require(evidence.sha256 == nil, "unresolved_evidence_is_not_proof")
            }
        }
        for ref in unverifiedRefs {
            try ContractRules.sourceRefs([.init(sourceId: ref.originalSourceId, operations: ref.operations)])
            try ContractRules.require(ContractRules.present(ref.reason), "unverified_reason_required")
        }
        switch origin {
        case .external:
            try ContractRules.require(!externalSourceRefs.isEmpty && unverifiedRefs.isEmpty, "external_origin_requires_sources")
        case .generated:
            try ContractRules.require([.aiGenerated, .humanAuthored].contains(method)
                && !internalEvidenceRefs.isEmpty && unverifiedRefs.isEmpty, "generated_origin_requires_work_evidence")
        case .unverified:
            try ContractRules.require(!unverifiedRefs.isEmpty, "unverified_origin_requires_original_refs")
        }
    }
}
public enum ProvenanceOrigin: String, Codable { case external, generated, unverified }
public enum EvidenceAvailability: String, Codable { case available, unresolved }
public struct InternalEvidenceRef: Codable {
    public let ref: String
    public let line: Int?
    public let availability: EvidenceAvailability
    public let sha256: String?
    public let reason: String
}
public struct UnverifiedOriginRef: Codable {
    public let originalSourceId: String
    public let operations: [SourceOperation]
    public let reason: String
}
/// A maintenance log, never an author/reviewer receipt or a rights grant.
public struct ProvenanceMigrationEvidence: Codable {
    public let historyRef: String
    public let historySha256: String
    public let reason: String
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
    public let migrationEvidence: ProvenanceMigrationEvidence?
    public func validate(recordId: String) throws {
        try validate(recordId: recordId, schema: "lexvane.content.v1")
    }
    public func validate(recordId: String, schema: String) throws {
        try ContractRules.schema(schema, kind: Self.kind)
        if schema == "lexvane.content.v1" {
            try ContractRules.require(migrationEvidence == nil, "v1_provenance_fields")
        }
        if let evidence = migrationEvidence {
            try ContractRules.require(ContractRules.localRef(evidence.historyRef)
                && CKIdentityJSON.hashValid(evidence.historySha256)
                && ContractRules.present(evidence.reason), "invalid_migration_evidence")
        }
        try ContractRules.require(ContractRules.localRef(recordId) && ContractRules.present(subjectId)
            && subjectRevision > 0 && CKIdentityJSON.hashValid(subjectContentSha256)
            && !fields.isEmpty && Set(fields.map(\.field)).count == fields.count, "provenance_required_fields")
        for field in fields {
            try ContractRules.require(ContractRules.present(field.field), "empty_derived_field")
            try field.validate(schema: schema)
        }
        try ContractRules.require(ContractRules.present(model) && CKIdentityJSON.hashValid(promptHash)
            && ContractRules.localRef(workUnitRef) && ContractRules.localRef(runReceiptRef)
            && transformChain.allSatisfy(ContractRules.present)
            && reviewRefs.allSatisfy(ContractRules.localRef)
            && humanModificationRefs.allSatisfy(ContractRules.localRef), "provenance_receipts_required")
    }
}
