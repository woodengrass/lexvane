import Foundation

public struct ReviewCoverageFailure: Error, CustomStringConvertible, Equatable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var description: String { "ReviewCoverageFailure(reason=\(reason))" }
}

public struct ReviewCoverageReport: Codable {
    public let valid: Bool
    public let denominatorSource: String
    public let reviewsSelfReportedDenominatorIgnored: Bool
    public let totalUnits: Int
    public let coveredUnits: Int
    public let coverage: Double
    public let subjectsByKind: [String: Int]
    public let coveredByKind: [String: Int]
    public let questionCount: Int
    public let blindSolveCount: Int
    public let blindAmbiguityCount: Int
    public let unresolvedCriticalFindings: Int
}

private struct CoverageSubject {
    let kind: ContractKind
    let id: String
    let revision: Int
    let hash: String
}

private struct BatchRow: Decodable {
    let batchId: String
    let generatorSession: String
    let subjectIds: [String]
}

private struct BlindSolveRow: Decodable {
    let questionId: String
    let questionRevision: Int
    let blindSession: String
    let chosenOptionId: String?
    let responseText: String?
    let reasoning: String
    let answerable: Bool
    let ambiguityNotes: String
}

private struct HumanRow {
    let recordId: String
    let status: String
    let reply: String?
    let signedBy: String?
}

