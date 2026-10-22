import Foundation

public struct ContractValidationReport: Encodable {
    public let valid: Bool
    public let stage: String
    public let recordCount: Int
    public let counts: [String: Int]
    public let canonicalSha256: String
    public let acceptanceEvaluated: Bool
    public let releaseEligible: Bool
    // Optional additions are omitted on the byte-stable candidate receipt.
    public var acceptedCount: Int? = nil
    public var quarantinedCount: Int? = nil
    public var expectedWords: Int? = nil
    public var actualWords: Int? = nil
    public var expectedPhrases: Int? = nil
    public var actualPhrases: Int? = nil
    public var reviewCoverage: ReviewCoverageReport? = nil
}
public enum ContractDataset {
    public static func validateEntries(_ records: [ContractRecord]) throws -> Int {
        let entries = records.compactMap { record -> Entry? in
            if case .entry(let entry) = record { return entry }; return nil
        }
        try ContractRules.require(Set(entries.map(\.recordId)).count == entries.count, "duplicate_entry_identity")
        // Exact spelling collisions retain all identities; no case-folded union is performed.
        for entry in entries {
            for spelling in entry.payload.aliases + entry.payload.variants {
                try ContractRules.require(!entries.contains { $0.recordId != entry.recordId && $0.payload.lemma == spelling.text },
                                          "distinct_word_in_variant_list")
            }
        }
        return entries.count
    }
    public static func validate(at directory: URL) throws -> ContractValidationReport {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        try ContractRules.require(!files.isEmpty, "empty_dataset")
        var records: [ContractRecord] = []; var canonical = Data(); var counts: [String: Int] = [:]
        var identities = Set<String>()
        for file in files {
            let bytes = try Data(contentsOf: file)
            guard let text = String(data: bytes, encoding: .utf8) else { throw ContractFailure("invalid_utf8") }
            try ContractRules.require(!text.isEmpty && text.hasSuffix("\n") && !bytes.contains(13), "invalid_jsonl")
            for (offset, line) in text.dropLast().split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                do {
                    let record = try ContractJSON.decode(Data(line.utf8))
                    try ContractRules.require(identities.insert("\(record.document.kind.rawValue)|\(record.recordId)").inserted,
                                              "duplicate_record")
                    canonical.append(try ContractJSON.line(record)); records.append(record)
                    counts[record.document.kind.rawValue, default: 0] += 1
                } catch { throw ContractFailure("\(file.lastPathComponent):\(offset + 1):\(error)") }
            }
        }
        _ = try validateEntries(records)
        return .init(valid: true, stage: "candidate", recordCount: records.count, counts: counts,
                     canonicalSha256: CKHash.sha256Hex(of: canonical), acceptanceEvaluated: false, releaseEligible: false)
    }
    public static func validate(arguments: [String]) throws -> ContractValidationReport {
        if arguments.count != 6 && arguments.contains("agent-accepted") {
            return try validateAccepted(arguments: arguments)
        }
        var flags: [String: String] = [:]
        try ContractRules.require(arguments.count == 6, "required_flags:dataset,stage,evidence")
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let flag = arguments[index]
            try ContractRules.require(["--dataset", "--stage", "--evidence"].contains(flag)
                && flags[flag] == nil && !arguments[index + 1].hasPrefix("--"), "invalid_flags")
            flags[flag] = arguments[index + 1]
        }
        guard let dataset = flags["--dataset"], let stage = flags["--stage"], let evidence = flags["--evidence"] else {
            throw ContractFailure("required_flags:dataset,stage,evidence")
        }
        try ContractRules.require(stage == "candidate", "unsupported_stage")
        let input = URL(fileURLWithPath: dataset).resolvingSymlinksInPath().standardizedFileURL
        let output = URL(fileURLWithPath: evidence).resolvingSymlinksInPath().standardizedFileURL
        try ContractRules.require(!output.path.hasPrefix(input.path + "/") && output != input, "evidence_overlaps_input")
        let report = try validate(at: input)
        try CKPaths.ensureDirectory(at: output.deletingLastPathComponent())
        try (ContractJSON.bytes(report) + Data([10])).write(to: output, options: .atomic)
        return report
    }

    private static func validateAccepted(arguments: [String]) throws -> ContractValidationReport {
        let allowed = ["--dataset", "--stage", "--evidence", "--reviews", "--profile",
                       "--expected-words", "--expected-phrases"]
        try ContractRules.require(arguments.count == allowed.count * 2, "required_acceptance_flags")
        var flags: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let flag = arguments[index], value = arguments[index + 1]
            try ContractRules.require(allowed.contains(flag) && flags[flag] == nil && !value.hasPrefix("--"), "invalid_flags")
            flags[flag] = value
        }
        guard flags["--stage"] == "agent-accepted",
              let words = Int(flags["--expected-words"] ?? ""), words >= 0,
              let phrases = Int(flags["--expected-phrases"] ?? ""), phrases >= 0 else {
            throw ContractFailure("invalid_acceptance_flags")
        }
        let input = URL(fileURLWithPath: flags["--dataset"]!).resolvingSymlinksInPath().standardizedFileURL
        let reviews = URL(fileURLWithPath: flags["--reviews"]!).resolvingSymlinksInPath().standardizedFileURL
        let profile = URL(fileURLWithPath: flags["--profile"]!).resolvingSymlinksInPath().standardizedFileURL
        let output = URL(fileURLWithPath: flags["--evidence"]!).resolvingSymlinksInPath().standardizedFileURL
        for source in [input, reviews, profile] {
            try ContractRules.require(output != source && !output.path.hasPrefix(source.path + "/"), "evidence_overlaps_input")
        }
        let candidate = try validate(at: input)
        var actualWords = 0, actualPhrases = 0, quarantined = 0
        for file in try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            where file.pathExtension == "jsonl" {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                let record = try ContractJSON.decode(Data(line.utf8))
                if case .entry(let entry) = record {
                    if entry.payload.entryKind == .word { actualWords += 1 } else { actualPhrases += 1 }
                }
                switch record {
                case .entry(let v): if v.payload.status == .quarantined { quarantined += 1 }
                case .sense(let v): if v.payload.status == .quarantined { quarantined += 1 }
                case .target(let v): if v.payload.status == .quarantined { quarantined += 1 }
                case .teaching(let v): if v.payload.status == .quarantined { quarantined += 1 }
                case .question(let v): if v.payload.status == .quarantined { quarantined += 1 }
                case .provenance, .review, .manifest: break
                }
            }
        }
        try ContractRules.require(actualWords == words && actualPhrases == phrases, "expected_entry_count_mismatch")
        // Whole-dataset acceptance is fail-closed: quarantined content is never
        // silently dropped or counted accepted; no partial success receipt.
        try ContractRules.require(quarantined == 0, "quarantined_records:\(quarantined)")
        let coverage = try ReviewCoverage.audit(dataset: input, reviews: reviews, profile: profile)
        var report = ContractValidationReport(valid: true, stage: "agent-accepted",
            recordCount: candidate.recordCount, counts: candidate.counts,
            canonicalSha256: candidate.canonicalSha256, acceptanceEvaluated: true, releaseEligible: false)
        report.acceptedCount = coverage.subjectsByKind.values.reduce(0, +)
        report.quarantinedCount = quarantined
        report.expectedWords = words; report.actualWords = actualWords
        report.expectedPhrases = phrases; report.actualPhrases = actualPhrases
        report.reviewCoverage = coverage
        try CKPaths.ensureDirectory(at: output.deletingLastPathComponent())
        try (ContractJSON.bytes(report) + Data([10])).write(to: output, options: .atomic)
        return report
    }
}
