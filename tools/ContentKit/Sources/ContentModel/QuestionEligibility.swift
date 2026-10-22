import Foundation

/// Successor serving policy, deliberately separate from the frozen content.v1 contract.
/// An assessment is reviewer evidence, not an author rationale or a status promotion.
public struct QuestionEligibilityPolicy: Codable {
    public let version: String
    public let assessments: [QuestionQualityAssessment]

    public func validate() throws {
        try ContractRules.require(version == "question-eligibility-v3", "unknown_question_eligibility_policy")
    }
}

public struct QualityEvidence: Codable {
    public let passed: Bool
    public let reason: String
    public let evidence: [String]

    var complete: Bool { ContractRules.present(reason) && ContractRules.refs(evidence) }
}

public struct DistractorAssessment: Codable {
    public let optionId: String
    public let plausibility: QualityEvidence
}

public struct QuestionQualityAssessment: Codable {
    public let questionId: String
    public let revision: Int
    public let contentSha256: String
    public let authorSession: String
    public let evaluatorSession: String
    public let distractors: [DistractorAssessment]
    public let uniqueAnswer: QualityEvidence
    public let noLeakage: QualityEvidence
    /// Only two-option TRAIN practice can use this explicit, content-bound exception.
    public let binaryContrast: QualityEvidence?

    func matches(_ question: Question) -> Bool {
        questionId == question.recordId && revision == question.revision && contentSha256 == question.contentSha256
    }
}

public enum QuestionEligibilityState: String, Codable { case eligible, pending, rejected }
public struct QuestionEligibilityDecision: Codable {
    public let questionId: String
    public let revision: Int
    public let contentSha256: String
    public let split: FamilySplit
    public let optionCount: Int
    public let contentStatus: ContentStatus
    public let state: QuestionEligibilityState
    public let missingWork: [String]
    public let needsAuthor: Bool
    public let needsReview: Bool
    public var eligible: Bool { state == .eligible }
}

public enum QuestionEligibility {
    public static func evaluate(_ question: Question, policy: QuestionEligibilityPolicy,
                                reviews: [Review]) -> QuestionEligibilityDecision {
        let p = question.payload
        var work: [String] = [], author = false, review = false, rejected = false
        func reject(_ reason: String, authorWork: Bool = false) {
            work.append(reason); rejected = true; author = author || authorWork
        }
        if policy.version != "question-eligibility-v3" { reject("unsupported_policy") }
        if p.testedAbility == .writing { reject("writing_not_supported") }
        if p.status == .quarantined { reject("quarantined") }
        if (try? question.revisionHash()) != question.contentSha256 { reject("invalid_content_binding") }
        if p.testedAbility == .writing {
            return QuestionEligibilityDecision(questionId: question.recordId, revision: question.revision,
                contentSha256: question.contentSha256, split: p.split, optionCount: p.options.count,
                contentStatus: p.status, state: .rejected, missingWork: work.sorted(),
                needsAuthor: false, needsReview: false)
        }
        let binary = p.split == .train && p.options.count == 2
        if p.options.count != 4 && !binary { reject("requires_four_options", authorWork: true) }
        let ids = Set(p.options.map(\.optionId))
        if p.acceptedAnswers.count != 1 || !Set(p.acceptedAnswers).isSubset(of: ids) {
            reject("requires_one_correct_option", authorWork: true)
        }
        let texts = p.options.map { $0.english.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased() }
        if ids.count != p.options.count || Set(texts).count != texts.count || texts.contains("") {
            reject("duplicate_or_empty_options", authorWork: true)
        }
        let wrong = ids.subtracting(p.acceptedAnswers)
        if Set(p.distractorRationales.map(\.optionId)) != wrong
            || p.distractorRationales.count != wrong.count
            || p.distractorRationales.contains(where: { !ContractRules.present($0.reason) }) {
            reject("author_distractor_rationales_required", authorWork: true)
        }
        if !ContractRules.present(p.postAnswerFeedback.answer) || !ContractRules.present(p.postAnswerFeedback.explanation) {
            reject("answer_feedback_required", authorWork: true)
        }

        let subjectReviews = reviews.filter { $0.payload.subjectKind == .question && $0.payload.subjectId == question.recordId }
        let currentReviews = subjectReviews.filter {
            $0.payload.subjectRevision == question.revision && $0.payload.subjectContentSha256 == question.contentSha256
        }
        var reviewHashes: [String: String] = [:]
        for item in subjectReviews {
            if let prior = reviewHashes[item.recordId], prior != item.contentSha256 {
                reject("conflicting_review_identity"); review = true
            }
            reviewHashes[item.recordId] = item.contentSha256
        }
        if currentReviews.isEmpty {
            work.append(subjectReviews.isEmpty ? "current_review_missing" : "current_review_stale"); review = true
        }
        // A favourable current row never overrides another current unresolved finding.
        if currentReviews.contains(where: { $0.payload.verdict != .passed
            || $0.payload.findings.contains { $0.state == .unresolved }
            || $0.payload.checklist.contains { $0.result == .failed } }) {
            reject("current_quality_findings_unresolved"); review = true
        }
        let requiredChecks = ReviewCoverage.checklistIDs["question"] ?? []
        if currentReviews.contains(where: { item in
            requiredChecks.contains { required in
                !item.payload.checklist.contains { $0.item == required && $0.result == .passed }
            }
        }) {
            reject("current_review_checklist_incomplete"); review = true
        }
        let all = policy.assessments.filter { $0.questionId == question.recordId }
        let current = all.filter { $0.matches(question) }
        if current.isEmpty {
            work.append(all.isEmpty ? "independent_semantic_assessment_missing" : "independent_semantic_assessment_stale")
            review = true
        }
        for assessment in current {
            if currentReviews.contains(where: { $0.payload.reviewerSession == assessment.authorSession }) {
                reject("self_review"); review = true
            }
            if !ContractRules.present(assessment.authorSession) || !ContractRules.present(assessment.evaluatorSession)
                || assessment.authorSession == assessment.evaluatorSession {
                reject("independent_evaluator_required"); review = true
            }
            if Set(assessment.distractors.map(\.optionId)) != wrong || assessment.distractors.count != wrong.count {
                reject("assess_every_distractor"); review = true
            }
            var facets = assessment.distractors.map(\.plausibility) + [assessment.uniqueAnswer, assessment.noLeakage]
            if binary {
                if let contrast = assessment.binaryContrast { facets.append(contrast) }
                else { reject("explicit_binary_contrast_required"); review = true }
            }
            if facets.contains(where: { !$0.complete }) { reject("semantic_reason_and_evidence_required"); review = true }
            if facets.contains(where: { !$0.passed }) { reject("semantic_assessment_failed"); author = true; review = true }
        }
        return QuestionEligibilityDecision(questionId: question.recordId, revision: question.revision,
            contentSha256: question.contentSha256, split: p.split, optionCount: p.options.count, contentStatus: p.status,
            state: rejected ? .rejected : (work.isEmpty ? .eligible : .pending), missingWork: work.sorted(),
            needsAuthor: author, needsReview: review)
    }
}
