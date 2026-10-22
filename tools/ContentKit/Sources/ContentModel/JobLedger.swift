import Foundation
import Darwin

public struct JobFailure: Error, Equatable, CustomStringConvertible {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var description: String { "JobFailure(reason=\(reason))" }
}
public enum JobState: String, Codable {
    case pending, running, received, validated, quarantined
    case jobFailed = "job_failed"
}
public enum JobRole: String, Codable, CaseIterable {
    case author
    case languageReview = "language-review"
    case questionReview = "question-review"
    case blindSolve = "blind-solve"
    case checkAuthor = "check-author"
    case familyReview = "family-review"
    public var isReview: Bool { ![.author, .checkAuthor].contains(self) }
}
public enum JobFailureReason: String, Codable { case quota, interrupted, worker, invalidOutput = "invalid_output" }
public struct JobFailureDetail: Codable {
    public let reason: JobFailureReason
    public let resumable: Bool
    public init(reason: JobFailureReason, resumable: Bool) { self.reason = reason; self.resumable = resumable }
}
public struct JobRecord: Codable, Equatable {
    public let recordId: String
    public let kind: ContractKind
    public let revision: Int
    public let contentHash: String
    public init(recordId: String, kind: ContractKind, revision: Int, contentHash: String) {
        self.recordId = recordId; self.kind = kind; self.revision = revision; self.contentHash = contentHash
    }
}
public struct JobBinding: Codable, Equatable {
    public var jobId: String
    public var role: JobRole
    public var inputHash: String
    public var model: String
    public var modelHash: String
    public var promptRef: String
    public var promptHash: String?
    public var records: [JobRecord]
    public init(jobId: String, role: JobRole, inputHash: String, model: String, modelHash: String,
                promptRef: String, promptHash: String?, records: [JobRecord]) {
        self.jobId = jobId; self.role = role; self.inputHash = inputHash; self.model = model
        self.modelHash = modelHash; self.promptRef = promptRef; self.promptHash = promptHash; self.records = records
    }
    public func validate() throws {
        guard ContractRules.localRef(jobId), ContractRules.present(model), CKIdentityJSON.hashValid(inputHash),
              modelHash == CKHash.sha256Hex(of: Data(model.utf8)), ContractRules.localRef(promptRef),
              promptHash.map(CKIdentityJSON.hashValid) ?? true,
              !records.isEmpty, Set(records.map(\.recordId)).count == records.count,
              records.filter({ $0.kind == .entry }).count <= 25,
              role != .blindSolve || records.filter({ $0.kind == .question }).count <= 25 else {
            throw JobFailure("invalid_binding")
        }
        for record in records {
            guard record.revision > 0, CKIdentityJSON.hashValid(record.contentHash) else { throw JobFailure("invalid_record_revision") }
            let kinds: [IdentityKind]
            switch record.kind {
            case .entry: kinds = [.word, .phrase]
            case .sense: kinds = [.sense]
            case .target: kinds = [.target]
            case .teaching: kinds = [.usage]
            case .question: kinds = [.question]
            default: throw JobFailure("unsupported_job_record_kind")
            }
            try ContractRules.id(record.recordId, kinds)
        }
    }
}
public struct JobReceipt: Codable {
    public var binding: JobBinding
    public var sessionId: String
    public var runId: String
    public var evidenceRef: String
    public var evidenceHash: String
    public var resultRecords: [JobRecord]
    public var findingRefs: [String]
    public var tokens: String
    public var cost: String
    public var generatorSessionId: String?
    public init(binding: JobBinding, sessionId: String, runId: String, evidenceRef: String, evidenceHash: String,
                resultRecords: [JobRecord], findingRefs: [String], tokens: String, cost: String, generatorSessionId: String?) {
        self.binding = binding; self.sessionId = sessionId; self.runId = runId; self.evidenceRef = evidenceRef
        self.evidenceHash = evidenceHash; self.resultRecords = resultRecords; self.findingRefs = findingRefs
        self.tokens = tokens; self.cost = cost; self.generatorSessionId = generatorSessionId
    }
}
public struct JobEvent: Codable {
    public let schema: String
    public let binding: JobBinding
    public let state: JobState
    public let receiptRef: String?
    public var receiptHash: String?
    public let findingRefs: [String]
    public let failure: JobFailureDetail?
    public init(binding: JobBinding, state: JobState, receiptRef: String? = nil,
                findingRefs: [String] = [], failure: JobFailureDetail? = nil, receiptHash: String? = nil) {
        schema = "lexvane.jobs.v1"; self.binding = binding; self.state = state
        self.receiptRef = receiptRef; self.findingRefs = findingRefs; self.failure = failure
        self.receiptHash = receiptHash
    }
}
public enum JobResume: String { case receiptAvailable, alreadyAccepted, retryAllowed, reconcileRunning, blocked }
public struct JobSnapshot {
    public var events: [String: JobEvent] = [:]
    public var receipts: [String: JobReceipt] = [:]
    public var acceptedKeys: Set<String> = []
    public var acceptedCount: Int { acceptedKeys.count }
    public var status: String {
        if events.isEmpty || events.values.allSatisfy({ $0.state == .pending }) { return "not_dispatched" }
        return "dispatched"
    }
}
public enum JobLedger {
    public static func bytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try bytes(value).write(to: url, options: .atomic)
    }
    public static func read<T: Codable>(_ type: T.Type, at url: URL) throws -> T {
        try decode(type, data: Data(contentsOf: url))
    }
    private static func decode<T: Codable>(_ type: T.Type, data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let value = try decoder.decode(type, from: data)
        try JSONDecoder().decode(JSONShape.self, from: data).checkKeys(against: JSONDecoder().decode(JSONShape.self, from: bytes(value)))
        return value
    }
    public static func localURL(_ ref: String, base: URL) throws -> URL {
        guard ContractRules.localRef(ref) else { throw JobFailure("invalid_local_ref") }
        let root = base.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(ref).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else { throw JobFailure("invalid_local_ref") }
        return url
    }
    public static func validateReceipt(_ receipt: JobReceipt, binding: JobBinding, base: URL) throws {
        guard receipt.binding == binding else { throw JobFailure("changed_input_receipt") }
        guard ContractRules.present(receipt.sessionId), ContractRules.present(receipt.runId),
              !["unknown", "dummy", "pending"].contains(receipt.sessionId.lowercased()),
              !["unknown", "dummy", "pending"].contains(receipt.runId.lowercased()) else { throw JobFailure("missing_session_receipt") }
        guard binding.promptHash != nil else { throw JobFailure("blocked_prompts") }
        if binding.role.isReview {
            guard let generator = receipt.generatorSessionId, ContractRules.present(generator) else { throw JobFailure("missing_generator_session") }
            guard generator != receipt.sessionId else { throw JobFailure("reviewer_generator_session_collision") }
        }
        guard !receipt.resultRecords.isEmpty, Set(receipt.resultRecords.map(\.recordId)).count == receipt.resultRecords.count,
              receipt.findingRefs.allSatisfy(ContractRules.localRef),
              ContractRules.present(receipt.tokens), ContractRules.present(receipt.cost) else { throw JobFailure("invalid_receipt_payload") }
        var resultBinding = binding; resultBinding.records = receipt.resultRecords; try resultBinding.validate()
        guard Set(binding.records.map(\.recordId)).isSubset(of: Set(receipt.resultRecords.map(\.recordId))) else { throw JobFailure("missing_result_record") }
        let evidence = try localURL(receipt.evidenceRef, base: base)
        guard FileManager.default.fileExists(atPath: evidence.path), CKIdentityJSON.hashValid(receipt.evidenceHash),
              try CKHash.sha256Hex(ofFileAt: evidence) == receipt.evidenceHash else { throw JobFailure("run_evidence_mismatch") }
    }
    private static func loadReceipt(_ ref: String, binding: JobBinding, base: URL) throws -> JobReceipt {
        let url = try localURL(ref, base: base)
        guard FileManager.default.fileExists(atPath: url.path) else { throw JobFailure("dangling_receipt") }
        let receipt = try read(JobReceipt.self, at: url)
        try validateReceipt(receipt, binding: binding, base: base)
        return receipt
    }
    private static func apply(_ event: JobEvent, to snapshot: inout JobSnapshot, base: URL) throws {
        guard event.schema == "lexvane.jobs.v1" else { throw JobFailure("unknown_schema") }
        try event.binding.validate()
        let id = event.binding.jobId, key = id + ":" + event.binding.inputHash
        if let previous = snapshot.events[id] {
            guard previous.binding == event.binding else { throw JobFailure("changed_input_receipt") }
            if event.state == .validated && snapshot.acceptedKeys.contains(key) { throw JobFailure("duplicate_accept") }
            let transitions: [JobState: Set<JobState>] = [
                .pending: [.running], .running: [.received, .quarantined, .jobFailed],
                .received: [.validated, .quarantined, .jobFailed], .validated: [], .quarantined: [],
                .jobFailed: [.running, .received]
            ]
            guard transitions[previous.state, default: []].contains(event.state),
                  previous.state != .jobFailed || previous.failure?.resumable == true else { throw JobFailure("invalid_transition") }
            if event.state == .validated && event.receiptRef != previous.receiptRef { throw JobFailure("changed_receipt_ref") }
        } else if event.state != .pending { throw JobFailure("missing_pending_job") }
        guard (event.state == .jobFailed) == (event.failure != nil) else { throw JobFailure("failure_detail_required") }
        if event.failure?.reason == .quota && event.failure?.resumable != true { throw JobFailure("quota_must_be_resumable") }
        if event.state == .quarantined && !ContractRules.refs(event.findingRefs) { throw JobFailure("finding_refs_required") }
        guard event.findingRefs.allSatisfy(ContractRules.localRef) else { throw JobFailure("invalid_finding_ref") }
        if [.received, .validated].contains(event.state) {
            guard let ref = event.receiptRef else { throw JobFailure("missing_session_receipt") }
            snapshot.receipts[id] = try loadReceipt(ref, binding: event.binding, base: base)
            let url = try localURL(ref, base: base)
            guard event.receiptHash == (try CKHash.sha256Hex(ofFileAt: url)) else { throw JobFailure("receipt_hash_mismatch") }
            if event.state == .validated, let previous = snapshot.events[id], event.receiptHash != previous.receiptHash {
                throw JobFailure("receipt_hash_mismatch")
            }
        } else if event.receiptRef != nil || event.receiptHash != nil { throw JobFailure("unexpected_receipt") }
        if event.state == .running && event.binding.promptHash == nil { throw JobFailure("blocked_prompts") }
        if event.state == .running && snapshot.events.values.filter({ $0.state == .running }).count >= 3 {
            throw JobFailure("parallel_limit")
        }
        if event.state == .validated { snapshot.acceptedKeys.insert(key) }
        snapshot.events[id] = event
    }
    public static func audit(at url: URL) throws -> JobSnapshot {
        var snapshot = JobSnapshot()
        for line in try CKJSONL.readLines(at: url) {
            let event = try decode(JobEvent.self, data: Data(line.utf8))
            try apply(event, to: &snapshot, base: url.deletingLastPathComponent())
        }
        return snapshot
    }
    public static func append(_ event: JobEvent, to url: URL) throws {
        let fd = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw JobFailure("ledger_open_failed") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw JobFailure("ledger_lock_failed") }
        defer { flock(fd, LOCK_UN) }
        var snapshot = try audit(at: url)
        var sealed = event
        if let ref = event.receiptRef {
            let receiptURL = try localURL(ref, base: url.deletingLastPathComponent())
            guard FileManager.default.fileExists(atPath: receiptURL.path) else { throw JobFailure("dangling_receipt") }
            let hash = try CKHash.sha256Hex(ofFileAt: receiptURL)
            guard event.receiptHash == nil || event.receiptHash == hash else { throw JobFailure("receipt_hash_mismatch") }
            sealed.receiptHash = hash
        }
        try apply(sealed, to: &snapshot, base: url.deletingLastPathComponent())
        try CKJSONL.appendLine(String(decoding: bytes(sealed), as: UTF8.self), to: url)
        guard fsync(fd) == 0 else { throw JobFailure("ledger_sync_failed") }
    }
    public static func resume(at url: URL, binding: JobBinding, receiptRef: String?) throws -> JobResume {
        let snapshot = try audit(at: url)
        guard let event = snapshot.events[binding.jobId] else { throw JobFailure("missing_pending_job") }
        guard event.binding == binding else { throw JobFailure("changed_input_receipt") }
        if event.state == .validated { return .alreadyAccepted }
        if event.state == .quarantined { return .blocked }
        if let ref = receiptRef ?? event.receiptRef {
            _ = try loadReceipt(ref, binding: binding, base: url.deletingLastPathComponent())
            return .receiptAvailable
        }
        switch event.state {
        case .pending: return .retryAllowed
        case .running: return .reconcileRunning
        case .jobFailed: return event.failure?.resumable == true ? .retryAllowed : .blocked
        case .received, .validated, .quarantined: return .blocked
        }
    }
}
