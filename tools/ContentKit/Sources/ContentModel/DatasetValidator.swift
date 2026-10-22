import Foundation

public enum DatasetDefectCode: String, Codable {
    case duplicateID = "duplicate_id"
    case danglingReference = "dangling_reference"
    case wrongKind = "wrong_kind"
    case quarantineDependency = "quarantine_dependency"
    case targetSenseMismatch = "target_sense_mismatch"
    case targetAbilityMismatch = "target_ability_mismatch"
    case inverseMismatch = "inverse_mismatch"
    case unknownAliasCollision = "unknown_alias_collision"
    case sourcePermission = "source_permission"
    case invalidRecord = "invalid_record"
    case provenanceBinding = "provenance_binding"
    case provenanceFields = "provenance_fields"
    case missingReview = "missing_review"
    case reviewBinding = "review_binding"
    case reviewRejected = "review_rejected"
    case familyMismatch = "family_mismatch"
    case feedbackMismatch = "feedback_mismatch"
    case identityBinding = "identity_binding"
    case evidenceClosure = "evidence_closure"
    case humanClosure = "human_closure"
    case profile = "profile"
}

public struct DatasetDefect: Codable, Equatable {
    public let code: DatasetDefectCode
    public let recordId: String
    public let field: String
    public let detail: String
    public init(code: DatasetDefectCode, recordId: String, field: String, detail: String) {
        self.code = code; self.recordId = recordId; self.field = field; self.detail = detail
    }
}

public struct DatasetGraphReport: Encodable {
    public var valid: Bool { defects.isEmpty }
    public let stage = "private-pack"
    public let recordCount: Int
    public let activeRecordIds: [String]
    public let quarantinedRecordIds: [String]
    /// Always multi-valued: a collision can never overwrite another identity.
    public let aliasIndex: [String: [String]]
    public var defects: [DatasetDefect]
    public var humanReviewPending = true
    public let releaseEligible = false

    enum CodingKeys: String, CodingKey {
        case valid, stage, recordCount, activeRecordIds, quarantinedRecordIds, aliasIndex, defects
        case humanReviewPending, releaseEligible
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(valid, forKey: .valid); try c.encode(stage, forKey: .stage)
        try c.encode(recordCount, forKey: .recordCount)
        try c.encode(activeRecordIds, forKey: .activeRecordIds)
        try c.encode(quarantinedRecordIds, forKey: .quarantinedRecordIds)
        try c.encode(aliasIndex, forKey: .aliasIndex); try c.encode(defects, forKey: .defects)
        try c.encode(humanReviewPending, forKey: .humanReviewPending)
        try c.encode(releaseEligible, forKey: .releaseEligible)
    }
}

private struct DatasetEdge {
    let field: String
    let id: String
    let kind: ContractKind
}

