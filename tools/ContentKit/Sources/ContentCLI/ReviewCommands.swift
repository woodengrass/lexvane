import ContentModel
import Foundation

private struct ReviewCommandFailure: Encodable {
    let valid = false
    let error: String
}
public enum ReviewCommands {
    public static func run(_ arguments: [String]) -> Int32 {
        var output: URL?
        do {
            let allowed = ["--dataset", "--reviews", "--evidence", "--profile"]
            guard arguments.first == "audit", arguments.count == 7 || arguments.count == 9 else {
                throw ReviewCoverageFailure("missing_explicit_flags")
            }
            var flags: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) {
                let flag = arguments[index]; let value = arguments[index + 1]
                guard allowed.contains(flag), flags[flag] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                    throw ReviewCoverageFailure("invalid_or_duplicate_flag")
                }
                flags[flag] = value
            }
            guard let datasetPath = flags["--dataset"], let reviewsPath = flags["--reviews"],
                  let evidencePath = flags["--evidence"],
                  Set(flags.keys).isSubset(of: allowed)
                  && Set(flags.keys).isSuperset(of: ["--dataset", "--reviews", "--evidence"]) else {
                throw ReviewCoverageFailure("invalid_flags_or_counts")
            }
            let destination = URL(fileURLWithPath: evidencePath).standardizedFileURL.resolvingSymlinksInPath()
            for path in [datasetPath, reviewsPath] + (flags["--profile"].map { [$0] } ?? []) {
                let input = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                guard input != destination, !destination.path.hasPrefix(input.path + "/") else {
                    throw ReviewCoverageFailure("evidence_overlaps_input")
                }
                if FileManager.default.fileExists(atPath: destination.path) {
                    let a = try FileManager.default.attributesOfItem(atPath: input.path)
                    let b = try FileManager.default.attributesOfItem(atPath: destination.path)
                    guard a[.systemFileNumber] as? NSNumber != b[.systemFileNumber] as? NSNumber ||
                          a[.systemNumber] as? NSNumber != b[.systemNumber] as? NSNumber else {
                        throw ReviewCoverageFailure("evidence_overlaps_input")
                    }
                }
            }
            output = destination
            let profile = flags["--profile"].map { URL(fileURLWithPath: $0) }
            let report = try ReviewCoverage.audit(dataset: URL(fileURLWithPath: datasetPath),
                                                  reviews: URL(fileURLWithPath: reviewsPath),
                                                  profile: profile)
            try write(report, to: destination)
            print("reviews audit valid=true coverage=\(report.coveredUnits)/\(report.totalUnits) blind=\(report.blindSolveCount) unresolved_critical=\(report.unresolvedCriticalFindings)")
            return 0
        } catch {
            let description = (error as? ReviewCoverageFailure)?.description ?? "ReviewCoverageFailure(reason=io_or_decode:\(error))"
            if let output {
                do { try write(ReviewCommandFailure(error: description), to: output) }
                catch { fputs("ReviewCoverageFailure(reason=evidence_write_failed:\(error))\n", stderr) }
            }
            fputs("\(description)\n", stderr)
            return 65
        }
    }
    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
