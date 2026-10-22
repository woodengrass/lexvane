import ContentModel
import Foundation

struct FamiliesFailure: Error, Equatable, CustomStringConvertible {
    let reason: String
    var description: String { "FamiliesFailure(reason=\(reason))" }
}

private struct FamilyBinding: Decodable, Equatable {
    let recordId: String
    let revision: Int
    let contentSha256: String

    func matches(_ document: any ContractDocumentInfo) -> Bool {
        recordId == document.recordId && revision == document.revision && contentSha256 == document.contentSha256
    }
}

private struct FamilyVerdict: Decodable {
    let targetId: String
    let trainFamily: String
    let checkFamily: String
    let verdict: String
    let evidence: String
    let evaluatorSession: String
    let findingIds: [String]?
    let currentMemberBindings: [String: FamilyBinding]
    let currentTeachingBindings: [FamilyBinding]

    func bindingsMatch(check: Question, train: Question, teaching: [Teaching]) -> Bool {
        let members = currentMemberBindings, teachings = currentTeachingBindings
        return members["check"]?.matches(check) == true
            && members["train"]?.matches(train) == true
            && teachings.count == teaching.count
            && Set(teachings.map(\.recordId)).count == teaching.count
            && teachings.allSatisfy { binding in teaching.contains { binding.matches($0) } }
    }
}

struct FamiliesAuditReport: Codable {
    let valid: Bool
    let denominatorSource: String
    let checkCount: Int
    let independentCheckFamiliesByTarget: [String: Int]
    let excludedTargetIds: [String]
    let acceptanceEvaluated: Bool
    let releaseEligible: Bool
}

