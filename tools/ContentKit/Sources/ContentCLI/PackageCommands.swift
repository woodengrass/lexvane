import ContentModel
import Foundation

public enum PackageCommands {
    public static func run(_ arguments: [String]) -> Int32 {
        do {
            guard let command = arguments.first else { throw PackageFailure(reason: "missing_pack_command") }
            let required: [String]
            switch command {
            case "build": required = ["--dataset", "--sources", "--reviews", "--ledger", "--profile", "--mode", "--out"]
            case "compare": required = ["--left", "--right"]
            case "verify": required = ["--pack"]
            default: throw PackageFailure(reason: "unknown_pack_command")
            }
            guard arguments.count % 2 == 1 else { throw PackageFailure(reason: "missing_flag_value") }
            var flags: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) {
                let key = arguments[index], value = arguments[index + 1]
                guard (required + (command == "build" ? [] : ["--evidence"])).contains(key),
                      flags[key] == nil, ContractRules.present(value), !value.hasPrefix("--") else { throw PackageFailure(reason: "invalid_or_duplicate_flag") }
                flags[key] = value
            }
            guard Set(required).isSubset(of: Set(flags.keys)) else { throw PackageFailure(reason: "missing_explicit_flags") }
            func url(_ key: String) throws -> URL {
                guard let value = flags[key] else { throw PackageFailure(reason: "missing_explicit_flags") }
                return URL(fileURLWithPath: value).standardizedFileURL
            }
            if let evidence = flags["--evidence"] {
                let output = URL(fileURLWithPath: evidence).standardizedFileURL.resolvingSymlinksInPath()
                for key in required {
                    let input = try url(key).resolvingSymlinksInPath()
                    guard output != input, !output.path.hasPrefix(input.path + "/") else { throw PackageFailure(reason: "evidence_overlaps_pack") }
                }
                guard !FileManager.default.fileExists(atPath: output.path) else { throw PackageFailure(reason: "evidence_exists") }
            }
            switch command {
            case "build":
                guard let mode = flags["--mode"] else { throw PackageFailure(reason: "missing_explicit_flags") }
                try PackageBuilder.build(dataset: url("--dataset"), sources: url("--sources"), reviews: url("--reviews"),
                    ledger: url("--ledger"), profile: url("--profile"), mode: mode, out: url("--out"))
            case "compare": try PackageBuilder.compare(url("--left"), url("--right"))
            case "verify": _ = try PackageBuilder.verify(url("--pack"))
            default: throw PackageFailure(reason: "unknown_pack_command")
            }
            if let evidence = flags["--evidence"] {
                try JobLedger.write(["valid": true, "release_eligible": false], to: URL(fileURLWithPath: evidence))
            }
            print("valid=true command=pack-\(command) release_eligible=false")
            return 0
        } catch {
            fputs("\(error)\n", stderr)
            return 65
        }
    }
}
