import ContentModel
import Foundation

/// Typed CLI failures. Every rejection exits non-zero with a `CKError` reason;
/// errors are never swallowed into a success message.
public enum CKError: Error, CustomStringConvertible, Equatable {
    case noCommand
    case unknownCommand(String)

    public var description: String {
        switch self {
        case .noCommand:
            "CKError(no command: expected a subcommand; see Usage)"
        case .unknownCommand(let name):
            "CKError(unknown command: '\(name)')"
        }
    }

    /// EX_USAGE-style non-zero exit for CLI misuse.
    public var exitCode: Int32 { 64 }
}

public enum CKCLI {
    public static let usage = """
        Usage: contentkit [--help] <command>
          --help    Print this usage and exit 0.
          sources validate --registry PATH --evidence PATH
          sources audit-inventory --inventory PATH --discovery PATH --from YEAR --evidence PATH
          ids audit --ledger PATH --coverage PATH --evidence PATH
          ids extract-pdf --file PATH --rule PATH --registry PATH --source-id ID --evidence PATH
          selection validate --selection PATH --ledger PATH --words COUNT --phrases COUNT --subset-words COUNT --evidence PATH
          validate --dataset PATH --stage candidate --evidence PATH
          validate --dataset PATH --stage agent-accepted --reviews PATH --profile PATH --expected-words N --expected-phrases N --evidence PATH
          validate --dataset PATH --stage private-pack --sources PATH --reviews PATH --ledger PATH --profile PATH --evidence PATH
          jobs plan --selection PATH --subset pilot-50|pilot --prompts PATH --out PATH
          jobs audit --jobs PATH --evidence PATH
          quality audit-profile --profile PATH --trial PATH --evidence PATH
          supply simulate --dataset PATH --profile PATH --scenario PATH --seed INTEGER --out PATH
          reviews audit --dataset PATH --reviews PATH --evidence PATH [--profile PATH]
          families audit --dataset PATH --reviews PATH --profile PATH --evidence PATH
          reports human-recheck|audit-human-recheck --dataset PATH --reviews PATH --profile PATH --seed INTEGER --out PATH --evidence PATH
          reports current-recheck|audit-current-recheck --dataset PATH --reviews PATH --out PATH --evidence PATH [--policy PATH [--quality-profile PATH]]
          index build --dataset PATH --out PATH --evidence PATH
          search --index PATH --query WORD
          pack build --dataset PATH --sources PATH --reviews PATH --ledger PATH --profile PATH --mode private-preview --out PATH
          pack compare --left PATH --right PATH [--evidence PATH]
          pack verify --pack PATH [--evidence PATH]
          reviews --dump-checklist-ids    JSON required IDs; writing distractor-rationales must be not_applicable, all others passed.
        """

    public static func run(_ arguments: [String]) -> Int32 {
        if arguments.first == "reports",
           ["current-recheck", "audit-current-recheck"].contains(arguments.dropFirst().first),
           arguments.contains("--help") || arguments.contains("-h") {
            print(CurrentRecheckReport.usage)
            return 0
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            print(usage)
            return 0
        }
        guard let first = arguments.first else {
            let error = CKError.noCommand
            fputs("\(error)\n\(usage)\n", stderr)
            return error.exitCode
        }
        if first == "validate" {
            if arguments.contains("private-pack") {
                return JobCommands.validateDataset(Array(arguments.dropFirst()))
            }
            do {
                let report = try ContractDataset.validate(arguments: Array(arguments.dropFirst()))
                print("valid=true stage=\(report.stage) records=\(report.recordCount) acceptance_evaluated=\(report.acceptanceEvaluated)")
                return 0
            } catch {
                fputs("\(error)\n", stderr)
                return 65
            }
        }
        if arguments.starts(with: ["sources", "audit-inventory"]) {
            return InventoryCommands.run(Array(arguments.dropFirst(2)))
        }
        if first == "pack" {
            return PackageCommands.run(Array(arguments.dropFirst()))
        }
        if first == "index" {
            return IndexCommands.runIndex(Array(arguments.dropFirst()))
        }
        if first == "search" {
            return IndexCommands.runSearch(Array(arguments.dropFirst()))
        }
        if first == "reviews" {
            if arguments == ["reviews", "--dump-checklist-ids"] {
                do {
                    print(String(decoding: try ContractJSON.bytes(ReviewCoverage.checklistIDs), as: UTF8.self))
                    return 0
                } catch {
                    fputs("\(error)\n", stderr)
                    return 65
                }
            }
            return ReviewCommands.run(Array(arguments.dropFirst()))
        }
        if first == "reports" {
            let rest = Array(arguments.dropFirst())
            if rest.first == "current-recheck" || rest.first == "audit-current-recheck" {
                if rest.contains("--help") || rest.contains("-h") {
                    print(CurrentRecheckReport.usage)
                    return 0
                }
                return CurrentRecheckReport.run(rest)
            }
            return HumanReportCommands.run(rest)
        }
        if first == "families" {
            return FamiliesCommands.run(Array(arguments.dropFirst()))
        }
        if first == "selection" {
            return SelectionCommands.run(Array(arguments.dropFirst()))
        }
        if first == "jobs" {
            return JobCommands.run(Array(arguments.dropFirst()))
        }
        if first == "quality" && arguments.dropFirst().first == "audit-profile" {
            return QualityCommands.run(Array(arguments.dropFirst()))
        }
        if first == "supply" && arguments.dropFirst().first == "simulate" {
            return QualityCommands.run(Array(arguments.dropFirst()))
        }
        if first == "ids" {
            return IdentityCommands.run(Array(arguments.dropFirst()))
        }
        if first == "sources" {
            return SourceCommands.run(Array(arguments.dropFirst()))
        }
        let error = CKError.unknownCommand(first)
        fputs("\(error)\n\(usage)\n", stderr)
        return error.exitCode
    }

}
