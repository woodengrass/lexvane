import Foundation

public enum CoverageStatus: String, Codable {
    case mapped, ambiguous
    case notYetAuthored = "not_yet_authored"
    case rightsPending = "rights_pending"
}
public enum CoverageRowType: String, Codable {
    case sourcePending = "source_pending"
    case originalItem = "original_item"
    case alias
}
public struct ExtractedItem: Codable, Equatable {
    public let originalId: String
    public let page: Int
    public let line: Int
    public let term: String
    public let pos: String
    public let level: String
    public let aliasOf: String?
    public init(originalId: String, page: Int, line: Int, term: String, pos: String, level: String, aliasOf: String? = nil) {
        self.originalId = originalId; self.page = page; self.line = line; self.term = term
        self.pos = pos; self.level = level; self.aliasOf = aliasOf
    }
}
public struct ExtractionLine: Codable, Equatable {
    public let page: Int
    public let line: Int
    public let text: String
    public let reason: String
    public init(page: Int, line: Int, text: String, reason: String) {
        self.page = page; self.line = line; self.text = text; self.reason = reason
    }
}
public struct ExtractionAudit: Codable {
    public let contentHash: String
    public let parseRule: String
    public let pageCount: Int
    public let lineCount: Int
    public let items: [ExtractedItem]
    public let ignoredLines: [ExtractionLine]
    public let fieldMapping: [String]
    public var complete: Bool
    public let parsedItemCount: Int
    public let originalItemCount: Int
    public init(contentHash: String, parseRule: String, pageCount: Int, lineCount: Int, items: [ExtractedItem],
                ignoredLines: [ExtractionLine], fieldMapping: [String], complete: Bool) {
        self.contentHash = contentHash; self.parseRule = parseRule; self.pageCount = pageCount; self.lineCount = lineCount
        self.items = items; self.ignoredLines = ignoredLines; self.fieldMapping = fieldMapping; self.complete = complete
        self.parsedItemCount = items.count; self.originalItemCount = items.filter { $0.aliasOf == nil }.count
    }
}
public struct CoverageHeader: Codable {
    public let recordType: String
    public let sourceVersion: String
    public let url: String
    public let cutoff: String
    public let inventoryRefs: [String]
    public let parseRule: String
    public var contentHash: String?
    public var denominator: Int?
    public var extractionAudit: ExtractionAudit?
    public var status: CoverageStatus
    public var complete: Bool
}
public struct CoverageRow: Codable {
    public let recordType: CoverageRowType
    public let sourceVersion: String
    public let item: ExtractedItem?
    public var entryId: String?
    public var status: CoverageStatus
    public var qualifiedActiveTarget: Bool
    public let reason: String
    public let evidenceRefs: [String]
}
public struct CoverageAuditReport: Codable {
    public let valid: Bool
    public let mappingBlocked: Bool
    public let materialComplete: Bool
    public let denominator: Int?
    public let denominatorState: String
    public let originalRowCount: Int
    public let aliasCount: Int
    public let mappedHeadwords: Int
    public let rightsPendingCount: Int
    public let notYetAuthoredCount: Int
    public let qualifiedActiveTargetCount: Int
    enum CodingKeys: String, CodingKey {
        case valid, mappingBlocked, materialComplete, denominator, denominatorState, originalRowCount, aliasCount
        case mappedHeadwords, rightsPendingCount, notYetAuthoredCount, qualifiedActiveTargetCount
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(valid, forKey: .valid); try values.encode(mappingBlocked, forKey: .mappingBlocked)
        try values.encode(materialComplete, forKey: .materialComplete); try values.encode(denominator, forKey: .denominator)
        try values.encode(denominatorState, forKey: .denominatorState); try values.encode(originalRowCount, forKey: .originalRowCount)
        try values.encode(aliasCount, forKey: .aliasCount); try values.encode(mappedHeadwords, forKey: .mappedHeadwords)
        try values.encode(rightsPendingCount, forKey: .rightsPendingCount); try values.encode(notYetAuthoredCount, forKey: .notYetAuthoredCount)
        try values.encode(qualifiedActiveTargetCount, forKey: .qualifiedActiveTargetCount)
    }
}
public enum CoverageMap {
    public static func read(at url: URL) throws -> (CoverageHeader, [CoverageRow]) {
        let lines = try CKJSONL.readLines(at: url)
        guard let first = lines.first else { throw IdentityFailure("missing_coverage_header") }
        return try (CKIdentityJSON.decode(CoverageHeader.self, line: first),
                    lines.dropFirst().map { try CKIdentityJSON.decode(CoverageRow.self, line: $0) })
    }
    public static func audit(header: CoverageHeader, rows: [CoverageRow], identities: IdentitySnapshot) throws -> CoverageAuditReport {
        guard header.recordType == "header", !header.sourceVersion.isEmpty, !header.parseRule.isEmpty,
              URL(string: header.url)?.scheme == "https", !header.cutoff.isEmpty, !header.inventoryRefs.isEmpty,
              header.inventoryRefs.allSatisfy({ !$0.isEmpty }) else { throw IdentityFailure("invalid_coverage_header") }
        let pending = header.status == .rightsPending
        if pending {
            guard header.contentHash == nil, header.extractionAudit == nil, header.denominator == nil,
                  !header.complete else { throw IdentityFailure("pending_material_cannot_claim_counts") }
        } else {
            guard let extraction = header.extractionAudit, let contentHash = header.contentHash,
                  CKIdentityJSON.hashValid(contentHash), extraction.contentHash == contentHash,
                  extraction.parseRule == header.parseRule, extraction.pageCount > 0,
                  extraction.parsedItemCount == extraction.items.count,
                  extraction.originalItemCount == extraction.items.filter({ $0.aliasOf == nil }).count,
                  !extraction.items.isEmpty, Set(extraction.fieldMapping) == Set(["term", "pos", "level"]),
                  extraction.lineCount == extraction.items.count + extraction.ignoredLines.count,
                  Set(extraction.items.map(\.originalId)).count == extraction.items.count,
                  header.complete == extraction.complete else { throw IdentityFailure("invalid_extraction_lock") }
            guard header.denominator == extraction.originalItemCount else { throw IdentityFailure("fabricated_denominator") }
            guard rows.compactMap(\.item).sorted(by: { $0.originalId < $1.originalId }) == extraction.items.sorted(by: { $0.originalId < $1.originalId }),
                  rows.allSatisfy({ $0.recordType != .sourcePending }) else { throw IdentityFailure("truncated_or_changed_extraction") }
            guard header.complete else { throw IdentityFailure("incomplete_extraction_requires_manual_review") }
        }
        var seen = Set<String>()
        let originalIds = Set(rows.filter { $0.recordType == .originalItem }.compactMap { $0.item?.originalId })
        for row in rows {
            guard row.sourceVersion == header.sourceVersion, !row.reason.isEmpty, !row.evidenceRefs.isEmpty,
                  row.evidenceRefs.allSatisfy({ !$0.isEmpty }) else { throw IdentityFailure("invalid_mapping_evidence") }
            switch row.recordType {
            case .sourcePending:
                guard pending, row.item == nil, row.entryId == nil, row.status == .rightsPending,
                      !row.qualifiedActiveTarget else { throw IdentityFailure("fabricated_pending_item") }
                guard seen.insert(row.evidenceRefs.joined(separator: "|")).inserted else { throw IdentityFailure("duplicate_mapping_row") }
            case .originalItem, .alias:
                guard !pending, let item = row.item, seen.insert(item.originalId).inserted,
                      item.page > 0, item.page <= (header.extractionAudit?.pageCount ?? 0), item.line > 0,
                      !item.term.isEmpty, !item.pos.isEmpty, !item.level.isEmpty else { throw IdentityFailure("invalid_original_locator") }
                switch row.recordType {
                case .alias:
                    guard let aliasOf = item.aliasOf, originalIds.contains(aliasOf), aliasOf != item.originalId,
                          !row.qualifiedActiveTarget else { throw IdentityFailure("alias_inflation") }
                case .originalItem:
                    guard item.aliasOf == nil else { throw IdentityFailure("alias_inflation") }
                case .sourcePending: break
                }
            }
            switch row.status {
            case .mapped:
                guard let id = row.entryId, let entry = identities.records[id], [.word, .phrase].contains(entry.kind),
                      !identities.retiredIds.contains(id) else { throw IdentityFailure("unknown_or_retired_entry") }
            case .ambiguous, .notYetAuthored, .rightsPending:
                guard row.entryId == nil, !row.qualifiedActiveTarget else { throw IdentityFailure("unwritten_active_target") }
            }
            if row.recordType == .alias, row.status == .mapped {
                guard let parent = rows.first(where: { $0.item?.originalId == row.item?.aliasOf }),
                      parent.status == .mapped, parent.entryId == row.entryId else { throw IdentityFailure("alias_mapping_conflict") }
            }
        }
        guard !pending || !rows.isEmpty else { throw IdentityFailure("missing_pending_source_evidence") }
        let originals = rows.filter { $0.recordType == .originalItem }
        return CoverageAuditReport(valid: true, mappingBlocked: pending, materialComplete: header.complete,
            denominator: header.denominator, denominatorState: pending ? "rights_pending-unknown" : "locked_extraction",
            originalRowCount: originals.count, aliasCount: rows.filter { $0.recordType == .alias }.count,
            mappedHeadwords: originals.filter { $0.status == .mapped }.count,
            rightsPendingCount: rows.filter { $0.status == .rightsPending }.count,
            notYetAuthoredCount: originals.filter { $0.status == .notYetAuthored }.count,
            qualifiedActiveTargetCount: originals.filter(\.qualifiedActiveTarget).count)
    }
}
