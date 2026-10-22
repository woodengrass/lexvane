import ContentModel
import Foundation

public enum SourceCommands {
    public static func run(_ arguments: [String]) -> Int32 {
        var evidenceURL: URL?
        do {
            guard arguments.first == "validate", arguments.count == 5 else {
                throw SourceRegistryFailure(sourceID: "cli", reason: "usage:sources validate --registry PATH --evidence PATH")
            }
            var flags: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) {
                let flag = arguments[index]
                guard ["--registry", "--evidence"].contains(flag), flags[flag] == nil,
                      !arguments[index + 1].isEmpty, !arguments[index + 1].hasPrefix("--") else {
                    throw SourceRegistryFailure(sourceID: "cli", reason: "invalid_or_duplicate_flag:\(flag)")
                }
                flags[flag] = arguments[index + 1]
            }
            guard let registryPath = flags["--registry"], let evidencePath = flags["--evidence"] else {
                throw SourceRegistryFailure(sourceID: "cli", reason: "missing_explicit_paths")
            }
            let registry = URL(fileURLWithPath: registryPath).standardizedFileURL
            let output = URL(fileURLWithPath: evidencePath).standardizedFileURL
            // Keep evidence outside the registry tree: never overwrite registry/license inputs.
            guard !output.resolvingSymlinksInPath().path.hasPrefix(registry.deletingLastPathComponent().resolvingSymlinksInPath().path + "/") else {
                throw SourceRegistryFailure(sourceID: "cli", reason: "evidence_overlaps_registry_inputs")
            }
            evidenceURL = output
            let report = try SourceRegistry.validate(at: registry)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: output, options: .atomic)
            print("Registry structurally valid: \(report.rowCount) rows; private-pack eligible \(report.privatePackAllowedCount); distribution eligible \(report.distributionAllowedCount). Validation is not a license grant.")
            return 0
        } catch {
            let failure = (error as? SourceRegistryFailure) ?? .init(sourceID: "registry", reason: "io:\(error)")
            if let evidenceURL {
                do {
                    let data = try JSONSerialization.data(withJSONObject: ["valid": false, "error": failure.description], options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: evidenceURL, options: .atomic)
                } catch {
                    fputs("SourceRegistryFailure(source_id=evidence, purpose=registry_validation, reason=write:\(error))\n", stderr)
                }
            }
            fputs("\(failure)\n", stderr)
            return 65
        }
    }
}
