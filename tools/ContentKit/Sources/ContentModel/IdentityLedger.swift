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
public enum IdentityOperation: String, Codable { case issue, revise, split, merge }
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
            switch event.operation {
            case .issue:
                guard event.records.count == 1, event.predecessors.isEmpty else { throw IdentityFailure("invalid_issue") }
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
                let parts = record.id.split(separator: ":")
                guard parts.count == 3, parts[0] == "lx", parts[1] == record.kind.rawValue,
                      UUID(uuidString: String(parts[2])) != nil, !record.issuanceKey.isEmpty,
                      CKIdentityJSON.hashValid(record.contentHash), CKIdentityJSON.hashValid(record.semanticHash),
                      Set(record.vendorIds).count == record.vendorIds.count else { throw IdentityFailure("invalid_record") }
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
        var sealed = event; sealed.eventHash = try digest(event)
        _ = try replay(events + [sealed])
        let length = try handle.seekToEnd()
        if length > 0 {
            try handle.seek(toOffset: length - 1)
            guard try handle.read(upToCount: 1) == Data([10]) else { throw IdentityFailure("unterminated_ledger") }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: Data((try CKIdentityJSON.line(sealed) + "\n").utf8))
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