public enum ReviewCoverage {
    /// Audits review coverage. The denominator is ALWAYS derived from the
    /// dataset's current revisions; any reviews-side self-reported totals
    /// (claimed-coverage.json / summary.json / coverage.json) are ignored.
    public static func audit(dataset: URL, reviews: URL, profile: URL?) throws -> ReviewCoverageReport {
        let datasetRecords = try loadRecords(at: dataset)
        var subjects: [String: CoverageSubject] = [:]
        var questions: [String: Question] = [:]
        var senses: [String: Sense] = [:]
        var targets: [String: Target] = [:]
        var provenances: Set<String> = []
        for record in datasetRecords {
            let doc = record.document
            let key = "\(doc.kind.rawValue)|\(doc.recordId)"
            guard subjects[key] == nil else { throw ReviewCoverageFailure("duplicate_record:\(key)") }
            switch record {
            case .entry, .sense, .target, .teaching, .question:
                subjects[key] = CoverageSubject(kind: doc.kind, id: doc.recordId, revision: doc.revision, hash: doc.contentSha256)
            case .provenance(let provenance):
                provenances.insert("\(provenance.payload.subjectId)|\(provenance.payload.subjectRevision)")
            case .review, .manifest:
                throw ReviewCoverageFailure("unexpected_kind_in_dataset:\(doc.kind.rawValue)")
            }
            if case .question(let question) = record { questions[question.recordId] = question }
            if case .sense(let sense) = record { senses[sense.recordId] = sense }
            if case .target(let target) = record { targets[target.recordId] = target }
        }
        guard !subjects.isEmpty else { throw ReviewCoverageFailure("empty_dataset") }

        let reviewDocs = try loadReviewDocs(at: reviews)
        let batches = try loadBatches(at: reviews)
        var generatorBySubject: [String: String] = [:]
        var batchBySubject: [String: String] = [:]
        for batch in batches {
            for id in batch.subjectIds {
                if let prior = batchBySubject[id] {
                    throw ReviewCoverageFailure("duplicate_record:batch_subject:\(id):batches=\(prior),\(batch.batchId)")
                }
                batchBySubject[id] = batch.batchId
                generatorBySubject[id] = batch.generatorSession
            }
        }
        let allGeneratorSessions = Set(batches.map(\.generatorSession))

        var coveredByKind: [String: Int] = [:]
        var subjectsByKind: [String: Int] = [:]
        var unresolvedCritical = 0
        var reviewerSessions: Set<String> = []
        for subject in subjects.values {
            subjectsByKind[subject.kind.rawValue, default: 0] += 1
            let candidates = reviewDocs.filter { $0.payload.subjectId == subject.id }
            guard !candidates.isEmpty else {
                throw ReviewCoverageFailure("missing_review:\(subject.id)@\(subject.revision)")
            }
            guard let match = candidates.first(where: {
                $0.payload.subjectRevision == subject.revision
                    && $0.payload.subjectContentSha256 == subject.hash
                    && $0.payload.subjectKind == subject.kind
            }) else {
                throw ReviewCoverageFailure("stale_revision:\(subject.id)")
            }
            guard match.payload.verdict == .passed else {
                throw ReviewCoverageFailure("review_not_passed:\(subject.id)")
            }
            try requireChecklist(match, subject: subject, questions: questions)
            if let generator = generatorBySubject[subject.id],
               match.payload.reviewerSession == generator {
                throw ReviewCoverageFailure("self_review:\(subject.id)")
            }
            reviewerSessions.insert(match.payload.reviewerSession)
            unresolvedCritical += match.payload.findings.filter {
                $0.severity == .critical && $0.state == .unresolved
            }.count
            coveredByKind[subject.kind.rawValue, default: 0] += 1
        }
        for review in reviewDocs {
            // Provenance is checked separately by complete_provenance; question
            // checklists carry lineage. Extras never widen Task8's denominator.
            if review.payload.subjectKind == .provenance { continue }
            let key = "\(review.payload.subjectKind.rawValue)|\(review.payload.subjectId)"
            guard subjects[key] != nil else {
                throw ReviewCoverageFailure("unknown_subject:\(review.payload.subjectId)")
            }
        }

        // Blind integrity: every current question needs a leak-free input and a solve.
        let blindSolves = try loadBlindSolves(at: reviews)
        var blindCount = 0
        var ambiguityCount = 0
        for question in questions.values {
            try requireBlindInput(for: question, senses: senses, reviewsDir: reviews)
            let solves = blindSolves.filter {
                $0.questionId == question.recordId && $0.questionRevision == question.revision
            }
            guard !solves.isEmpty else {
                throw ReviewCoverageFailure("missing_blind:\(question.recordId)")
            }
            for solve in solves {
                guard solve.answerable else {
                    throw ReviewCoverageFailure("blind_unanswerable:\(question.recordId)")
                }
                guard !reviewerSessions.contains(solve.blindSession),
                      !allGeneratorSessions.contains(solve.blindSession) else {
                    throw ReviewCoverageFailure("blind_session_not_independent:\(question.recordId)")
                }
                if question.payload.testedAbility != .writing {
                    let optionIds = Set(question.payload.options.map(\.optionId))
                    guard let chosen = solve.chosenOptionId, optionIds.contains(chosen) else {
                        throw ReviewCoverageFailure("blind_answer_not_an_option:\(question.recordId)")
                    }
                    guard question.payload.acceptedAnswers.contains(chosen) else {
                        throw ReviewCoverageFailure("blind_key_mismatch:\(question.recordId)")
                    }
                } else {
                    // Writing is free text: require a response, not an option-key
                    // match. Lexical ambiguity disposition belongs to reviewers.
                    guard let response = solve.responseText, ContractRules.present(response) else {
                        throw ReviewCoverageFailure("blind_writing_response_required:\(question.recordId)")
                    }
                }
                guard ContractRules.present(solve.reasoning) else {
                    throw ReviewCoverageFailure("blind_reasoning_required:\(question.recordId)")
                }
                // Count current solve rows with notes; notes alone do not fail.
                if ContractRules.present(solve.ambiguityNotes) { ambiguityCount += 1 }
            }
            blindCount += solves.count
        }

        try requireHumanRecheck(at: reviews,
                                forbiddenSigners: reviewerSessions.union(allGeneratorSessions))

        if let profile {
            let expectedProvenance = Set(subjects.values.map { "\($0.id)|\($0.revision)" })
            try requireTrialProfile(at: profile, questions: questions, targets: targets,
                                    provenances: provenances, expectedProvenance: expectedProvenance,
                                    unresolvedCritical: unresolvedCritical)
        }

        // Denominator units: one per current subject revision, plus one
        // feedback unit and one distractor-rationale unit per question. Both
        // question extras are covered only by the matching required checklist
        // items in the question's passed current-revision review.
        let questionCount = questions.count
        let total = subjects.count + questionCount * 2
        let covered = subjects.count + questionCount * 2
        return ReviewCoverageReport(
            valid: true,
            denominatorSource: "dataset-current-revisions",
            reviewsSelfReportedDenominatorIgnored: true,
            totalUnits: total,
            coveredUnits: covered,
            coverage: total == 0 ? 0 : Double(covered) / Double(total),
            subjectsByKind: subjectsByKind,
            coveredByKind: coveredByKind,
            questionCount: questionCount,
            blindSolveCount: blindCount,
            blindAmbiguityCount: ambiguityCount,
            unresolvedCriticalFindings: unresolvedCritical
        )
    }

