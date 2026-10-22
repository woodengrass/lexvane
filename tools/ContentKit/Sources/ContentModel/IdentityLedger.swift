import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

public struct IdentityFailure: Error, CustomStringConvertible, Equatable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var description: String { "IdentityFailure(reason=\(reason))" }
}
public enum IdentityKind: String, Codable, CaseIterable { case word, phrase, sense, usage, target, question, family }
public enum IdentityBasis: String, Codable { case coordinator, translation }
public enum IdentityOperation: String, Codable { case issue, registerExisting, revise, split, merge }
public struct IdentityDraft {
    public var kind: IdentityKind
    public var issuanceKey: String
    public var contentHash: String
    public var semanticHash: String
    public var vendorIds: [String]
    public var basis: IdentityBasis
    public init(kind: IdentityKind, issuanceKey: String, contentHash: String, semanticHash: String, vendorIds: [String], basis: IdentityBasis = .coordinator) {
        self.kind = kind; self.issuanceKey = issuanceKey; self.contentHash = contentHash
        self.semanticHash = semanticHash; self.vendorIds = vendorIds; self.basis = basis
    }
}
public struct IdentityRecord: Codable, Equatable {
    public let id: String
    public let kind: IdentityKind
    public let issuanceKey: String
    public let revision: Int
    public let contentHash: String
    public let semanticHash: String
    public let vendorIds: [String]
}
public struct IdentityRevision {
    public let id: String
    public let contentHash: String
    public let semanticHash: String
    public let vendorIds: [String]
    public init(id: String, contentHash: String, semanticHash: String, vendorIds: [String]) {
        self.id = id; self.contentHash = contentHash; self.semanticHash = semanticHash; self.vendorIds = vendorIds
    }
}
/// A document observed at adoption time, not an assertion about historical issuance.
public struct IdentityObservation: Codable, Equatable {
    public let recordId: String
    public let revision: Int
    public let contentSha256: String
    public init(recordId: String, revision: Int, contentSha256: String) {
        self.recordId = recordId; self.revision = revision; self.contentSha256 = contentSha256
    }
}
public struct IdentityRegistration {
    public let id: String
    public let draft: IdentityDraft
    public let observations: [IdentityObservation]
    public let reason: String
    public let evidenceRefs: [String]
    public init(id: String, draft: IdentityDraft, observations: [IdentityObservation], reason: String, evidenceRefs: [String]) {
        self.id = id; self.draft = draft; self.observations = observations
        self.reason = reason; self.evidenceRefs = evidenceRefs
    }
}
public struct IdentityTransition {
    public let operation: IdentityOperation
    public let predecessors: [String]
    public let successors: [IdentityDraft]
    public let reason: String
    public let evidenceRefs: [String]
    public init(operation: IdentityOperation, predecessors: [String], successors: [IdentityDraft], reason: String, evidenceRefs: [String]) {
        self.operation = operation; self.predecessors = predecessors; self.successors = successors
        self.reason = reason; self.evidenceRefs = evidenceRefs
    }
}
public struct IdentityEvent: Codable {
    public let sequence: Int
    public let previousHash: String?
    public var eventHash: String
    public let operation: IdentityOperation
    public let records: [IdentityRecord]
    public let predecessors: [String]
    public let reason: String
    public let evidenceRefs: [String]
    // Nil on historical events, so their canonical hash payload remains byte-compatible.
    public var observations: [IdentityObservation]? = nil
}
public struct IdentitySnapshot {
    public var records: [String: IdentityRecord] = [:]
    public var retiredIds: Set<String> = []
    public var eventCount = 0
    public var terminalHash: String?
    public static var empty: Self { Self() }
}
public enum CKIdentityJSON {
    public static func line<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    public static func decode<T: Decodable>(_ type: T.Type, line: String) throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(line.utf8))
    }
    public static func hashValid(_ hash: String) -> Bool {
        hash.count == 64 && hash.allSatisfy { "0123456789abcdef".contains($0) }
    }
}
public enum IdentityLedger {
    public static func audit(at url: URL) throws -> IdentitySnapshot { try replay(read(at: url)) }
    private static func read(at url: URL) throws -> [IdentityEvent] {
        try CKJSONL.readLines(at: url).map { try CKIdentityJSON.decode(IdentityEvent.self, line: $0) }
    }
    private static func digest(_ event: IdentityEvent) throws -> String {
        var payload = event; payload.eventHash = ""
        return CKHash.sha256Hex(of: Data(try CKIdentityJSON.line(payload).utf8))
    }
    private static func replay(_ events: [IdentityEvent]) throws -> IdentitySnapshot {
        var state = IdentitySnapshot.empty; var keys = Set<String>()
        for event in events {
            guard event.sequence == state.eventCount + 1, event.previousHash == state.terminalHash,
                  try event.eventHash == digest(event) else { throw IdentityFailure("broken_append_chain") }
            guard !event.records.isEmpty else { throw IdentityFailure("empty_event") }
            guard event.operation == .registerExisting || event.observations == nil else {
                throw IdentityFailure("unexpected_registration_evidence")
            }
            switch event.operation {
            case .issue:
                guard event.records.count == 1, event.predecessors.isEmpty else { throw IdentityFailure("invalid_issue") }
            case .registerExisting:
                guard event.records.count == 1, event.predecessors.isEmpty else { throw IdentityFailure("invalid_registration") }
                try validateRegistrationEvidence(event)
            case .revise:
                guard event.records.count == 1, event.predecessors.isEmpty else { throw IdentityFailure("invalid_revision") }
            case .split, .merge:
                let split = event.operation == .split
                guard (split ? event.predecessors.count == 1 && event.records.count >= 2 : event.predecessors.count >= 2 && event.records.count == 1),
                      Set(event.predecessors).count == event.predecessors.count, !event.reason.isEmpty,
                      !event.evidenceRefs.isEmpty, event.evidenceRefs.allSatisfy({ !$0.isEmpty }),
                      event.predecessors.allSatisfy({ state.records[$0] != nil && !state.retiredIds.contains($0) }),
                      Set(event.predecessors.compactMap { state.records[$0]?.kind }).count == 1,
                      event.records.allSatisfy({ $0.kind == state.records[event.predecessors[0]]?.kind }) else {
                    throw IdentityFailure("invalid_transition")
                }
                state.retiredIds.formUnion(event.predecessors)
            }
            for record in event.records {
                try validateRecord(record)
                if event.operation == .revise {
                    guard let old = state.records[record.id], !state.retiredIds.contains(record.id),
                          old.kind == record.kind, old.issuanceKey == record.issuanceKey,
                          old.revision + 1 == record.revision else { throw IdentityFailure("invalid_revision") }
                    guard old.semanticHash == record.semanticHash else { throw IdentityFailure("semantic_change_requires_mapping") }
                } else {
                    guard state.records[record.id] == nil, keys.insert(record.issuanceKey).inserted,
                          record.revision == 1 else { throw IdentityFailure("duplicate_identity") }
                }
                state.records[record.id] = record
            }
            state.eventCount += 1; state.terminalHash = event.eventHash
        }
        return state
    }
    private static func validateRecord(_ record: IdentityRecord) throws {
        let parts = record.id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "lx", parts[1] == record.kind.rawValue,
              UUID(uuidString: String(parts[2])) != nil,
              !record.issuanceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              CKIdentityJSON.hashValid(record.contentHash), CKIdentityJSON.hashValid(record.semanticHash),
              Set(record.vendorIds).count == record.vendorIds.count else { throw IdentityFailure("invalid_record") }
    }
    private static func validateRegistrationEvidence(_ event: IdentityEvent) throws {
        func nonblank(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard nonblank(event.reason), !event.evidenceRefs.isEmpty, event.evidenceRefs.allSatisfy(nonblank),
              Set(event.evidenceRefs).count == event.evidenceRefs.count,
              let observations = event.observations, !observations.isEmpty,
              Set(observations.map(\.recordId)).count == observations.count,
              observations.allSatisfy({ nonblank($0.recordId) && $0.revision > 0 && CKIdentityJSON.hashValid($0.contentSha256) }) else {
            throw IdentityFailure("invalid_registration_evidence")
        }
    }
    private static func record(_ draft: IdentityDraft) throws -> IdentityRecord {
        switch draft.basis {
        case .translation: throw IdentityFailure("translation_cannot_be_identity")
        case .coordinator: break
        }
        return IdentityRecord(id: "lx:\(draft.kind.rawValue):\(UUID().uuidString.lowercased())", kind: draft.kind,
            issuanceKey: draft.issuanceKey, revision: 1, contentHash: draft.contentHash, semanticHash: draft.semanticHash, vendorIds: draft.vendorIds)
    }
    private static func transaction<T>(at url: URL, action: ([IdentityEvent], IdentitySnapshot, FileHandle) throws -> T) throws -> T {
        let descriptor = open(url.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw IdentityFailure("open_failed") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { do { try handle.close() } catch { fputs("IdentityFailure(reason=close_failed)\n", stderr) } }
        guard flock(handle.fileDescriptor, LOCK_EX) == 0 else { throw IdentityFailure("lock_failed") }
        let events = try read(at: url)
        return try action(events, replay(events), handle)
    }
    private static func append(_ event: IdentityEvent, events: [IdentityEvent], handle: FileHandle) throws {
        try append([event], events: events, handle: handle)
    }
    private static func append(_ pending: [IdentityEvent], events: [IdentityEvent], handle: FileHandle) throws {
        guard !pending.isEmpty else { return }
        let sealed = try pending.map { event in
            var value = event; value.eventHash = try digest(event); return value
        }
        _ = try replay(events + sealed)
        let length = try handle.seekToEnd()
        if length > 0 {
            try handle.seek(toOffset: length - 1)
            guard try handle.read(upToCount: 1) == Data([10]) else { throw IdentityFailure("unterminated_ledger") }
            try handle.seekToEnd()
        }
        let lines = try sealed.map { try CKIdentityJSON.line($0) + "\n" }.joined()
        try handle.write(contentsOf: Data(lines.utf8))
        try handle.synchronize()
    }
    public static func issue(_ draft: IdentityDraft, at url: URL) throws -> IdentityRecord {
        let candidate = try record(draft)
        return try transaction(at: url) { events, state, handle in
            if let old = state.records.values.first(where: { $0.issuanceKey == draft.issuanceKey }) {
                guard old.kind == draft.kind, old.semanticHash == draft.semanticHash else { throw IdentityFailure("issuance_key_conflict") }
                return old
            }
            let event = IdentityEvent(sequence: state.eventCount + 1, previousHash: state.terminalHash, eventHash: "",
                operation: .issue, records: [candidate], predecessors: [], reason: "coordinator_issuance", evidenceRefs: [])
            try append(event, events: events, handle: handle)
            return candidate
        }
    }
    /// Adopt an already assigned opaque ID. Ledger revision 1 means adoption now;
    /// source document revisions are retained separately in observations.
    public static func registerExisting(_ registration: IdentityRegistration, at url: URL) throws -> IdentityRecord {
        try registerExisting([registration], at: url)[0]
    }
    /// Validate a whole adoption batch under one lock before appending any of it.
    public static func registerExisting(_ registrations: [IdentityRegistration], at url: URL) throws -> [IdentityRecord] {
        return try transaction(at: url) { events, state, handle in
            var current = state
            var keys = Set(state.records.values.map(\.issuanceKey))
            var adoptions: [String: IdentityEvent] = [:]
            for event in events where event.operation == .registerExisting {
                adoptions[event.records[0].id] = event
            }
            var pending: [IdentityEvent] = []; var result: [IdentityRecord] = []
            for registration in registrations {
                guard registration.draft.basis == .coordinator else { throw IdentityFailure("translation_cannot_be_identity") }
                let draft = registration.draft
                let candidate = IdentityRecord(id: registration.id, kind: draft.kind, issuanceKey: draft.issuanceKey,
                    revision: 1, contentHash: draft.contentHash, semanticHash: draft.semanticHash, vendorIds: draft.vendorIds)
                try validateRecord(candidate)
                var event = IdentityEvent(sequence: current.eventCount + 1, previousHash: current.terminalHash, eventHash: "",
                    operation: .registerExisting, records: [candidate], predecessors: [], reason: registration.reason,
                    evidenceRefs: registration.evidenceRefs, observations: registration.observations)
                try validateRegistrationEvidence(event)
                guard !current.retiredIds.contains(candidate.id) else { throw IdentityFailure("unknown_or_retired_identity") }
                if let old = current.records[candidate.id] {
                    guard old == candidate, let adoption = adoptions[candidate.id],
                          adoption.reason == event.reason, adoption.evidenceRefs == event.evidenceRefs,
                          adoption.observations == event.observations else { throw IdentityFailure("registration_conflict") }
                    result.append(old); continue
                }
                guard keys.insert(candidate.issuanceKey).inserted else { throw IdentityFailure("issuance_key_conflict") }
                event.eventHash = try digest(event)
                pending.append(event); adoptions[candidate.id] = event; result.append(candidate)
                current.records[candidate.id] = candidate
                current.eventCount += 1; current.terminalHash = event.eventHash
            }
            try append(pending, events: events, handle: handle)
            return result
        }
    }
    public static func revise(_ revision: IdentityRevision, at url: URL) throws -> IdentityRecord {
        try transaction(at: url) { events, state, handle in
            guard let old = state.records[revision.id], !state.retiredIds.contains(old.id) else { throw IdentityFailure("unknown_or_retired_identity") }
            guard old.semanticHash == revision.semanticHash else { throw IdentityFailure("semantic_change_requires_mapping") }
            if old.contentHash == revision.contentHash && old.vendorIds == revision.vendorIds { return old }
            let updated = IdentityRecord(id: old.id, kind: old.kind, issuanceKey: old.issuanceKey, revision: old.revision + 1,
                contentHash: revision.contentHash, semanticHash: revision.semanticHash, vendorIds: revision.vendorIds)
            try append(IdentityEvent(sequence: state.eventCount + 1, previousHash: state.terminalHash, eventHash: "", operation: .revise,
                records: [updated], predecessors: [], reason: "text_or_vendor_revision", evidenceRefs: []), events: events, handle: handle)
            return updated
        }
    }
    public static func transition(_ transition: IdentityTransition, at url: URL) throws -> [IdentityRecord] {
        let successors = try transition.successors.map(record)
        return try transaction(at: url) { events, state, handle in
            guard [.split, .merge].contains(transition.operation) else { throw IdentityFailure("invalid_transition") }
            if let old = events.first(where: { $0.records.map(\.issuanceKey) == successors.map(\.issuanceKey) }) {
                guard old.operation == transition.operation, old.predecessors == transition.predecessors,
                      old.records.map(\.semanticHash) == successors.map(\.semanticHash),
                      old.records.map(\.kind) == successors.map(\.kind), old.reason == transition.reason,
                      old.evidenceRefs == transition.evidenceRefs else { throw IdentityFailure("issuance_key_conflict") }
                return old.records
            }
            try append(IdentityEvent(sequence: state.eventCount + 1, previousHash: state.terminalHash, eventHash: "",
                operation: transition.operation, records: successors, predecessors: transition.predecessors,
                reason: transition.reason, evidenceRefs: transition.evidenceRefs), events: events, handle: handle)
            return successors
        }
    }
}
