import Foundation

public enum ContractRecord: Encodable {
    case entry(Entry), sense(Sense), target(Target), teaching(Teaching)
    case question(Question), provenance(Provenance), review(Review), manifest(Manifest)
    public var document: any ContractDocumentInfo {
        switch self {
        case .entry(let v): v
        case .sense(let v): v
        case .target(let v): v
        case .teaching(let v): v
        case .question(let v): v
        case .provenance(let v): v
        case .review(let v): v
        case .manifest(let v): v
        }
    }
    public var recordId: String { document.recordId }
    public var contentSha256: String { document.contentSha256 }
    public func encode(to encoder: any Encoder) throws { try document.encode(to: encoder) }
}
public enum ContractJSON {
    static let sealingKey = CodingUserInfoKey(rawValue: "contract_sealing")!
    public static func bytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    public static func line(_ record: ContractRecord) throws -> Data {
        try bytes(record) + Data([10])
    }
    public static func revisionHash(_ record: ContractRecord) throws -> String { try record.document.revisionHash() }
    public static func decode(_ data: Data) throws -> ContractRecord { try load(data, sealing: false) }
    public static func seal(_ data: Data) throws -> ContractRecord { try load(data, sealing: true) }
    private struct Header: Decodable { let schema: String; let kind: ContractKind }
    private static func load(_ data: Data, sealing: Bool) throws -> ContractRecord {
        guard let text = String(data: data, encoding: .utf8) else { throw ContractFailure("invalid_utf8") }
        try ContractRules.require(!data.contains(13) && !text.hasPrefix("\u{feff}")
            && !text.dropLast(text.hasSuffix("\n") ? 1 : 0).contains("\n"), "invalid_line")
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.userInfo[sealingKey] = sealing
        do {
            let header = try decoder.decode(Header.self, from: data)
            try ContractRules.require(header.schema == "lexvane.content.v1", "unknown_schema")
            switch header.kind {
            case .entry: return .entry(try decoder.decode(Entry.self, from: data))
            case .sense: return .sense(try decoder.decode(Sense.self, from: data))
            case .target: return .target(try decoder.decode(Target.self, from: data))
            case .teaching: return .teaching(try decoder.decode(Teaching.self, from: data))
            case .question: return .question(try decoder.decode(Question.self, from: data))
            case .provenance: return .provenance(try decoder.decode(Provenance.self, from: data))
            case .review: return .review(try decoder.decode(Review.self, from: data))
            case .manifest: return .manifest(try decoder.decode(Manifest.self, from: data))
            }
        } catch let failure as ContractFailure { throw failure }
        catch { throw ContractFailure("decode:\(error)") }
    }
}
