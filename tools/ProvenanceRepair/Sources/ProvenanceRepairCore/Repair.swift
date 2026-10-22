import Foundation
import ContentModel

public struct RepairResult: Encodable {
    public let changedRowsByFile: [String: Int]
    public var changedRows: Int { changedRowsByFile.values.reduce(0, +) }
}

public enum ProvenanceRepair {
    public static let history = "content/history/provenance-repair-v2"
    public static let writingUsages: Set<String> = [
        "lx:usage:07c3df26-12fb-484b-bfa6-efd11f402277",
        "lx:usage:2aab3654-b856-4c3d-a8e5-8fa5003a36ea",
    ]
    public static let senseIds: Set<String> = [
        "lx:sense:4ce7d12e-49f7-4135-a134-3aac1dc30b60",
        "lx:sense:3b4b445f-4e73-4163-bfe4-91d14615380c",
    ]

    private static let orderFiles: [String: String] = [
        "p230-check-fix-r5-sanitized-a": "a1-task14/check-fix-r5-a.jsonl",
        "p230-check-fix-r3-sanitized-c": "a1-task14/check-fix-r3-c.jsonl",
        "p230-check-fix-r3-sanitized-a": "a1-task14/check-fix-r3-a.jsonl",
        "p230-check-fix-r4-sanitized-b": "a1-task14/check-fix-r4-b.jsonl",
        "p230-check-fix-r1-sanitized-a": "a1-task14/check-fix-r1-a.jsonl",
        "p230-check-fix-r3-sanitized-b": "a1-task14/check-fix-r3-b.jsonl",
        "check-bank-rewrite-r2-sanitized-a": "a1-task13/check-rewrite-r2-a.jsonl",
        "p230-check-fix-r1-sanitized-c": "a1-task14/check-fix-r1-c.jsonl",
        "p230-check-fix-r1-sanitized-b": "a1-task14/check-fix-r1-b.jsonl",
        "check-bank-rewrite-r3-sanitized-c": "a1-task13/check-rewrite-r3-c.jsonl",
        "check-bank-rewrite-r3-sanitized-a": "a1-task13/check-rewrite-r3-a.jsonl",
        "check-bank-rewrite-r4-sanitized-b": "a1-task13/check-rewrite-r4-b.jsonl",
        "check-bank-rewrite-r4-sanitized-a": "a1-task13/check-rewrite-r4-a.jsonl",
        "check-bank-rewrite-r3-sanitized-b": "a1-task13/check-rewrite-r3-b.jsonl",
        "p230-check-fix-r6-sanitized": "a1-task14/check-fix-r6.jsonl",
    ]
    private static let omoFiles = [
        "check-contracts-b.jsonl", "check-contracts-c.jsonl", "check-contracts-d.jsonl",
        "check-rewrite-r2-d.jsonl", "check-rewrite-r3-d.jsonl",
    ]
    private static let citedLines: [String: [Int]] = [
        "check-bank-d.jsonl": [3, 13, 23, 27, 29, 37, 41, 43, 45, 47, 49, 55, 61, 73, 75, 81, 87, 89, 95, 107, 111, 119, 121, 127, 131, 133, 141, 145, 151, 153, 155, 157],
        "check-rewrite2-d.jsonl": [5, 7, 13, 25, 31, 39, 47, 49, 57, 61, 63, 69, 71, 73, 89, 101, 103, 113, 117, 119, 121, 123],
        "check-rewrite3-ab.jsonl": [7, 35, 37],
        "check-rewrite3-c.jsonl": [7, 9],
        "check-rewrite3-d.jsonl": [1, 17, 19],
    ]

    public static var inspectedUnknownIds: Set<String> {
        var ids = Set(orderFiles.keys)
        ids.formUnion(omoFiles.map { ".omo/evidence/m1-content-pilot/a1-task13/" + $0 })
        for (file, lines) in citedLines {
            ids.formUnion(lines.map { "content/records/pilot-230/\(file)#L\($0)" })
        }
        return ids
    }

    private struct PlannedFile {
        let path: String
        let original: Data
        let output: Data
        let changed: Int
        let archive: String
    }

