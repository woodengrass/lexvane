import Foundation

/// Metadata inventory, deliberately independent of permission authorization.
/// A found URL is not evidence of permission, readable bytes, or reliable pagination.
public struct InventoryRow: Codable {
    public let id: String
    public let examYear: Int?
    public let kind: String
    public let variant: String
    public let revision: String
    public let url: String?
    public let indexRef: String
    public let status: String
    public let scope: String
    public let reliability: String
    public let originalQuestionNumbersReliable: Bool
    public let originalPageCountReliable: Bool
    public let publicationDate: String?
    public let effectiveFrom: Int?
    public let effectiveTo: Int?
    public let permissions: [String: String]
    public let rightsReason: String
    public let contentSHA256: String?
    public let duplicateOf: String?
    public let supersedes: [String]?
    public let correctionEvidence: [String]?
    public let officialEvidence: [String]?
    public let nonPublicationStatement: String?
    public let searchEvidence: [String]?

    enum CodingKeys: String, CodingKey {
        case id, kind, variant, revision, url, status, scope, reliability, permissions, supersedes
        case examYear = "exam_year", indexRef = "index_ref", publicationDate = "publication_date"
        case effectiveFrom = "effective_from", effectiveTo = "effective_to", rightsReason = "rights_reason"
        case contentSHA256 = "content_sha256", duplicateOf = "duplicate_of"
        case correctionEvidence = "correction_evidence", officialEvidence = "official_evidence", searchEvidence = "search_evidence"
        case originalQuestionNumbersReliable = "original_question_numbers_reliable", originalPageCountReliable = "original_page_count_reliable"
        case nonPublicationStatement = "non_publication_statement"
    }
}

public struct InventoryDiscovery: Codable {
    public struct Snapshot: Codable {
        public let url: String
        public let title: String
        public let retrievedAt: String
        public let snapshotSHA256: String
        public let hashBasis: String
        public let hrefs: [String]
        public let nonPublicationStatements: [String]?
        enum CodingKeys: String, CodingKey {
            case url, title, hrefs
            case retrievedAt = "retrieved_at", snapshotSHA256 = "snapshot_sha256", hashBasis = "hash_basis"
            case nonPublicationStatements = "non_publication_statements"
        }
    }
    public let retrievedAt: String
    public let cutoffDate: String
    public let cutoffYear: Int
    public let snapshots: [Snapshot]
    public let exclusions: [String: String]
    public let necessaryGaps: [String]
    enum CodingKeys: String, CodingKey {
        case snapshots, exclusions
        case retrievedAt = "retrieved_at", cutoffDate = "cutoff_date", cutoffYear = "cutoff_year", necessaryGaps = "necessary_gaps"
    }
}

public struct InventoryIssue: Codable {
    public let code: String
    public let subject: String
    public let detail: String
}

public struct InventoryAuditResult: Encodable {
    public let complete: Bool
    public let cutoffYear: Int
    public let fromYear: Int
    public let rowCount: Int
    public let snapshotCount: Int
    public let issues: [InventoryIssue]
    public let rightsPendingCount: Int
    public let originalFilesVerified: Bool
}

public enum InventoryAudit {
    public static let operations = ["reference", "fetch", "retain", "extract", "adapt", "local_analysis", "private_pack", "distribution"]