public enum DatasetValidator {
    /// Pure graph layer. Disk-backed evidence, blind solves, and human closure
    /// are added by validate(at:...). No registry permission is inferred.
    public static func audit(records: [ContractRecord], sources: [SourceRecord], reviews: [Review],
                             identities: IdentitySnapshot? = nil,
                             aliasCollisions: [String: [String]] = [:]) -> DatasetGraphReport {
        var defects: [DatasetDefect] = []
        func fail(_ code: DatasetDefectCode, _ id: String, _ field: String, _ detail: String) {
            defects.append(.init(code: code, recordId: id, field: field, detail: detail))
        }
        var lookup: [String: ContractRecord] = [:]
        var reviewLookup: [String: Review] = [:]
        var allIDs = Set<String>()
        for record in records {
            if !allIDs.insert(record.recordId).inserted {
                fail(.duplicateID, record.recordId, "record_id", "duplicate dataset identity; revisions must be merged before validation")
            } else { lookup[record.recordId] = record }
            do { _ = try ContractJSON.decode(ContractJSON.line(record).dropLast()) }
            catch { fail(.invalidRecord, record.recordId, "payload", String(describing: error)) }
        }
        for review in reviews {
            do { _ = try ContractJSON.decode(ContractJSON.line(.review(review)).dropLast()) }
            catch { fail(.invalidRecord, review.recordId, "payload", String(describing: error)) }
            if !allIDs.insert(review.recordId).inserted {
                fail(.duplicateID, review.recordId, "record_id", "duplicate review/dataset identity")
            } else { reviewLookup[review.recordId] = review }
        }
        if records.isEmpty { fail(.invalidRecord, "dataset", "records", "empty dataset") }
        var sourceIDs = Set<String>()
        for source in sources where !sourceIDs.insert(source.sourceID).inserted {
            fail(.duplicateID, source.sourceID, "source_id", "duplicate source identity")
        }
        let active = records.filter { status($0) != nil && status($0) != .quarantined }
        let quarantine = records.filter { status($0) == .quarantined }
        var edges: [String: [DatasetEdge]] = [:]
        var sourceEdges: [String: [(String, ContractSourceRef)]] = [:]
        var aliases: [String: Set<String>] = [:]
        var familyMembers: [String: [Question]] = [:]

        for record in records {
            let id = record.recordId
            var refs: [DatasetEdge] = []
            func edge(_ field: String, _ target: String, _ kind: ContractKind) {
                refs.append(.init(field: "payload." + field, id: target, kind: kind))
            }
            func many(_ field: String, _ ids: [String], _ kind: ContractKind) {
                for (index, target) in ids.enumerated() { edge("\(field)[\(index)]", target, kind) }
            }
            func sourcesAt(_ field: String, _ values: [ContractSourceRef]) {
                for (index, value) in values.enumerated() {
                    sourceEdges[id, default: []].append(("payload.\(field)[\(index)]", value))
                }
            }
            switch record {
            case .entry(let v):
                many("sense_ids", v.payload.senseIds, .sense)
                many("provenance_refs", v.payload.provenanceRefs, .provenance)
                for text in [v.payload.lemma] + (v.payload.aliases + v.payload.variants).map(\.text) {
                    aliases[text, default: []].insert(id)
                }
                for senseID in v.payload.senseIds {
                    if case .sense(let sense) = lookup[senseID], sense.payload.entryId != id {
                        fail(.inverseMismatch, id, "payload.sense_ids", "\(senseID) belongs to \(sense.payload.entryId)")
                    }
                }
            case .sense(let v):
                edge("entry_id", v.payload.entryId, .entry)
                many("usage_ids", v.payload.usageIds, .teaching)
                many("provenance_refs", v.payload.provenanceRefs, .provenance)
                sourcesAt("source_refs", v.payload.sourceRefs)
                if case .entry(let entry) = lookup[v.payload.entryId], !entry.payload.senseIds.contains(id) {
                    fail(.inverseMismatch, id, "payload.entry_id", "entry does not list sense")
                }
                for usageID in v.payload.usageIds {
                    if case .teaching(let usage) = lookup[usageID],
                       case .target(let target) = lookup[usage.payload.primaryTargetId], target.payload.senseId != id {
                        fail(.targetSenseMismatch, id, "payload.usage_ids", "\(usageID) teaches \(target.payload.senseId)")
                    }
                }
            case .target(let v):
                edge("entry_id", v.payload.entryId, .entry); edge("sense_id", v.payload.senseId, .sense)
                many("usage_ids", v.payload.usageIds, .teaching)
                many("provenance_refs", v.payload.provenanceRefs, .provenance)
                sourcesAt("source_refs", v.payload.sourceRefs)
                if case .sense(let sense) = lookup[v.payload.senseId], sense.payload.entryId != v.payload.entryId {
                    fail(.targetSenseMismatch, id, "payload.sense_id", "sense belongs to \(sense.payload.entryId)")
                }
                for usageID in v.payload.usageIds {
                    if case .teaching(let usage) = lookup[usageID], usage.payload.primaryTargetId != id {
                        fail(.inverseMismatch, id, "payload.usage_ids", "\(usageID) belongs to \(usage.payload.primaryTargetId)")
                    }
                }
            case .teaching(let v):
                edge("primary_target_id", v.payload.primaryTargetId, .target)
                many("provenance_refs", v.payload.provenanceRefs, .provenance)
                sourcesAt("source_refs", v.payload.sourceRefs)
                if case .target(let target) = lookup[v.payload.primaryTargetId] {
                    if target.payload.testedAbility != v.payload.testedAbility {
                        fail(.targetAbilityMismatch, id, "payload.tested_ability", "target ability differs")
                    }
                    if !target.payload.usageIds.contains(id) {
                        fail(.inverseMismatch, id, "payload.primary_target_id", "target does not list teaching")
                    }
                }
            case .question(let v):
                let p = v.payload
                edge("primary_target_id", p.primaryTargetId, .target)
                edge("correct_sense_id", p.correctSenseId, .sense)
                many("correct_usage_ids", p.correctUsageIds, .teaching)
                many("provenance_refs", p.provenanceRefs, .provenance)
                familyMembers[p.familyId, default: []].append(v)
                if case .target(let target) = lookup[p.primaryTargetId] {
                    if target.payload.senseId != p.correctSenseId {
                        fail(.targetSenseMismatch, id, "payload.correct_sense_id", "target \(target.recordId) requires \(target.payload.senseId)")
                    }
                    if target.payload.testedAbility != p.testedAbility {
                        fail(.targetAbilityMismatch, id, "payload.tested_ability", "target ability differs")
                    }
                    if target.payload.activation != .active && status(record) != .quarantined {
                        fail(.quarantineDependency, id, "payload.primary_target_id", "inactive target cannot enter pack")
                    }
                }
                for usageID in p.correctUsageIds {
                    if case .teaching(let usage) = lookup[usageID], usage.payload.primaryTargetId != p.primaryTargetId {
                        fail(.targetSenseMismatch, id, "payload.correct_usage_ids", "\(usageID) belongs to another target")
                    }
                }
                let acceptedText = p.testedAbility == .writing ? p.acceptedAnswers
                    : p.options.filter { p.acceptedAnswers.contains($0.optionId) }.map(\.english)
                if !acceptedText.contains(p.postAnswerFeedback.answer) {
                    fail(.feedbackMismatch, id, "payload.post_answer_feedback.answer", "feedback answer is not an accepted answer/variant")
                }
            case .provenance(let v):
                let p = v.payload
                edge("subject_id", p.subjectId, p.subjectKind)
                for (index, field) in p.fields.enumerated() {
                    sourcesAt("fields[\(index)].source_refs", field.sourceRefs)
                    let operation: SourceOperation?
                    switch field.method {
                    case .reference: operation = .reference
                    case .extract: operation = .extract
                    case .adapt: operation = .adapt
                    case .aiGenerated, .humanAuthored: operation = nil
                    }
                    if let operation, field.sourceRefs.contains(where: { !$0.operations.contains(operation) }) {
                        fail(.provenanceFields, id, "payload.fields[\(index)].method", "source operations do not cover derivation method")
                    }
                }
                if let subject = lookup[p.subjectId] {
                    if subject.document.revision != p.subjectRevision || subject.document.contentSha256 != p.subjectContentSha256 {
                        fail(.provenanceBinding, id, "payload.subject_revision", "not the current subject revision/hash: \(p.subjectId)")
                    }
                    do {
                        let raw = try JSONSerialization.jsonObject(with: ContractJSON.line(subject)) as? [String: Any]
                        let payload = raw?["payload"] as? [String: Any] ?? [:]
                        let expected = Set(payload.keys).subtracting(["status", "provenance_refs"])
                        if Set(p.fields.map(\.field)) != expected {
                            fail(.provenanceFields, id, "payload.fields", "expected fields: \(expected.sorted().joined(separator: ","))")
                        }
                    } catch { fail(.invalidRecord, id, "payload.fields", String(describing: error)) }
                }
                if p.reviewRefs.isEmpty {
                    fail(.missingReview, id, "payload.review_refs", "provenance has no current review edges")
                }
                for (index, ref) in p.reviewRefs.enumerated() {
                    guard let review = reviewLookup[ref] else {
                        fail(.danglingReference, id, "payload.review_refs[\(index)]", ref); continue
                    }
                    if review.payload.subjectId != p.subjectId || review.payload.subjectKind != p.subjectKind
                        || review.payload.subjectRevision != p.subjectRevision
                        || review.payload.subjectContentSha256 != p.subjectContentSha256 {
                        fail(.reviewBinding, id, "payload.review_refs[\(index)]", "review \(ref) covers a different subject/revision")
                    }
                }
            case .review, .manifest:
                fail(.wrongKind, id, "kind", "not a dataset content/provenance record")
            }
            edges[id] = refs
            for ref in refs {
                guard let destination = lookup[ref.id] else {
                    fail(.danglingReference, id, ref.field, ref.id); continue
                }
                if destination.document.kind != ref.kind { fail(.wrongKind, id, ref.field, ref.id) }
                if status(record) != nil && status(record) != .quarantined && status(destination) == .quarantined {
                    fail(.quarantineDependency, id, ref.field, ref.id)
                }
                if ref.kind == .provenance, case .provenance(let provenance) = destination {
                    let p = provenance.payload
                    if p.subjectId != id || p.subjectKind != record.document.kind || p.subjectRevision != record.document.revision
                        || p.subjectContentSha256 != record.document.contentSha256 {
                        fail(.provenanceBinding, id, ref.field, "\(ref.id) does not bind this current record")
                    }
                }
            }
        }

        for (text, ids) in aliases where ids.count > 1 {
            let declared = aliasCollisions[text] ?? []
            if Set(declared) != ids || declared.count != ids.count {
                for id in ids.sorted() { fail(.unknownAliasCollision, id, "payload.aliases", "\(text): \(ids.sorted().joined(separator: ","))") }
            }
        }
        for (text, ids) in aliasCollisions where Set(ids) != aliases[text] || ids.count < 2 || Set(ids).count != ids.count {
            fail(.unknownAliasCollision, "alias-index", text, "collision declaration does not match all current identities")
        }
        for (family, members) in familyMembers {
            if Set(members.map(\.payload.primaryTargetId)).count != 1 || Set(members.map(\.payload.split)).count != 1 {
                for member in members { fail(.familyMismatch, member.recordId, "payload.family_id", "\(family) spans targets or train/check splits") }
            }
            if let identities, identities.records[family]?.kind != .family || identities.retiredIds.contains(family) {
                for member in members { fail(.identityBinding, member.recordId, "payload.family_id", "unissued/retired family \(family)") }
            }
        }
        for record in active {
            let id = record.recordId
            if let identities {
                let expectedKind: IdentityKind?
                switch record {
                case .entry(let entry): expectedKind = entry.payload.entryKind
                case .sense: expectedKind = .sense
                case .target: expectedKind = .target
                case .teaching: expectedKind = .usage
                case .question: expectedKind = .question
                default: expectedKind = nil
                }
                if identities.records[id]?.kind != expectedKind || identities.retiredIds.contains(id) {
                    fail(.identityBinding, id, "record_id", "identity not issued/current in ledger")
                }
            }
            let current = reviews.filter {
                $0.payload.subjectId == id && $0.payload.subjectKind == record.document.kind
                    && $0.payload.subjectRevision == record.document.revision
                    && $0.payload.subjectContentSha256 == record.document.contentSha256
            }
            if current.isEmpty { fail(.missingReview, id, "revision", "no matching current revision/hash review") }
            for review in current {
                if review.payload.verdict != .passed || review.payload.findings.contains(where: { $0.state == .unresolved }) {
                    fail(.reviewRejected, id, "revision", "\(review.recordId) has unresolved findings or non-passed verdict")
                }
                for item in ReviewCoverage.checklistIDs[record.document.kind.rawValue] ?? [] {
                    let expected: ChecklistResult
                    if case .question(let question) = record, question.payload.testedAbility == .writing,
                       item == "distractor-rationales" { expected = .notApplicable } else { expected = .passed }
                    if !review.payload.checklist.contains(where: { $0.item == item && $0.result == expected }) {
                        fail(.reviewRejected, review.recordId, "payload.checklist", "\(id): missing/pending/failed \(item)")
                    }
                }
            }
            // Traverse all content/provenance edges, not just direct citations.
            // Legitimate reciprocal ownership edges are visited once.
            var visited = Set<String>()
            func authorize(_ ancestor: String, path: [String]) {
                guard visited.insert(ancestor).inserted else { return }
                for (field, ref) in sourceEdges[ancestor] ?? [] {
                    do {
                        if SourcePermissionGate.isReferenceOnly(ref.operations) {
                            _ = try SourcePermissionGate.authorizeReference(sourceID: ref.sourceId, purpose: .privatePreview, registry: sources)
                            continue
                        }
                        _ = try SourcePermissionGate.authorize(sourceID: ref.sourceId, purpose: .privatePreview, registry: sources)
                        guard let source = sources.first(where: { $0.sourceID == ref.sourceId }) else { continue }
                        for operation in ref.operations where source.permission(for: operation).status != .allowed {
                            throw SourceGateFailure(sourceID: ref.sourceId, purpose: .privatePreview,
                                reason: .permission(operation, source.permission(for: operation).status))
                        }
                    } catch {
                        fail(.sourcePermission, id, ancestor == id ? field : "ancestors.\(ancestor).\(field)",
                             "\(path.joined(separator: " -> ")): \(error)")
                    }
                }
                for ref in edges[ancestor] ?? [] where lookup[ref.id] != nil {
                    authorize(ref.id, path: path + [ref.id])
                }
            }
            authorize(id, path: [id])
        }
        for review in reviews {
            guard let subject = lookup[review.payload.subjectId] else {
                fail(.danglingReference, review.recordId, "payload.subject_id", review.payload.subjectId); continue
            }
            if subject.document.kind != review.payload.subjectKind {
                fail(.reviewBinding, review.recordId, "payload.subject_kind", "wrong subject kind")
            }
            // Historical reviews may remain, but never satisfy current coverage.
            if review.payload.subjectRevision > subject.document.revision
                || (review.payload.subjectRevision == subject.document.revision && review.payload.subjectContentSha256 != subject.document.contentSha256) {
                fail(.reviewBinding, review.recordId, "payload.subject_content_sha256", "unknown subject revision/hash")
            }
        }
        return DatasetGraphReport(recordCount: records.count, activeRecordIds: active.map(\.recordId).sorted(),
            quarantinedRecordIds: quarantine.map(\.recordId).sorted(), aliasIndex: aliases.mapValues { $0.sorted() },
            defects: defects.sorted { ($0.recordId, $0.field, $0.code.rawValue, $0.detail) < ($1.recordId, $1.field, $1.code.rawValue, $1.detail) })
    }

