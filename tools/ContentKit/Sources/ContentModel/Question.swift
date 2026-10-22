import Foundation

public typealias Question = ContentDocument<QuestionPayload>
public struct QuestionOption: Codable {
    public let optionId: String
    public let english: String
}
public struct AnswerFeedback: Codable {
    public let answer: String
    public let explanation: String
}
public struct DistractorRationale: Codable {
    public let optionId: String
    public let reason: String
}
public struct QuestionPayload: ContractPayload {
    public static let kind = ContractKind.question
    public let primaryTargetId: String
    public let testedAbility: TestedAbility
    public let familyId: String
    public let split: FamilySplit
    public let stem: String
    public let options: [QuestionOption]
    public let acceptedAnswers: [String]
    public let correctSenseId: String
    public let correctUsageIds: [String]
    public let postAnswerFeedback: AnswerFeedback
    public let distractorRationales: [DistractorRationale]
    public let provenanceRefs: [String]
    public let status: ContentStatus
    public func validate(recordId: String) throws {
        try ContractRules.id(recordId, [.question]); try ContractRules.id(primaryTargetId, [.target])
        try ContractRules.id(familyId, [.family]); try ContractRules.id(correctSenseId, [.sense])
        for id in correctUsageIds { try ContractRules.id(id, [.usage]) }
        try ContractRules.require(ContractRules.present(stem) && ContractRules.refs(acceptedAnswers)
            && ContractRules.refs(provenanceRefs), "question_required_fields")
        try ContractRules.require(ContractRules.present(postAnswerFeedback.answer)
            && ContractRules.present(postAnswerFeedback.explanation), "feedback_required")
        let optionIds = Set(options.map(\.optionId))
        try ContractRules.require(optionIds.count == options.count
            && options.allSatisfy { ContractRules.present($0.optionId) && ContractRules.present($0.english) }, "invalid_options")
        switch testedAbility {
        case .contextualChoice, .meaningRecognition:
            try ContractRules.require(options.count >= 2 && Set(acceptedAnswers).isSubset(of: optionIds), "choice_answers_required")
            let wrong = optionIds.subtracting(acceptedAnswers)
            try ContractRules.require(Set(distractorRationales.map(\.optionId)) == wrong
                && distractorRationales.count == wrong.count
                && distractorRationales.allSatisfy { ContractRules.present($0.reason) }, "distractor_rationale_required")
        case .writing:
            try ContractRules.require(options.isEmpty && distractorRationales.isEmpty, "writing_not_choice")
        }
    }
}
