import Foundation
import ProvenanceRepairCore

guard CommandLine.arguments.count == 2 else {
    fputs("usage: ProvenanceRepair <repository-root>\n", stderr)
    exit(64)
}
do {
    let result = try ProvenanceRepair.run(root: URL(fileURLWithPath: CommandLine.arguments[1]))
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(result), as: UTF8.self))
    print("changed_rows=\(result.changedRows)")
} catch {
    fputs("ProvenanceRepair: \(error)\n", stderr)
    exit(65)
}
