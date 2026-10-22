import ContentCLI
import ContentModel
import Foundation

struct MigrationFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
func require(_ condition: Bool, _ reason: String) throws {
    if !condition { throw MigrationFailure(reason) }
}
let version = "pilot230-semantic-target-basis-v1"
let evidencePath = "content/ids/registration-20261022.json"
let adoptionReason = "existing_identity_adoption_2026-10-22_not_historical_issuance"
let originalHash = "c1b5f9c1d26da52d8266fccf225044b21fe14d89fba57810e5d2e83dabe964a6"

struct SemanticBasis: Codable, Equatable {
    let version: String
    let kind: IdentityKind
    let fields: [String: String]
    let sets: [String: [String]]
    var hash: String { get throws { try CKHash.sha256Hex(of: ContractJSON.bytes(self)) } }
}
struct ObservedDocument: Codable, Equatable {
    let path: String
    let line: Int
    let binding: IdentityObservation
}
struct Candidate: Codable {
    let id: String
    let basis: SemanticBasis
    let contentHash: String
    let observed: [ObservedDocument]
    var registration: IdentityRegistration {
        get throws {
            let fingerprint = try basis.hash
            return IdentityRegistration(id: id,
                draft: IdentityDraft(kind: basis.kind, issuanceKey: "pilot-230:existing-registration-v1:\(basis.kind.rawValue):\(fingerprint)",
                    contentHash: contentHash, semanticHash: fingerprint, vendorIds: []),
                observations: observed.map(\.binding), reason: adoptionReason, evidenceRefs: ["\(evidencePath)#\(id)"])
        }
    }
}
struct SourceSnapshot: Codable {
    let path: String
    let sha256: String
}
struct Receipt: Codable {
    let schema: String
    let adoptedOn: String
    let scope: String
    let fingerprint: String
    let fingerprintFields: [String: [String]]
    let excludedFromFingerprint: [String]
    let ledgerRevisionMeaning: String
    let familyContentHashMeaning: String
    let legacyPrefixBytes: Int
    let legacyPrefixSha256: String
    let legacyEventCount: Int
    let legacyTerminalHash: String?
    let finalLedgerSha256: String
    let finalTerminalHash: String?
    let requiredCount: Int
    let registeredCount: Int
    let requiredByKind: [String: Int]
    let appendedByKind: [String: Int]
    let previouslyRegisteredIds: [String]
    let sourceSnapshots: [SourceSnapshot]
    let registrations: [Candidate]
    let dryRunReplayed: Bool
    let retryByteIdempotent: Bool
    let semanticConflicts: [String]
    let nativeIdsAudit: IdentityAuditReport
}
struct Inventory {
    let candidates: [Candidate]
    let sources: [SourceSnapshot]
}

