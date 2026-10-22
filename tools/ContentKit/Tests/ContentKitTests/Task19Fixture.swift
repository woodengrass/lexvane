import Foundation
import XCTest
import ContentModel
@testable import ContentCLI

final class Task19Fixture {
    let root: URL
    let pack: URL
    let records: [ContractRecord]
    private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        pack = root.appendingPathComponent("fixture-pack")
        records = try IndexBuild.loadRecords(at: fixtures.appendingPathComponent("reviews/valid/dataset")).records
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            try PackageBuilder.assemble(PackageSnapshot(records: records,
                sources: [PackageSource(sourceId: "S01", sourceVersion: String(repeating: "a", count: 64),
                    attribution: "Fixture author", license: Data("Fixture grant; not a grant for pilot content.\n".utf8))],
                lineage: ["fixture": String(repeating: "b", count: 64)], humanReviewPending: true),
                mode: "private-preview", out: pack)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func packBytes() throws -> [String: Data] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: pack, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[String(url.path.dropFirst(pack.path.count + 1))] = try Data(contentsOf: url)
        }
        return result
    }

    func editManifest(_ edit: (inout [String: Any]) throws -> Void) throws {
        let url = pack.appendingPathComponent("manifest.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        try edit(&object)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }

    func replacePayload(_ path: String, bytes: Data) throws {
        try bytes.write(to: pack.appendingPathComponent(path))
        try editManifest { object in
            var payloads = try XCTUnwrap(object["payloads"] as? [String: Any])
            var payload = try XCTUnwrap(payloads[path] as? [String: Any])
            payload["sha256"] = CKHash.sha256Hex(of: bytes)
            payload["bytes"] = bytes.count
            payloads[path] = payload
            object["payloads"] = payloads
        }
    }

    func trialQuestions() throws -> [Question] {
        let directory = fixtures.appendingPathComponent("PilotFifty/dataset")
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.path < $1.path }
            .flatMap { try CKJSONL.readLines(at: $0).map { try ContractJSON.decode(Data($0.utf8)) } }
            .compactMap { if case .question(let value) = $0 { return value }; return nil }
    }
}
