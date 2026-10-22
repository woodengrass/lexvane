import Foundation

public typealias Manifest = ContentDocument<ManifestPayload>
public enum ContentBuildMode: String, Codable { case privatePreview = "private-preview" }
public enum TrialPolicyVersion: String, Codable { case trialV0 = "pilot-trial-v0" }
public struct ManifestHash: Codable {
    public let ref: String
    public let sha256: String
}
public struct ManifestCount: Codable {
    public let kind: ContractKind
    public let count: Int
}
public struct ManifestSourceVersion: Codable {
    public let sourceId: String
    public let sourceVersion: String
}
public struct ManifestPayload: ContractPayload {
    public static let kind = ContractKind.manifest
    public let schemaVersion: String
    public let contentVersion: String
    public let policyVersion: TrialPolicyVersion
    public let promptVersion: String
    public let sourceVersions: [ManifestSourceVersion]
    public let inputHashes: [ManifestHash]
    public let counts: [ManifestCount]
    public let buildMode: ContentBuildMode
    public let releaseEligible: Bool
    public let humanReviewPending: Bool
    public let fileHashes: [ManifestHash]
    public let licenseSummary: String
    public let indexFormat: String
    public let checkBankHash: String
    public let fixedInputTime: String
    public func validate(recordId: String) throws {
        try ContractRules.require(ContractRules.localRef(recordId) && schemaVersion == "lexvane.content.v1"
            && ContractRules.present(contentVersion) && ContractRules.present(promptVersion)
            && !releaseEligible && humanReviewPending && ContractRules.present(licenseSummary)
            && ContractRules.present(indexFormat) && CKIdentityJSON.hashValid(checkBankHash)
            && ISO8601DateFormatter().date(from: fixedInputTime) != nil, "manifest_required_fields")
        try ContractRules.require(!sourceVersions.isEmpty && sourceVersions.allSatisfy {
            ContractRules.present($0.sourceId) && CKIdentityJSON.hashValid($0.sourceVersion)
        }, "invalid_source_versions")
        for hashes in [inputHashes, fileHashes] {
            try ContractRules.require(!hashes.isEmpty && Set(hashes.map(\.ref)).count == hashes.count
                && hashes.allSatisfy { ContractRules.localRef($0.ref) && CKIdentityJSON.hashValid($0.sha256) }, "invalid_manifest_hashes")
        }
        try ContractRules.require(Set(counts.map(\.kind)).count == counts.count
            && counts.count == ContractKind.allCases.count && counts.allSatisfy { $0.count >= 0 }, "invalid_counts")
    }
}
