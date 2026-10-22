import ContentModel
import Foundation

public enum InventoryCommandError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case input(String)
    public var description: String {
        switch self {
        case .invalidArguments(let reason): "InventoryError(invalid_arguments): \(reason)"
        case .input(let reason): "InventoryError(input): \(reason)"
        }
    }
}

public enum InventoryCommands {
    public static let usage = "sources audit-inventory --inventory <jsonl> --discovery <json> --from <year> --evidence <json>"

    public static func run(_ arguments: [String]) -> Int32 {
        do {
            let flags = ["--inventory", "--discovery", "--from", "--evidence"]
            guard arguments.count == 8 else { throw InventoryCommandError.invalidArguments(usage) }
            var values: [String: String] = [:]
            for offset in stride(from: 0, to: arguments.count, by: 2) {
                let flag = arguments[offset]
                let value = arguments[offset + 1]
                guard flags.contains(flag), values[flag] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                    throw InventoryCommandError.invalidArguments("Unknown/duplicate flag or missing value: \(flag)")
                }
                values[flag] = value
            }
            guard let inventory = values["--inventory"], let discovery = values["--discovery"],
                  let evidence = values["--evidence"], let yearText = values["--from"], let year = Int(yearText) else {
                throw InventoryCommandError.invalidArguments(usage)
            }
            let inventoryURL = URL(fileURLWithPath: inventory).standardizedFileURL
            let discoveryURL = URL(fileURLWithPath: discovery).standardizedFileURL
            let evidenceURL = URL(fileURLWithPath: evidence).standardizedFileURL
            guard evidenceURL != inventoryURL && evidenceURL != discoveryURL else {
                throw InventoryCommandError.invalidArguments("Evidence must not overwrite inputs")
            }
            let decoder = JSONDecoder()
            let lines = try CKJSONL.readLines(at: inventoryURL)
            let rows = try lines.enumerated().map { offset, line in
                do { return try decoder.decode(InventoryRow.self, from: Data(line.utf8)) }
                catch { throw InventoryCommandError.input("inventory line \(offset + 1): \(error)") }
            }
            let snapshot = try decoder.decode(InventoryDiscovery.self, from: Data(contentsOf: discoveryURL))
            let result = InventoryAudit.audit(rows: rows, discovery: snapshot, from: year)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result).write(to: evidenceURL, options: .atomic)
            print("InventoryAudit complete=\(result.complete) rows=\(result.rowCount) snapshots=\(result.snapshotCount) cutoff=\(result.cutoffYear) rights_pending=\(result.rightsPendingCount)")
            for issue in result.issues { print("InventoryError(\(issue.code)): \(issue.subject): \(issue.detail)") }
            return result.complete ? 0 : 65
        } catch {
            print("InventoryError: \(error)")
            return 64
        }
    }
}