    // MARK: - Loading

    private static func loadRecords(at directory: URL) throws -> [ContractRecord] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw ReviewCoverageFailure("empty_dataset") }
        var records: [ContractRecord] = []
        for file in files {
            let bytes = try Data(contentsOf: file)
            guard let text = String(data: bytes, encoding: .utf8),
                  !text.isEmpty, text.hasSuffix("\n"), !bytes.contains(13) else {
                throw ReviewCoverageFailure("invalid_jsonl:\(file.lastPathComponent)")
            }
            for (offset, line) in text.dropLast().split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                do { records.append(try ContractJSON.decode(Data(line.utf8))) }
                catch { throw ReviewCoverageFailure("\(file.lastPathComponent):\(offset + 1):\(error)") }
            }
        }
        return records
    }

    private static func loadReviewDocs(at reviews: URL) throws -> [Review] {
        let files = try FileManager.default.contentsOfDirectory(at: reviews, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var docs: [Review] = []
        for file in files {
            for line in try ReviewInputReader.lines(at: file) {
                switch try ReviewInputReader.decode(line, file: file.lastPathComponent) {
                case .sealed(let review): docs.append(review)
                case .artifact: break
                }
            }
        }
        return docs
    }

    private static func jsonLines(of file: URL) throws -> [Data] {
        let bytes = try Data(contentsOf: file)
        guard let text = String(data: bytes, encoding: .utf8),
              !text.isEmpty, text.hasSuffix("\n"), !bytes.contains(13) else {
            throw ReviewCoverageFailure("invalid_jsonl:\(file.lastPathComponent)")
        }
        return text.dropLast().split(separator: "\n", omittingEmptySubsequences: false).map { Data($0.utf8) }
    }

    private static func loadBatches(at reviews: URL) throws -> [BatchRow] {
        let file = reviews.appendingPathComponent("batches.jsonl")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try jsonLines(of: file).map { line in
            do { return try decoder.decode(BatchRow.self, from: line) }
            catch { throw ReviewCoverageFailure("batches.jsonl:\(error)") }
        }
    }

    private static func loadBlindSolves(at reviews: URL) throws -> [BlindSolveRow] {
        let files = try FileManager.default.contentsOfDirectory(at: reviews, includingPropertiesForKeys: nil)
            .filter { isBlindSolveFile($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try files.flatMap { file in try jsonLines(of: file).map { line in
            do { return try decoder.decode(BlindSolveRow.self, from: line) }
            catch { throw ReviewCoverageFailure("\(file.lastPathComponent):\(error)") }
        } }
    }

    private static func isBlindSolveFile(_ name: String) -> Bool {
        name == "blind-solves.jsonl" || name == "blind-train-r3.jsonl"
            || (name.hasSuffix(".jsonl") && (name.hasPrefix("blind-batch-") || name.hasPrefix("blind-check-")
                || name.hasPrefix("blind-230-") || name.hasPrefix("blind-r")))
    }

    // MARK: - Checklist

    /// Machine-readable conformance aid. Exact required IDs, not replacements
    /// for extended reviewer checklists. Writing requires distractor-rationales
    /// to be not_applicable; every other required result must be passed.
    public static let checklistIDs: [String: [String]] = [
        "entry": ["lemma-pos-alias", "sense-coverage"],
        "sense": ["gloss-precision", "priority-evidence"],
        "target": ["ability-target-match", "activation-priority"],
        "teaching": ["usage-naturalness", "example-alignment"],
        "question": ["target-ability-match", "stem-tests-sense", "options-no-leak",
                     "single-answer-or-listed", "distractor-rationales", "feedback-consistency",
                     "no-pre-answer-hint", "family-independence"],
    ]

    private static func requireChecklist(_ review: Review, subject: CoverageSubject,
                                        questions: [String: Question]) throws {
        let required: [(item: String, mustPass: Bool)]
        switch subject.kind {
        case .entry:
            required = [("lemma-pos-alias", true), ("sense-coverage", true)]
        case .sense:
            required = [("gloss-precision", true), ("priority-evidence", true)]
        case .target:
            required = [("ability-target-match", true), ("activation-priority", true)]
        case .teaching:
            required = [("usage-naturalness", true), ("example-alignment", true)]
        case .question:
            let isWriting = questions[subject.id]?.payload.testedAbility == .writing
            required = [
                ("target-ability-match", true),
                ("stem-tests-sense", true),
                ("options-no-leak", true),
                ("single-answer-or-listed", true),
                ("distractor-rationales", !isWriting),
                ("feedback-consistency", true),
                ("no-pre-answer-hint", true),
                ("family-independence", true),
            ]
        default:
            return
        }
        let byItem = Dictionary(uniqueKeysWithValues: review.payload.checklist.map { ($0.item, $0.result) })
        for (item, mustPass) in required {
            guard let result = byItem[item] else {
                throw ReviewCoverageFailure("missing_checklist_item:\(subject.id):\(item)")
            }
            if mustPass, result != .passed {
                throw ReviewCoverageFailure("checklist_failed:\(subject.id):\(item)")
            }
            if !mustPass, result != .notApplicable {
                throw ReviewCoverageFailure("checklist_failed:\(subject.id):\(item)")
            }
        }
    }

    // MARK: - Blind inputs

    private static func requireBlindInput(for question: Question, senses: [String: Sense],
                                         reviewsDir: URL) throws {
        let fm = FileManager.default
        let inputDirs = ((try? fm.contentsOfDirectory(at: reviewsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("blind-inputs") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let inputsRoot = reviewsDir.appendingPathComponent("blind-inputs")
        let searchDirs = inputDirs.isEmpty
            ? (fm.fileExists(atPath: inputsRoot.path) ? [inputsRoot] : [])
            : inputDirs
        let files = searchDirs.flatMap { dir in
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }) ?? [])
        }
        let uuid = question.recordId.split(separator: ":").last.map(String.init) ?? ""
        let expectedName = "blind-\(uuid).json"
        guard let file = files.first(where: {
            (try? filenameQuestionId(of: $0)) == question.recordId
        }) else {
            throw ReviewCoverageFailure("missing_blind:\(question.recordId)")
        }
        guard file.lastPathComponent == expectedName else {
            throw ReviewCoverageFailure("blind_leak:\(question.recordId):non-opaque-filename:\(file.lastPathComponent)")
        }
        let idPattern = #"^lx:question:[0-9a-fA-F-]{36}$"#
        guard question.recordId.range(of: idPattern, options: .regularExpression) != nil else {
            throw ReviewCoverageFailure("blind_leak:\(question.recordId):non-opaque-id")
        }
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        guard let input = raw else {
            throw ReviewCoverageFailure("blind_leak:\(question.recordId):unreadable-input")
        }
        let forbiddenKeys = Set(["accepted_answers", "acceptedanswers", "key", "answer_key", "answerkey",
                                 "correct_answer", "correctanswer", "correct_option", "correctoption",
                                 "gloss", "target_gloss", "targetgloss", "core_meaning", "coremeaning",
                                 "feedback", "post_answer_feedback", "postanswerfeedback", "distractor",
                                 "rationale", "rationales", "prior_comments", "priorcomments", "analysis",
                                 "review_notes", "reviewnotes", "correct_sense", "correctsense"])
        for key in input.keys where forbiddenKeys.contains(key.lowercased()) {
            throw ReviewCoverageFailure("blind_leak:\(question.recordId):forbidden-key:\(key)")
        }
        let allowedKeys = Set(["question_id", "question_revision", "stem", "options", "rules"])
        guard Set(input.keys) == allowedKeys else {
            throw ReviewCoverageFailure("blind_leak:\(question.recordId):unexpected-keys:\(Set(input.keys).subtracting(allowedKeys).sorted().joined(separator: ","))")
        }
        guard input["question_id"] as? String == question.recordId,
              input["question_revision"] as? Int == question.revision else {
            throw ReviewCoverageFailure("blind_leak:\(question.recordId):stale-input")
        }
        guard input["stem"] as? String == question.payload.stem else {
            throw ReviewCoverageFailure("blind_leak:\(question.recordId):stem-tampered")
        }
        let expectedOptions = question.payload.options.map { ["option_id": $0.optionId, "english": $0.english] }
        let actualOptions = input["options"] as? [[String: String]]
        guard actualOptions == expectedOptions else {
            throw ReviewCoverageFailure("blind_leak:\(question.recordId):options-tampered")
        }
        // The free-text rules must not smuggle the key, the target gloss, or feedback.
        var secrets: [String] = question.payload.options.map(\.english)
            + [question.payload.postAnswerFeedback.answer, question.payload.postAnswerFeedback.explanation]
            + question.payload.acceptedAnswers
        if let sense = senses[question.payload.correctSenseId] {
            secrets.append(sense.payload.coreMeaningZhHant)
        }
        let rules = (input["rules"] as? String) ?? ""
        for secret in secrets where !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if rules.lowercased().contains(secret.lowercased()) {
                throw ReviewCoverageFailure("blind_leak:\(question.recordId):rules-contain-answer-hint")
            }
        }
        // G5: all 100 trial UUID filenames scanned clean. Retain this scan and
        // the exact opaque-name check above; no hex-name exemption is needed.
        // Filenames carry no answer-derived words either.
        let filenameTokens = file.deletingPathExtension().lastPathComponent.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var leakTokens = Set(["answer", "key", "gloss", "correct"])
        for secret in secrets {
            for token in secret.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            where token.count >= 2 { leakTokens.insert(token) }
        }
        for token in filenameTokens where leakTokens.contains(token) && token != "blind" {
            throw ReviewCoverageFailure("blind_leak:\(question.recordId):answer-derivable-filename")
        }
    }

    private static func filenameQuestionId(of file: URL) throws -> String? {
        guard let raw = try? JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else {
            return nil
        }
        return raw["question_id"] as? String
    }

    // MARK: - Human recheck

    private static func requireHumanRecheck(at reviews: URL, forbiddenSigners: Set<String>) throws {
        let file = reviews.appendingPathComponent("human-recheck.jsonl")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        for line in try jsonLines(of: file) {
            guard let raw = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let recordId = raw["record_id"] as? String,
                  let status = raw["human_status"] as? String else {
                throw ReviewCoverageFailure("human_signoff_forged:unreadable-row")
            }
            let reply = raw["human_reply_source"] as? String
            let signedBy = raw["signed_by"] as? String
            switch status {
            case "pending":
                guard reply == nil || reply!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ReviewCoverageFailure("human_reply_mismatch:\(recordId)")
                }
            case "accepted", "changes_requested":
                guard let reply, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let signedBy, !signedBy.isEmpty, !forbiddenSigners.contains(signedBy) else {
                    throw ReviewCoverageFailure("human_signoff_forged:\(recordId)")
                }
            default:
                throw ReviewCoverageFailure("human_signoff_forged:\(recordId):unknown-status")
            }
        }
    }

    // MARK: - Trial profile

    private static func requireTrialProfile(at profile: URL, questions: [String: Question],
                                           targets: [String: Target], provenances: Set<String>,
                                           expectedProvenance: Set<String>,
                                           unresolvedCritical: Int) throws {
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: profile)) as? [String: Any]
        guard let gates = (raw?["active_target_gates"] as? [String: Any]),
              raw?["profile"] as? String == "pilot-trial-v0" else {
            throw ReviewCoverageFailure("unsupported_profile")
        }
        let maxCritical = gates["unresolved_critical_maximum"] as? Int ?? 0
        guard unresolvedCritical <= maxCritical else {
            throw ReviewCoverageFailure("unresolved_critical:\(unresolvedCritical)")
        }
        let minTrain = gates["minimum_train_questions"] as? Int ?? 1
        let minCheck = gates["minimum_check_families"] as? Int ?? 1
        let independentCheck = gates["independent_check_family_required"] as? Bool ?? true
        for target in targets.values where target.payload.activation == .active {
            let owned = questions.values.filter { $0.payload.primaryTargetId == target.recordId }
            let trains = owned.filter { $0.payload.split == .train }
            let checks = owned.filter { $0.payload.split == .check }
            guard trains.count >= minTrain else {
                throw ReviewCoverageFailure("train_supply_short:\(target.recordId)")
            }
            guard Set(checks.map { $0.payload.familyId }).count >= minCheck else {
                throw ReviewCoverageFailure("check_supply_short:\(target.recordId)")
            }
            if independentCheck {
                let trainFamilies = Set(trains.map(\.payload.familyId))
                for check in checks where trainFamilies.contains(check.payload.familyId) {
                    throw ReviewCoverageFailure("check_family_not_independent:\(check.recordId)")
                }
            }
        }
        if (gates["complete_provenance"] as? Bool) == true {
            for key in expectedProvenance where !provenances.contains(key) {
                throw ReviewCoverageFailure("provenance_missing:\(key)")
            }
        }
    }
}
