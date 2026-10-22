import ContentModel
import Foundation

/// Current-tree human triage. Binds each dataset subject to its CURRENT
/// (id/revision/hash) reviews and separates three buckets: machine
/// (deterministic integrity failures and structural author work), human
/// (current unresolved judgments needing independent review), historical
/// (superseded-revision risks retained as context, never dropped).
///
/// Every dataset and review row is decoded as ContractJSON, so seals are
/// verified rather than trusted. Identical review copies dedup preserving
/// all locations; conflicting duplicate identities fail the run.
/// Optional v3 quality-audit items are emitted per missing_work entry, but
/// only when bound to the current dataset revision and hash.
/// Generating this packet never grants approval and never touches
/// `human-decisions.jsonl`.
public enum CurrentRecheckReport {
    public static let usage = """
        Usage: reports current-recheck|audit-current-recheck --dataset PATH --reviews PATH --out PATH --evidence PATH [--policy PATH [--quality-profile PATH]]
          --dataset PATH   Merged dataset directory (e.g. content/records/pilot-230/merged)
          --reviews PATH   Current review collection (e.g. content/reviews/pilot-230-current)
          --out PATH       Output current-triage.json path; siblings current-human-recheck.jsonl and OWNER-RECHECK-CURRENT.md are derived in the same directory
          --evidence PATH  Evidence report JSON path
          --policy PATH    Optional question-quality audit JSON; items bind to current revisions only
          --quality-profile PATH  Profile JSON the audit was generated with; required to verify the audit manifest profile role
        """

