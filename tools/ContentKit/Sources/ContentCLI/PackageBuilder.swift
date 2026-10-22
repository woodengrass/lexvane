import ContentModel
import Foundation

struct PackageFailure: Error, Equatable, CustomStringConvertible {
    let reason: String
    var description: String { "PackageFailure(reason=\(reason))" }
}

struct PackageSource: Codable {
    let sourceId: String
    let sourceVersion: String
    let attribution: String
    let license: Data
}

/// Internal serialization input. Only build() establishes disk-backed acceptance;
/// assemble() is deliberately not exposed as a CLI validation bypass.
struct PackageSnapshot {
    let records: [ContractRecord]
    let sources: [PackageSource]
    let lineage: [String: String]
    let humanReviewPending: Bool
}

struct PackagePayload: Codable, Equatable {
    let sha256: String
    let bytes: Int
    let count: Int
}

struct PackageManifest: Codable {
    let schema: String
    let contentSchema: String
    let builderVersion: Int
    let indexNormalization: String
    let buildMode: String
    let releaseEligible: Bool
    let humanReviewPending: Bool
    let lineageVersions: [String: String]
    let payloads: [String: PackagePayload]
}

enum PackageBuilder {
    private static var fm: FileManager { FileManager.default }
    private static let maximumFileBytes = 64 * 1024 * 1024