    private static func status(_ record: ContractRecord) -> ContentStatus? {
        switch record {
        case .entry(let v): v.payload.status
        case .sense(let v): v.payload.status
        case .target(let v): v.payload.status
        case .teaching(let v): v.payload.status
        case .question(let v): v.payload.status
        default: nil
        }
    }

    public static func validate(at dataset: URL, sources registry: URL, reviews directory: URL,
                                ledger: URL, profile: URL) -> DatasetGraphReport {
        var defects: [DatasetDefect] = []
        func fail(_ code: DatasetDefectCode, _ id: String, _ field: String, _ detail: String) {
            defects.append(.init(code: code, recordId: id, field: field, detail: detail))
        }
        var records: [ContractRecord] = []
        var reviews: [Review] = []
        var sources: [SourceRecord] = []
        var identities: IdentitySnapshot?
        var policy: GraphPolicy?
        var artifacts: [String: [[String: Any]]] = [:]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            for file in try jsonFiles(dataset) {
                do {
                    for (index, line) in try CKJSONL.readLines(at: file).enumerated() {
                        do { records.append(try ContractJSON.decode(Data(line.utf8))) }
                        catch { fail(.invalidRecord, file.lastPathComponent, "line[\(index + 1)]", String(describing: error)) }
                    }
                } catch { fail(.invalidRecord, file.lastPathComponent, "jsonl", String(describing: error)) }
            }
        } catch { fail(.invalidRecord, dataset.path, "dataset", String(describing: error)) }
        do {
            for file in try jsonFiles(directory) {
                do {
                    for (index, line) in try ReviewInputReader.lines(at: file).enumerated() {
                        do {
                            switch try ReviewInputReader.decode(line, file: file.lastPathComponent) {
                            case .sealed(let review): reviews.append(review)
                            case .artifact(let raw): artifacts[file.lastPathComponent, default: []].append(raw)
                            }
                        } catch { fail(.invalidRecord, file.lastPathComponent, "line[\(index + 1)]", String(describing: error)) }
                    }
                } catch { fail(.invalidRecord, file.lastPathComponent, "jsonl", String(describing: error)) }
            }
        } catch { fail(.invalidRecord, directory.path, "reviews", String(describing: error)) }
        do { sources = try SourceRegistry.read(at: registry); _ = try SourceRegistry.validate(at: registry) }
        catch { fail(.sourcePermission, registry.path, "registry", String(describing: error)) }
        do { identities = try IdentityLedger.audit(at: ledger) }
        catch { fail(.identityBinding, ledger.path, "ledger", String(describing: error)) }
        do {
            policy = try decoder.decode(GraphPolicy.self, from: Data(contentsOf: profile))
            guard let policy, !policy.activeAbilities.isEmpty,
                  Set(policy.activeAbilities).count == policy.activeAbilities.count,
                  Set(policy.perAbilityMinimums.keys) == Set(policy.activeAbilities.map(\.rawValue)),
                  policy.perAbilityMinimums.values.allSatisfy({ $0.trainFamilies > 0 && $0.independentCheckFamilies > 0 }),
                  policy.unresolvedCriticalMaximum == 0,
                  policy.humanSamplePolicy.denominator > 0, policy.humanSamplePolicy.maximum > 0,
                  policy.humanSamplePolicy.maximum <= policy.humanSamplePolicy.denominator else {
                throw ContractFailure("invalid_graph_profile")
            }
        } catch { fail(.profile, profile.path, "profile", String(describing: error)) }
        var report = audit(records: records, sources: sources, reviews: reviews, identities: identities,
                           aliasCollisions: policy?.aliasCollisions ?? [:])
        let lookup = records.reduce(into: [String: ContractRecord]()) { if $0[$1.recordId] == nil { $0[$1.recordId] = $1 } }
        let reviewLookup = reviews.reduce(into: [String: Review]()) { if $0[$1.recordId] == nil { $0[$1.recordId] = $1 } }
        let base = ledger.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var receipts: [String: JobReceipt] = [:]
        var jobSnapshots: [String: JobSnapshot] = [:]
        var failedJobLedgers = Set<String>()
        func receipt(_ ref: String, id: String, field: String) -> JobReceipt? {
            if let cached = receipts[ref] { return cached }
            do {
                let url = try JobLedger.localURL(ref, base: base)
                let value = try JobLedger.read(JobReceipt.self, at: url)
                try JobLedger.validateReceipt(value, binding: value.binding, base: base)
                receipts[ref] = value
                return value
            } catch { fail(.evidenceClosure, id, field, "\(ref): \(error)"); return nil }
        }
        var generatorSessions: [String: Set<String>] = [:]
        for record in records {
            guard case .provenance(let provenance) = record else { continue }
            let p = provenance.payload
            let id = provenance.recordId
            if let result = receipt(p.runReceiptRef, id: id, field: "payload.run_receipt_ref") {
                generatorSessions[p.subjectId, default: []].insert(result.sessionId)
                if result.binding.jobId != p.workUnitRef || result.binding.model != p.model || result.binding.promptHash != p.promptHash {
                    fail(.evidenceClosure, id, "payload.work_unit_ref", "work unit/model/prompt does not match receipt")
                }
                if result.binding.role.isReview {
                    fail(.evidenceClosure, id, "payload.run_receipt_ref", "author provenance references review receipt")
                }
                if let subject = lookup[p.subjectId], p.subjectRevision == subject.document.revision,
                   p.subjectContentSha256 == subject.document.contentSha256 {
                    var transforms: [String: ProvenanceTransform] = [:]
                    for ref in p.transformChain {
                        do {
                            let transform = try JobLedger.read(ProvenanceTransform.self, at: JobLedger.localURL(ref, base: base))
                            guard transforms[ref] == nil else { throw JobFailure("duplicate_transform") }
                            transforms[ref] = transform
                        } catch { fail(.evidenceClosure, id, "payload.transform_chain", "\(ref): \(error)") }
                    }
                    do {
                        let receiptURL = try JobLedger.localURL(p.runReceiptRef, base: base)
                        let jobsURL = receiptURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("jobs.jsonl")
                        if jobSnapshots[jobsURL.path] == nil && !failedJobLedgers.contains(jobsURL.path) {
                            do { jobSnapshots[jobsURL.path] = try JobLedger.audit(at: jobsURL) }
                            catch { failedJobLedgers.insert(jobsURL.path) }
                        }
                        guard let jobs = jobSnapshots[jobsURL.path] else {
                            throw JobFailure("missing_or_invalid_job_ledger:\(jobsURL.path)")
                        }
                        try ProvenanceValidator.validate(provenance, subject: subject.document,
                            requiredFields: Set(p.fields.map(\.field)), sourceIds: Set(sources.map(\.sourceID)),
                            jobs: jobs, reviews: reviewLookup, transforms: transforms,
                            humanModificationRefs: Set(p.humanModificationRefs.filter { ref in
                                guard let url = try? JobLedger.localURL(ref, base: base) else { return false }
                                return FileManager.default.fileExists(atPath: url.path)
                            }), base: base)
                    } catch { fail(.evidenceClosure, id, "payload", String(describing: error)) }
                }
            }
            for ref in p.humanModificationRefs {
                do {
                    let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: JobLedger.localURL(ref, base: base))) as? [String: Any]
                    guard raw?["subject_id"] as? String == p.subjectId,
                          let signer = raw?["signed_by"] as? String, ContractRules.present(signer),
                          let response = raw?["human_reply_source"] as? String, ContractRules.present(response) else {
                        throw ContractFailure("unbound_human_modification")
                    }
                } catch { fail(.humanClosure, id, "payload.human_modification_refs", "\(ref): \(error)") }
            }
        }
        var reviewSessions = Set<String>()
        for review in reviews {
            let p = review.payload
            reviewSessions.insert(p.reviewerSession)
            for ref in p.receiptRefs {
                guard let value = receipt(ref, id: review.recordId, field: "payload.receipt_refs") else { continue }
                let binding = JobRecord(recordId: p.subjectId, kind: p.subjectKind, revision: p.subjectRevision, contentHash: p.subjectContentSha256)
                if !value.binding.role.isReview || value.sessionId != p.reviewerSession || value.binding.model != p.reviewerModel
                    || value.binding.inputHash != p.inputHash || value.binding.promptHash != p.promptHash
                    || !value.binding.records.contains(binding) || generatorSessions[p.subjectId, default: []].contains(p.reviewerSession) {
                    fail(.reviewBinding, review.recordId, "payload.receipt_refs", "\(ref): receipt or independent session mismatch")
                }
            }
        }
        let forbiddenSessions = reviewSessions.union(generatorSessions.values.reduce(into: Set<String>()) { $0.formUnion($1) })
        let families = Set(records.compactMap { record -> String? in
            if case .question(let q) = record { return q.payload.familyId }; return nil
        })
        for (file, rows) in artifacts {
            for (index, row) in rows.enumerated() {
                for field in ["target_id", "train_family", "check_family"] {
                    guard let id = row[field] as? String else { continue }
                    let exists = field == "target_id" ? lookup[id]?.document.kind == .target : families.contains(id)
                    if !exists { fail(.danglingReference, file, "line[\(index + 1)].\(field)", id) }
                }
                for id in row["subject_ids"] as? [String] ?? [] where lookup[id] == nil {
                    fail(.danglingReference, file, "line[\(index + 1)].subject_ids", id)
                }
            }
        }
        auditBlind(records: records, directory: directory, artifacts: artifacts, forbiddenSessions: forbiddenSessions, fail: fail)
        auditHuman(records: lookup, artifacts: artifacts, policy: policy, forbiddenSessions: forbiddenSessions, fail: fail)
        if let policy {
            for record in records {
                guard case .target(let target) = record, target.payload.activation == .active,
                      target.payload.status != .quarantined else { continue }
                let id = target.recordId
                if policy.excludedTargetIds.contains(id) {
                    fail(.profile, id, "payload.activation", "excluded target is still active in pack")
                }
                guard let minimum = policy.perAbilityMinimums[target.payload.testedAbility.rawValue] else {
                    fail(.profile, id, "payload.tested_ability", "no active ability minimum"); continue
                }
                let owned = records.compactMap { record -> Question? in
                    if case .question(let q) = record, q.payload.primaryTargetId == id, q.payload.status != .quarantined { return q }
                    return nil
                }
                if Set(owned.filter { $0.payload.split == .train }.map(\.payload.familyId)).count < minimum.trainFamilies
                    || Set(owned.filter { $0.payload.split == .check }.map(\.payload.familyId)).count < minimum.independentCheckFamilies {
                    fail(.familyMismatch, id, "payload.activation", "active target lacks required train/check families")
                }
            }
        }
        report.defects.append(contentsOf: defects)
        report.defects.sort { ($0.recordId, $0.field, $0.code.rawValue, $0.detail) < ($1.recordId, $1.field, $1.code.rawValue, $1.detail) }
        report.humanReviewPending = policy?.humanReviewPending ?? true
        return report
    }

    private static func jsonFiles(_ directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func auditBlind(records: [ContractRecord], directory: URL, artifacts: [String: [[String: Any]]],
                                   forbiddenSessions: Set<String>,
                                   fail: (DatasetDefectCode, String, String, String) -> Void) {
        var inputs: [String: [[String: Any]]] = [:]
        do {
            for folder in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where folder.lastPathComponent.hasPrefix("blind-inputs") {
                for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    where file.pathExtension == "json" {
                    let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
                    guard var raw, let id = raw["question_id"] as? String else { throw ContractFailure("invalid_blind_input:\(file.path)") }
                    let uuid = id.split(separator: ":").last.map(String.init) ?? ""
                    if file.lastPathComponent != "blind-\(uuid).json" {
                        fail(.evidenceClosure, id, "blind.input.filename", "non-opaque filename \(file.lastPathComponent)")
                    }
                    raw["_file"] = file.path
                    inputs[id, default: []].append(raw)
                }
            }
        } catch { fail(.evidenceClosure, directory.path, "blind.inputs", String(describing: error)) }
        let solves = artifacts.filter { $0.key.hasPrefix("blind-") }.values.flatMap { $0 }
        let questionIDs = Set(records.filter { $0.document.kind == .question }.map(\.recordId))
        for solve in solves {
            if let id = solve["question_id"] as? String, !questionIDs.contains(id) {
                fail(.danglingReference, id, "blind.question_id", "unknown question in blind solve")
            }
        }
        for record in records {
            guard case .question(let q) = record, q.payload.status != .quarantined else { continue }
            let id = q.recordId, p = q.payload
            let currentInputs = (inputs[id] ?? []).filter { $0["question_revision"] as? Int == q.revision }
            if currentInputs.isEmpty { fail(.evidenceClosure, id, "blind.input", "missing current blind input") }
            for input in currentInputs {
                let expectedOptions = p.options.map { ["option_id": $0.optionId, "english": $0.english] }
                if Set(input.keys) != Set(["question_id", "question_revision", "stem", "options", "rules", "_file"])
                    || input["stem"] as? String != p.stem || input["options"] as? [[String: String]] != expectedOptions {
                    fail(.evidenceClosure, id, "blind.input", "leaked fields or changed stem/options")
                }
                let rules = (input["rules"] as? String ?? "").lowercased()
                var secrets = p.acceptedAnswers + p.options.map(\.english) + [p.postAnswerFeedback.answer, p.postAnswerFeedback.explanation]
                for record in records {
                    if case .sense(let sense) = record, sense.recordId == p.correctSenseId { secrets.append(sense.payload.coreMeaningZhHant) }
                }
                if secrets.contains(where: { ContractRules.present($0) && rules.contains($0.lowercased()) }) {
                    fail(.evidenceClosure, id, "blind.input.rules", "answer hint in blind rules")
                }
            }
            let currentSolves = solves.filter { $0["question_id"] as? String == id && $0["question_revision"] as? Int == q.revision }
            if currentSolves.isEmpty { fail(.evidenceClosure, id, "blind.solve", "missing current blind solve") }
            for solve in currentSolves {
                let session = solve["blind_session"] as? String ?? ""
                if !ContractRules.present(session) || forbiddenSessions.contains(session)
                    || solve["answerable"] as? Bool != true || !ContractRules.present(solve["reasoning"] as? String ?? "") {
                    fail(.evidenceClosure, id, "blind.solve", "not answerable, missing reasoning, or non-independent session")
                }
                if p.testedAbility == .writing {
                    if !ContractRules.present(solve["response_text"] as? String ?? "") { fail(.evidenceClosure, id, "blind.response_text", "missing writing response") }
                } else if !p.acceptedAnswers.contains(solve["chosen_option_id"] as? String ?? "") {
                    fail(.feedbackMismatch, id, "blind.chosen_option_id", "blind answer differs from accepted options")
                }
            }
        }
    }

    private static func auditHuman(records: [String: ContractRecord], artifacts: [String: [[String: Any]]], policy: GraphPolicy?,
                                   forbiddenSessions: Set<String>,
                                   fail: (DatasetDefectCode, String, String, String) -> Void) {
        let rows = artifacts["human-recheck.jsonl"] ?? []
        var seen = Set<String>()
        for row in rows {
            let id = row["record_id"] as? String ?? "human-recheck"
            if !seen.insert(id).inserted { fail(.duplicateID, id, "human.record_id", "duplicate human row") }
            if records[id] == nil { fail(.danglingReference, id, "human.record_id", "unknown human subject") }
            let reply = row["human_reply_source"] as? String ?? ""
            let signer = row["signed_by"] as? String ?? ""
            switch row["human_status"] as? String {
            case "pending":
                if ContractRules.present(reply) || ContractRules.present(signer) { fail(.humanClosure, id, "human.human_status", "pending must not claim reply/signoff") }
            case "accepted", "changes_requested":
                if !ContractRules.present(reply) || !ContractRules.present(signer) || forbiddenSessions.contains(signer) {
                    fail(.humanClosure, id, "human.signed_by", "missing actual human reply or independent signer")
                }
            default: fail(.humanClosure, id, "human.human_status", "unknown status")
            }
        }
        guard let policy else { return }
        if policy.humanReviewPending {
            if policy.humanSamplePolicy.humanStatus != "pending" || policy.humanSamplePolicy.humanAcceptedCount != 0
                || policy.humanSamplePolicy.actualHumanResponseRef != nil {
                fail(.humanClosure, "profile", "human_sample_policy", "pending profile cannot claim human acceptance")
            }
        } else if rows.isEmpty || rows.contains(where: { $0["human_status"] as? String != "accepted" }) {
            fail(.humanClosure, "profile", "human_review_pending", "no complete actual human acceptance")
        }
        for id in policy.humanSamplePolicy.highRiskIds {
            if records[id] == nil { fail(.danglingReference, id, "profile.human_sample_policy.high_risk_ids", "sample subject missing from dataset") }
            if !seen.contains(id) { fail(.humanClosure, id, "human.human_status", "sample has no explicit human pending/response row") }
        }
    }
}

private struct GraphPolicy: Decodable {
    struct Minimum: Decodable { let trainFamilies: Int; let independentCheckFamilies: Int }
    struct Human: Decodable {
        let denominator: Int
        let maximum: Int
        let highRiskIds: [String]
        let humanStatus: String
        let humanAcceptedCount: Int
        let actualHumanResponseRef: String?
    }
    let activeAbilities: [TestedAbility]
    let perAbilityMinimums: [String: Minimum]
    let excludedTargetIds: [String]
    let unresolvedCriticalMaximum: Int
    let humanReviewPending: Bool
    let humanSamplePolicy: Human
    let aliasCollisions: [String: [String]]?
}
