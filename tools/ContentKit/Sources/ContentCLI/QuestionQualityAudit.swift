import ContentModel
import Foundation

struct QualityInputFile: Codable {
    let role: String
    let path: String
    let sha256: String
}

enum QualityInventory {
    static func files(at roots: [URL]) throws -> [URL] {
        try roots.flatMap { root in
            let merged = root.appendingPathComponent("merged")
            let directory = FileManager.default.fileExists(atPath: merged.path) ? merged : root
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    static func loadRecords(at roots: [URL]) throws -> [ContractRecord] {
        var current: [String: ContractRecord] = [:]
        for file in try files(at: roots) {
            for line in try CKJSONL.readLines(at: file) {
                let record = try ContractJSON.decode(Data(line.utf8))
                let key = "\(record.document.kind.rawValue)|\(record.recordId)"
                if let old = current[key] {
                    if old.document.revision == record.document.revision {
                        guard old.contentSha256 == record.contentSha256 else {
                            throw QualityFailure(reason: "conflicting_current_revision:\(key)")
                        }
                    } else if record.document.revision > old.document.revision { current[key] = record }
                } else { current[key] = record }
            }
        }
        guard !current.isEmpty else { throw QualityFailure(reason: "empty_dataset") }
        return current.keys.sorted().compactMap { current[$0] }
    }

    static func loadReviews(at roots: [URL]) throws -> [Review] {
        var result: [Review] = []
        for file in try files(at: roots) {
            if file.lastPathComponent == "human-decisions.jsonl" { continue }
            for line in try CKJSONL.readLines(at: file) {
                let bytes = Data(line.utf8)
                guard let raw = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                    throw QualityFailure(reason: "invalid_review_object:\(file.lastPathComponent)")
                }
                if raw["schema"] != nil || raw["payload"] != nil || raw["kind"] as? String == "review" {
                    guard case .review(let review) = try ContractJSON.decode(bytes) else {
                        throw QualityFailure(reason: "unexpected_sealed_review_kind:\(file.lastPathComponent)")
                    }
                    result.append(review)
                }
            }
        }
        return result
    }

    static func questionManifest(_ questions: [Question]) -> String {
        let rows = questions.map { "\($0.recordId)|\($0.revision)|\($0.contentSha256)\n" }.sorted().joined()
        return CKHash.sha256Hex(of: Data(rows.utf8))
    }
}

struct QuestionBankQualityReport: Codable {
    let policyVersion: String
    let inputFiles: [QualityInputFile]
    let questionManifestSha256: String
    let totalQuestions: Int
    let totalMCQs: Int
    let eligibleQuestions: Int
    let notUsableQuestions: Int
    let pendingQuestions: Int
    let rejectedQuestions: Int
    let needsAuthor: Int
    let needsReview: Int
    let candidateQuestions: Int
    let approvedEligibleQuestions: Int
    let optionCountInventory: [String: Int]
    let items: [QuestionEligibilityDecision]
    let acceptanceEvaluated: Bool
    let releaseEligible: Bool
}

public enum QuestionQualityAuditCommands {
    public static func run(_ arguments: [String]) -> Int32 {
        do {
            let required: Set<String> = ["--datasets", "--reviews", "--profile", "--out"]
            guard arguments.count == 8 else { throw QualityFailure(reason: "required_flags:datasets,reviews,profile,out") }
            var flags: [String: String] = [:]
            for index in stride(from: 0, to: arguments.count, by: 2) {
                let key = arguments[index], value = arguments[index + 1]
                guard required.contains(key), flags[key] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                    throw QualityFailure(reason: "invalid_or_duplicate_flag")
                }
                flags[key] = value
            }
            guard let datasetPaths = flags["--datasets"], let reviewPaths = flags["--reviews"],
                  let profilePath = flags["--profile"], let outputPath = flags["--out"] else {
                throw QualityFailure(reason: "missing_explicit_flags")
            }
            func roots(_ paths: String) -> [URL] {
                paths.split(separator: ",").map { URL(fileURLWithPath: String($0)).standardizedFileURL.resolvingSymlinksInPath() }
            }
            let datasets = roots(datasetPaths), reviewRoots = roots(reviewPaths)
            let profileURL = URL(fileURLWithPath: profilePath).standardizedFileURL.resolvingSymlinksInPath()
            let output = URL(fileURLWithPath: outputPath).standardizedFileURL.resolvingSymlinksInPath()
            guard !datasets.isEmpty, !reviewRoots.isEmpty else { throw QualityFailure(reason: "empty_input_roots") }
            for input in datasets + reviewRoots + [profileURL] {
                guard output != input, !output.path.hasPrefix(input.path + "/") else { throw QualityFailure(reason: "output_overlaps_input") }
            }
            let inputURLs = try QualityInventory.files(at: datasets) + QualityInventory.files(at: reviewRoots) + [profileURL]
            if FileManager.default.fileExists(atPath: output.path) {
                let dest = try FileManager.default.attributesOfItem(atPath: output.path)
                for input in inputURLs {
                    let source = try FileManager.default.attributesOfItem(atPath: input.path)
                    guard source[.systemFileNumber] as? NSNumber != dest[.systemFileNumber] as? NSNumber else {
                        throw QualityFailure(reason: "output_overlaps_input")
                    }
                }
            }
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            let profile = try decoder.decode(QualityProfile.self, from: Data(contentsOf: profileURL))
            try profile.validateEligibilityVersion()
            guard let policy = profile.questionEligibility else { throw QualityFailure(reason: "explicit_v3_policy_required") }
            let records = try QualityInventory.loadRecords(at: datasets)
            let questions = records.compactMap { record -> Question? in
                if case .question(let q) = record { return q }; return nil
            }.sorted { $0.recordId < $1.recordId }
            guard !questions.isEmpty else { throw QualityFailure(reason: "empty_question_bank") }
            let reviews = try QualityInventory.loadReviews(at: reviewRoots)
            let items = questions.map { QuestionEligibility.evaluate($0, policy: policy, reviews: reviews) }
            var manifest: [QualityInputFile] = []
            for (role, inputs) in [("dataset", datasets), ("reviews", reviewRoots)] {
                for (index, root) in inputs.enumerated() {
                    for file in try QualityInventory.files(at: [root]) {
                        manifest.append(QualityInputFile(role: role, path: "\(index)/\(root.lastPathComponent)/\(file.lastPathComponent)",
                            sha256: CKHash.sha256Hex(of: try Data(contentsOf: file))))
                    }
                }
            }
            manifest.append(QualityInputFile(role: "profile", path: profileURL.lastPathComponent,
                sha256: CKHash.sha256Hex(of: try Data(contentsOf: profileURL))))
            let usable = items.filter(\.eligible).count
            let histogram = Dictionary(grouping: items, by: { String($0.optionCount) }).mapValues(\.count)
            let report = QuestionBankQualityReport(policyVersion: policy.version, inputFiles: manifest,
                questionManifestSha256: QualityInventory.questionManifest(questions), totalQuestions: items.count,
                totalMCQs: questions.filter { $0.payload.testedAbility != .writing }.count,
                eligibleQuestions: usable, notUsableQuestions: items.count - usable,
                pendingQuestions: items.filter { $0.state == .pending }.count, rejectedQuestions: items.filter { $0.state == .rejected }.count,
                needsAuthor: items.filter(\.needsAuthor).count, needsReview: items.filter(\.needsReview).count,
                candidateQuestions: items.filter { $0.contentStatus == .candidate }.count,
                approvedEligibleQuestions: items.filter { $0.eligible && $0.contentStatus == .approved }.count,
                optionCountInventory: histogram, items: items, acceptanceEvaluated: false, releaseEligible: false)
            try JobLedger.write(report, to: output)
            print("total=\(items.count) mcqs=\(report.totalMCQs) eligible=\(usable) not_usable=\(report.notUsableQuestions) pending=\(report.pendingQuestions) needs_author=\(report.needsAuthor) needs_review=\(report.needsReview) approved_eligible=\(report.approvedEligibleQuestions) release_eligible=false")
            return 0
        } catch {
            fputs("\(error)\n", stderr)
            return 65
        }
    }
}
