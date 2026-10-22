import ContentModel
import Foundation

public struct JobDispatchUnit: Codable {
    public let binding: JobBinding
    public let state: JobState
    public let batch: Int
    public let inputStatus: String
    public let requiredRecordKinds: [ContractKind]
    public let dependsOn: [String]
}
public struct JobDispatchManifest: Encodable {
    public let schema = "lexvane.dispatch.v1"
    public let status: String
    public let maxParallel = 3
    public let batchCap = 25
    public let selectionHash: String
    public let recordHashBasis = "selection_candidate_not_authored_content"
    public let workerProtocol = "coordinator_only_ledger_writer; dispatch_via_existing_task; persist_raw_return_and_session_run_receipt_before_received; reconcile_unknown_running_without_redispatch; freeze_actual_model_prompt_input_and_record_revisions_before_running; reviewers_use_distinct_sessions; blind_inputs_exclude_answers_and_glosses"
    public let jobs: [JobDispatchUnit]
}
public enum JobPlanner {
    public static func plan(selection: PilotSelection, subset: String, prompts: URL) throws -> JobDispatchManifest {
        let entries: [SelectionEntry]
        switch subset {
        case "pilot-50":
            let ids = Set(selection.subsetWordIds)
            guard ids.count == selection.subsetWordIds.count, ids.isSubset(of: Set(selection.words.map(\.id))) else { throw JobFailure("invalid_subset") }
            entries = selection.words.filter { ids.contains($0.id) }
        case "pilot": entries = selection.words + selection.phrases
        default: throw JobFailure("unknown_subset")
        }
        guard Set(entries.map(\.id)).count == entries.count else { throw JobFailure("duplicate_record") }
        let selectionHash = try CKHash.sha256Hex(of: JobLedger.bytes(selection))
        let model = "configured-available"
        var units: [JobDispatchUnit] = []
        var missingPrompts = false
        for start in stride(from: 0, to: entries.count, by: 25) {
            let batch = Array(entries[start..<min(start + 25, entries.count)])
            let records = try batch.map { entry in
                JobRecord(recordId: entry.id, kind: .entry, revision: 1, contentHash: try CKHash.sha256Hex(of: JobLedger.bytes(entry)))
            }
            for role in JobRole.allCases {
                let promptRef = role.rawValue + ".md"
                let promptURL = try JobLedger.localURL(promptRef, base: prompts)
                let promptHash: String?
                if FileManager.default.fileExists(atPath: promptURL.path) { promptHash = try CKHash.sha256Hex(ofFileAt: promptURL) }
                else { promptHash = nil; missingPrompts = true }
                let id = "jobs/\(subset)/\(role.rawValue)/batch-\(start / 25 + 1)"
                let input = try CKJSONL.canonicalJSON(["selection_hash": selectionHash, "role": role.rawValue,
                    "records_hash": CKHash.sha256Hex(of: JobLedger.bytes(records)), "prompt_hash": promptHash ?? "pending"])
                let binding = JobBinding(jobId: id, role: role, inputHash: CKHash.sha256Hex(of: Data(input.utf8)),
                    model: model, modelHash: CKHash.sha256Hex(of: Data(model.utf8)), promptRef: promptRef,
                    promptHash: promptHash, records: records)
                try binding.validate()
                let kinds: [ContractKind]
                switch role {
                case .author: kinds = [.entry, .sense, .target, .teaching, .question]
                case .languageReview: kinds = [.entry, .sense, .target, .teaching]
                case .checkAuthor: kinds = [.target, .question]
                case .questionReview, .blindSolve, .familyReview: kinds = [.question]
                }
                let dependency = "jobs/\(subset)/author/batch-\(start / 25 + 1)"
                units.append(JobDispatchUnit(binding: binding, state: .pending, batch: start / 25 + 1,
                    inputStatus: role == .author ? "selection_candidate" : "awaiting_frozen_records_rebatch_questions_at_25",
                    requiredRecordKinds: kinds, dependsOn: role == .author ? [] : [dependency]))
            }
        }
        return JobDispatchManifest(status: missingPrompts ? "blocked_prompts" : "planned_not_dispatched",
            selectionHash: selectionHash, jobs: units)
    }
}
private struct JobAuditReport: Encodable {
    let valid: Bool
    let status: String
    let jobCount: Int
    let acceptedCount: Int
    let generationComplete = false
    let tokens = "unknown"
    let cost = "unknown"
}
public enum JobCommands {
    public static func validateDataset(_ arguments: [String]) -> Int32 {
        do {
            let required = ["--dataset", "--stage", "--sources", "--reviews", "--ledger", "--profile", "--evidence"]
            guard arguments.count == required.count * 2 else { throw JobFailure("required_graph_flags") }
            var flags: [String: String] = [:]
            for index in stride(from: 0, to: arguments.count, by: 2) {
                let flag = arguments[index], value = arguments[index + 1]
                guard required.contains(flag), flags[flag] == nil, ContractRules.present(value), !value.hasPrefix("--") else {
                    throw JobFailure("invalid_or_duplicate_flag")
                }
                flags[flag] = value
            }
            guard flags["--stage"] == "private-pack", let dataset = flags["--dataset"], let sources = flags["--sources"],
                  let reviews = flags["--reviews"], let ledger = flags["--ledger"], let profile = flags["--profile"],
                  let evidence = flags["--evidence"] else { throw JobFailure("required_graph_flags") }
            let contentRoot = URL(fileURLWithPath: ledger).deletingLastPathComponent().deletingLastPathComponent()
            let output = try safeOutput(evidence, inputs: [sources, ledger, profile],
                protectedDirectories: [dataset, reviews, contentRoot.path])
            var report = DatasetValidator.validate(at: URL(fileURLWithPath: dataset), sources: URL(fileURLWithPath: sources),
                reviews: URL(fileURLWithPath: reviews), ledger: URL(fileURLWithPath: ledger), profile: URL(fileURLWithPath: profile))
            do {
                let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
                let quality = try decoder.decode(QualityProfile.self, from: Data(contentsOf: URL(fileURLWithPath: profile)))
                _ = try FamiliesAudit.audit(dataset: URL(fileURLWithPath: dataset), reviews: URL(fileURLWithPath: reviews), profile: quality)
            } catch {
                let detail = String(describing: error)
                let id = detail.range(of: #"lx:(?:target|question|usage|sense|word|phrase):[0-9a-fA-F-]{36}"#, options: .regularExpression)
                    .map { String(detail[$0]) } ?? dataset
                report.defects.append(.init(code: .familyMismatch, recordId: id, field: "payload.family_id", detail: detail))
            }
            try CKPaths.ensureDirectory(at: output.deletingLastPathComponent())
            try JobLedger.write(report, to: output)
            print("valid=\(report.valid) stage=private-pack records=\(report.recordCount) defects=\(report.defects.count) human_review_pending=\(report.humanReviewPending) release_eligible=false")
            return report.valid ? 0 : 65
        } catch {
            fputs("\(error)\n", stderr)
            return 65
        }
    }

    public static func run(_ arguments: [String]) -> Int32 {
        do {
            guard let command = arguments.first, ["plan", "audit"].contains(command) else { throw JobFailure("unknown_jobs_command") }
            let required = command == "plan" ? ["--selection", "--subset", "--prompts", "--out"] : ["--jobs", "--evidence"]
            guard arguments.count == 1 + 2 * required.count else { throw JobFailure("missing_explicit_flags") }
            var flags: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) {
                let flag = arguments[index], value = arguments[index + 1]
                guard required.contains(flag), flags[flag] == nil, ContractRules.present(value), !value.hasPrefix("--") else { throw JobFailure("invalid_or_duplicate_flag") }
                flags[flag] = value
            }
            guard Set(flags.keys) == Set(required) else { throw JobFailure("missing_explicit_flags") }
            if command == "plan" {
                guard let input = flags["--selection"], let subset = flags["--subset"], let prompts = flags["--prompts"], let output = flags["--out"] else { throw JobFailure("missing_explicit_flags") }
                let destination = try safeOutput(output, inputs: [input], protectedDirectories: [prompts])
                let plan = try JobPlanner.plan(selection: SelectionValidator.read(at: URL(fileURLWithPath: input)),
                    subset: subset, prompts: URL(fileURLWithPath: prompts))
                try JobLedger.write(plan, to: destination)
                print("valid=true status=\(plan.status) jobs=\(plan.jobs.count) dispatched=0")
            } else {
                guard let input = flags["--jobs"], let output = flags["--evidence"] else { throw JobFailure("missing_explicit_flags") }
                let jobsURL = URL(fileURLWithPath: input)
                let destination = try safeOutput(output, inputs: [input], protectedDirectories: [])
                let snapshot = try JobLedger.audit(at: jobsURL)
                for event in snapshot.events.values {
                    if let ref = event.receiptRef {
                        let receiptURL = try JobLedger.localURL(ref, base: jobsURL.deletingLastPathComponent())
                        _ = try safeOutput(output, inputs: [receiptURL.path], protectedDirectories: [])
                        if let receipt = snapshot.receipts[event.binding.jobId] {
                            let evidenceURL = try JobLedger.localURL(receipt.evidenceRef, base: jobsURL.deletingLastPathComponent())
                            _ = try safeOutput(output, inputs: [evidenceURL.path], protectedDirectories: [])
                        }
                    }
                }
                try JobLedger.write(JobAuditReport(valid: true, status: snapshot.status, jobCount: snapshot.events.count,
                    acceptedCount: snapshot.acceptedCount), to: destination)
                print("valid=true status=\(snapshot.status) accepted=\(snapshot.acceptedCount) generation_complete=false")
            }
            return 0
        } catch {
            fputs("\((error as? JobFailure)?.description ?? "JobFailure(reason=io_or_decode:\(error))")\n", stderr)
            return 65
        }
    }
    private static func safeOutput(_ path: String, inputs: [String], protectedDirectories: [String]) throws -> URL {
        let output = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        for directory in protectedDirectories {
            let root = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath()
            guard output != root, !output.path.hasPrefix(root.path + "/") else { throw JobFailure("output_overlaps_input") }
        }
        for path in inputs {
            let input = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            guard output != input else { throw JobFailure("output_overlaps_input") }
            if FileManager.default.fileExists(atPath: output.path), FileManager.default.fileExists(atPath: input.path) {
                let a = try FileManager.default.attributesOfItem(atPath: input.path)
                let b = try FileManager.default.attributesOfItem(atPath: output.path)
                guard a[.systemFileNumber] as? NSNumber != b[.systemFileNumber] as? NSNumber ||
                    a[.systemNumber] as? NSNumber != b[.systemNumber] as? NSNumber else { throw JobFailure("output_overlaps_input") }
            }
        }
        return output
    }
}