    private typealias Row = [String: Any]
    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ reason: String) { description = "CurrentRecheckFailure(\(reason))" }
    }
    private struct FileLine {
        let file: URL
        let line: Int
    }
    /// One distinct sealed review; identical copies share the entry and keep
    /// every location they were read from.
    private struct ReviewHit {
        let record: Review
        var locations: [FileLine]
    }
    private struct PolicyManifestEntry: Codable {
        var role: String
        var path: String
        var sha256: String
    }
    private struct PolicyQualityItem: Codable {
        var questionId: String
        var revision: Int
        var contentSha256: String
        var state: String
        var missingWork: [String]
        var needsAuthor: Bool
        var needsReview: Bool
    }
    private struct PolicyAudit: Codable {
        var inputFiles: [PolicyManifestEntry]
        var items: [PolicyQualityItem]
        var candidateQuestions: Int?
        var pendingQuestions: Int?
        var needsAuthor: Int?
        var needsReview: Int?
        var totalQuestions: Int?
    }

    /// Structural content defects owned by the author pipeline.
    private static let authorWorkReasons: Set<String> = [
        "writing_not_supported", "requires_four_options", "requires_one_correct_option",
        "duplicate_or_empty_options", "author_distractor_rationales_required",
        "answer_feedback_required", "semantic_assessment_failed",
    ]
    /// Review-evidence reasons already owned by the binding classifier, so
    /// quality items must not re-emit them.
    private static let bindingOwnedReasons: Set<String> = [
        "current_review_missing", "current_review_stale", "current_quality_findings_unresolved",
    ]

    private static func bytes(_ value: Any, pretty: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes])
    }
    private static func text(_ value: Any, pretty: Bool = false) throws -> String {
        String(decoding: try bytes(value, pretty: pretty), as: UTF8.self)
    }
    private static func jsonFiles(_ directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private static func relative(_ file: URL, from directory: URL) -> String {
        let a = directory.standardizedFileURL.pathComponents, b = file.standardizedFileURL.pathComponents
        var common = 0
        while common < min(a.count, b.count), a[common] == b[common] { common += 1 }
        return (Array(repeating: "..", count: a.count - common) + b.dropFirst(common)).joined(separator: "/")
    }
    private static func check(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw Failure(reason) }
    }
    private static func canonical(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    }
    private static func reasonSnippet(_ reason: String, limit: Int = 500) -> String {
        let flat = reason.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)) + "…"
    }
    private static func datasetKey(_ record: ContractRecord) -> String {
        "\(record.document.kind.rawValue)|\(record.recordId)"
    }

    public static func run(_ arguments: [String]) -> Int32 {
        do {
            let required = ["--dataset", "--reviews", "--out", "--evidence"]
            guard let mode = arguments.first, ["current-recheck", "audit-current-recheck"].contains(mode) else {
                throw Failure("required_flags:dataset,reviews,out,evidence")
            }
            var flags: [String: String] = [:]
            var index = 1
            while index < arguments.count {
                let key = arguments[index]
                guard ["--dataset", "--reviews", "--out", "--evidence", "--policy", "--quality-profile"].contains(key), index + 1 < arguments.count else {
                    throw Failure("invalid_or_duplicate_flag")
                }
                let value = arguments[index + 1]
                try check(flags[key] == nil && !value.isEmpty && !value.hasPrefix("--"), "invalid_or_duplicate_flag")
                flags[key] = value
                index += 2
            }
            for key in required { try check(flags[key] != nil, "missing_flags") }
            if flags["--quality-profile"] != nil { try check(flags["--policy"] != nil, "quality_profile_requires_policy") }
            let dataset = canonical(flags["--dataset"]!), reviews = canonical(flags["--reviews"]!)
            let out = canonical(flags["--out"]!), evidence = canonical(flags["--evidence"]!)
            let base = out.deletingLastPathComponent()
            let policyURL = flags["--policy"].map { canonical($0) }
            let qualityProfileURL = flags["--quality-profile"].map { canonical($0) }
            let decisions = reviews.appendingPathComponent("human-decisions.jsonl")
            if FileManager.default.fileExists(atPath: decisions.path) {
                try check(Data(contentsOf: decisions).isEmpty, "pending_packet_has_existing_human_decisions")
            }
            let jsonlOut = base.appendingPathComponent("current-human-recheck.jsonl")
            let mdOut = base.appendingPathComponent("OWNER-RECHECK-CURRENT.md")
            try check(out.lastPathComponent == "current-triage.json", "out_must_be_current-triage.json")
            try check(base.standardizedFileURL.path.hasPrefix(reviews.standardizedFileURL.path + "/"), "triage_must_live_under_reviews_collection")
            let datasetFiles = try jsonFiles(dataset)
            try check(!datasetFiles.isEmpty, "empty_dataset")
            let disambiguated = reviews.appendingPathComponent("reviews-disambiguated.jsonl")
            try check(FileManager.default.fileExists(atPath: disambiguated.path), "missing_reviews-disambiguated.jsonl")
            let reviewFilesAll = try jsonFiles(reviews)
            var inputs: [URL] = datasetFiles + reviewFilesAll
            let mappingFile = reviews.appendingPathComponent("mapping.json")
            let ambiguousFile = reviews.appendingPathComponent("ambiguous-references.json")
            for extra in [mappingFile, ambiguousFile] where FileManager.default.fileExists(atPath: extra.path) { inputs.append(extra) }
            if let policyURL, FileManager.default.fileExists(atPath: policyURL.path) { inputs.append(policyURL) }
            if let qualityProfileURL, FileManager.default.fileExists(atPath: qualityProfileURL.path) { inputs.append(qualityProfileURL) }
            for output in [out, evidence, jsonlOut, mdOut] {
                try check(output != dataset && !output.path.hasPrefix(dataset.path + "/"), "output_overlaps_dataset")
                try check(output != reviews.appendingPathComponent("reviews-disambiguated.jsonl"), "output_overlaps_input")
                try check(output != reviews.appendingPathComponent("human-decisions.jsonl"), "output_overlaps_decisions")
                for input in inputs {
                    try check(output != input, "output_overlaps_input")
                    if FileManager.default.fileExists(atPath: output.path) {
                        let a = try FileManager.default.attributesOfItem(atPath: input.path)
                        let b = try FileManager.default.attributesOfItem(atPath: output.path)
                        try check(a[.systemFileNumber] as? NSNumber != b[.systemFileNumber] as? NSNumber, "output_aliases_input")
                    }
                }
            }
            try check(Set([out.path, evidence.path, jsonlOut.path, mdOut.path]).count == 4, "colliding_outputs")

            // Dataset rows are verified ContractJSON: seals recomputed, so no
            // hash is trusted from the bytes. Same key and revision with a
            // different seal is a conflicting duplicate identity and fails.
            var records: [String: ContractRecord] = [:]
            var locations: [String: FileLine] = [:]
            for file in datasetFiles {
                for (offset, line) in try CKJSONL.readLines(at: file).enumerated() {
                    let record = try ContractJSON.decode(Data(line.utf8))
                    let key = datasetKey(record)
                    if let old = records[key] {
                        if old.document.revision == record.document.revision {
                            try check(old.contentSha256 == record.contentSha256, "conflicting_duplicate_identity:\(key)")
                        } else if record.document.revision > old.document.revision {
                            records[key] = record
                            locations[key] = FileLine(file: file, line: offset + 1)
                        }
                    } else {
                        records[key] = record
                        locations[key] = FileLine(file: file, line: offset + 1)
                    }
                }
            }
            try check(!records.isEmpty, "empty_dataset")

            // Canonical review rows come from the disambiguated collection
            // only. Byte-identical copies dedup into one entry preserving
            // every location; same review id with different content fails.
            var reviewIndex: [String: ReviewHit] = [:]
            for (offset, line) in try CKJSONL.readLines(at: disambiguated).enumerated() {
                let decoded = try ContractJSON.decode(Data(line.utf8))
                guard case .review(let review) = decoded else {
                    throw Failure("unexpected_sealed_review_kind:\(disambiguated.lastPathComponent)")
                }
                let id = review.recordId
                if var hit = reviewIndex[id] {
                    try check(hit.record.contentSha256 == review.contentSha256
                        && hit.record.revision == review.revision, "conflicting_review_identity:\(id)")
                    hit.locations.append(FileLine(file: disambiguated, line: offset + 1))
                    reviewIndex[id] = hit
                } else {
                    reviewIndex[id] = ReviewHit(record: review, locations: [FileLine(file: disambiguated, line: offset + 1)])
                }
            }
            var bySubject: [String: [ReviewHit]] = [:]
            for hit in reviewIndex.values {
                bySubject[hit.record.payload.subjectId, default: []].append(hit)
            }
            for key in bySubject.keys {
                bySubject[key]?.sort { $0.record.recordId < $1.record.recordId }
            }
            let reviewRowsCount = reviewIndex.count
            let reviewLocationsCount = reviewIndex.values.reduce(0) { $0 + $1.locations.count }
            let ambiguousCount: Int = {
                guard FileManager.default.fileExists(atPath: ambiguousFile.path),
                      let data = try? Data(contentsOf: ambiguousFile),
                      let doc = try? JSONSerialization.jsonObject(with: data) as? Row,
                      let conflicts = doc["conflicts"] as? [Any] else { return 0 }
                return conflicts.count
            }()
            let mappingCount: Int = {
                guard FileManager.default.fileExists(atPath: mappingFile.path),
                      let data = try? Data(contentsOf: mappingFile),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return 0 }
                return arr.count
            }()

            // V3 audit freshness: each manifest role must exactly cover its
            // actual input set with matching hashes. Dataset and review roles
            // compare against the real file sets; the profile role compares
            // against the explicit --quality-profile file.
            var policySummary: Row = ["policy_checked": false]
            var qualityItems: [PolicyQualityItem] = []
            var policyRel: String = ""
            if let policyURL {
                guard FileManager.default.fileExists(atPath: policyURL.path),
                      let policyData = try? Data(contentsOf: policyURL) else {
                    throw Failure("missing_policy_file")
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let audit: PolicyAudit
                do {
                    audit = try decoder.decode(PolicyAudit.self, from: policyData)
                } catch {
                    throw Failure("invalid_policy_file")
                }
                policyRel = relative(policyURL, from: base)
                qualityItems = audit.items
                func actualSet(_ files: [URL]) throws -> [String: String] {
                    var out: [String: String] = [:]
                    for file in files { out[file.lastPathComponent] = try CKHash.sha256Hex(of: Data(contentsOf: file)) }
                    return out
                }
                func roleMatches(role: String, actual: [String: String]) -> Bool {
                    let entries = audit.inputFiles.filter { $0.role == role }
                    let names = entries.map { URL(fileURLWithPath: $0.path).lastPathComponent }
                    guard !entries.isEmpty, Set(names).count == names.count, Set(names) == Set(actual.keys) else { return false }
                    return entries.allSatisfy { actual[URL(fileURLWithPath: $0.path).lastPathComponent] == $0.sha256 }
                }
                let datasetMatch = roleMatches(role: "dataset", actual: try actualSet(datasetFiles))
                let reviewsMatch = roleMatches(role: "reviews", actual: try actualSet(reviewFilesAll))
                var profileMatch = false
                if let qualityProfileURL, FileManager.default.fileExists(atPath: qualityProfileURL.path) {
                    let profileEntries = audit.inputFiles.filter { $0.role == "profile" }
                    let profileSha = try CKHash.sha256Hex(of: Data(contentsOf: qualityProfileURL))
                    profileMatch = profileEntries.count == 1
                        && URL(fileURLWithPath: profileEntries[0].path).lastPathComponent == qualityProfileURL.lastPathComponent
                        && profileEntries[0].sha256 == profileSha
                }
                let fresh = datasetMatch && reviewsMatch && profileMatch
                policySummary = [
                    "policy_checked": true, "policy_path": policyRel,
                    "policy_fresh": fresh,
                    "dataset_match": datasetMatch, "reviews_match": reviewsMatch, "profile_match": profileMatch,
                    "quality_profile_required": qualityProfileURL == nil,
                    "candidate_questions": audit.candidateQuestions ?? NSNull(),
                    "pending_questions": audit.pendingQuestions ?? NSNull(),
                    "needs_review": audit.needsReview ?? NSNull(),
                    "release_eligible": false,
                ]
            }

            var provenanceBlocked: Set<String> = []
            for (_, record) in records where record.document.kind == .provenance {
                let current = (bySubject[record.recordId] ?? []).filter { isCurrentBinding($0.record, datasetRecord: record) }
                if current.contains(where: { hasUnresolvedFindings($0.record) }) {
                    provenanceBlocked.insert(record.recordId)
                }
            }

            var issues: [Row] = []
            var qualityBound = 0
            func emit(bucket: String, kind: String, action: String, priority: String,
                      subjectID: String, severity: String, reason: String, sources: [Row],
                      extra: Row = [:]) {
                let record = records.first { $0.value.recordId == subjectID }?.value
                var row: Row = [
                    "bucket": bucket, "issue_kind": kind, "action": action, "priority": priority,
                    "subject_id": subjectID, "subject_kind": record?.document.kind.rawValue ?? NSNull(),
                    "subject_revision": record?.document.revision ?? NSNull(),
                    "subject_sha256": record?.contentSha256 ?? NSNull(),
                    "severity": severity, "reason": reasonSnippet(reason),
                    "source_refs": sources, "source_count": sources.count,
                    "human_status": "pending", "human_decision": NSNull(),
                    "release_eligible": false,
                ]
                for (k, v) in extra { row[k] = v }
                issues.append(row)
            }
            func datasetRef(_ key: String) -> Row {
                guard let loc = locations[key] else { return ["source": "dataset:unknown", "line": NSNull()] }
                return ["source": relative(loc.file, from: base), "line": loc.line]
            }
            func reviewRefs(_ hits: [ReviewHit]) -> [Row] {
                var out: [Row] = []
                for hit in hits.sorted(by: { $0.record.recordId < $1.record.recordId }) {
                    for loc in hit.locations.sorted(by: { $0.line < $1.line }) {
                        out.append(["review_record_id": hit.record.recordId,
                                    "verdict": hit.record.payload.verdict.rawValue,
                                    "source": relative(loc.file, from: base), "line": loc.line])
                    }
                }
                return out
            }

            let subjectIDs = Set(records.values.map(\.recordId)).sorted()
            for id in subjectIDs {
                guard let record = records.first(where: { $0.value.recordId == id })?.value else { continue }
                let key = datasetKey(record)
                let kind = record.document.kind
                let all = bySubject[id] ?? []
                let current = all.filter { isCurrentBinding($0.record, datasetRecord: record) }
                let stale = all.filter { !isCurrentBinding($0.record, datasetRecord: record) }

                if current.isEmpty {
                    // Deterministic integrity failure: nothing current-bound to judge.
                    // Uncovered non-provenance content stays pending for
                    // independent review at medium priority, never an automatic
                    // high-risk rejection. Only a provenance gap is high.
                    let high = kind == .provenance
                    emit(bucket: "machine", kind: "missing-current-review",
                         action: "independent-review-needed",
                         priority: high ? "high" : "medium",
                         subjectID: id, severity: "major",
                         reason: kind == .question && questionStatus(record) == "candidate"
                            ? "Candidate has no current-binding review; pending independent review, not an automatic high-risk rejection."
                            : "No review binds to the current id/revision/hash; dataset cannot be judged until a current review exists.",
                         sources: [datasetRef(key)] + reviewRefs(stale),
                         extra: ["current_review_count": 0, "historical_review_count": stale.count])
                }

                if !current.isEmpty {
                    if kind == .provenance, current.contains(where: { hasUnresolvedFindings($0.record) }) {
                        for entry in groupUnresolved(current) {
                            emit(bucket: "machine", kind: "unresolved-provenance",
                                 action: "machine-fix", priority: "high",
                                 subjectID: id, severity: entry.severity, reason: entry.reason,
                                 sources: [datasetRef(key)] + reviewRefs(entry.items),
                                 extra: ["occurrence_count": entry.items.count])
                        }
                    }

                    let verdicts = Set(current.map { $0.record.payload.verdict.rawValue })
                    if verdicts.count > 1 {
                        emit(bucket: "human", kind: "review-disagreement",
                             action: "independent-review-needed", priority: "high",
                             subjectID: id, severity: "major",
                             reason: "Exact current-binding reviews disagree (\(verdicts.sorted().joined(separator: ", "))); needs independent human tie-break, never auto-resolution.",
                             sources: [datasetRef(key)] + reviewRefs(current))
                    }

                    for entry in groupUnresolved(current) where kind != .provenance {
                        var extra: Row = ["occurrence_count": entry.items.count]
                        if case .question(let question) = record {
                            let blocked = question.payload.provenanceRefs.filter { provenanceBlocked.contains($0) }
                            if !blocked.isEmpty { extra["blocked_by_unresolved_provenance"] = blocked.sorted() }
                        }
                        emit(bucket: "human", kind: "unresolved-finding",
                             action: "independent-review-needed",
                             priority: entry.severity == "minor" ? "medium" : "high",
                             subjectID: id, severity: entry.severity, reason: entry.reason,
                             sources: [datasetRef(key)] + reviewRefs(entry.items), extra: extra)
                    }

                    let quarantinedBare = current.filter { hit in
                        hit.record.payload.verdict == .quarantined && !hasUnresolvedFindings(hit.record)
                    }
                    if !quarantinedBare.isEmpty, verdicts.count <= 1, groupUnresolved(current).isEmpty {
                        emit(bucket: "human", kind: "incomplete-evidence",
                             action: "independent-review-needed", priority: "medium",
                             subjectID: id, severity: "major",
                             reason: "Current review quarantines without itemized unresolved findings; evidence is incomplete so the subject stays pending independent review.",
                             sources: [datasetRef(key)] + reviewRefs(quarantinedBare))
                    }
                }

                // Historical-only context: never dropped, never current, even
                // when no current review exists for the subject.
                if !stale.isEmpty {
                    let staleVerdicts = Set(stale.map { $0.record.payload.verdict.rawValue })
                    let verdicts = Set(current.map { $0.record.payload.verdict.rawValue })
                    if staleVerdicts.count > 1 || !staleVerdicts.isSubset(of: verdicts) {
                        emit(bucket: "historical", kind: "historical-disagreement",
                             action: "monitor-context", priority: "low",
                             subjectID: id,
                             severity: "minor",
                             reason: "Superseded revisions disagreed (\(staleVerdicts.sorted().joined(separator: ", "))); retained as context only, current binding governs.",
                             sources: reviewRefs(stale),
                             extra: ["current_verdicts": Array(verdicts).sorted(), "historical_only": true])
                    }
                    let resolved = stale.filter { hasResolvedFindings($0.record) }
                    if !resolved.isEmpty {
                        emit(bucket: "historical", kind: "historical-fixed-error",
                             action: "monitor-context", priority: "low",
                             subjectID: id, severity: "minor",
                             reason: "Earlier revision carried findings later marked resolved; kept as fix context, not a current judgment.",
                             sources: reviewRefs(resolved),
                             extra: ["historical_only": true])
                    }
                    // Stale unresolved findings keep their actual severity and
                    // matching priority; the historical_only flag marks that
                    // they do not describe the current binding.
                    for entry in groupUnresolved(stale) {
                        emit(bucket: "historical", kind: "historical-unresolved-stale",
                             action: "monitor-context",
                             priority: entry.severity == "minor" ? "medium" : "high",
                             subjectID: id, severity: entry.severity,
                             reason: "Historical only (superseded revision): \(entry.reason) Retained as context while the current binding is judged separately.",
                             sources: reviewRefs(entry.items),
                             extra: ["historical_only": true, "current_binding": false,
                                     "occurrence_count": entry.items.count,
                                     "current_verdicts": Array(Set(current.map { $0.record.payload.verdict.rawValue })).sorted()])
                    }
                }
            }

            // Quality-audit items with current binding only. Structural author
            // work goes to the machine bucket; missing or failed independent
            // assessment goes to human review. Review-evidence reasons are
            // owned by the binding classifier above and are not re-emitted.
            if !qualityItems.isEmpty {
                for item in qualityItems.sorted(by: { $0.questionId < $1.questionId }) {
                    guard let record = records["question|\(item.questionId)"],
                          case .question(let question) = record,
                          question.revision == item.revision,
                          question.contentSha256 == item.contentSha256 else { continue }
                    qualityBound += 1
                    if question.payload.testedAbility == .writing {
                        emit(bucket: "machine", kind: "scope-excluded", action: "excluded-from-supply",
                             priority: "low", subjectID: item.questionId, severity: "minor",
                             reason: "Writing is outside the active scope; retained for history, not queued for four-option authoring or semantic assessment.",
                             sources: [datasetRef(datasetKey(record))], extra: ["quality_state": item.state])
                        continue
                    }
                    for reason in item.missingWork.sorted() where !bindingOwnedReasons.contains(reason) {
                        let rejected = item.state == "rejected"
                        if authorWorkReasons.contains(reason) {
                            emit(bucket: "machine", kind: "author-revision-needed",
                                 action: "author-revision-needed",
                                 priority: rejected ? "high" : "medium",
                                 subjectID: item.questionId, severity: rejected ? "major" : "minor",
                                 reason: "Quality audit (\(item.state)): \(reason) (current binding \(item.questionId) r\(item.revision)).",
                                 sources: [datasetRef(datasetKey(record)), ["source": policyRel, "detail": "quality-audit-item"]],
                                 extra: ["quality_state": item.state, "missing_work": reason])
                        } else {
                            emit(bucket: "human", kind: "assessment-pending",
                                 action: "independent-review-needed",
                                 priority: rejected ? "high" : "medium",
                                 subjectID: item.questionId, severity: rejected ? "major" : "minor",
                                 reason: "Quality audit (\(item.state)): \(reason) (current binding \(item.questionId) r\(item.revision)).",
                                 sources: [datasetRef(datasetKey(record)), ["source": policyRel, "detail": "quality-audit-item"]],
                                 extra: ["quality_state": item.state, "missing_work": reason])
                        }
                    }
                }
            }

            let bucketRank = ["machine": 0, "human": 1, "historical": 2]
            issues.sort {
                let a = $0, b = $1
                let ba = bucketRank[a["bucket"] as? String ?? ""] ?? 9, bb = bucketRank[b["bucket"] as? String ?? ""] ?? 9
                if ba != bb { return ba < bb }
                let sa = a["subject_id"] as? String ?? "", sb = b["subject_id"] as? String ?? ""
                if sa != sb { return sa < sb }
                let ka = a["issue_kind"] as? String ?? "", kb = b["issue_kind"] as? String ?? ""
                if ka != kb { return ka < kb }
                return (a["reason"] as? String ?? "") < (b["reason"] as? String ?? "")
            }

            func count(_ selector: (Row) -> String) -> [String: Int] {
                var out: [String: Int] = [:]
                for issue in issues { out[selector(issue), default: 0] += 1 }
                return out
            }
            let byBucket = count { $0["bucket"] as? String ?? "" }
            let byKind = count { $0["issue_kind"] as? String ?? "" }
            let byAction = count { $0["action"] as? String ?? "" }
            let byPriority = count { $0["priority"] as? String ?? "" }
            let summary: Row = [
                "issue_count": issues.count,
                "subject_count": records.count,
                "by_bucket": byBucket,
                "by_kind": byKind,
                "by_action": byAction,
                "by_priority": byPriority,
            ]
            if !policySummary.isEmpty { policySummary["quality_items_bound"] = qualityBound }
            let bindings: [Row] = try inputs.map { file in
                ["path": relative(file, from: base), "sha256": CKHash.sha256Hex(of: try Data(contentsOf: file))]
            }
            let triage: Row = [
                "generator": "CurrentRecheckReport",
                "human_review_pending": true, "release_eligible": false, "approval": NSNull(),
                "note": "Triage only. Generating this packet grants no approval; owner decisions in human-decisions.jsonl are never written here.",
                "dataset_subjects": records.count,
                "disambiguated_reviews": reviewRowsCount,
                "disambiguated_review_locations": reviewLocationsCount,
                "ambiguous_conflicts_retained": ambiguousCount,
                "mapping_entries": mappingCount,
                "policy": policySummary,
                "summary": summary,
                "inputs": bindings,
                "issues": issues,
            ]

            var artifacts: [URL: Data] = [:]
            artifacts[out] = try bytes(triage, pretty: true)
            artifacts[jsonlOut] = Data(try issues.map { try text($0) + "\n" }.joined().utf8)

            var md = "# Owner recheck — CURRENT TREE (pending)\n\n"
            md += "No human decisions have been made. This packet grants no approval and no release eligibility. Source rights pending; costs unknown.\n\n"
            md += "Dataset subjects: \(records.count); disambiguated reviews: \(reviewRowsCount); issues: \(issues.count) "
            md += "(machine \((summary["by_bucket"] as? Row)?["machine"] ?? 0), human \((summary["by_bucket"] as? Row)?["human"] ?? 0), historical \((summary["by_bucket"] as? Row)?["historical"] ?? 0)).\n\n"
            md += "Ambiguous raw-ID conflicts retained without auto-resolution: \(ambiguousCount); mapping entries: \(mappingCount)."
            md += " Quality items bound to current revisions: \(qualityBound).\n\n"
            md += "## Summary\n\n"
            for key in ["by_bucket", "by_kind", "by_action", "by_priority"] {
                let counts = (summary[key] as? [String: Int] ?? [:]).sorted { $0.key < $1.key }
                    .map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
                md += "### \(key)\n\n\(counts)\n\n"
            }
            md += "## Issues\n\n"
            md += "Full rows live in [current-triage.json](current-triage.json) and [current-human-recheck.jsonl](current-human-recheck.jsonl). "
            md += "Each row carries its current binding (id/revision/hash), pending reason, severity, source refs and the current problem text.\n\n"
            for issue in issues {
                md += "- [\(issue["bucket"] ?? "")/\(issue["issue_kind"] ?? "")] `\(issue["subject_id"] ?? "")` "
                md += "r\(issue["subject_revision"] ?? "") · \(issue["priority"] ?? "") · \(issue["action"] ?? "") — \(issue["reason"] ?? "")\n"
            }
            md += "\nHuman decision: **pending**. Owner signature: —\n"
            artifacts[mdOut] = Data(md.utf8)

            if mode == "audit-current-recheck" {
                for (file, expected) in artifacts {
                    try check(FileManager.default.fileExists(atPath: file.path), "missing_artifact:\(file.lastPathComponent)")
                    try check(Data(contentsOf: file) == expected, "stale_or_incomplete_packet:\(file.lastPathComponent)")
                }
            } else {
                for (file, data) in artifacts {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: file, options: .atomic)
                }
            }
            let evidenceDoc: Row = ["valid": true, "mode": mode, "issue_count": issues.count,
                "summary": summary, "human_review_pending": true, "release_eligible": false,
                "artifacts": artifacts.keys.sorted { $0.path < $1.path }.map { file -> Row in
                    ["path": relative(file, from: base), "sha256": CKHash.sha256Hex(of: artifacts[file] ?? Data())]
                }]
            try FileManager.default.createDirectory(at: evidence.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: evidence.path) {
                try bytes(evidenceDoc, pretty: true).write(to: evidence, options: .withoutOverwriting)
            }
            let machine = (summary["by_bucket"] as? Row)?["machine"] ?? 0
            let human = (summary["by_bucket"] as? Row)?["human"] ?? 0
            let historical = (summary["by_bucket"] as? Row)?["historical"] ?? 0
            print("valid=true issues=\(issues.count) machine=\(machine) human=\(human) historical=\(historical) human_review_pending=true release_eligible=false")
            return 0
        } catch {
            fputs("\(error)\n", stderr)
            return 65
        }
    }

    private struct UnresolvedGroup {
        let severity: String
        let reason: String
        let items: [ReviewHit]
    }

    private static func questionStatus(_ record: ContractRecord) -> String? {
        guard case .question(let question) = record else { return nil }
        return question.payload.status.rawValue
    }

    private static func isCurrentBinding(_ review: Review, datasetRecord: ContractRecord) -> Bool {
        review.payload.subjectRevision == datasetRecord.document.revision
            && review.payload.subjectContentSha256 == datasetRecord.contentSha256
    }

    private static func hasUnresolvedFindings(_ review: Review) -> Bool {
        review.payload.findings.contains { $0.state == .unresolved }
    }

    private static func hasResolvedFindings(_ review: Review) -> Bool {
        review.payload.findings.contains { $0.state == .resolved }
    }

    private static func groupUnresolved(_ hits: [ReviewHit]) -> [UnresolvedGroup] {
        var groups: [String: [ReviewHit]] = [:]
        var meta: [String: (severity: String, reason: String)] = [:]
        for hit in hits {
            for finding in hit.record.payload.findings where finding.state == .unresolved {
                let severity = finding.severity.rawValue
                let reason = finding.reason
                let key = "\(severity)|\(reasonSnippet(reason, limit: 300))"
                groups[key, default: []].append(hit)
                meta[key] = (severity, reason)
            }
        }
        return groups.keys.sorted().compactMap { key in
            guard let m = meta[key], let list = groups[key] else { return nil }
            var seen: Set<String> = []
            let unique = list.filter { seen.insert($0.record.recordId).inserted }
            return UnresolvedGroup(severity: m.severity, reason: m.reason, items: unique)
        }
    }
}
