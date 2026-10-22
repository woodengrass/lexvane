import Foundation

public enum SourceOperation: String, Codable, CaseIterable, Sendable {
    case reference, fetch, retain, extract, adapt
    case localAnalysis = "local_analysis"
    case privatePack = "private_pack"
    case distribution
}

public enum PermissionStatus: String, Codable, Sendable {
    case allowed, pending, rejected
}

/// Unknown states fail closed, never infer authorization from a URL or private use.
public struct SourcePermission: Codable, Equatable, Sendable {
    public var status: PermissionStatus
    public var evidence: String
    public var quote: String?

    public init(status: PermissionStatus, evidence: String, quote: String? = nil) {
        self.status = status; self.evidence = evidence; self.quote = quote
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent(String.self, forKey: .status)
        status = raw.flatMap(PermissionStatus.init(rawValue:)) ?? .pending
        evidence = try container.decode(String.self, forKey: .evidence)
        quote = try container.decodeIfPresent(String.self, forKey: .quote)
    }
}

/// A provenance edge records the actual operations used, not just a citation.
public struct SourceAncestor: Codable, Equatable, Sendable {
    public var sourceID: String
    public var operations: [SourceOperation]
    enum CodingKeys: String, CodingKey { case sourceID = "source_id", operations }
    public init(sourceID: String, operations: [SourceOperation]) {
        self.sourceID = sourceID; self.operations = operations
    }
}