    static func build(dataset: URL, sources: URL, reviews: URL, ledger: URL,
                      profile: URL, mode: String, out: URL) throws {
        try requireMode(mode)
        let output = out.standardizedFileURL.resolvingSymlinksInPath()
        for input in [dataset, sources.deletingLastPathComponent(), reviews, ledger, profile] {
            let path = input.standardizedFileURL.resolvingSymlinksInPath().path
            guard output.path != path, !output.path.hasPrefix(path + "/"),
                  !path.hasPrefix(output.path + "/") else { throw PackageFailure(reason: "output_overlaps_input") }
        }
        guard !fm.fileExists(atPath: out.path) else { throw PackageFailure(reason: "output_exists") }
        _ = try SourceRegistry.validate(at: sources)
        let loaded = try IndexBuild.loadRecords(at: dataset)
        // Task16 requires an already-merged dataset; never conceal duplicate IDs
        // or substitute a permissive overlay for its full evidence/rights gate.
        let merged = dataset.appendingPathComponent("merged")
        let directory = fm.fileExists(atPath: merged.path) ? merged : dataset
        let report = DatasetValidator.validate(at: directory, sources: sources, reviews: reviews, ledger: ledger, profile: profile)
        guard report.valid else {
            let counts = Dictionary(grouping: report.defects, by: { $0.code.rawValue })
                .map { "\($0.key)=\($0.value.count)" }.sorted().joined(separator: ",")
            throw PackageFailure(reason: "private_pack_validation_failed:\(counts)")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let quality = try decoder.decode(QualityProfile.self, from: Data(contentsOf: profile))
        _ = try FamiliesAudit.audit(dataset: directory, reviews: reviews, profile: quality)
        let content = ledger.deletingLastPathComponent().deletingLastPathComponent()
        let index = content.appendingPathComponent("derived/pilot-v1/index.json")
        let generated = try SearchIndex.bytes(SearchIndex.build(records: loaded.records))
        guard generated == (try boundedRead(index)) else { throw PackageFailure(reason: "derived_index_mismatch") }
        var lineage: [String: String] = [:]
        for (label, url) in [("sources", sources), ("ledger", ledger), ("profile", profile), ("derived-index", index)] {
            lineage[label] = CKHash.sha256Hex(of: try boundedRead(url))
        }
        for file in loaded.files { lineage["dataset/" + file.lastPathComponent] = CKHash.sha256Hex(of: try boundedRead(file)) }
        for file in try inventory(reviews) {
            lineage["reviews/" + file] = CKHash.sha256Hex(of: try boundedRead(reviews.appendingPathComponent(file)))
        }
        // Registry metadata is not a license grant. Only sources actually used
        // by accepted records (and their ancestor chains) enter the pack.
        var used = Set<String>()
        func collect(_ value: Any) {
            if let object = value as? [String: Any] {
                if let id = object["source_id"] as? String { used.insert(id) }
                for value in object.values { collect(value) }
            } else if let array = value as? [Any] { for value in array { collect(value) } }
        }
        for record in loaded.records { collect(try JSONSerialization.jsonObject(with: ContractJSON.bytes(record))) }
        let registry = try SourceRegistry.read(at: sources)
        func ancestors(_ id: String) throws {
            guard let row = registry.first(where: { $0.sourceID == id }) else { throw PackageFailure(reason: "unknown_source") }
            for edge in row.ancestors where used.insert(edge.sourceID).inserted { try ancestors(edge.sourceID) }
        }
        for id in used.sorted() { try ancestors(id) }
        let attribution = try registry.filter { used.contains($0.sourceID) }.map { row in
            _ = try SourcePermissionGate.authorize(sourceID: row.sourceID, purpose: .privatePreview, registry: registry)
            let license = try boundedRead(sources.deletingLastPathComponent().appendingPathComponent(row.licenseTextRef))
            lineage["license/" + row.sourceID] = CKHash.sha256Hex(of: license)
            return PackageSource(sourceId: row.sourceID, sourceVersion: try row.sourceVersionHash(), attribution: row.attribution, license: license)
        }
        try assemble(PackageSnapshot(records: loaded.records, sources: attribution, lineage: lineage,
                                     humanReviewPending: report.humanReviewPending), mode: mode, out: out)
    }

    static func requireMode(_ mode: String) throws {
        guard mode != "production" else { throw PackageFailure(reason: "production_mode_not_supported") }
        guard mode == "private-preview" else { throw PackageFailure(reason: "unknown_build_mode") }
    }

    static func assemble(_ snapshot: PackageSnapshot, mode: String, out: URL) throws {
        try requireMode(mode)
        guard !fm.fileExists(atPath: out.path) else { throw PackageFailure(reason: "output_exists") }
        let parent = out.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".\(out.lastPathComponent).staging-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        var payloads: [String: PackagePayload] = [:]
        func write(_ path: String, _ bytes: Data, count: Int) throws {
            try safePath(path)
            try safeText(bytes)
            let destination = staging.appendingPathComponent(path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: destination)
            payloads[path] = PackagePayload(sha256: CKHash.sha256Hex(of: bytes), bytes: bytes.count, count: count)
        }
        let records = snapshot.records.sorted { $0.recordId < $1.recordId }
        _ = try ContractDataset.validateEntries(records)
        var groups: [String: [ContractRecord]] = [:]
        for record in records {
            let raw = try JSONSerialization.jsonObject(with: ContractJSON.bytes(record)) as? [String: Any]
            let payload = raw?["payload"] as? [String: Any]
            guard payload?["status"] as? String != "quarantined" else { throw PackageFailure(reason: "quarantined_record") }
            let path: String
            if case .question(let question) = record {
                path = question.payload.split == .check ? "check-bank/questions.jsonl" : "records/questions.jsonl"
            } else {
                guard record.document.kind != .review, record.document.kind != .manifest else { throw PackageFailure(reason: "private_record_kind") }
                path = "records/\(record.document.kind.rawValue).jsonl"
            }
            groups[path, default: []].append(record)
        }
        for path in groups.keys.sorted() {
            let group = groups[path] ?? []
            try write(path, try group.reduce(into: Data()) { $0.append(try ContractJSON.line($1)) }, count: group.count)
        }
        let index = try SearchIndex.bytes(SearchIndex.build(records: records))
        try write("index.json", index, count: 1)
        for source in snapshot.sources.sorted(by: { $0.sourceId < $1.sourceId }) {
            guard ContractRules.present(source.attribution) else { throw PackageFailure(reason: "missing_attribution") }
            guard !source.license.isEmpty else { throw PackageFailure(reason: "missing_license") }
            try write("licenses/\(source.sourceId).txt", source.license, count: 1)
        }
        let attribution = snapshot.sources.sorted { $0.sourceId < $1.sourceId }.map {
            ["source_id": $0.sourceId, "source_version": $0.sourceVersion, "attribution": $0.attribution,
             "license": "licenses/\($0.sourceId).txt"]
        }
        try write("attribution.json", ContractJSON.bytes(attribution), count: attribution.count)
        let manifest = PackageManifest(schema: "lexvane.private-pack.v1", contentSchema: "lexvane.content.v1",
            builderVersion: 1, indexNormalization: SearchIndex.normalization, buildMode: mode, releaseEligible: false,
            humanReviewPending: snapshot.humanReviewPending, lineageVersions: snapshot.lineage, payloads: payloads)
        try ContractJSON.bytes(manifest).write(to: staging.appendingPathComponent("manifest.json"))
        _ = try verify(staging)
        // Sibling directory move is an atomic filesystem rename. Existing output
        // is never removed or replaced, including validation/serialization failures.
        guard !fm.fileExists(atPath: out.path) else { throw PackageFailure(reason: "output_exists") }
        try fm.moveItem(at: staging, to: out)
    }

    static func verify(_ pack: URL) throws -> PackageManifest {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(PackageManifest.self, from: boundedRead(pack.appendingPathComponent("manifest.json")))
        guard manifest.schema == "lexvane.private-pack.v1", manifest.contentSchema == "lexvane.content.v1",
              manifest.builderVersion == 1, manifest.indexNormalization == SearchIndex.normalization,
              manifest.buildMode == "private-preview", !manifest.releaseEligible,
              !manifest.lineageVersions.isEmpty, manifest.lineageVersions.values.allSatisfy(validHash),
              manifest.payloads.count <= 2048 else { throw PackageFailure(reason: "invalid_manifest_version_or_policy") }
        let files = try inventory(pack)
        guard Set(files) == Set(manifest.payloads.keys).union(["manifest.json"]),
              manifest.payloads["index.json"] != nil, manifest.payloads["attribution.json"] != nil else {
            throw PackageFailure(reason: "payload_inventory_mismatch")
        }
        var records: [ContractRecord] = []
        var total = 0
        for path in manifest.payloads.keys.sorted() {
            try safePath(path)
            guard let expected = manifest.payloads[path], expected.bytes >= 0,
                  expected.bytes <= maximumFileBytes, expected.count >= 0, validHash(expected.sha256) else {
                throw PackageFailure(reason: "payload_bounds")
            }
            total += expected.bytes
            guard total <= 512 * 1024 * 1024 else { throw PackageFailure(reason: "pack_bounds") }
            let bytes = try boundedRead(pack.appendingPathComponent(path))
            try safeText(bytes)
            guard bytes.count == expected.bytes, CKHash.sha256Hex(of: bytes) == expected.sha256 else {
                throw PackageFailure(reason: "payload_hash_mismatch:\(path)")
            }
            if path.hasSuffix(".jsonl") {
                guard path.hasPrefix("records/") || path == "check-bank/questions.jsonl",
                      let text = String(data: bytes, encoding: .utf8), text.hasSuffix("\n") else { throw PackageFailure(reason: "invalid_records_path") }
                let rows = try text.dropLast().split(separator: "\n", omittingEmptySubsequences: false).map { try ContractJSON.decode(Data($0.utf8)) }
                guard rows.count == expected.count else { throw PackageFailure(reason: "record_count_mismatch") }
                for row in rows {
                    if case .question(let question) = row {
                        guard (question.payload.split == .check) == (path == "check-bank/questions.jsonl") else { throw PackageFailure(reason: "check_bank_not_isolated") }
                    } else if path == "check-bank/questions.jsonl" { throw PackageFailure(reason: "invalid_check_bank_kind") }
                }
                records.append(contentsOf: rows)
            } else if path != "index.json" && path != "attribution.json" && !(path.hasPrefix("licenses/") && path.hasSuffix(".txt")) {
                throw PackageFailure(reason: "unexpected_payload")
            }
        }
        _ = try ContractDataset.validateEntries(records)
        try validateReferences(records)
        let rebuilt = try SearchIndex.bytes(SearchIndex.build(records: records))
        guard rebuilt == (try boundedRead(pack.appendingPathComponent("index.json"))) else { throw PackageFailure(reason: "index_dataset_mismatch") }
        let attribution = try decoder.decode([[String: String]].self, from: boundedRead(pack.appendingPathComponent("attribution.json")))
        guard attribution.count == manifest.payloads["attribution.json"]?.count else { throw PackageFailure(reason: "attribution_count_mismatch") }
        var ids = Set<String>()
        for source in attribution {
            guard let id = source["source_id"], ids.insert(id).inserted,
                  let text = source["attribution"], ContractRules.present(text),
                  let version = source["source_version"], validHash(version),
                  let license = source["license"], license == "licenses/\(id).txt",
                  let payload = manifest.payloads[license], payload.bytes > 0, payload.count == 1 else { throw PackageFailure(reason: "missing_attribution_or_license") }
        }
        return manifest
    }

    static func compare(_ left: URL, _ right: URL) throws {
        _ = try verify(left); _ = try verify(right)
        let files = try inventory(left)
        guard files == (try inventory(right)) else { throw PackageFailure(reason: "different_inventory") }
        for path in files where try boundedRead(left.appendingPathComponent(path)) != boundedRead(right.appendingPathComponent(path)) {
            throw PackageFailure(reason: "different_bytes:\(path)")
        }
    }

    private static func validateReferences(_ records: [ContractRecord]) throws {
        guard Set(records.map(\.recordId)).count == records.count else { throw PackageFailure(reason: "duplicate_record_identity") }
        let lookup = Dictionary(uniqueKeysWithValues: records.map { ($0.recordId, $0.document.kind.rawValue) })
        let fields = ["entry_id": "entry", "sense_id": "sense", "sense_ids": "sense", "usage_ids": "teaching",
                      "primary_target_id": "target", "correct_sense_id": "sense", "correct_usage_ids": "teaching", "provenance_refs": "provenance"]
        for record in records {
            let raw = try JSONSerialization.jsonObject(with: ContractJSON.bytes(record)) as? [String: Any]
            let payload = raw?["payload"] as? [String: Any] ?? [:]
            for (field, kind) in fields {
                let ids = payload[field] as? [String] ?? (payload[field] as? String).map { [$0] } ?? []
                guard ids.allSatisfy({ lookup[$0] == kind }) else { throw PackageFailure(reason: "dangling_or_wrong_kind_reference") }
            }
            if case .provenance(let provenance) = record {
                guard lookup[provenance.payload.subjectId] == provenance.payload.subjectKind.rawValue else { throw PackageFailure(reason: "dangling_provenance_subject") }
            }
        }
    }

    private static func validHash(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private static func safePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PackageFailure(reason: "unsafe_relative_path")
        }
    }

