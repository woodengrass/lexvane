import Foundation

public struct ContractFailure: Error, CustomStringConvertible {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var description: String { "ContractFailure(reason=\(reason))" }
}
public enum ContractKind: String, Codable, CaseIterable, Sendable {
    case entry, sense, target, teaching, question, provenance, review, manifest
}
public enum ContentStatus: String, Codable { case candidate, approved, quarantined }
public enum TestedAbility: String, Codable, CaseIterable {
    case contextualChoice = "contextual_choice"
    case meaningRecognition = "meaning_recognition"
    case writing
}
public enum FamilySplit: String, Codable { case train, check }
public enum PriorityTier: String, Codable { case foundational, supplementary, deferred }
public enum PartOfSpeech: String, Codable {
    case noun, verb, adjective, adverb, pronoun, preposition, conjunction, determiner, interjection
}
public struct ContractSourceRef: Codable {
    public let sourceId: String
    public let operations: [SourceOperation]
    public var ancestor: SourceAncestor { .init(sourceID: sourceId, operations: operations) }
}
public protocol ContractPayload: Codable {
    static var kind: ContractKind { get }
    func validate(recordId: String) throws
}
public protocol ContractDocumentInfo: Encodable {
    var kind: ContractKind { get }
    var recordId: String { get }
    var revision: Int { get }
    var contentSha256: String { get }
    func revisionHash() throws -> String
}
public struct ContentDocument<Payload: ContractPayload>: Codable, ContractDocumentInfo {
    public let schema: String
    public let kind: ContractKind
    public let recordId: String
    public let revision: Int
    public var contentSha256: String
    public let payload: Payload
    enum CodingKeys: String, CodingKey { case schema, kind, recordId, revision, contentSha256, payload }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema)
        try ContractRules.require(schema == "lexvane.content.v1", "unknown_schema")
        kind = try c.decode(ContractKind.self, forKey: .kind)
        try ContractRules.require(kind == Payload.kind, "kind_mismatch")
        recordId = try c.decode(String.self, forKey: .recordId)
        revision = try c.decode(Int.self, forKey: .revision)
        contentSha256 = try c.decode(String.self, forKey: .contentSha256)
        payload = try c.decode(Payload.self, forKey: .payload)
        try ContractRules.require(revision > 0 && ContractRules.present(recordId), "invalid_revision_or_id")
        let raw = try JSONShape(from: decoder)
        try raw.checkKeys(against: JSONDecoder().decode(JSONShape.self, from: ContractJSON.bytes(self)))
        try payload.validate(recordId: recordId)
        if decoder.userInfo[ContractJSON.sealingKey] as? Bool == true {
            contentSha256 = try revisionHash()
        } else {
            try ContractRules.require(CKIdentityJSON.hashValid(contentSha256), "invalid_hash")
            try ContractRules.require(contentSha256 == revisionHash(), "hash_mismatch")
        }
    }
    public func revisionHash() throws -> String {
        var unsigned = self; unsigned.contentSha256 = ""
        return try CKHash.sha256Hex(of: ContractJSON.bytes(unsigned))
    }
}
public enum ContractRules {
    public static func require(_ condition: Bool, _ reason: String) throws {
        if !condition { throw ContractFailure(reason) }
    }
    public static func present(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public static func refs(_ values: [String]) -> Bool {
        !values.isEmpty && values.allSatisfy(present) && Set(values).count == values.count
    }
    public static func id(_ value: String, _ kinds: [IdentityKind]) throws {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        try require(parts.count == 3 && parts[0] == "lx" && kinds.contains(where: { $0.rawValue == parts[1] })
            && UUID(uuidString: String(parts[2])) != nil, "invalid_identity:\(value)")
    }
    public static func sourceRefs(_ refs: [ContractSourceRef]) throws {
        try require(!refs.isEmpty && refs.allSatisfy { present($0.sourceId) && !$0.operations.isEmpty
            && Set($0.operations).count == $0.operations.count }, "source_refs_required")
    }
    public static func localRef(_ ref: String) -> Bool {
        present(ref) && !ref.hasPrefix("/") && !ref.contains(":") && !ref.split(separator: "/").contains("..")
    }
}

// A raw JSON tree is used only to reject unmodeled keys, never as validated content.
indirect enum JSONShape: Decodable {
    case object([String: JSONShape]), array([JSONShape]), scalar
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let object = try? c.decode([String: JSONShape].self) { self = .object(object) }
        else if let array = try? c.decode([JSONShape].self) { self = .array(array) }
        else { self = .scalar }
    }
    func checkKeys(against expected: JSONShape) throws {
        switch (self, expected) {
        case (.object(let raw), .object(let modeled)):
            let extra = Set(raw.keys).subtracting(modeled.keys)
            try ContractRules.require(extra.isEmpty, "unknown_field:\(extra.sorted().joined(separator: ","))")
            for (key, value) in raw { if let other = modeled[key] { try value.checkKeys(against: other) } }
        case (.array(let raw), .array(let modeled)):
            for (value, other) in zip(raw, modeled) { try value.checkKeys(against: other) }
        default: break
        }
    }
}