func inventory(root: URL) throws -> Inventory {
    let relative = "content/records/pilot-230/merged"
    let directory = root.appendingPathComponent(relative)
    _ = try ContractDataset.validate(at: directory)
    var records: [String: ContractRecord] = [:]
    var observed: [String: ObservedDocument] = [:]
    var sources: [SourceSnapshot] = []
    for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter({ $0.pathExtension == "jsonl" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let path = "\(relative)/\(file.lastPathComponent)"
        sources.append(SourceSnapshot(path: path, sha256: try CKHash.sha256Hex(ofFileAt: file)))
        for (offset, line) in try CKJSONL.readLines(at: file).enumerated() {
            let record = try ContractJSON.decode(Data(line.utf8))
            try require(records[record.recordId] == nil, "duplicate_document:\(record.recordId)")
            records[record.recordId] = record
            observed[record.recordId] = ObservedDocument(path: path, line: offset + 1,
                binding: IdentityObservation(recordId: record.recordId, revision: record.document.revision,
                    contentSha256: record.contentSha256))
        }
    }
    func target(_ id: String) throws -> Target {
        guard case .target(let value)? = records[id] else { throw MigrationFailure("missing_target:\(id)") }
        return value
    }
    var candidates: [Candidate] = []
    var families: [String: [Question]] = [:]
    for record in records.values.sorted(by: { $0.recordId < $1.recordId }) {
        let kind: IdentityKind
        let fields: [String: String]
        var sets: [String: [String]] = [:]
        switch record {
        case .entry(let v):
            kind = v.payload.entryKind == .word ? .word : .phrase
            fields = ["entry_kind": v.payload.entryKind.rawValue, "lemma": v.payload.lemma]
        case .sense(let v):
            kind = .sense
            guard case .entry(let entry)? = records[v.payload.entryId], entry.payload.senseIds.contains(v.recordId) else {
                throw MigrationFailure("sense_entry_conflict:\(v.recordId)")
            }
            fields = ["entry_id": v.payload.entryId, "pos": v.payload.pos.rawValue, "core_meaning_zh_hant": v.payload.coreMeaningZhHant]
        case .target(let v):
            kind = .target
            guard case .sense(let sense)? = records[v.payload.senseId], sense.payload.entryId == v.payload.entryId else {
                throw MigrationFailure("target_sense_conflict:\(v.recordId)")
            }
            fields = ["entry_id": v.payload.entryId, "sense_id": v.payload.senseId, "tested_ability": v.payload.testedAbility.rawValue]
        case .teaching(let v):
            kind = .usage
            let parent = try target(v.payload.primaryTargetId)
            try require(parent.payload.usageIds.contains(v.recordId) && parent.payload.testedAbility == v.payload.testedAbility,
                "teaching_target_conflict:\(v.recordId)")
            fields = ["primary_target_id": v.payload.primaryTargetId, "tested_ability": v.payload.testedAbility.rawValue, "usage": v.payload.usage]
        case .question(let v):
            kind = .question
            let parent = try target(v.payload.primaryTargetId)
            try require(parent.payload.senseId == v.payload.correctSenseId && parent.payload.testedAbility == v.payload.testedAbility
                && Set(v.payload.correctUsageIds).isSubset(of: Set(parent.payload.usageIds)), "question_target_conflict:\(v.recordId)")
            fields = ["primary_target_id": v.payload.primaryTargetId, "tested_ability": v.payload.testedAbility.rawValue,
                "family_id": v.payload.familyId, "split": v.payload.split.rawValue, "correct_sense_id": v.payload.correctSenseId]
            sets["correct_usage_ids"] = v.payload.correctUsageIds.sorted()
            families[v.payload.familyId, default: []].append(v)
        case .provenance, .review, .manifest: continue
        }
        guard let observation = observed[record.recordId] else { throw MigrationFailure("missing_observation:\(record.recordId)") }
        candidates.append(Candidate(id: record.recordId, basis: SemanticBasis(version: version, kind: kind, fields: fields, sets: sets),
            contentHash: record.contentSha256, observed: [observation]))
    }
    for (id, members) in families.sorted(by: { $0.key < $1.key }) {
        try ContractRules.id(id, [.family])
        let ordered = members.sorted { $0.recordId < $1.recordId }
        try require(Set(ordered.map { $0.payload.primaryTargetId }).count == 1 && Set(ordered.map { $0.payload.split.rawValue }).count == 1,
            "family_semantic_conflict:\(id)")
        let bindings = try ordered.map { member in
            guard let binding = observed[member.recordId] else { throw MigrationFailure("missing_member:\(member.recordId)") }
            return binding
        }
        let basis = SemanticBasis(version: version, kind: .family,
            fields: ["primary_target_id": ordered[0].payload.primaryTargetId, "split": ordered[0].payload.split.rawValue],
            sets: ["member_question_ids": ordered.map(\.recordId)])
        candidates.append(Candidate(id: id, basis: basis,
            contentHash: try CKHash.sha256Hex(of: ContractJSON.bytes(bindings.map(\.binding))), observed: bindings))
    }
    var semantics: [String: String] = [:]
    for candidate in candidates {
        let key = "\(candidate.basis.kind.rawValue):\(try candidate.basis.hash)"
        if let other = semantics[key], other != candidate.id {
            throw MigrationFailure("semantic_conflict:\(other):\(candidate.id)")
        }
        semantics[key] = candidate.id
    }
    try require(candidates.count == 2756 && Set(candidates.map(\.id)).count == 2756, "required_identity_count_changed")
    return Inventory(candidates: candidates.sorted { $0.id < $1.id }, sources: sources)
}

func verifyCoverage(_ candidates: [Candidate], state: IdentitySnapshot) throws {
    for candidate in candidates {
        try require(state.records[candidate.id]?.kind == candidate.basis.kind && !state.retiredIds.contains(candidate.id),
            "unresolved_identity:\(candidate.id)")
    }
}
func nativeAudit(root: URL, ledger: URL, evidence: URL) throws -> IdentityAuditReport {
    try require(IdentityCommands.run(["audit", "--ledger", ledger.path, "--coverage",
        root.appendingPathComponent("content/coverage/ceec-map.jsonl").path, "--evidence", evidence.path]) == 0, "native_ids_audit_failed")
    return try JSONDecoder().decode(IdentityAuditReport.self, from: Data(contentsOf: evidence))
}
func verifySources(_ sources: [SourceSnapshot], root: URL) throws {
    for source in sources {
        try require(try CKHash.sha256Hex(ofFileAt: root.appendingPathComponent(source.path)) == source.sha256,
            "source_changed_during_registration:\(source.path)")
    }
}
func counts(_ candidates: [Candidate]) -> [String: Int] {
    Dictionary(grouping: candidates, by: { $0.basis.kind.rawValue }).mapValues(\.count)
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    try require(args.count == 5 && ["--dry-run", "--apply", "--verify"].contains(args[0]) && args[1] == "--root" && args[3] == "--scratch",
        "usage: register-existing-20261022 --dry-run|--apply|--verify --root REPOSITORY --scratch EXISTING_DIRECTORY")
    let mode = args[0]
    let root = URL(fileURLWithPath: args[2]).standardizedFileURL.resolvingSymlinksInPath()
    let scratchParent = URL(fileURLWithPath: args[4]).standardizedFileURL.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    try require(FileManager.default.fileExists(atPath: scratchParent.path, isDirectory: &isDirectory) && isDirectory.boolValue, "missing_scratch_parent")
    let scratch = scratchParent.appendingPathComponent("registration-20261022-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
    let ledger = root.appendingPathComponent("content/ids/ledger.jsonl")
    let evidence = root.appendingPathComponent(evidencePath)
    let input = try inventory(root: root)
    let before = try Data(contentsOf: ledger)
    let initial = try IdentityLedger.audit(at: ledger)

    if FileManager.default.fileExists(atPath: evidence.path) {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let receipt = try decoder.decode(Receipt.self, from: Data(contentsOf: evidence))
        try require(receipt.schema == "lexvane.existing-identity-registration.v1" && receipt.registrations.count == 2466
            && receipt.previouslyRegisteredIds.count == 290, "invalid_registration_receipt")
        try require(initial.eventCount == 2756 && initial.records.count == 2756 && initial.retiredIds.isEmpty
            && CKHash.sha256Hex(of: before) == receipt.finalLedgerSha256, "registered_ledger_changed")
        try require(before.count >= receipt.legacyPrefixBytes && CKHash.sha256Hex(of: Data(before.prefix(receipt.legacyPrefixBytes))) == originalHash,
            "historical_prefix_changed")
        let current = Dictionary(uniqueKeysWithValues: input.candidates.map { ($0.id, $0) })
        try require(Set(current.keys) == Set(receipt.previouslyRegisteredIds + receipt.registrations.map(\.id)), "required_id_set_changed")
        for candidate in receipt.registrations {
            try require(current[candidate.id]?.basis == candidate.basis, "semantic_conflict_since_adoption:\(candidate.id)")
        }
        try verifyCoverage(input.candidates, state: initial)
        _ = try IdentityLedger.registerExisting(receipt.registrations.map { try $0.registration }, at: ledger)
        try require(try Data(contentsOf: ledger) == before, "retry_appended_or_changed_ledger")
        _ = try nativeAudit(root: root, ledger: ledger, evidence: scratch.appendingPathComponent("ids-audit.json"))
        print("Verified 2756/2756 identities; 2466 exact registration retries appended zero bytes; historical prefix unchanged. Evidence retained at \(evidence.path)")
        return
    }
    try require(mode != "--verify", "registration_evidence_missing")
    try require(initial.eventCount == 290 && initial.records.count == 290 && initial.retiredIds.isEmpty
        && CKHash.sha256Hex(of: before) == originalHash, "unexpected_legacy_ledger")
    try require(Set(initial.records.keys).isSubset(of: Set(input.candidates.map(\.id))), "legacy_id_outside_pilot")
    for candidate in input.candidates where initial.records[candidate.id] != nil {
        try require(initial.records[candidate.id]?.kind == candidate.basis.kind, "legacy_kind_conflict:\(candidate.id)")
    }
    let missing = input.candidates.filter { initial.records[$0.id] == nil }
    try require(missing.count == 2466 && counts(missing) == ["sense": 303, "target": 363, "usage": 360, "question": 720, "family": 720],
        "missing_identity_counts_changed")
    let registrations = try missing.map { try $0.registration }
    let trial = scratch.appendingPathComponent("ledger.jsonl")
    try before.write(to: trial)
    _ = try IdentityLedger.registerExisting(registrations, at: trial)
    let after = try Data(contentsOf: trial)
    let final = try IdentityLedger.audit(at: trial)
    try require(after.starts(with: before) && final.eventCount == 2756 && final.records.count == 2756, "dry_run_count_or_prefix_failure")
    try verifyCoverage(input.candidates, state: final)
    _ = try IdentityLedger.registerExisting(registrations, at: trial)
    try require(try Data(contentsOf: trial) == after, "dry_run_not_idempotent")
    let audit = try nativeAudit(root: root, ledger: trial, evidence: scratch.appendingPathComponent("ids-audit.json"))
    let receipt = Receipt(schema: "lexvane.existing-identity-registration.v1", adoptedOn: "2026-10-22",
        scope: "Existing pilot-230 identity adoption only. No ID minting, dataset edits, source rights, approvals, review acceptance, or release eligibility.",
        fingerprint: "SHA-256 of ContractJSON.bytes(SemanticBasis): sorted-key UTF-8 JSON without slash escaping, snake_case keys, version/kind/fields/sets. Sets sorted lexicographically; text exact, no normalization. Issuance key is pilot-230:existing-registration-v1:<kind>:<semantic fingerprint>.",
        fingerprintFields: ["word/phrase": ["entry_kind", "lemma"], "sense": ["entry_id", "pos", "core_meaning_zh_hant"],
            "target": ["entry_id", "sense_id", "tested_ability"], "usage (from teaching)": ["primary_target_id", "tested_ability", "usage"],
            "question": ["primary_target_id", "tested_ability", "family_id", "split", "correct_sense_id", "correct_usage_ids (sorted)"],
            "family": ["primary_target_id (single target verified)", "split (single split verified)", "member_question_ids (sorted)"]],
        excludedFromFingerprint: ["status", "activation", "priority", "revision", "content_sha256", "sources", "provenance", "review", "stem", "options", "explanations", "examples", "pronunciation"],
        ledgerRevisionMeaning: "1 = first registration in this ledger on adoption date, NOT original document revision or invented past issuance. Each observation binds the actual content revision and sealed hash seen now. Earlier 290 records/events are not revised or reinterpreted.",
        familyContentHashMeaning: "No standalone family document exists: SHA-256 of ContractJSON.bytes(sorted member IdentityObservation array). Semantic hash separately binds actual target, split, and member IDs.",
        legacyPrefixBytes: before.count, legacyPrefixSha256: CKHash.sha256Hex(of: before), legacyEventCount: initial.eventCount,
        legacyTerminalHash: initial.terminalHash, finalLedgerSha256: CKHash.sha256Hex(of: after), finalTerminalHash: final.terminalHash,
        requiredCount: input.candidates.count, registeredCount: missing.count, requiredByKind: counts(input.candidates), appendedByKind: counts(missing),
        previouslyRegisteredIds: initial.records.keys.sorted(), sourceSnapshots: input.sources, registrations: missing,
        dryRunReplayed: true, retryByteIdempotent: true, semanticConflicts: [], nativeIdsAudit: audit)
    let receiptBytes = try ContractJSON.bytes(receipt) + Data([10])
    try receiptBytes.write(to: scratch.appendingPathComponent("registration-20261022.json"))
    try verifySources(input.sources, root: root)
    try require(try Data(contentsOf: ledger) == before, "ledger_changed_after_dry_run")
    if mode == "--apply" {
        _ = try IdentityLedger.registerExisting(registrations, at: ledger)
        try require(try Data(contentsOf: ledger) == after, "applied_bytes_differ_from_validated_dry_run")
        try receiptBytes.write(to: evidence, options: .atomic)
        print("Applied 2466 existing-ID registrations; 2756/2756 resolved; 290-event prefix preserved exactly. Evidence: \(evidence.path)")
    } else {
        print("DRY RUN PASS: 2466 registrations, 2756/2756 resolved, replay/prefix/idempotency/native audit passed; repository untouched. Evidence: \(scratch.path)")
    }
}
do { try run() }
catch {
    FileHandle.standardError.write(Data("Registration stopped without bypassing validation: \(error)\n".utf8))
    exit(1)
}
