import ContentModel
import Foundation
import ProvenanceRepairCore
import XCTest

final class RepairTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func originalRepository() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try CKPaths.ensureDirectory(at: dir.appendingPathComponent("content/sources"))
        addTeardownBlock { try FileManager.default.removeItem(at: dir) }
        try FileManager.default.copyItem(at: root.appendingPathComponent("content/sources/registry.jsonl"),
                                        to: dir.appendingPathComponent("content/sources/registry.jsonl"))
        for pilot in ["pilot-50", "pilot-230"] {
            let destination = dir.appendingPathComponent("content/records/\(pilot)/merged")
            try CKPaths.ensureDirectory(at: destination)
            for kind in ["sense", "provenance"] {
                let name = "\(pilot)-\(kind).jsonl"
                try FileManager.default.copyItem(at: root.appendingPathComponent("\(ProvenanceRepair.history)/\(pilot)/\(name)"),
                                                to: destination.appendingPathComponent(name))
            }
        }
        return dir
    }

    private func records(_ url: URL) throws -> [ContractRecord] {
        try CKJSONL.readLines(at: url).map { try ContractJSON.decode(Data($0.utf8)) }
    }

    private func snapshot(_ dir: URL) throws -> [String: String] {
        let base = dir.standardizedFileURL.resolvingSymlinksInPath()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: String] = [:]
        for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
            XCTAssertTrue(path.hasPrefix(prefix), "snapshot path \(path) outside \(prefix)")
            result[String(path.dropFirst(prefix.count))] = try CKHash.sha256Hex(ofFileAt: url)
        }
        return result
    }

    func testMigrationPreservesOriginalClaimsAndRerunIsByteIdentical() throws {
        let dir = try originalRepository()
        let initial = try snapshot(dir)
        let sources = Set(try SourceRegistry.read(at: dir.appendingPathComponent("content/sources/registry.jsonl")).map(\.sourceID))
        let result = try ProvenanceRepair.run(root: dir)
        XCTAssertEqual(result.changedRows, 468)
        var changedProvenance = 0, changedSenses = 0, preservedUnknowns = Set<String>(), unknownOccurrences = 0
        for pilot in ["pilot-50", "pilot-230"] {
            for kind in ["sense", "provenance"] {
                let path = "content/records/\(pilot)/merged/\(pilot)-\(kind).jsonl"
                let archive = "\(ProvenanceRepair.history)/\(pilot)/\(pilot)-\(kind).jsonl"
                XCTAssertEqual(initial[path], try CKHash.sha256Hex(ofFileAt: dir.appendingPathComponent(archive)))
                let old = try records(dir.appendingPathComponent(archive)), current = try records(dir.appendingPathComponent(path))
                XCTAssertEqual(old.count, current.count)
                for (before, after) in zip(old, current) {
                    XCTAssertEqual(before.recordId, after.recordId)
                    if before.contentSha256 == after.contentSha256 { continue }
                    XCTAssertEqual(after.document.revision, before.document.revision + 1)
                    switch (before, after) {
                    case (.sense(let a), .sense(let b)):
                        changedSenses += 1
                        XCTAssertTrue(ProvenanceRepair.senseIds.contains(b.recordId))
                        XCTAssertEqual(b.payload.usageIds, a.payload.usageIds.filter { !ProvenanceRepair.writingUsages.contains($0) })
                        XCTAssertEqual(try ContractJSON.bytes(a.payload.sourceRefs), try ContractJSON.bytes(b.payload.sourceRefs))
                        XCTAssertEqual(a.payload.status, b.payload.status)
                    case (.provenance(let a), .provenance(let b)):
                        changedProvenance += 1
                        XCTAssertEqual(b.schema, "lexvane.provenance.v2")
                        XCTAssertEqual(a.payload.model, b.payload.model)
                        XCTAssertEqual(a.payload.promptHash, b.payload.promptHash)
                        XCTAssertEqual(a.payload.workUnitRef, b.payload.workUnitRef)
                        XCTAssertEqual(a.payload.runReceiptRef, b.payload.runReceiptRef)
                        XCTAssertEqual(a.payload.transformChain, b.payload.transformChain)
                        XCTAssertEqual(a.payload.humanModificationRefs, b.payload.humanModificationRefs)
                        if ProvenanceRepair.senseIds.contains(b.payload.subjectId) {
                            XCTAssertEqual(b.payload.subjectRevision, a.payload.subjectRevision + 1)
                            XCTAssertTrue(b.payload.reviewRefs.isEmpty)
                        } else {
                            XCTAssertEqual(a.payload.subjectRevision, b.payload.subjectRevision)
                            XCTAssertEqual(a.payload.subjectContentSha256, b.payload.subjectContentSha256)
                            XCTAssertEqual(a.payload.reviewRefs, b.payload.reviewRefs)
                        }
                        XCTAssertEqual(a.payload.fields.map(\.field), b.payload.fields.map(\.field))
                        for (oldField, field) in zip(a.payload.fields, b.payload.fields) {
                            XCTAssertEqual(oldField.method, field.method)
                            XCTAssertEqual(try ContractJSON.bytes(oldField.sourceRefs.filter { sources.contains($0.sourceId) }), try ContractJSON.bytes(field.sourceRefs))
                            let unknown = oldField.sourceRefs.filter { !sources.contains($0.sourceId) }
                            XCTAssertEqual(unknown.map(\.sourceId), field.unverifiedRefs?.map(\.originalSourceId))
                            XCTAssertEqual(unknown.map { $0.operations.map(\.rawValue) }, field.unverifiedRefs?.map { $0.operations.map(\.rawValue) })
                            for ref in field.unverifiedRefs ?? [] { preservedUnknowns.insert(ref.originalSourceId); unknownOccurrences += 1 }
                            for evidence in field.internalEvidenceRefs ?? [] where evidence.availability == .unresolved {
                                XCTAssertNil(evidence.sha256)
                            }
                        }
                    default: XCTFail("Unexpected changed kind")
                    }
                }
            }
        }
        XCTAssertEqual(changedProvenance, 464)
        XCTAssertEqual(changedSenses, 4)
        XCTAssertEqual(preservedUnknowns, ProvenanceRepair.inspectedUnknownIds)
        XCTAssertEqual(preservedUnknowns.count, 82)
        XCTAssertEqual(unknownOccurrences, 4634)
        let migrated = try snapshot(dir)
        XCTAssertEqual(initial["content/sources/registry.jsonl"], migrated["content/sources/registry.jsonl"])
        XCTAssertEqual(try ProvenanceRepair.run(root: dir).changedRows, 0)
        XCTAssertEqual(try snapshot(dir), migrated)
    }

    func testUninspectedSourceFailsBeforeArchivesOrCurrentFilesAreWritten() throws {
        let dir = try originalRepository()
        let url = dir.appendingPathComponent("content/records/pilot-230/merged/pilot-230-provenance.jsonl")
        var lines = try CKJSONL.readLines(at: url)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        var payload = try XCTUnwrap(raw["payload"] as? [String: Any])
        var fields = try XCTUnwrap(payload["fields"] as? [[String: Any]])
        fields[0]["source_refs"] = [["source_id": "uninspected-origin", "operations": ["reference"]]]
        payload["fields"] = fields; raw["payload"] = payload
        let sealed = try ContractJSON.seal(JSONSerialization.data(withJSONObject: raw))
        lines[0] = String(decoding: try ContractJSON.line(sealed).dropLast(), as: UTF8.self)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        let initial = try snapshot(dir)
        XCTAssertThrowsError(try ProvenanceRepair.run(root: dir))
        XCTAssertEqual(try snapshot(dir), initial)
    }

    func testCurrentPilotsDecodeAndHaveNoTargetedSourceOrQuarantineGraphDefects() throws {
        let registry = try SourceRegistry.read(at: root.appendingPathComponent("content/sources/registry.jsonl"))
        for pilot in ["pilot-50", "pilot-230"] {
            let directory = root.appendingPathComponent("content/records/\(pilot)/merged")
            XCTAssertTrue(try ContractDataset.validate(at: directory).valid)
            let all = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "jsonl" }.flatMap { try records($0) }
            let report = DatasetValidator.audit(records: all, sources: registry, reviews: [])
            XCTAssertFalse(report.defects.contains { $0.code == .quarantineDependency })
            XCTAssertFalse(report.defects.contains { $0.code == .danglingReference && ($0.field.contains("source_refs")) })
            for record in all {
                guard case .provenance(let p) = record else { continue }
                if ProvenanceRepair.senseIds.contains(p.payload.subjectId) {
                    let subject = try XCTUnwrap(all.first { $0.recordId == p.payload.subjectId })
                    XCTAssertEqual(p.payload.subjectRevision, subject.document.revision)
                    XCTAssertEqual(p.payload.subjectContentSha256, subject.contentSha256)
                    XCTAssertTrue(p.payload.workUnitRef.hasPrefix("content/jobs/pilot-50/batch-author-"))
                }
            }
        }
    }
}
