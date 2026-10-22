import ContentModel
import Foundation

public struct IdentityAuditReport: Codable {
    public let valid: Bool
    public let identityCount: Int
    public let eventCount: Int
    public let retiredCount: Int
    public let ledgerHash: String
    public let terminalEventHash: String?
    public let coverageHash: String
    public let coverage: CoverageAuditReport
    public let scope: String
}
private struct IdentityCommandFailure: Encodable {
    let valid = false
    let error: String
}
public enum IdentityCommands {
    public static func run(_ arguments: [String]) -> Int32 {
        var output: URL?
        do {
            guard let command = arguments.first else { throw IdentityFailure("missing_ids_subcommand") }
            let allowed: [String]
            switch command {
            case "audit": allowed = ["--ledger", "--coverage", "--evidence"]
            case "extract-pdf": allowed = ["--file", "--rule", "--registry", "--source-id", "--evidence"]
            default: throw IdentityFailure("unknown_ids_subcommand")
            }
            guard arguments.count == allowed.count * 2 + 1 else { throw IdentityFailure("missing_explicit_flags") }
            var flags: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) {
                let flag = arguments[index]; let value = arguments[index + 1]
                guard allowed.contains(flag), flags[flag] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                    throw IdentityFailure("invalid_or_duplicate_flag")
                }
                flags[flag] = value
            }
            guard Set(flags.keys) == Set(allowed), let evidence = flags["--evidence"] else { throw IdentityFailure("missing_explicit_flags") }
            let destination = URL(fileURLWithPath: evidence).standardizedFileURL.resolvingSymlinksInPath()
            let inputFlags = allowed.filter { $0 != "--evidence" && $0 != "--source-id" }
            for flag in inputFlags {
                guard let path = flags[flag] else { throw IdentityFailure("missing_explicit_flags") }
                let input = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                guard input != destination else { throw IdentityFailure("evidence_overlaps_input") }
                if FileManager.default.fileExists(atPath: destination.path) {
                    let before = try FileManager.default.attributesOfItem(atPath: input.path)
                    let after = try FileManager.default.attributesOfItem(atPath: destination.path)
                    guard before[.systemFileNumber] as? NSNumber != after[.systemFileNumber] as? NSNumber ||
                          before[.systemNumber] as? NSNumber != after[.systemNumber] as? NSNumber else {
                        throw IdentityFailure("evidence_overlaps_input")
                    }
                }
            }
            output = destination
            switch command {
            case "audit":
                guard let ledgerPath = flags["--ledger"], let coveragePath = flags["--coverage"] else { throw IdentityFailure("missing_explicit_flags") }
                let ledger = URL(fileURLWithPath: ledgerPath); let coverage = URL(fileURLWithPath: coveragePath)
                let state = try IdentityLedger.audit(at: ledger)
                let (header, rows) = try CoverageMap.read(at: coverage)
                let report = IdentityAuditReport(valid: true, identityCount: state.records.count, eventCount: state.eventCount,
                    retiredCount: state.retiredIds.count, ledgerHash: try CKHash.sha256Hex(ofFileAt: ledger), terminalEventHash: state.terminalHash,
                    coverageHash: try CKHash.sha256Hex(ofFileAt: coverage), coverage: try CoverageMap.audit(header: header, rows: rows, identities: state),
                    scope: "content_identity_only; append_chain_checked; external_receipt_required_to_detect_history_truncation; no_learner_replay")
                try write(report, to: destination)
                print("IDs structurally valid: \(report.identityCount) identities, \(report.eventCount) append-only events; denominator=\(report.coverage.denominatorState); \(report.coverage.mappingBlocked ? "T005 mapping-blocked (rights_pending)" : "locked material mapped structurally")")
            case "extract-pdf":
                return try extract(flags, to: destination)
            default: throw IdentityFailure("unknown_ids_subcommand")
            }
            return 0
        } catch {
            let description: String
            switch error {
            case let failure as IdentityFailure: description = failure.description
            case let failure as PDFExtractionFailure: description = failure.description
            case let failure as SourceRegistryFailure: description = failure.description
            default: description = IdentityFailure("io_or_decode:\(error)").description
            }
            if let output {
                do { try write(IdentityCommandFailure(error: description), to: output) }
                catch { fputs("IdentityFailure(reason=evidence_write_failed:\(error))\n", stderr) }
            }
            fputs("\(description)\n", stderr)
            return 65
        }
    }
    private static func write<T: Encodable>(_ report: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: url, options: .atomic)
    }
    private static func extract(_ flags: [String: String], to destination: URL) throws -> Int32 {
        guard let file = flags["--file"], let ruleFile = flags["--rule"], let registryPath = flags["--registry"],
              let sourceId = flags["--source-id"] else { throw IdentityFailure("missing_explicit_flags") }
        let registryURL = URL(fileURLWithPath: registryPath).resolvingSymlinksInPath()
        guard !destination.path.hasPrefix(registryURL.deletingLastPathComponent().path + "/") else {
            throw IdentityFailure("evidence_overlaps_registry_tree")
        }
        _ = try SourceRegistry.validate(at: registryURL)
        let registry = try SourceRegistry.read(at: registryURL)
        func authorize(_ id: String, operations: [SourceOperation], ancestors: Set<String>) throws {
            guard !ancestors.contains(id), let source = registry.first(where: { $0.sourceID == id }) else {
                throw IdentityFailure("missing_or_cyclic_extraction_source")
            }
            for operation in operations {
                guard source.permission(for: operation).status == .allowed else {
                    throw IdentityFailure("rights_pending_or_rejected:\(id):\(operation.rawValue)")
                }
            }
            for edge in source.ancestors { try authorize(edge.sourceID, operations: edge.operations, ancestors: ancestors.union([id])) }
        }
        try authorize(sourceId, operations: [.retain, .extract, .localAnalysis], ancestors: [])
        guard let source = registry.first(where: { $0.sourceID == sourceId }), let hash = source.contentSHA256 else {
            throw IdentityFailure("source_bytes_hash_required")
        }
        let fileURL = URL(fileURLWithPath: file)
        guard try CKHash.sha256Hex(ofFileAt: fileURL) == hash else { throw IdentityFailure("source_bytes_hash_mismatch") }
        let rule = try JSONDecoder().decode(PDFParseRule.self, from: Data(contentsOf: URL(fileURLWithPath: ruleFile)))
        let report = try PDFExtractor.extract(file: fileURL, rule: rule)
        try write(report, to: destination)
        guard report.complete else {
            fputs("\(PDFExtractionFailure(reason: "manual_line_review_required", page: nil))\n", stderr)
            return 65
        }
        print("Local extraction: \(report.pageCount) pages, \(report.lineCount) lines, \(report.parsedItemCount) parsed items; no OCR; not a CEEC coverage declaration")
        return 0
    }
}
