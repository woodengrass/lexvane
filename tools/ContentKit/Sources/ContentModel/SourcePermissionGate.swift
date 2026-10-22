import Foundation

public enum SourcePurpose: String, Codable, Sendable {
    case privatePreview = "private-preview"
    case production, distribution
}

public enum SourceGateReason: Equatable, Sendable {
    case permission(SourceOperation, PermissionStatus)
    case missingSource, missingAttribution, missingEvidence, cycle, duplicateSource, invalidAncestor
}

public struct SourceGateFailure: Error, Equatable, CustomStringConvertible, Sendable {
    public let sourceID: String
    public let purpose: SourcePurpose
    public let reason: SourceGateReason
    public var description: String {
        "SourceGateFailure(source_id=\(sourceID), purpose=\(purpose.rawValue), reason=\(reason))"
    }
}

public struct SourceGateApproval: Equatable, Sendable {
    public let sourceID: String
    public let purpose: SourcePurpose
    public let reason: String
    public let attributions: [String]
}

public enum SourcePermissionGate {
    /// Caller must supply every provenance edge and its actual operations. Registry
    /// validation resolves local evidence before this pure, offline authorization check.
    /// A private flag never changes an explicitly requested production/distribution purpose.
    public static func authorize(sourceID: String, purpose: SourcePurpose, registry: [SourceRecord],
                                 privatePreview: Bool = false) throws -> SourceGateApproval {
        try authorize(sourceID: sourceID, purpose: purpose, registry: registry, rootOperations: [], requirePack: true)
    }

    /// Owner decision 2026-10-22 (option B): a citation whose only operation is
    /// `reference` consults the source without copying its bytes into the pack, so it
    /// needs `reference` (and the ancestor chain's own operations) but no pack grant.
    public static func authorizeReference(sourceID: String, purpose: SourcePurpose,
                                          registry: [SourceRecord]) throws -> SourceGateApproval {
        try authorize(sourceID: sourceID, purpose: purpose, registry: registry, rootOperations: [.reference], requirePack: false)
    }

    /// True when a citation only consults the source (see `authorizeReference`).
    public static func isReferenceOnly(_ operations: [SourceOperation]) -> Bool {
        !operations.isEmpty && operations.allSatisfy { $0 == .reference }
    }

    private static func authorize(sourceID: String, purpose: SourcePurpose, registry: [SourceRecord],
                                  rootOperations: [SourceOperation], requirePack: Bool) throws -> SourceGateApproval {
        let packOperation: SourceOperation
        switch purpose {
        case .privatePreview: packOperation = .privatePack
        case .production, .distribution: packOperation = .distribution
        }
        var lookup: [String: SourceRecord] = [:]
        for row in registry {
            guard lookup.updateValue(row, forKey: row.sourceID) == nil else {
                throw SourceGateFailure(sourceID: row.sourceID, purpose: purpose, reason: .duplicateSource)
            }
        }
        var attributions: [String] = []
        var attributed = Set<String>()
        func visit(_ id: String, operations: [SourceOperation], path: Set<String>) throws {
            func fail(_ reason: SourceGateReason) -> SourceGateFailure {
                .init(sourceID: id, purpose: purpose, reason: reason)
            }
            guard !path.contains(id) else { throw fail(.cycle) }
            guard let row = lookup[id] else { throw fail(.missingSource) }
            guard !row.attribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw fail(.missingAttribution)
            }
            for operation in operations + (requirePack ? [packOperation] : []) {
                let permission = row.permission(for: operation)
                guard permission.status == .allowed else { throw fail(.permission(operation, permission.status)) }
                guard !permission.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !(permission.quote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !row.licenseTextRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw fail(.missingEvidence)
                }
            }
            if attributed.insert(id).inserted { attributions.append(row.attribution) }
            for edge in row.ancestors {
                guard !edge.sourceID.isEmpty, !edge.operations.isEmpty else { throw fail(.invalidAncestor) }
                try visit(edge.sourceID, operations: edge.operations, path: path.union([id]))
            }
        }
        try visit(sourceID, operations: rootOperations, path: [])
        return .init(sourceID: sourceID, purpose: purpose,
                     reason: requirePack ? "all_required_operations_allowed" : "reference_only_operations_allowed",
                     attributions: attributions)
    }
}
