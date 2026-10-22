import Foundation

enum ReviewInputRow {
    case sealed(Review)
    case artifact([String: Any])
}

enum ReviewInputReader {
    static func lines(at file: URL) throws -> [Data] {
        let bytes = try Data(contentsOf: file)
        if bytes.isEmpty && file.lastPathComponent == "human-decisions.jsonl" { return [] }
        guard let text = String(data: bytes, encoding: .utf8),
              !text.isEmpty, text.hasSuffix("\n"), !bytes.contains(13) else {
            throw ReviewCoverageFailure("invalid_jsonl:\(file.lastPathComponent)")
        }
        if file.lastPathComponent == "human-decisions.jsonl" {
            throw ReviewCoverageFailure("human_decisions_require_explicit_validation:\(file.lastPathComponent)")
        }
        return text.dropLast().split(separator: "\n", omittingEmptySubsequences: false).map { Data($0.utf8) }
    }

    static func decode(_ line: Data, file: String) throws -> ReviewInputRow {
        do {
            guard let raw = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw ReviewCoverageFailure("expected_object:\(file)")
            }
            // A packet's kind describes its nested subject, not a contract
            // envelope. Schema/payload markers always require sealed decoding,
            // even when a file is named like a raw blind/family artifact.
            let packetKind = file == "human-recheck.jsonl" && raw["kind"] as? String != "review"
            if raw["schema"] != nil || raw["payload"] != nil || (raw["kind"] != nil && !packetKind) {
                guard case .review(let review) = try ContractJSON.decode(line) else {
                    throw ReviewCoverageFailure("invalid_review_kind:\(file)")
                }
                return .sealed(review)
            }
            if file == "human-recheck.jsonl" {
                if raw["kind"] != nil {
                    guard let subject = raw["subject"] as? [String: Any],
                          subject["record_id"] as? String == raw["record_id"] as? String,
                          subject["kind"] as? String == raw["kind"] as? String else {
                        throw ReviewCoverageFailure("invalid_human_packet:\(file)")
                    }
                }
                return .artifact(raw)
            }
            guard file == "batches.jsonl" || file.hasPrefix("blind-") || file.hasPrefix("family-") else {
                throw ReviewCoverageFailure("unexpected_review_artifact:\(file)")
            }
            return .artifact(raw)
        } catch let failure as ReviewCoverageFailure { throw failure }
        catch { throw ReviewCoverageFailure("\(file):\(error)") }
    }
}