    public static func audit(rows: [InventoryRow], discovery: InventoryDiscovery, from: Int) -> InventoryAuditResult {
        var issues: [InventoryIssue] = []
        func issue(_ code: String, _ subject: String, _ detail: String) {
            issues.append(InventoryIssue(code: code, subject: subject, detail: detail))
        }
        func hashValid(_ value: String?) -> Bool {
            guard let value else { return false }
            return value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
        }
        func officialURL(_ value: String) -> Bool {
            guard let url = URL(string: value) else { return false }
            return url.scheme == "https" && ["ceec.edu.tw", "www.ceec.edu.tw"].contains(url.host ?? "")
        }
        let snapshotURLs = Set(discovery.snapshots.map(\.url))
        func evidenceValid(_ refs: [String]?) -> Bool {
            guard let refs, !refs.isEmpty else { return false }
            return refs.allSatisfy { snapshotURLs.contains($0) && officialURL($0) }
        }
        if from < 111 || from > discovery.cutoffYear || discovery.cutoffYear > 999 {
            issue("invalid_year_range", "discovery", "Expected 111 <= from <= fixed published cutoff <= 999")
        }
        if discovery.retrievedAt.isEmpty || discovery.cutoffDate.isEmpty || discovery.snapshots.isEmpty {
            issue("missing_snapshot", "discovery", "A fixed date and official index receipts are required")
        }
        for snapshot in discovery.snapshots {
            if !officialURL(snapshot.url) || snapshot.title.isEmpty || snapshot.retrievedAt.isEmpty || !hashValid(snapshot.snapshotSHA256) || snapshot.hashBasis != "metadata_projection" {
                issue("invalid_snapshot", snapshot.url, "Expected official metadata receipt with declared hash basis")
            }
        }
        for gap in discovery.necessaryGaps { issue("necessary_gap", "discovery", gap) }
        var byID: [String: InventoryRow] = [:]
        var tuples = Set<String>()
        for row in rows {
            if byID[row.id] != nil { issue("duplicate_id", row.id, "IDs must be unique") }
            byID[row.id] = row
            let key = "\(row.examYear.map(String.init) ?? "null")|\(row.kind)|\(row.variant)|\(row.revision)"
            if !tuples.insert(key).inserted { issue("duplicate_tuple", row.id, key) }
            if row.id.isEmpty || row.kind.isEmpty || row.variant.isEmpty || row.revision.isEmpty || row.scope != "gsat_english" || row.reliability.isEmpty || row.rightsReason.isEmpty {
                issue("invalid_row", row.id, "Required metadata, scope and rights reason must be explicit")
            }
            if !snapshotURLs.contains(row.indexRef) { issue("missing_index_receipt", row.id, row.indexRef) }
            if row.status == "found" && row.url == nil { issue("missing_found_url", row.id, "Found requires an observed href") }
            if row.status == "found", let url = row.url,
               !discovery.snapshots.contains(where: { $0.url == row.indexRef && $0.hrefs.contains(url) }) {
                issue("unobserved_found_href", row.id, "Found URL must occur in its captured index receipt")
            }
            if !["found", "not_found_after_search", "not_published", "unavailable"].contains(row.status) {
                issue("invalid_status", row.id, row.status)
            }
            if row.status == "not_published" {
                let statement = row.nonPublicationStatement ?? ""
                let quoted = !statement.isEmpty && discovery.snapshots.contains {
                    (row.officialEvidence ?? []).contains($0.url) && ($0.nonPublicationStatements ?? []).contains(statement)
                }
                if !evidenceValid(row.officialEvidence) || !quoted {
                    issue("unsupported_unpublished", row.id, "Requires an explicit official statement captured in its receipt, not just a search/index URL")
                }
            }
            if ["not_found_after_search", "unavailable"].contains(row.status) && !evidenceValid(row.searchEvidence) {
                issue("missing_search_evidence", row.id, "Missing/unavailable requires a captured search receipt")
            }
            if let start = row.effectiveFrom, let end = row.effectiveTo, start > end {
                issue("invalid_effective_range", row.id, "Publication date and applicability are distinct")
            }
            if operations.contains(where: { !["allowed", "pending", "rejected"].contains(row.permissions[$0] ?? "") }) {
                issue("invalid_permissions", row.id, "All eight operation states must be explicit")
            }
            if row.kind == "paper", row.variant.hasPrefix("general"), row.status == "found", let year = row.examYear, year > discovery.cutoffYear {
                issue("paper_after_cutoff", row.id, "Later publication belongs in the next inventory version")
            }
        }
        let accounted = Set(rows.compactMap(\.url))
        for snapshot in discovery.snapshots {
            for href in snapshot.hrefs where !accounted.contains(href) && (discovery.exclusions[href]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                issue("unaccounted_href", snapshot.url, href)
            }
        }
        if from >= 111 && from <= discovery.cutoffYear && discovery.cutoffYear <= 999 {
            for year in from...discovery.cutoffYear {
                for kind in ["paper", "answer_key"] {
                    let candidates = rows.filter { $0.examYear == year && $0.kind == kind && $0.variant.hasPrefix("general") }
                    if candidates.isEmpty { issue("missing_year_kind", "\(year):\(kind)", "No annual general-source row") }
                    else if !candidates.contains(where: { $0.status == "found" }) {
                        issue("necessary_source_missing", "\(year):\(kind)", "Evidenced missing is honest but not complete")
                    }
                }
            }
        }
        for row in rows {
            if let duplicate = row.duplicateOf {
                let verified = duplicate != row.id && hashValid(row.contentSHA256) && byID[duplicate]?.contentSHA256 == row.contentSHA256
                if !verified { issue("unverified_duplicate", row.id, "duplicate_of requires matching byte hashes") }
            }
            if let predecessors = row.supersedes, !predecessors.isEmpty {
                if !evidenceValid(row.correctionEvidence) { issue("missing_correction_evidence", row.id, "Supersession needs captured official notice") }
                for predecessor in predecessors {
                    guard let target = byID[predecessor] else {
                        issue("missing_predecessor", row.id, predecessor)
                        continue
                    }
                    if target.kind != row.kind || target.examYear != row.examYear || target.variant != row.variant {
                        issue("correction_scope_mismatch", row.id, predecessor)
                    }
                }
                var visiting = Set<String>()
                func cyclic(_ id: String) -> Bool {
                    if !visiting.insert(id).inserted { return true }
                    defer { visiting.remove(id) }
                    return (byID[id]?.supersedes ?? []).contains(where: cyclic)
                }
                if cyclic(row.id) { issue("correction_cycle", row.id, "Supersession must be acyclic") }
            }
        }
        return InventoryAuditResult(complete: issues.isEmpty, cutoffYear: discovery.cutoffYear, fromYear: from,
                                    rowCount: rows.count, snapshotCount: discovery.snapshots.count, issues: issues,
                                    rightsPendingCount: rows.filter { $0.permissions.values.contains("pending") }.count,
                                    originalFilesVerified: !rows.isEmpty && rows.allSatisfy { hashValid($0.contentSHA256) })
    }
}