public struct SourceRecord: Codable, Sendable {
    public var sourceID: String
    public var locator: String
    public var version: String
    public var publicationDate: String?
    public var effectiveFrom: Int?
    public var effectiveTo: Int?
    public var kind: String
    public var examYear: Int?
    public var retrievedAt: String
    public var contentSHA256: String?
    public var contentSHA256Reason: String?
    public var attribution: String
    public var licenseTextRef: String
    public var permissions: [String: SourcePermission]
    public var ancestors: [SourceAncestor]
    private var declaredSourceVersion: String?

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id", locator, version, publicationDate = "publication_date"
        case effectiveFrom = "effective_from", effectiveTo = "effective_to", kind, examYear = "exam_year"
        case retrievedAt = "retrieved_at", contentSHA256 = "content_sha256"
        case contentSHA256Reason = "content_sha256_reason", attribution, licenseTextRef = "license_text_ref"
        case permissions, ancestors, sourceVersion = "source_version"
    }

    public init(sourceID: String, locator: String, version: String, publicationDate: String?,
                effectiveFrom: Int?, effectiveTo: Int?, kind: String, examYear: Int?, retrievedAt: String,
                contentSHA256: String?, contentSHA256Reason: String?, attribution: String,
                licenseTextRef: String, permissions: [String: SourcePermission], ancestors: [SourceAncestor] = []) {
        self.sourceID = sourceID; self.locator = locator; self.version = version
        self.publicationDate = publicationDate; self.effectiveFrom = effectiveFrom; self.effectiveTo = effectiveTo
        self.kind = kind; self.examYear = examYear; self.retrievedAt = retrievedAt
        self.contentSHA256 = contentSHA256; self.contentSHA256Reason = contentSHA256Reason
        self.attribution = attribution; self.licenseTextRef = licenseTextRef
        self.permissions = permissions; self.ancestors = ancestors
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try c.decode(String.self, forKey: .sourceID)
        locator = try c.decode(String.self, forKey: .locator); version = try c.decode(String.self, forKey: .version)
        // Nullable fields must be present: missing is a malformed row, not an unknown value.
        publicationDate = try c.decode(String?.self, forKey: .publicationDate)
        effectiveFrom = try c.decode(Int?.self, forKey: .effectiveFrom)
        effectiveTo = try c.decode(Int?.self, forKey: .effectiveTo)
        kind = try c.decode(String.self, forKey: .kind); examYear = try c.decode(Int?.self, forKey: .examYear)
        retrievedAt = try c.decode(String.self, forKey: .retrievedAt)
        contentSHA256 = try c.decode(String?.self, forKey: .contentSHA256)
        contentSHA256Reason = try c.decodeIfPresent(String.self, forKey: .contentSHA256Reason)
        attribution = try c.decode(String.self, forKey: .attribution)
        licenseTextRef = try c.decode(String.self, forKey: .licenseTextRef)
        permissions = try c.decode([String: SourcePermission].self, forKey: .permissions)
        ancestors = try c.decodeIfPresent([SourceAncestor].self, forKey: .ancestors) ?? []
        declaredSourceVersion = try c.decode(String.self, forKey: .sourceVersion)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourceID, forKey: .sourceID); try c.encode(locator, forKey: .locator)
        try c.encode(version, forKey: .version); try c.encode(publicationDate, forKey: .publicationDate)
        try c.encode(effectiveFrom, forKey: .effectiveFrom); try c.encode(effectiveTo, forKey: .effectiveTo)
        try c.encode(kind, forKey: .kind); try c.encode(examYear, forKey: .examYear)
        try c.encode(retrievedAt, forKey: .retrievedAt); try c.encode(contentSHA256, forKey: .contentSHA256)
        try c.encode(contentSHA256Reason, forKey: .contentSHA256Reason)
        try c.encode(attribution, forKey: .attribution); try c.encode(licenseTextRef, forKey: .licenseTextRef)
        try c.encode(permissions, forKey: .permissions); try c.encode(ancestors, forKey: .ancestors)
        try c.encode(sourceVersionHash(), forKey: .sourceVersion)
    }

    /// SHA-256 of canonical sorted-key UTF-8 JSON, without escaped slashes.
    /// Retrieval time/rights changes do not masquerade as original-byte versions.
    public func sourceVersionHash() throws -> String {
        let fields: [String: Any] = [
            "source_id": sourceID, "locator": locator, "version": version, "kind": kind,
            "publication_date": publicationDate as Any? ?? NSNull(),
            "effective_from": effectiveFrom as Any? ?? NSNull(), "effective_to": effectiveTo as Any? ?? NSNull(),
            "exam_year": examYear as Any? ?? NSNull(), "content_sha256": contentSHA256 as Any? ?? NSNull()
        ]
        return CKHash.sha256Hex(of: try JSONSerialization.data(withJSONObject: fields,
                                                              options: [.sortedKeys, .withoutEscapingSlashes]))
    }

    public func permission(for operation: SourceOperation) -> SourcePermission {
        permissions[operation.rawValue] ?? .init(status: .pending, evidence: "")
    }

    public func validateStructure() throws {
        func require(_ condition: Bool, _ reason: String) throws {
            if !condition { throw SourceRegistryFailure(sourceID: sourceID, reason: reason) }
        }
        for (name, value) in [("source_id", sourceID), ("locator", locator), ("version", version),
                              ("kind", kind), ("attribution", attribution), ("license_text_ref", licenseTextRef)] {
            try require(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "missing_\(name)")
        }
        try require(ISO8601DateFormatter().date(from: retrievedAt) != nil, "invalid_retrieved_at")
        if let publicationDate {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            try require(formatter.date(from: publicationDate).map { formatter.string(from: $0) == publicationDate } ?? false,
                        "invalid_publication_date")
        }
        for year in [effectiveFrom, effectiveTo, examYear].compactMap({ $0 }) {
            try require(year > 0, "invalid_year")
        }
        if let from = effectiveFrom, let to = effectiveTo { try require(from <= to, "invalid_effective_range") }
        if let hash = contentSHA256 {
            try require(hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil, "invalid_content_sha256")
        } else {
            try require(!(contentSHA256Reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "missing_content_sha256_reason")
        }
        if let declaredSourceVersion { try require(declaredSourceVersion == sourceVersionHash(), "source_version_mismatch") }
        try require(Set(permissions.keys) == Set(SourceOperation.allCases.map(\.rawValue)), "incomplete_or_unknown_operations")
        for operation in SourceOperation.allCases {
            let permission = permission(for: operation)
            try require(!permission.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "missing_evidence:\(operation.rawValue)")
            if permission.status == .allowed {
                try require(!(permission.quote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            "missing_license_quote:\(operation.rawValue)")
            }
        }
        for edge in ancestors {
            try require(!edge.sourceID.isEmpty && !edge.operations.isEmpty, "invalid_ancestor_edge")
        }
    }
}

public struct SourceRegistryFailure: Error, Codable, CustomStringConvertible, Sendable {
    public var sourceID: String
    public var reason: String
    public init(sourceID: String, reason: String) { self.sourceID = sourceID; self.reason = reason }
    public var description: String { "SourceRegistryFailure(source_id=\(sourceID), purpose=registry_validation, reason=\(reason))" }
}

public struct SourceRegistryReport: Codable, Sendable {
    public let valid: Bool
    public let rowCount: Int
    public let privatePackAllowedCount: Int
    public let distributionAllowedCount: Int
    public let allSourcesUsable: Bool
    public let sourceVersions: [String: String]
}

public enum SourceRegistry {
    public static func read(at url: URL) throws -> [SourceRecord] {
        try CKJSONL.readLines(at: url).enumerated().map { index, line in
            do { return try JSONDecoder().decode(SourceRecord.self, from: Data(line.utf8)) }
            catch { throw SourceRegistryFailure(sourceID: "row:\(index + 1)", reason: "decode:\(error)") }
        }
    }

    public static func validate(at url: URL) throws -> SourceRegistryReport {
        let rows = try read(at: url)
        guard !rows.isEmpty else { throw SourceRegistryFailure(sourceID: "registry", reason: "empty_registry") }
        var versions: [String: String] = [:]
        let base = url.deletingLastPathComponent().resolvingSymlinksInPath()
        for row in rows {
            try row.validateStructure()
            guard versions[row.sourceID] == nil else {
                throw SourceRegistryFailure(sourceID: row.sourceID, reason: "duplicate_source_id")
            }
            versions[row.sourceID] = try row.sourceVersionHash()
            let refs = Set([row.licenseTextRef] + row.permissions.values.map(\.evidence))
            for ref in refs {
                // Evidence is local, relative, UTF-8 text; never fetch or execute source instructions.
                let path = base.appendingPathComponent(ref).resolvingSymlinksInPath().standardizedFileURL
                guard !ref.hasPrefix("/"), path.path.hasPrefix(base.path + "/"),
                      let text = try? String(contentsOf: path, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SourceRegistryFailure(sourceID: row.sourceID, reason: "missing_or_unsafe_evidence:\(ref)")
                }
                for permission in row.permissions.values where permission.status == .allowed && permission.evidence == ref {
                    guard let quote = permission.quote, text.contains(quote) else {
                        throw SourceRegistryFailure(sourceID: row.sourceID, reason: "license_quote_not_in_evidence:\(ref)")
                    }
                }
            }
        }
        // Validate graph integrity even for metadata-only/pending rows (no authorization implied).
        let lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0.sourceID, $0) })
        var visited = Set<String>()
        func visit(_ id: String, path: Set<String>) throws {
            guard !path.contains(id) else { throw SourceRegistryFailure(sourceID: id, reason: "ancestor_cycle") }
            guard let row = lookup[id] else { throw SourceRegistryFailure(sourceID: id, reason: "missing_ancestor") }
            if visited.contains(id) { return }
            for edge in row.ancestors { try visit(edge.sourceID, path: path.union([id])) }
            visited.insert(id)
        }
        for row in rows { try visit(row.sourceID, path: []) }
        // Count only chains the gate actually accepts, not merely allowed leaf flags.
        let privateCount = rows.filter {
            (try? SourcePermissionGate.authorize(sourceID: $0.sourceID, purpose: .privatePreview, registry: rows)) != nil
        }.count
        let distributionCount = rows.filter {
            (try? SourcePermissionGate.authorize(sourceID: $0.sourceID, purpose: .distribution, registry: rows)) != nil
        }.count
        return .init(valid: true, rowCount: rows.count, privatePackAllowedCount: privateCount,
                     distributionAllowedCount: distributionCount,
                     allSourcesUsable: distributionCount == rows.count, sourceVersions: versions)
    }
}
