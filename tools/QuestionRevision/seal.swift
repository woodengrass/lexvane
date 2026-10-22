import ContentModel
import Foundation

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 3, ["seal", "check"].contains(arguments[0]), arguments[1] == "--in" else {
        throw ContractFailure("usage: qr-seal (seal|check) --in <jsonl>")
    }
    let lines = try CKJSONL.readLines(at: URL(fileURLWithPath: arguments[2]))
    guard !lines.isEmpty else { throw ContractFailure("empty_input") }
    for line in lines {
        let data = Data(line.utf8)
        if arguments[0] == "check" {
            _ = try ContractJSON.decode(data)
        } else {
            FileHandle.standardOutput.write(try ContractJSON.line(ContractJSON.seal(data)))
        }
    }
    FileHandle.standardError.write(Data("qr-seal: \(arguments[0]) valid=true lines=\(lines.count)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("qr-seal: \(error)\n".utf8))
    exit(65)
}
