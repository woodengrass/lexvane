import ContentModel
import Foundation

struct IndexFailure: Error, Equatable, CustomStringConvertible {
    let reason: String
    var description: String { "IndexFailure(reason=\(reason))" }
}

struct IndexBuildEvidence: Codable {
    let valid: Bool
    let normalization: String
    let datasetFiles: [String]
    let datasetRecords: Int
    let entryCount: Int
    let termCount: Int
    let aliasFormCount: Int
    let indexSha256: String
    let acceptanceEvaluated: Bool
    let excludedQuarantinedIds: [String]
    let releaseEligible: Bool
}

enum IndexBuild {
    static func loadRecords(at root: URL) throws -> (files: [URL], records: [ContractRecord]) {
        let merged = root.appendingPathComponent("merged")
        let directory = FileManager.default.fileExists(atPath: merged.path) ? merged : root
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw IndexFailure(reason: "missing_dataset_directory")
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw IndexFailure(reason: "empty_dataset") }
        var overlay: [String: ContractRecord] = [:]
        for file in files {
            let bytes = try Data(contentsOf: file)
            guard let text = String(data: bytes, encoding: .utf8),
                  !text.isEmpty, text.hasSuffix("\n"), !bytes.contains(13) else {
                throw IndexFailure(reason: "invalid_jsonl:\(file.lastPathComponent)")
            }
            for line in text.dropLast().split(separator: "\n", omittingEmptySubsequences: false) {
                let record: ContractRecord
                do { record = try ContractJSON.decode(Data(line.utf8)) } catch {
                    throw IndexFailure(reason: "invalid_record:\(file.lastPathComponent):\(error)")
                }
                let key = "\(record.document.kind.rawValue)|\(record.recordId)"
                if let prior = overlay[key] {
                    guard record.document.revision != prior.document.revision else {
                        throw IndexFailure(reason: "duplicate_record:\(record.recordId)")
                    }
                    if record.document.revision > prior.document.revision { overlay[key] = record }
                } else {
                    overlay[key] = record
                }
            }
        }
        guard !overlay.isEmpty else { throw IndexFailure(reason: "empty_dataset") }
        return (files, Array(overlay.values))
    }
}

public enum IndexCommands {
    public static func runIndex(_ arguments: [String]) -> Int32 {
        do {
            guard arguments.first == "build", arguments.count == 7 else {
                throw IndexFailure(reason: "required_flags:index,build,dataset,out,evidence")
            }
            var flags: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) {
                let flag = arguments[index], value = arguments[index + 1]
                guard ["--dataset", "--out", "--evidence"].contains(flag),
                      flags[flag] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                    throw IndexFailure(reason: "invalid_or_duplicate_flag")
                }
                flags[flag] = value
            }
            guard let datasetPath = flags["--dataset"], let outPath = flags["--out"],
                  let evidencePath = flags["--evidence"] else {
                throw IndexFailure(reason: "missing_explicit_flags")
            }
            let dataset = URL(fileURLWithPath: datasetPath)
            let destination = URL(fileURLWithPath: outPath).standardizedFileURL.resolvingSymlinksInPath()
            let evidence = URL(fileURLWithPath: evidencePath).standardizedFileURL.resolvingSymlinksInPath()
            let datasetResolved = dataset.standardizedFileURL.resolvingSymlinksInPath()
            for output in [destination, evidence] {
                guard output != datasetResolved, !output.path.hasPrefix(datasetResolved.path + "/") else {
                    throw IndexFailure(reason: "output_overlaps_input")
                }
                guard destination != evidence else { throw IndexFailure(reason: "output_overlaps_input") }
            }
            if FileManager.default.fileExists(atPath: destination.path),
               FileManager.default.fileExists(atPath: evidence.path) {
                let a = try FileManager.default.attributesOfItem(atPath: destination.path)
                let b = try FileManager.default.attributesOfItem(atPath: evidence.path)
                guard a[.systemFileNumber] as? NSNumber != b[.systemFileNumber] as? NSNumber else {
                    throw IndexFailure(reason: "output_overlaps_input")
                }
            }
            let loaded = try IndexBuild.loadRecords(at: dataset)
            _ = try ContractDataset.validateEntries(loaded.records)
            let document = try SearchIndex.build(records: loaded.records)
            let indexBytes = try SearchIndex.bytes(document)
            let digest = CKHash.sha256Hex(of: indexBytes)
            let indexedIds = Set(document.entries.map(\.entryId))
            let aliasForms = loaded.records.compactMap { record -> Entry? in
                if case .entry(let entry) = record { return entry }
                return nil
            }.filter { indexedIds.contains($0.recordId) }
                .flatMap { $0.payload.aliases + $0.payload.variants }.count
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try indexBytes.write(to: destination, options: .atomic)
            let report = IndexBuildEvidence(
                valid: true,
                normalization: SearchIndex.normalization,
                datasetFiles: loaded.files.map(\.lastPathComponent).sorted(),
                datasetRecords: loaded.records.count,
                entryCount: document.entryCount,
                termCount: document.termCount,
                aliasFormCount: aliasForms,
                indexSha256: digest,
                acceptanceEvaluated: false,
                excludedQuarantinedIds: document.excludedQuarantinedIds,
                releaseEligible: false)
            try JobLedger.write(report, to: evidence)
            print("valid=true entries=\(document.entryCount) terms=\(document.termCount) " +
                "index_sha256=\(digest) acceptance_evaluated=false")
            return 0
        } catch {
            fputs("\(error)\n", stderr)
            return 65
        }
    }

    public static func runSearch(_ arguments: [String]) -> Int32 {
        do {
            guard arguments.count == 4 else {
                throw IndexFailure(reason: "required_flags:search,index,query")
            }
            var flags: [String: String] = [:]
            for index in stride(from: 0, to: arguments.count, by: 2) {
                let flag = arguments[index], value = arguments[index + 1]
                guard ["--index", "--query"].contains(flag),
                      flags[flag] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                    throw IndexFailure(reason: "invalid_or_duplicate_flag")
                }
                flags[flag] = value
            }
            guard let indexPath = flags["--index"], let query = flags["--query"] else {
                throw IndexFailure(reason: "missing_explicit_flags")
            }
            let document = try SearchIndex.decode(Data(contentsOf: URL(fileURLWithPath: indexPath)))
            let resolution = SearchIndex.resolve(query: query, index: document)
            let ids = resolution.entryIds.joined(separator: ",")
            print("query=\(query) key=\(resolution.queryKey) match=\(resolution.matchKind.rawValue) " +
                "ambiguous=\(resolution.ambiguous) entries=\(resolution.entryIds.count) ids=\(ids)")
            return 0
        } catch {
            fputs("\(error)\n", stderr)
            return 65
        }
    }
}