enum FamiliesAudit {
    static func audit(dataset: URL, reviews: URL, profile: QualityProfile) throws -> FamiliesAuditReport {
        let records = try overlaidRecords(at: dataset)
        _ = try ContractDataset.validateEntries(records)
        let targets = records.compactMap { record -> Target? in
            if case .target(let target) = record { return target }; return nil
        }
        let questions = records.compactMap { record -> Question? in
            if case .question(let question) = record { return question }; return nil
        }
        let teachings = records.compactMap { record -> Teaching? in
            if case .teaching(let teaching) = record { return teaching }; return nil
        }
        guard !targets.isEmpty, !profile.activeAbilities.isEmpty,
              Set(profile.activeAbilities.map(\.rawValue)) == Set(profile.perAbilityMinimums.keys),
              profile.perAbilityMinimums.values.allSatisfy({ $0.independentCheckFamilies > 0 }),
              Set(profile.excludedTargetIds).count == profile.excludedTargetIds.count else {
            throw FamiliesFailure(reason: "invalid_profile_minimums_or_inventory")
        }
        for id in profile.excludedTargetIds {
            guard targets.contains(where: { $0.recordId == id && $0.payload.testedAbility == .writing }) else {
                throw FamiliesFailure(reason: "only_writing_target_may_be_excluded:\(id)")
            }
        }
        let targetIds = Set(targets.map(\.recordId))
        for question in questions {
            guard targetIds.contains(question.payload.primaryTargetId),
                  targets.contains(where: { $0.recordId == question.payload.primaryTargetId && $0.payload.testedAbility == question.payload.testedAbility }) else {
                throw FamiliesFailure(reason: "unknown_or_mismatched_target:\(question.recordId)")
            }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let verdicts = try files(at: reviews).filter { $0.lastPathComponent.hasPrefix("family-verdicts") }.flatMap { file in
            try CKJSONL.readLines(at: file).map { line in
                do { return try decoder.decode(FamilyVerdict.self, from: Data(line.utf8)) }
                catch DecodingError.keyNotFound(let key, _) where
                    ["currentMemberBindings", "currentTeachingBindings"].contains(key.stringValue) {
                    throw FamiliesFailure(reason: "missing_family_bindings:\(file.lastPathComponent):\(key.stringValue)")
                }
                catch { throw FamiliesFailure(reason: "invalid_family_verdict:\(file.lastPathComponent):\(error)") }
            }
        }
        let checks = questions.filter { $0.payload.split == .check }
        for check in checks.sorted(by: { $0.recordId < $1.recordId }) {
            let targetId = check.payload.primaryTargetId
            let trains = questions.filter { $0.payload.primaryTargetId == targetId && $0.payload.split == .train }
            let teaching = teachings.filter { $0.payload.primaryTargetId == targetId }
            guard !trains.isEmpty else { throw FamiliesFailure(reason: "missing_train_comparison:\(targetId):\(check.recordId)") }
            for train in trains {
                let matching = verdicts.filter {
                    $0.targetId == targetId && $0.trainFamily == train.payload.familyId
                        && $0.checkFamily == check.payload.familyId
                        && $0.bindingsMatch(check: check, train: train, teaching: teaching)
                }
                guard !matching.isEmpty else {
                    throw FamiliesFailure(reason: "missing_current_family_verdict:\(targetId):\(check.recordId):\(train.recordId)")
                }
                for row in matching {
                    guard ContractRules.present(row.evidence), ContractRules.present(row.evaluatorSession),
                          ["independent", "contaminated"].contains(row.verdict) else {
                        throw FamiliesFailure(reason: "invalid_family_verdict:\(targetId):\(check.recordId)")
                    }
                    if row.verdict == "contaminated" {
                        throw contaminated(targetId, check.recordId, row.findingIds ?? [])
                    }
                }
                // A different UUID or a favourable reviewer label cannot make a
                // copied/renamed sentence unseen. Semantic scenario comparisons
                // beyond this conservative mechanical check remain reviewer work.
                if train.payload.familyId == check.payload.familyId || copied(train.payload.stem, check.payload.stem) {
                    throw contaminated(targetId, check.recordId, ["train-template:\(train.recordId)"])
                }
            }
            let answers = check.payload.options.filter { check.payload.acceptedAnswers.contains($0.optionId) }.map(\.english)
            let completed = answers.map { check.payload.stem.replacingOccurrences(of: "___", with: $0) } + [check.payload.stem]
            for usage in teaching {
                if usage.payload.examples.contains(where: { example in completed.contains { copied(example.english, $0) } }) {
                    throw contaminated(targetId, check.recordId, ["teaching-example:\(usage.recordId)"])
                }
            }
        }
        var supply: [String: Int] = [:]
        for target in targets.sorted(by: { $0.recordId < $1.recordId }) where target.payload.activation == .active {
            if profile.excludedTargetIds.contains(target.recordId) { continue }
            guard profile.activeAbilities.contains(target.payload.testedAbility),
                  let minimum = profile.perAbilityMinimums[target.payload.testedAbility.rawValue] else {
                throw FamiliesFailure(reason: "active_target_missing_minimum:\(target.recordId)")
            }
            let count = Set(checks.filter { $0.payload.primaryTargetId == target.recordId }.map { $0.payload.familyId }).count
            supply[target.recordId] = count
            guard count >= minimum.independentCheckFamilies else {
                throw FamiliesFailure(reason: "check_supply_short:\(target.recordId):actual=\(count):minimum=\(minimum.independentCheckFamilies)")
            }
        }
        return FamiliesAuditReport(valid: true, denominatorSource: "dataset-current-revisions", checkCount: checks.count,
            independentCheckFamiliesByTarget: supply, excludedTargetIds: profile.excludedTargetIds.sorted(),
            acceptanceEvaluated: false, releaseEligible: false)
    }

    private static func contaminated(_ target: String, _ check: String, _ findings: [String]) -> FamiliesFailure {
        FamiliesFailure(reason: "family_contamination:target=\(target):check=\(check):findings=\((findings.isEmpty ? ["family:\(check)"] : findings).joined(separator: ","))")
    }

    private static func copied(_ first: String, _ second: String) -> Bool {
        func tokens(_ text: String) -> [String] {
            text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        let a = tokens(first), b = tokens(second)
        guard !a.isEmpty, a.count == b.count else { return false }
        return zip(a, b).allSatisfy { left, right in
            left.lowercased() == right.lowercased()
                || (left.first?.isUppercase == true && right.first?.isUppercase == true)
                || (Double(left) != nil && Double(right) != nil)
        }
    }

    private static func files(at directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func overlaidRecords(at directory: URL) throws -> [ContractRecord] {
        var overlay: [String: ContractRecord] = [:]
        for file in try files(at: directory) {
            let bytes = try Data(contentsOf: file)
            guard let text = String(data: bytes, encoding: .utf8),
                  !text.isEmpty, text.hasSuffix("\n"), !bytes.contains(13) else {
                throw FamiliesFailure(reason: "invalid_jsonl:\(file.lastPathComponent)")
            }
            for line in text.dropLast().split(separator: "\n", omittingEmptySubsequences: false) {
                let record: ContractRecord
                do { record = try ContractJSON.decode(Data(line.utf8)) } catch {
                    throw FamiliesFailure(reason: "invalid_record:\(file.lastPathComponent):\(error)")
                }
                let key = "\(record.document.kind.rawValue)|\(record.recordId)"
                if let prior = overlay[key] {
                    guard record.document.revision != prior.document.revision else {
                        throw FamiliesFailure(reason: "duplicate_record:\(record.recordId)")
                    }
                    if record.document.revision > prior.document.revision { overlay[key] = record }
                } else {
                    overlay[key] = record
                }
            }
        }
        guard !overlay.isEmpty else { throw FamiliesFailure(reason: "empty_dataset") }
        return Array(overlay.values)
    }
}

public enum FamiliesCommands {
    public static func run(_ arguments: [String]) -> Int32 {
        do {
            let required = ["--dataset", "--reviews", "--profile", "--evidence"]
            guard arguments.first == "audit", arguments.count == 9 else {
                throw FamiliesFailure(reason: "required_flags:dataset,reviews,profile,evidence")
            }
            var flags: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) {
                let key = arguments[index], value = arguments[index + 1]
                guard required.contains(key), flags[key] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                    throw FamiliesFailure(reason: "invalid_or_duplicate_flag")
                }
                flags[key] = value
            }
            guard let datasetPath = flags["--dataset"], let reviewsPath = flags["--reviews"],
                  let profilePath = flags["--profile"], let evidencePath = flags["--evidence"] else {
                throw FamiliesFailure(reason: "missing_explicit_flags")
            }
            let output = URL(fileURLWithPath: evidencePath).standardizedFileURL.resolvingSymlinksInPath()
            for path in [datasetPath, reviewsPath, profilePath] {
                let input = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                guard output != input, !output.path.hasPrefix(input.path + "/") else {
                    throw FamiliesFailure(reason: "output_overlaps_input")
                }
                if FileManager.default.fileExists(atPath: output.path) {
                    let source = try FileManager.default.attributesOfItem(atPath: input.path)
                    let destination = try FileManager.default.attributesOfItem(atPath: output.path)
                    guard source[.systemFileNumber] as? NSNumber != destination[.systemFileNumber] as? NSNumber else {
                        throw FamiliesFailure(reason: "output_overlaps_input")
                    }
                }
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let profile = try decoder.decode(QualityProfile.self, from: Data(contentsOf: URL(fileURLWithPath: profilePath)))
            let report = try FamiliesAudit.audit(dataset: URL(fileURLWithPath: datasetPath), reviews: URL(fileURLWithPath: reviewsPath), profile: profile)
            try JobLedger.write(report, to: output)
            print("valid=true checks=\(report.checkCount) active_targets=\(report.independentCheckFamiliesByTarget.count) acceptance_evaluated=false")
            return 0
        } catch {
            fputs("\(error)\n", stderr)
            return 65
        }
    }
}
