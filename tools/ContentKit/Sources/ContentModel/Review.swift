import Foundation

public typealias Review = ContentDocument<ReviewPayload>
public enum ChecklistResult: String, Codable { case passed, failed; case notApplicable = "not_applicable" }
public enum ReviewVerdict: String, Codable { case passed, quarantined; case changesRequested = "changes_requested" }
public enum FindingSeverity: String, Codable { case critical, major, minor }
public enum FindingState: String, Codable { case unresolved, resolved }
public struct ReviewChecklistItem: Codable {
    public let item: String
    public let result: ChecklistResult
    public let reason: String
    public let sourceEvidence: [String]
}
public struct ReviewFinding: Codable {
    public let findingId: String
    public let severity: FindingSeverity
    public let state: FindingState
    public let reason: String
}
public struct ReviewPayload: ContractPayload {
    public static let kind = ContractKind.review
    public let subjectId: String
    public let subjectKind: ContractKind
    public let subjectRevision: Int
    public let subjectContentSha256: String
    public let reviewerSession: String
    public let reviewerModel: String
    public let inputHash: String
    public let promptHash: String
    public let checklist: [ReviewChecklistItem]
    public let verdict: ReviewVerdict
    public let findings: [ReviewFinding]
    public let receiptRefs: [String]
    public func validate(recordId: String) throws {
        try ContractRules.require(ContractRules.localRef(recordId) && ContractRules.present(subjectId)
            && subjectRevision > 0 && CKIdentityJSON.hashValid(subjectContentSha256)
            && CKIdentityJSON.hashValid(inputHash) && CKIdentityJSON.hashValid(promptHash)
            && ContractRules.present(reviewerSession) && ContractRules.present(reviewerModel)
            && !checklist.isEmpty && Set(checklist.map(\.item)).count == checklist.count
            && checklist.allSatisfy { ContractRules.present($0.item) && ContractRules.present($0.reason)
                && ContractRules.refs($0.sourceEvidence) }
            && ContractRules.refs(receiptRefs) && receiptRefs.allSatisfy(ContractRules.localRef), "review_required_fields")
        try ContractRules.require(Set(findings.map(\.findingId)).count == findings.count
            && findings.allSatisfy { ContractRules.present($0.findingId) && ContractRules.present($0.reason) }, "invalid_findings")
        if verdict == .passed {
            try ContractRules.require(!checklist.contains { $0.result == .failed }
                && !findings.contains { $0.state == .unresolved }, "passed_review_has_defects")
        }
    }
}
