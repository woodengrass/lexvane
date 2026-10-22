import ContentModel
import Foundation

private func fail(_ message: String) -> Never {
    fputs("review-disambiguate: \(message)\n", stderr)
    exit(65)
}

private func flag(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

guard let sourcePath = flag("--source"), let outputPath = flag("--output") else {
    fail("usage: review-disambiguate --source <reviews-dir> --output <canonical-dir>")
}
if CommandLine.arguments.contains("--help") {
    print("usage: review-disambiguate --source <reviews-dir> --output <canonical-dir>")
    exit(0)
}
do {
    let report = try ReviewDisambiguation.disambiguate(
        sourceDir: URL(fileURLWithPath: sourcePath),
        outputDir: URL(fileURLWithPath: outputPath))
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(report)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
} catch {
    fail("\(error)")
}