    private static func object(_ bytes: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw ContractFailure("expected_object")
        }
        return value
    }

    private static func seal(_ object: [String: Any]) throws -> ContractRecord {
        try ContractJSON.seal(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
    }

    private static func evidence(ref: String, line: Int? = nil, reason: String, root: URL) throws -> [String: Any] {
        let url = try JobLedger.localURL(ref, base: root)
        var item: [String: Any] = ["ref": ref, "reason": reason, "availability": "unresolved"]
        if let line { item["line"] = line }
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true,
           let data = try? Data(contentsOf: url) {
            let lines = String(data: data, encoding: .utf8)?.split(separator: "\n", omittingEmptySubsequences: false)
            if line == nil || lines.map({ line! <= $0.count && !$0[line! - 1].isEmpty }) == true {
                item["availability"] = "available"; item["sha256"] = CKHash.sha256Hex(of: data)
            }
        }
        return item
    }

    private static func internalEvidence(for id: String, root: URL) throws -> [[String: Any]] {
        if let order = orderFiles[id] {
            let ref = ".omo/evidence/m1-content-pilot/" + order
            let url = try JobLedger.localURL(ref, base: root)
            if let data = try? Data(contentsOf: url), let raw = try? object(data), raw["order_set"] as? String == id {
                return [try evidence(ref: ref, reason: "Exact historical order_set match for \(id); internal generation instructions, not an external source or proof of execution.", root: root)]
            }
            return [try evidence(ref: id, reason: "Historical work label; candidate order-file mapping is unavailable or not an exact order_set match. Unresolved, not proof.", root: root)]
        }
        let parts = id.components(separatedBy: "#L")
        return [try evidence(ref: parts[0], line: parts.count == 2 ? Int(parts[1]) : nil,
            reason: "Historical internal work-file citation; not an external source or proof of author/reviewer execution.", root: root)]
    }

    public static func run(root: URL) throws -> RepairResult {
        let sourceIds = Set(try SourceRegistry.read(at: root.appendingPathComponent("content/sources/registry.jsonl")).map(\.sourceID))
        var plans: [PlannedFile] = []
        for pilot in ["pilot-50", "pilot-230"] {
            let directory = "content/records/\(pilot)/merged"
            let sensePath = "\(directory)/\(pilot)-sense.jsonl"
            let provenancePath = "\(directory)/\(pilot)-provenance.jsonl"
            let senseOriginal = try Data(contentsOf: root.appendingPathComponent(sensePath))
            let provenanceOriginal = try Data(contentsOf: root.appendingPathComponent(provenancePath))
            let senseLines = try CKJSONL.readLines(at: root.appendingPathComponent(sensePath))
            let provenanceLines = try CKJSONL.readLines(at: root.appendingPathComponent(provenancePath))
            let senseHistory = "\(history)/\(pilot)/\(pilot)-sense.jsonl"
            let provenanceHistory = "\(history)/\(pilot)/\(pilot)-provenance.jsonl"
            var senseOut = Data(), provenanceOut = Data()
            var senses: [String: Sense] = [:]
            var senseChanges = 0, provenanceChanges = 0
            for line in senseLines {
                let bytes = Data(line.utf8)
                guard case .sense(let sense) = try ContractJSON.decode(bytes) else { throw ContractFailure("expected_sense") }
                if senseIds.contains(sense.recordId) {
                    let usages = sense.payload.usageIds.filter { !writingUsages.contains($0) }
                    if usages != sense.payload.usageIds {
                        guard sense.revision == 1 else { throw ContractFailure("unexpected_sense_revision") }
                        var raw = try object(bytes), p = try object(ContractJSON.bytes(sense.payload))
                        p["usage_ids"] = usages; raw["payload"] = p; raw["revision"] = sense.revision + 1
                        guard case .sense(let revised) = try seal(raw) else { throw ContractFailure("expected_sense") }
                        senseOut.append(try ContractJSON.line(.sense(revised))); senses[sense.recordId] = revised
                        senseChanges += 1
                        continue
                    }
                    senses[sense.recordId] = sense
                }
                senseOut.append(bytes + Data([10]))
            }
            guard senses.count == 2 else { throw ContractFailure("missing_targeted_senses") }
            for line in provenanceLines {
                let bytes = Data(line.utf8)
                guard case .provenance(let provenance) = try ContractJSON.decode(bytes) else { throw ContractFailure("expected_provenance") }
                let p = provenance.payload
                let unknowns = Set(p.fields.flatMap { $0.sourceRefs.map(\.sourceId) }).subtracting(sourceIds)
                guard unknowns.isSubset(of: inspectedUnknownIds) else { throw ContractFailure("uninspected_source_ids:\(unknowns.sorted())") }
                let sense = senses[p.subjectId]
                let rebind = sense.map { p.subjectRevision != $0.revision || p.subjectContentSha256 != $0.contentSha256 } ?? false
                guard !unknowns.isEmpty || rebind else { provenanceOut.append(bytes + Data([10])); continue }
                guard provenance.schema == "lexvane.content.v1" else { throw ContractFailure("unexpected_existing_v2_repair") }
                if rebind {
                    guard sense?.revision == p.subjectRevision + 1 else { throw ContractFailure("unexpected_sense_binding") }
                }
                var raw = try object(bytes), payload = try object(ContractJSON.bytes(p))
                var fields: [[String: Any]] = []
                let originalFields = try p.fields.map { try object(ContractJSON.bytes($0)) }
                for (index, field) in p.fields.enumerated() {
                    var updated = originalFields[index]
                    updated.removeValue(forKey: "source_refs")
                    updated["external_source_refs"] = try field.sourceRefs.filter { sourceIds.contains($0.sourceId) }.map { try object(ContractJSON.bytes($0)) }
                    var internalRefs: [[String: Any]] = [], unverified: [[String: Any]] = []
                    for source in field.sourceRefs where !sourceIds.contains(source.sourceId) {
                        internalRefs += try internalEvidence(for: source.sourceId, root: root)
                        unverified.append(["original_source_id": source.sourceId, "operations": source.operations.map(\.rawValue),
                            "reason": "Inspected historical identifier denotes internal work, not a registered external source. External origin/verification remains unverified; original claim and method preserved without granting rights."])
                    }
                    if rebind && field.field == "usage_ids" {
                        let archiveBytes = (try? Data(contentsOf: root.appendingPathComponent(senseHistory))) ?? senseOriginal
                        internalRefs.append(["ref": senseHistory, "availability": "available", "sha256": CKHash.sha256Hex(of: archiveBytes),
                            "reason": "Mechanical removal of the quarantined writing-teaching dependency from usage_ids. Archived subject is history, not a new author/reviewer execution."])
                    }
                    updated["origin"] = unverified.isEmpty ? "external" : "unverified"
                    updated["internal_evidence_refs"] = internalRefs
                    updated["unverified_refs"] = unverified
                    fields.append(updated)
                }
                payload["fields"] = fields
                if let sense, rebind {
                    payload["subject_revision"] = sense.revision; payload["subject_content_sha256"] = sense.contentSha256
                    payload["review_refs"] = []
                }
                let archived = (try? Data(contentsOf: root.appendingPathComponent(provenanceHistory))) ?? provenanceOriginal
                payload["migration_evidence"] = ["history_ref": provenanceHistory, "history_sha256": CKHash.sha256Hex(of: archived),
                    "reason": rebind ? "Remove quarantined writing usage dependency; preserve original work refs and retain pending current review. Maintenance only, not author/reviewer execution."
                        : "Separate external sources from internal work and preserve unverified original identifiers. No external verification, rights grant or new author/reviewer execution claimed."]
                raw["schema"] = "lexvane.provenance.v2"; raw["revision"] = provenance.revision + 1; raw["payload"] = payload
                let revised = try seal(raw)
                provenanceOut.append(try ContractJSON.line(revised)); provenanceChanges += 1
            }
            plans.append(.init(path: sensePath, original: senseOriginal, output: senseOut, changed: senseChanges, archive: senseHistory))
            plans.append(.init(path: provenancePath, original: provenanceOriginal, output: provenanceOut, changed: provenanceChanges, archive: provenanceHistory))
        }
        let dirty = plans.filter { $0.changed > 0 }
        for plan in dirty {
            let url = root.appendingPathComponent(plan.archive)
            if FileManager.default.fileExists(atPath: url.path) {
                guard try Data(contentsOf: url) == plan.original else { throw ContractFailure("history_collision:\(plan.archive)") }
            }
        }
        for plan in dirty {
            let url = root.appendingPathComponent(plan.archive)
            if !FileManager.default.fileExists(atPath: url.path) {
                try CKPaths.ensureDirectory(at: url.deletingLastPathComponent())
                try plan.original.write(to: url, options: .withoutOverwriting)
            }
        }
        for plan in dirty {
            guard try Data(contentsOf: root.appendingPathComponent(plan.path)) == plan.original else { throw ContractFailure("concurrent_input_change") }
        }
        for plan in dirty { try plan.output.write(to: root.appendingPathComponent(plan.path), options: .atomic) }
        return RepairResult(changedRowsByFile: Dictionary(uniqueKeysWithValues: dirty.map { ($0.path, $0.changed) }))
    }
}
