import Foundation
import XCTest
@testable import ContentModel
@testable import ContentCLI

final class QuestionEligibilityTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/contracts/valid")
    }

    private func question(count: Int = 4, split: String = "check", revision: Int = 1,
                          keys: [String] = ["option-a"], texts: [String]? = nil,
                          writing: Bool = false) throws -> Question {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("question.jsonl"))) as? [String: Any])
        var p = try XCTUnwrap(raw["payload"] as? [String: Any])
        let words = texts ?? Array(["form", "receipt", "menu", "ticket"].prefix(count))
        let ids = ["option-a", "option-b", "option-c", "option-d"]
        p["options"] = writing ? [] : words.enumerated().map { ["option_id": ids[$0.offset], "english": $0.element] }
        p["accepted_answers"] = writing ? ["form"] : keys
        let rationales = ["An application form collects new details; a receipt records a completed payment.",
            "A menu lists food choices rather than personal application details.",
            "A ticket grants admission or travel rather than collecting a job application."]
        p["distractor_rationales"] = writing ? [] : words.enumerated().filter { !keys.contains(ids[$0.offset]) }
            .map { ["option_id": ids[$0.offset], "reason": rationales[max(0, $0.offset - 1)]] }
        p["tested_ability"] = writing ? "writing" : "contextual_choice"
        p["split"] = split
        p["stem"] = split == "train"
            ? "For the job application, fill in each blank on this ___ with your name and address."
            : "At the passport office, enter your personal details in the boxes on this application ___."
        p["post_answer_feedback"] = ["answer": "form", "explanation": "A form has fields for entering requested information."]
        if split == "check" {
            raw["record_id"] = "lx:question:00000000-0000-0000-0000-000000000002"
            p["family_id"] = "lx:family:00000000-0000-0000-0000-000000000002"
        }
        raw["revision"] = revision; raw["payload"] = p
        guard case .question(let q) = try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw)) else {
            throw QualityFailure(reason: "fixture_not_question")
        }
        return q
    }

    private func evidence(_ reason: String, passed: Bool = true) -> QualityEvidence {
        QualityEvidence(passed: passed, reason: reason, evidence: ["synthetic-fixture:full-question-and-all-options"])
    }

    private func assessment(_ q: Question, contrast: Bool = false, sameAuthor: Bool = false,
                            missingReason: Bool = false, failed: Bool = false) -> QuestionQualityAssessment {
        QuestionQualityAssessment(questionId: q.recordId, revision: q.revision, contentSha256: q.contentSha256,
            authorSession: "fixture-author", evaluatorSession: sameAuthor ? "fixture-author" : "fixture-independent-reviewer",
            distractors: q.payload.distractorRationales.map { DistractorAssessment(optionId: $0.optionId,
                plausibility: evidence("Printed everyday documents are plausible to confuse, but: \($0.reason)")) },
            uniqueAnswer: evidence(missingReason ? "" : "Only form conventionally completes application form and supplies blank personal-detail fields.", passed: !failed),
            noLeakage: evidence("Neither stem spells form nor embeds it in a longer word; feedback is post-answer, and options are parallel document nouns."),
            binaryContrast: contrast ? evidence("Practice contrasts an application collecting details with a receipt recording payment; a deliberate document-function contrast, not unseen four-way assessment.") : nil)
    }

    private func review(_ q: Question, blocked: Bool = false, incomplete: Bool = false,
                        authorSession: Bool = false) throws -> Review {
        let hash = String(repeating: "a", count: 64)
        let checks = incomplete ? ["answer"] : (ReviewCoverage.checklistIDs["question"] ?? [])
        let raw: [String: Any] = ["schema": "lexvane.content.v1", "kind": "review", "record_id": "reviews/\(q.recordId.split(separator: ":").last!)/\(blocked ? "blocked" : "passed")",
            "revision": 1, "content_sha256": "", "payload": [
                "subject_id": q.recordId, "subject_kind": "question", "subject_revision": q.revision,
                "subject_content_sha256": q.contentSha256, "reviewer_session": authorSession ? "fixture-author" : "fixture-independent-reviewer",
                "reviewer_model": "fixture", "input_hash": hash, "prompt_hash": hash,
                "checklist": checks.map { ["item": $0, "result": "passed", "reason": "Reviewed full fixture", "source_evidence": ["fixture/question"]] as [String: Any] },
                "verdict": blocked ? "changes_requested" : "passed",
                "findings": blocked ? [["finding_id": "quality-1", "severity": "minor", "state": "unresolved", "reason": "An unresolved current fixture defect"]] : [],
                "receipt_refs": ["fixture/review-receipt"]]]
        guard case .review(let r) = try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw)) else {
            throw QualityFailure(reason: "fixture_not_review")
        }
        return r
    }

    private func policy(_ assessments: [QuestionQualityAssessment]) -> QuestionEligibilityPolicy {
        QuestionEligibilityPolicy(version: "question-eligibility-v3", assessments: assessments)
    }

    func testTwoAndThreeOptionChecksRejectedDespiteCurrentReviews() throws {
        for count in [2, 3] {
            let q = try question(count: count)
            let result = QuestionEligibility.evaluate(q, policy: policy([assessment(q, contrast: true)]), reviews: [try review(q)])
            XCTAssertFalse(result.eligible)
            XCTAssertTrue(result.missingWork.contains("requires_four_options"))
        }
    }

    func testThreeOptionTrainRejected() throws {
        let q = try question(count: 3, split: "train")
        XCTAssertFalse(QuestionEligibility.evaluate(q, policy: policy([assessment(q)]), reviews: [try review(q)]).eligible)
    }

    func testMultipleKeysRejected() throws {
        let q = try question(keys: ["option-a", "option-b"])
        let result = QuestionEligibility.evaluate(q, policy: policy([assessment(q)]), reviews: [try review(q)])
        XCTAssertTrue(result.missingWork.contains("requires_one_correct_option"))
        XCTAssertFalse(result.eligible)
    }

    func testNormalizedDuplicateTextRejected() throws {
        let q = try question(texts: ["form", " FORM \n", "menu", "ticket"])
        let result = QuestionEligibility.evaluate(q, policy: policy([assessment(q)]), reviews: [try review(q)])
        XCTAssertTrue(result.missingWork.contains("duplicate_or_empty_options"))
        XCTAssertFalse(result.eligible)
    }

    func testWritingDenied() throws {
        let q = try question(writing: true)
        let result = QuestionEligibility.evaluate(q, policy: policy([]), reviews: [])
        XCTAssertTrue(result.missingWork.contains("writing_not_supported"))
        XCTAssertFalse(result.eligible)
        XCTAssertFalse(result.needsAuthor)
        XCTAssertFalse(result.needsReview)
        XCTAssertFalse(result.missingWork.contains("requires_four_options"))
    }

    func testStalePassAndAssessmentCannotTransferToRevision() throws {
        let old = try question(), current = try question(revision: 2)
        let result = QuestionEligibility.evaluate(current, policy: policy([assessment(old)]), reviews: [try review(old)])
        XCTAssertFalse(result.eligible)
        XCTAssertEqual(result.state, .pending)
        XCTAssertTrue(result.missingWork.contains("current_review_stale"))
        XCTAssertTrue(result.missingWork.contains("independent_semantic_assessment_stale"))
    }

    func testHashMismatchAssessmentCannotQualifySameRevision() throws {
        let old = try question(), changed = try question(texts: ["form", "letter", "menu", "ticket"])
        let result = QuestionEligibility.evaluate(changed, policy: policy([assessment(old)]), reviews: [try review(old)])
        XCTAssertFalse(result.eligible)
        XCTAssertTrue(result.missingWork.contains("independent_semantic_assessment_stale"))
    }

    func testIndependentlyReviewedFourOptionFixtureEligibleWithoutStatusPromotion() throws {
        let q = try question()
        let result = QuestionEligibility.evaluate(q, policy: policy([assessment(q)]), reviews: [try review(q)])
        XCTAssertTrue(result.eligible, result.missingWork.joined(separator: ","))
        XCTAssertEqual(result.contentStatus, .candidate)
        XCTAssertTrue(result.missingWork.isEmpty)
    }

    func testFormatAndAuthorRationalesAloneArePending() throws {
        let q = try question()
        let result = QuestionEligibility.evaluate(q, policy: policy([]), reviews: [try review(q)])
        XCTAssertEqual(result.state, .pending)
        XCTAssertTrue(result.needsReview)
        XCTAssertFalse(result.needsAuthor)
    }

    func testIncompleteCurrentReviewCannotQualify() throws {
        let q = try question()
        let result = QuestionEligibility.evaluate(q, policy: policy([assessment(q)]),
            reviews: [try review(q, incomplete: true)])
        XCTAssertFalse(result.eligible)
        XCTAssertTrue(result.missingWork.contains("current_review_checklist_incomplete"))
    }

    func testAuthorCannotSupplyOwnCurrentReview() throws {
        let q = try question()
        let result = QuestionEligibility.evaluate(q, policy: policy([assessment(q)]),
            reviews: [try review(q, authorSession: true)])
        XCTAssertFalse(result.eligible)
        XCTAssertTrue(result.missingWork.contains("self_review"))
    }

    func testConflictingReviewIdentityCannotQualify() throws {
        let q = try question()
        let result = QuestionEligibility.evaluate(q, policy: policy([assessment(q)]),
            reviews: [try review(q), try review(q, incomplete: true)])
        XCTAssertFalse(result.eligible)
        XCTAssertTrue(result.missingWork.contains("conflicting_review_identity"))
    }

    func testApprovedBinaryPracticeIsWeakerThanCheck() throws {
        let train = try question(count: 2, split: "train"), check = try question(count: 2)
        XCTAssertTrue(QuestionEligibility.evaluate(train, policy: policy([assessment(train, contrast: true)]), reviews: [try review(train)]).eligible)
        let noContrast = QuestionEligibility.evaluate(train, policy: policy([assessment(train)]), reviews: [try review(train)])
        XCTAssertFalse(noContrast.eligible)
        XCTAssertTrue(noContrast.missingWork.contains("explicit_binary_contrast_required"))
        XCTAssertFalse(QuestionEligibility.evaluate(check, policy: policy([assessment(check, contrast: true)]), reviews: [try review(check)]).eligible)
    }

    func testCurrentUnresolvedQualityBlocksEvenWithAnotherPass() throws {
        let q = try question()
        let result = QuestionEligibility.evaluate(q, policy: policy([assessment(q)]), reviews: [try review(q), try review(q, blocked: true)])
        XCTAssertFalse(result.eligible)
        XCTAssertTrue(result.missingWork.contains("current_quality_findings_unresolved"))
    }

    func testIndependentEvaluatorAndReasonEvidenceRequired() throws {
        let q = try question()
        for a in [assessment(q, sameAuthor: true), assessment(q, missingReason: true), assessment(q, failed: true)] {
            XCTAssertFalse(QuestionEligibility.evaluate(q, policy: policy([a]), reviews: [try review(q)]).eligible)
        }
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractJSON.bytes(assessment(q))) as? [String: Any])
        var facet = try XCTUnwrap(raw["unique_answer"] as? [String: Any]); facet["evidence"] = []
        raw["unique_answer"] = facet
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let incomplete = try decoder.decode(QuestionQualityAssessment.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertFalse(QuestionEligibility.evaluate(q, policy: policy([incomplete]), reviews: [try review(q)]).eligible)
    }

    private func integration(assessed: Bool, familyEvidence: Bool = true) throws -> (URL, [Question], [Review], QualityProfile) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dataset"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("reviews"), withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let train = try question(split: "train"), check = try question()
        let reviews = try [review(train), review(check)]
        var bytes = try Data(contentsOf: fixtures.appendingPathComponent("target.jsonl"))
        bytes.append(try ContractJSON.line(.question(train))); bytes.append(try ContractJSON.line(.question(check)))
        try bytes.write(to: root.appendingPathComponent("dataset/current.jsonl"))
        try (ContractJSON.line(.review(reviews[0])) + ContractJSON.line(.review(reviews[1]))).write(to: root.appendingPathComponent("reviews/reviews.jsonl"))
        if familyEvidence {
            func binding(_ q: Question) -> [String: Any] {
                ["record_id": q.recordId, "revision": q.revision, "content_sha256": q.contentSha256]
            }
            let family: [String: Any] = ["target_id": train.payload.primaryTargetId,
                "train_family": train.payload.familyId, "check_family": check.payload.familyId,
                "verdict": "independent", "evidence": "Job application instruction versus passport-office request, compared full fixture prompts and all options.",
                "evaluator_session": "fixture-family-reviewer", "finding_ids": [],
                "current_member_bindings": ["train": binding(train), "check": binding(check)], "current_teaching_bindings": []]
            try (JSONSerialization.data(withJSONObject: family) + Data([10])).write(to: root.appendingPathComponent("reviews/family-bound.jsonl"))
        }
        var (profile, _) = QualityProfileTests.baseline()
        profile.profile = "pilot-quality-v3"
        profile.questionEligibility = policy(assessed ? [assessment(train), assessment(check)] : [])
        try ContractJSON.bytes(profile).write(to: root.appendingPathComponent("profile.json"))
        return (root, [train, check], reviews, profile)
    }

    func testV3QualityRejectionNeverCountsAsFamilyAndMinimumRemainsPositive() throws {
        let (root, questions, reviews, profile) = try integration(assessed: false)
        let family = try FamiliesAudit.audit(dataset: root.appendingPathComponent("dataset"), reviews: root.appendingPathComponent("reviews"), profile: profile)
        XCTAssertFalse(family.valid)
        XCTAssertEqual(family.independentCheckFamiliesByTarget[questions[0].payload.primaryTargetId], 0)
        XCTAssertEqual(family.shortages?.count, 1)
        XCTAssertEqual(profile.perAbilityMinimums["contextual_choice"]?.independentCheckFamilies, 1)
        let result = try simulate(questions, reviews: reviews, profile: profile, family: family)
        XCTAssertEqual(result.eligibleQuestionCount, 0)
        XCTAssertTrue(result.allocations.allSatisfy { $0.trainFamilyIds.isEmpty && $0.consumedCheckFamilyIds.isEmpty })
        XCTAssertEqual(result.allocations.first?.checkShortfall, 1)
        XCTAssertEqual(result.allocations.first?.trainShortfall, 1)
    }

    private func simulate(_ questions: [Question], reviews: [Review], profile: QualityProfile,
                          family: FamiliesAuditReport?) throws -> SupplySimulationReport {
        let scenario = SupplyScenarios(targetIds: [questions[0].payload.primaryTargetId],
            scenarios: [SupplyScenario(id: "v3", trainPresentationsPerTarget: 1, checkPresentationsPerTarget: 1)],
            eligibleQuestions: questions.map { SupplyBinding(questionId: $0.recordId, revision: $0.revision, contentSha256: $0.contentSha256) })
        var request = SupplyRequest(profile: profile, scenarios: scenario, seed: 111)
        request.reviews = reviews; request.familyAudit = family
        return try SupplySimulation.simulate(questions: questions, request: request)
    }

    func testV3ReviewedIndependentFixtureActuallySuppliesAndMissingFamilyDoesNot() throws {
        for hasFamily in [true, false] {
            let (root, questions, reviews, profile) = try integration(assessed: true, familyEvidence: hasFamily)
            let family = try FamiliesAudit.audit(dataset: root.appendingPathComponent("dataset"), reviews: root.appendingPathComponent("reviews"), profile: profile)
            let result = try simulate(questions, reviews: reviews, profile: profile, family: family)
            XCTAssertEqual(result.eligibleQuestionCount, 2)
            XCTAssertEqual(result.allocations.first?.consumedCheckFamilyIds.count, hasFamily ? 1 : 0)
            XCTAssertEqual(result.allocations.first?.checkShortfall, hasFamily ? 0 : 1)
            XCTAssertEqual(family.valid, hasFamily)
            XCTAssertFalse(result.releaseEligible)
            XCTAssertEqual(result.acceptedCount, 0)
        }
    }

    func testV3CannotFallbackToLegacyScenarioOnlyQualification() throws {
        let (_, questions, reviews, profile) = try integration(assessed: true)
        XCTAssertThrowsError(try simulate(questions, reviews: reviews, profile: profile, family: nil))
        var missingPolicy = profile; missingPolicy.questionEligibility = nil
        XCTAssertThrowsError(try missingPolicy.validateEligibilityVersion())
        let (_, trial) = QualityProfileTests.baseline()
        XCTAssertThrowsError(try QualityAudit.audit(profile: profile, trial: trial))
    }

    func testAuditManifestAndMissingWorkAreReproducible() throws {
        let (root, _, _, _) = try integration(assessed: false)
        let args = ["--datasets", root.appendingPathComponent("dataset").path,
            "--reviews", root.appendingPathComponent("reviews").path, "--profile", root.appendingPathComponent("profile.json").path]
        let first = root.appendingPathComponent("first.json"), second = root.appendingPathComponent("second.json")
        XCTAssertEqual(QuestionQualityAuditCommands.run(args + ["--out", first.path]), 0)
        XCTAssertEqual(QuestionQualityAuditCommands.run(args + ["--out", second.path]), 0)
        XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: second))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: first)) as? [String: Any])
        XCTAssertEqual(raw["total_questions"] as? Int, 2)
        XCTAssertEqual(raw["eligible_questions"] as? Int, 0)
        XCTAssertEqual(raw["needs_review"] as? Int, 2)
        XCTAssertNotNil(raw["question_manifest_sha256"])
    }
}