    private static func safeText(_ bytes: Data) throws {
        guard let text = String(data: bytes, encoding: .utf8),
              text.range(of: #"(?:/Users/|/home/|/private/|/var/|file://|Bearer\s|-----BEGIN .*PRIVATE KEY|sk-[A-Za-z0-9]{20})"#, options: .regularExpression) == nil else {
            throw PackageFailure(reason: "nontext_or_private_payload")
        }
    }

    private static func boundedRead(_ url: URL) throws -> Data {
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= maximumFileBytes else { throw PackageFailure(reason: "unsafe_file_or_size") }
        return try Data(contentsOf: url)
    }

    private static func inventory(_ root: URL) throws -> [String] {
        var result: [String] = []
        func visit(_ directory: URL, prefix: String, depth: Int) throws {
            guard depth <= 16 else { throw PackageFailure(reason: "directory_depth_bounds") }
            let entries = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            for url in entries {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
                guard values.isSymbolicLink != true else { throw PackageFailure(reason: "symlink_not_allowed") }
                let path = prefix + url.lastPathComponent
                try safePath(path)
                if values.isDirectory == true {
                    try visit(url, prefix: path + "/", depth: depth + 1)
                } else {
                    guard values.isRegularFile == true else { throw PackageFailure(reason: "nonregular_payload") }
                    result.append(path)
                    guard result.count <= 10000 else { throw PackageFailure(reason: "inventory_bounds") }
                }
            }
        }
        try visit(root, prefix: "", depth: 0)
        return result.sorted()
    }
}
