import ContentCLI
import Foundation

// Standalone current-tree triage executable. Delegates to the same
// CurrentRecheckReport helper that backs `contentkit reports current-recheck`
// so both entry points produce byte-identical packets.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") || arguments.contains("-h") || arguments.isEmpty {
    print(CurrentRecheckReport.usage)
    exit(arguments.isEmpty ? 64 : 0)
}
exit(CurrentRecheckReport.run(arguments))
