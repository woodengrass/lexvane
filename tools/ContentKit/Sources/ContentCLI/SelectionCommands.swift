import ContentModel
import Foundation

private struct SelectionCommandFailure: Encodable {
    let structurallyValid = false
    let error: String
}
public enum SelectionCommands {
    public static func run(_ arguments: [String]) -> Int32 {
        var output: URL?
        do {
            let allowed = ["--selection", "--ledger", "--words", "--phrases", "--subset-words", "--evidence"]
            guard arguments.first == "validate", arguments.count == 13 else { throw SelectionFailure("missing_explicit_flags") }
            var flags: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) {
                let flag = arguments[index]; let value = arguments[index + 1]
                guard allowed.contains(flag), flags[flag] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                    throw SelectionFailure("invalid_or_duplicate_flag")
                }
                flags[flag] = value
            }
            guard Set(flags.keys) == Set(allowed), let selectionPath = flags["--selection"],
                  let ledgerPath = flags["--ledger"], let evidencePath = flags["--evidence"],
                  let words = flags["--words"].flatMap(Int.init), let phrases = flags["--phrases"].flatMap(Int.init),
                  let subset = flags["--subset-words"].flatMap(Int.init) else { throw SelectionFailure("invalid_flags_or_counts") }
            let destination = URL(fileURLWithPath: evidencePath).standardizedFileURL.resolvingSymlinksInPath()
            for path in [selectionPath, ledgerPath] {
                let input = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                guard input != destination else { throw SelectionFailure("evidence_overlaps_input") }
                if FileManager.default.fileExists(atPath: destination.path) {
                    let a = try FileManager.default.attributesOfItem(atPath: input.path)
                    let b = try FileManager.default.attributesOfItem(atPath: destination.path)
                    guard a[.systemFileNumber] as? NSNumber != b[.systemFileNumber] as? NSNumber ||
                          a[.systemNumber] as? NSNumber != b[.systemNumber] as? NSNumber else { throw SelectionFailure("evidence_overlaps_input") }
                }
            }
            output = destination
            let selection = try SelectionValidator.read(at: URL(fileURLWithPath: selectionPath))
            let identities = try IdentityLedger.audit(at: URL(fileURLWithPath: ledgerPath))
            let report = try SelectionValidator.validate(selection, identities: identities, words: words, phrases: phrases, subsetWords: subset)
            try write(report, to: destination)
            print("Selection structurally valid: \(report.candidateWords) candidate words + \(report.candidatePhrases) whole phrases; subset=\(report.subsetWords); mapping-verified=\(report.mappingVerifiedWords); accepted=\(report.acceptedContentCount); acceptance BLOCKED (rights_pending)")
            return 0
        } catch {
            let description = (error as? SelectionFailure)?.description ?? "SelectionFailure(reason=io_or_decode:\(error))"
            if let output {
                do { try write(SelectionCommandFailure(error: description), to: output) }
                catch { fputs("SelectionFailure(reason=evidence_write_failed:\(error))\n", stderr) }
            }
            fputs("\(description)\n", stderr)
            return 65
        }
    }
    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
