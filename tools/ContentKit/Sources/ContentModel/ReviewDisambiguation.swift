import CryptoKit
import Foundation

/// Review-ID disambiguation: a data migration, not reviewer judgment.
///
/// The raw `pilot-230` review history contains one `record_id` carried by
/// several byte-different sealed rows (548 conflicting IDs, 112 of them with
/// disagreeing verdicts). `ReviewCoverage` fails those closed
/// (`duplicate_review`), so the raw directory can never audit green, and no
/// worker may pick an oldest/latest/passing winner.
///
/// This helper gives every distinct sealed row its own imported identity:
///
/// - Exact byte duplicates collapse to one output row. Every occurrence
///   location (`file:line`) is retained in the mapping.
/// - Conflicting rows keep ALL variants under distinct derived IDs of the
///   form `<old>~h<12hex>`, where `<12hex>` is the first 12 hex characters of
///   the SHA-256 of the row's canonical sealed bytes. The derivation is a pure
///   function of `(oldID, canonicalHash)`, so input file/line ordering cannot
///   change it. Derived IDs must be globally unique across every output ID
///   (including unconflicted originals): any collision fails loudly with
///   `disambiguation_id_collision` instead of silently extending, indexing,
///   or overwriting.
/// - Derived rows are resealed with `ContractJSON.seal`, which recomputes
///   only `content_sha256` for the new `record_id`. Payload bytes (verdict,
///   checklist, findings, sessions, model, hashes) are asserted identical
///   before and after; nothing here approves content or resolves the 112
///   verdict disagreements, which stay visible and still fail the
///   all-current aggregate (`review_not_passed`).
/// - No mapping can choose a passing winner: every variant is preserved,
///   including every non-passed one.
///
/// Safety contract (fail before any write, never erase):
/// - Source and output must not be the same path, overlap by ancestry, or be
///   symlinks themselves; violations throw before anything is read.
/// - Empty review input throws; nothing is materialized from zero rows.
/// - Destination artifacts (blind/batch/family copies, blind-input dirs,
///   human decisions) are only ever permitted when byte-identical
///   (recursive for directories). A differing same-named destination throws
///   `disambiguation_output_conflict` BEFORE any write, so later owner
///   decisions are never erased. Unknown existing output entries (such as a
///   human triage subdirectory) are never listed, copied over, or deleted.
/// - Nothing in `sourceDir` is ever modified.
public struct ReviewIdentityMapping: Codable {
    public let oldRecordId: String
    public let oldCanonicalHash: String
    public let newRecordId: String
    public let newSealedHash: String
    public let derivation: String
    public let verdict: String
    public let subjectId: String
    public let subjectKind: String
    public let subjectRevision: Int
    public let occurrenceCount: Int
    public let sourceLocations: [String]
    public let outputLocation: String
}

public struct ReviewAmbiguityEntry: Codable {
    public let oldRecordId: String
    public let candidateNewIds: [String]
    public let verdicts: [String]
    public let note: String
}

public struct AmbiguousReferencesReport: Codable {
    public let note: String
    public let downstreamNote: String
    public let conflicts: [ReviewAmbiguityEntry]
}

public struct RawProvenanceEntry: Codable {
    public let path: String
    public let sha256: String
    public let bytes: Int
    public let note: String
}

public struct RawProvenanceReport: Codable {
    public let sourceDir: String
    public let files: [RawProvenanceEntry]
}

public struct ReviewDisambiguationReport: Codable {
    public let totalRows: Int
    public let distinctOldIds: Int
    public let singletonIds: Int
    public let conflictIds: Int
    public let verdictConflictIds: Int
    public let exactDuplicateRowsCollapsed: Int
    public let outputRows: Int
    public let outputDistinctIds: Int
    public let outputFile: String
}

public enum ReviewDisambiguation {
    public static let derivationNote =
        "imported-identity: new record_id imports one byte-exact raw sealed row; " +
        "payload (verdict/checklist/findings/sessions/model/hashes) unchanged; " +
        "resealed with ContractJSON.seal for the new record_id only; not a new reviewer judgment"

    public static let outputFileName = "reviews-disambiguated.jsonl"

    /// Materializes the canonical current review collection.
    ///
    /// Reads sealed reviews from `review-*.jsonl` in `sourceDir` (never
    /// modified), writes the deduplicated/disambiguated rows plus preserved
    /// artifact copies, mapping, ambiguity candidates, and raw hash
    /// provenance into `outputDir`. Deterministic: same row multiset yields
    /// byte-identical outputs regardless of input file/line order.
    @discardableResult
    public static func disambiguate(sourceDir: URL, outputDir: URL) throws -> ReviewDisambiguationReport {
        let fm = FileManager.default
        // Phase 0: preflight. Missing raw input fails actionably before any
        // read or write; nothing is created at outputDir on this path. The
        // full raw history is private local input from the data owner or a
        // controlled backup (see tools/ReviewDisambiguate/README.md).
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw ReviewCoverageFailure(
                "disambiguation_missing_source:\(sourceDir.lastPathComponent):" +
                "raw review history is private local input from the data owner/controlled backup; " +
                "place it at --source and rerun; nothing was written")
        }
        // Path safety. No reads, no writes on violation.
        try validatePaths(sourceDir: sourceDir, outputDir: outputDir)

        // Phase 1: parse inputs into memory. No writes.
        struct Occurrence {
            let file: String
            let line: Int
            let canonical: Data
            let hash: String
            let review: Review
        }
        var occurrences: [Occurrence] = []
        var rawProvenance: [RawProvenanceEntry] = []
        var artifactFiles: [(name: String, bytes: Data)] = []
        var artifactDirs: [(name: String, files: [(path: String, bytes: Data)])] = []

        let sourceFiles = try fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in sourceFiles {
            let name = file.lastPathComponent
            let bytes = try Data(contentsOf: file)
            rawProvenance.append(RawProvenanceEntry(
                path: name, sha256: CKHash.sha256Hex(of: bytes), bytes: bytes.count,
                note: rawNote(for: name)))
            guard isReviewFile(name) else { continue }
            let lines = try splitLines(bytes, file: name)
            for (offset, line) in lines.enumerated() {
                let record: ContractRecord
                do {
                    record = try ContractJSON.decode(line)
                } catch {
                    throw ReviewCoverageFailure("disambiguation_unreadable:\(name):\(offset + 1):\(error)")
                }
                guard case .review(let review) = record else {
                    throw ReviewCoverageFailure("disambiguation_non_review:\(name):\(offset + 1)")
                }
                let canonical = try ContractJSON.bytes(ContractRecord.review(review))
                occurrences.append(Occurrence(
                    file: name, line: offset + 1, canonical: canonical,
                    hash: CKHash.sha256Hex(of: canonical), review: review))
            }
        }
        guard !occurrences.isEmpty else {
            throw ReviewCoverageFailure("disambiguation_empty_reviews:\(sourceDir.lastPathComponent)")
        }
        try collectArtifacts(from: sourceDir, files: &artifactFiles, dirs: &artifactDirs,
                             provenance: &rawProvenance)

        // Group by old record_id. Sorting inputs by (id, hash) makes every
        // downstream step independent of raw file/line order.
        let ordered = occurrences.sorted {
            if $0.review.recordId != $1.review.recordId { return $0.review.recordId < $1.review.recordId }
            if $0.hash != $1.hash { return $0.hash < $1.hash }
            if $0.file != $1.file { return $0.file < $1.file }
            return $0.line < $1.line
        }
        var groups: [(id: String, rows: [Occurrence])] = []
        for row in ordered {
            if let last = groups.last, last.id == row.review.recordId {
                groups[groups.count - 1].rows.append(row)
            } else {
                groups.append((id: row.review.recordId, rows: [row]))
            }
        }

        struct OutputRow {
            let mapping: ReviewIdentityMapping
            let line: Data
        }
        var outputs: [OutputRow] = []
        var mappings: [ReviewIdentityMapping] = []
        var ambiguities: [ReviewAmbiguityEntry] = []
        var verdictConflicts = 0

        for group in groups {
            var variants: [(hash: String, canonical: Data, review: Review, locations: [String])] = []
            for row in group.rows {
                if let index = variants.firstIndex(where: { $0.hash == row.hash }) {
                    variants[index].locations.append("\(row.file):\(row.line)")
                } else {
                    variants.append((hash: row.hash, canonical: row.canonical, review: row.review,
                                     locations: ["\(row.file):\(row.line)"]))
                }
            }
            if variants.count > 1 {
                let verdicts = Set(variants.map { $0.review.payload.verdict.rawValue })
                if verdicts.count > 1 { verdictConflicts += 1 }
                ambiguities.append(ReviewAmbiguityEntry(
                    oldRecordId: group.id,
                    candidateNewIds: [], // filled after derivation below
                    verdicts: verdicts.sorted(),
                    note: "old ID is ambiguous: every candidate is preserved; downstream review_refs must be rebound by the owning worker, never auto-resolved here"))
            }
            // Deterministic derived IDs: pure function of (oldID, hash) with a
            // fixed 12-hex prefix. No extension, no index fallback: any
            // duplicate fails loudly below instead of inventing an identity.
            var newIds: [String] = []
            for variant in variants {
                if variants.count == 1 {
                    newIds.append(group.id)
                } else {
                    newIds.append(derivedId(old: group.id, hash: variant.hash))
                }
            }
            if variants.count > 1, let last = ambiguities.last, last.oldRecordId == group.id {
                ambiguities[ambiguities.count - 1] = ReviewAmbiguityEntry(
                    oldRecordId: group.id, candidateNewIds: newIds.sorted(),
                    verdicts: last.verdicts, note: last.note)
            }
            for (variant, newId) in zip(variants, newIds) {
                let sealedLine: Data
                let sealedHash: String
                if newId == group.id {
                    sealedLine = variant.canonical
                    sealedHash = variant.hash
                } else {
                    sealedLine = try resealedWithId(variant.canonical, newId: newId, old: variant.review)
                    sealedHash = CKHash.sha256Hex(of: sealedLine)
                }
                let outLocation = "\(outputFileName):\(outputs.count + 1)"
                let review = variant.review
                mappings.append(ReviewIdentityMapping(
                    oldRecordId: group.id, oldCanonicalHash: variant.hash,
                    newRecordId: newId, newSealedHash: sealedHash,
                    derivation: derivationNote,
                    verdict: review.payload.verdict.rawValue,
                    subjectId: review.payload.subjectId,
                    subjectKind: review.payload.subjectKind.rawValue,
                    subjectRevision: review.payload.subjectRevision,
                    occurrenceCount: variant.locations.count,
                    sourceLocations: variant.locations,
                    outputLocation: outLocation))
                outputs.append(OutputRow(mapping: mappings[mappings.count - 1], line: sealedLine))
            }
        }

        // Global uniqueness across every output ID, including unconflicted
        // originals. A derived ID that equals any other output ID (or a
        // second variant sharing one) fails here: no silent duplicate, no
        // invented fallback identity.
        var newIdCounts: [String: Int] = [:]
        var newIdOlds: [String: [String]] = [:]
        for m in mappings {
            newIdCounts[m.newRecordId, default: 0] += 1
            newIdOlds[m.newRecordId, default: []].append(m.oldRecordId)
        }
        if let collision = newIdCounts.first(where: { $0.value > 1 }) {
            let olds = (newIdOlds[collision.key] ?? []).sorted().joined(separator: ",")
            throw ReviewCoverageFailure("disambiguation_id_collision:\(collision.key):olds=\(olds)")
        }

        // Canonical output order: by new ID, then hash. Never input order.
        outputs.sort {
            if $0.mapping.newRecordId != $1.mapping.newRecordId {
                return $0.mapping.newRecordId < $1.mapping.newRecordId
            }
            return $0.mapping.newSealedHash < $1.mapping.newSealedHash
        }
        var outData = Data()
        var relocated: [ReviewIdentityMapping] = []
        for (index, row) in outputs.enumerated() {
            outData.append(row.line)
            outData.append(10)
            let m = row.mapping
            relocated.append(ReviewIdentityMapping(
                oldRecordId: m.oldRecordId, oldCanonicalHash: m.oldCanonicalHash,
                newRecordId: m.newRecordId, newSealedHash: m.newSealedHash,
                derivation: m.derivation, verdict: m.verdict,
                subjectId: m.subjectId, subjectKind: m.subjectKind,
                subjectRevision: m.subjectRevision, occurrenceCount: m.occurrenceCount,
                sourceLocations: m.sourceLocations,
                outputLocation: "\(outputFileName):\(index + 1)"))
        }
        relocated.sort {
            if $0.oldRecordId != $1.oldRecordId { return $0.oldRecordId < $1.oldRecordId }
            return $0.newRecordId < $1.newRecordId
        }

        // Phase 2: every output payload is fully prepared in memory, then the
        // destination is validated, all before a single write. A differing
        // same-named destination artifact (including a later owner decision)
        // fails here with the destination left untouched.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let mappingData = try encoder.encode(relocated)
        let ambiguityReport = AmbiguousReferencesReport(
            note: "Every conflicting old review ID lists ALL derived candidates. " +
                "Nothing here resolves references; provenance review_refs and " +
                "human-recheck review_refs that name an old conflicting ID are " +
                "ambiguous until the owning worker rebinds them explicitly.",
            downstreamNote: "content/records provenance review_refs and the raw " +
                "human-recheck packet (regenerated later, not copied) may name old " +
                "conflicting IDs; each such reference now has N candidates in mapping.json. " +
                "Do not edit dataset/provenance here.",
            conflicts: ambiguities.sorted { $0.oldRecordId < $1.oldRecordId })
        let ambiguityData = try encoder.encode(ambiguityReport)
        rawProvenance.sort { $0.path < $1.path }
        let provenanceData = try encoder.encode(RawProvenanceReport(
            sourceDir: sourceDir.lastPathComponent, files: rawProvenance))
        let readmeData = Data(readmeText(sourceDirName: sourceDir.lastPathComponent).utf8)
        let parentJSON = try parentJSONData(outputName: outputDir.lastPathComponent,
                                            sourceDirName: sourceDir.lastPathComponent)
        let stubData = Data(humanRecheckStubText().utf8)
        try validateDestination(outputDir, files: artifactFiles, dirs: artifactDirs)

        // Phase 3: writes only. Nothing is ever deleted; unknown existing
        // entries (such as a human triage subdirectory) are left alone.
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try outData.write(to: outputDir.appendingPathComponent(outputFileName), options: .atomic)
        try mappingData.write(to: outputDir.appendingPathComponent("mapping.json"), options: .atomic)
        try ambiguityData.write(
            to: outputDir.appendingPathComponent("ambiguous-references.json"), options: .atomic)
        try provenanceData.write(to: outputDir.appendingPathComponent("provenance.json"), options: .atomic)
        try readmeData.write(to: outputDir.appendingPathComponent("README.md"), options: .atomic)
        try parentJSON.write(to: outputDir.appendingPathComponent("PARENT.json"), options: .atomic)
        try stubData.write(to: outputDir.appendingPathComponent("human-recheck.STUB.md"), options: .atomic)
        try writeArtifacts(files: artifactFiles, dirs: artifactDirs, to: outputDir)

        let collapsed = occurrences.count - relocated.count
        return ReviewDisambiguationReport(
            totalRows: occurrences.count, distinctOldIds: groups.count,
            singletonIds: groups.count - ambiguities.count,
            conflictIds: ambiguities.count, verdictConflictIds: verdictConflicts,
            exactDuplicateRowsCollapsed: collapsed,
            outputRows: relocated.count, outputDistinctIds: relocated.count,
            outputFile: outputFileName)
    }

    // MARK: - Internals

    private static func validatePaths(sourceDir: URL, outputDir: URL) throws {
        let fm = FileManager.default
        for (label, url) in [("source", sourceDir), ("output", outputDir)] as [(String, URL)] {
            if fm.fileExists(atPath: url.path) {
                var isLink = false
                do {
                    _ = try fm.destinationOfSymbolicLink(atPath: url.path)
                    isLink = true
                } catch {}
                if isLink {
                    throw ReviewCoverageFailure("disambiguation_symlink:\(label):\(url.path)")
                }
            }
        }
        let s = sourceDir.standardizedFileURL.resolvingSymlinksInPath().path
        let o = outputDir.standardizedFileURL.resolvingSymlinksInPath().path
        if s == o {
            throw ReviewCoverageFailure("disambiguation_source_is_output")
        }
        if (o + "/").hasPrefix(s + "/") {
            throw ReviewCoverageFailure("disambiguation_output_inside_source:\(o)")
        }
        if (s + "/").hasPrefix(o + "/") {
            throw ReviewCoverageFailure("disambiguation_source_inside_output:\(s)")
        }
    }

    /// Review rows live in `review-*.jsonl`, plus this helper's own canonical
    /// output (so re-running on an already-disambiguated directory is an
    /// identity pass, never a `~h` re-derivation).
    private static func isReviewFile(_ name: String) -> Bool {
        name.hasPrefix("review-") || name == outputFileName
    }

    private static func derivedId(old: String, hash: String) -> String {
        "\(old)~h\(hash.prefix(12))"
    }

    /// Returns resealed canonical bytes for `newId`, asserting the payload is
    /// byte-identical to the imported row (no new reviewer judgment).
    private static func resealedWithId(_ canonical: Data, newId: String, old: Review) throws -> Data {
        guard var raw = try JSONSerialization.jsonObject(with: canonical) as? [String: Any] else {
            throw ReviewCoverageFailure("disambiguation_unreadable_json")
        }
        raw["record_id"] = newId
        let edited = try JSONSerialization.data(
            withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        let sealed = try ContractJSON.seal(edited)
        guard case .review(let fresh) = sealed else {
            throw ReviewCoverageFailure("disambiguation_reseal_kind")
        }
        let oldPayload = try ContractJSON.bytes(old.payload)
        let newPayload = try ContractJSON.bytes(fresh.payload)
        guard oldPayload == newPayload else {
            throw ReviewCoverageFailure("disambiguation_payload_changed:\(old.recordId)")
        }
        guard fresh.recordId == newId else {
            throw ReviewCoverageFailure("disambiguation_id_mismatch:\(old.recordId)")
        }
        return try ContractJSON.bytes(ContractRecord.review(fresh))
    }

    private static func splitLines(_ bytes: Data, file: String) throws -> [Data] {
        guard let text = String(data: bytes, encoding: .utf8),
              !text.isEmpty, text.hasSuffix("\n"), !bytes.contains(13) else {
            throw ReviewCoverageFailure("invalid_jsonl:\(file)")
        }
        return text.dropLast().split(separator: "\n", omittingEmptySubsequences: false)
            .map { Data($0.utf8) }
    }

    private static func rawNote(for name: String) -> String {
        if name.hasPrefix("review-") { return "raw history; sealed review rows; read-only input" }
        if name.hasPrefix("blind-") || name.hasPrefix("family-") || name == "batches.jsonl" {
            return "raw history; blind/batch/family artifact; preserved by verbatim copy"
        }
        if name == "human-recheck.jsonl" {
            return "raw history; 112MB owner packet; NOT copied; regenerates later"
        }
        if name == "human-decisions.jsonl" { return "raw history; explicit-validation artifact; preserved by verbatim copy" }
        return "raw history; preserved hash only"
    }

    private static func collectArtifacts(from source: URL,
                                        files: inout [(name: String, bytes: Data)],
                                        dirs: inout [(name: String, files: [(path: String, bytes: Data)])],
                                        provenance: inout [RawProvenanceEntry]) throws {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for entry in entries {
            let name = entry.lastPathComponent
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard name.hasPrefix("blind-inputs") else { continue }
                let inner = try fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                var packed: [(path: String, bytes: Data)] = []
                for file in inner where file.pathExtension == "json" {
                    let bytes = try Data(contentsOf: file)
                    packed.append((path: file.lastPathComponent, bytes: bytes))
                    provenance.append(RawProvenanceEntry(
                        path: "\(name)/\(file.lastPathComponent)",
                        sha256: CKHash.sha256Hex(of: bytes), bytes: bytes.count,
                        note: "raw history; blind input; preserved by verbatim copy"))
                }
                dirs.append((name: name, files: packed))
                continue
            }
            if entry.pathExtension == "json" {
                guard name.hasPrefix("blind-") else {
                    if name == "sample.json" {
                        let bytes = try Data(contentsOf: entry)
                        provenance.append(RawProvenanceEntry(
                            path: name, sha256: CKHash.sha256Hex(of: bytes), bytes: bytes.count,
                            note: "raw history; sampler manifest references raw filenames; NOT copied; regenerates with canonical inputs"))
                    }
                    continue
                }
                let bytes = try Data(contentsOf: entry)
                files.append((name: name, bytes: bytes))
                provenance.append(RawProvenanceEntry(
                    path: name, sha256: CKHash.sha256Hex(of: bytes), bytes: bytes.count,
                    note: "raw history; blind evidence; preserved by verbatim copy"))
                continue
            }
            guard entry.pathExtension == "jsonl" else { continue }
            if isReviewFile(name) || name == "human-recheck.jsonl" { continue }
            if name == "batches.jsonl" || name.hasPrefix("blind-") || name.hasPrefix("family-")
                || name == "human-decisions.jsonl" {
                let bytes = try Data(contentsOf: entry)
                files.append((name: name, bytes: bytes))
            } else {
                throw ReviewCoverageFailure("unexpected_review_artifact:\(name)")
            }
        }
    }

    private static func validateDestination(_ output: URL,
                                            files: [(name: String, bytes: Data)],
                                            dirs: [(name: String, files: [(path: String, bytes: Data)])]) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: output.path) else { return }
        for file in files {
            let dest = output.appendingPathComponent(file.name)
            if fm.fileExists(atPath: dest.path) {
                let existing = try Data(contentsOf: dest)
                if existing != file.bytes {
                    throw ReviewCoverageFailure("disambiguation_output_conflict:\(file.name)")
                }
            }
        }
        for dir in dirs {
            let dest = output.appendingPathComponent(dir.name)
            if fm.fileExists(atPath: dest.path) {
                var existing: [String: Data] = [:]
                if let enumerator = fm.enumerator(at: dest, includingPropertiesForKeys: nil) {
                    for case let url as URL in enumerator {
                        var isDir: ObjCBool = false
                        if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                            let rel = url.path.hasPrefix(dest.path + "/")
                                ? String(url.path.dropFirst(dest.path.count + 1)) : url.lastPathComponent
                            existing[rel] = try Data(contentsOf: url)
                        }
                    }
                }
                let planned = Dictionary(uniqueKeysWithValues: dir.files.map { ($0.path, $0.bytes) })
                if Set(existing.keys) != Set(planned.keys)
                    || planned.contains(where: { existing[$0.key] != $0.value }) {
                    throw ReviewCoverageFailure("disambiguation_output_conflict:\(dir.name)/")
                }
            }
        }
    }

    private static func writeArtifacts(files: [(name: String, bytes: Data)],
                                       dirs: [(name: String, files: [(path: String, bytes: Data)])],
                                       to output: URL) throws {
        let fm = FileManager.default
        for file in files {
            let dest = output.appendingPathComponent(file.name)
            if fm.fileExists(atPath: dest.path) { continue }
            try file.bytes.write(to: dest, options: .atomic)
        }
        for dir in dirs {
            let dest = output.appendingPathComponent(dir.name)
            if !fm.fileExists(atPath: dest.path) {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                for file in dir.files {
                    try file.bytes.write(to: dest.appendingPathComponent(file.path), options: .atomic)
                }
            }
        }
    }

    private static func humanRecheckStubText() -> String {
        [
            "This canonical directory intentionally omits `human-recheck.jsonl`",
            "(112MB raw owner packet in `content/reviews/pilot-230/`).",
            "",
            "The ReviewCoverage audit treats a missing packet as pending, never as",
            "approval. Regenerate the packet from canonical inputs later; do not",
            "copy the raw packet here.",
            "",
        ].joined(separator: "\n")
    }

    private static func readmeText(sourceDirName: String) -> String {
        [
            "# pilot-230-current: canonical current review collection\n",
            "Parent history (read-only, never edited): `content/reviews/\(sourceDirName)/`.\n",
            "- `reviews-disambiguated.jsonl`: every distinct sealed review row exactly once.\n",
            "- Conflicting raw IDs survive under derived `<old>~h<12hex>` identities;\n",
            "  12 hex prefixes the row canonical SHA-256, so derivation is order-independent.\n",
            "- Derived IDs are IMPORTED identities, not new reviewer judgments.\n",
            "- No mapping chooses a passing winner: 112 verdict disagreements stay\n",
            "  present and still fail the all-current aggregate (`review_not_passed`).\n",
            "- `mapping.json`: old-ID + old-hash -> new-ID + new-hash + location.\n",
            "- `ambiguous-references.json`: every conflicting old ID with ALL candidates.\n",
            "- `provenance.json`: SHA-256 of every raw input file.\n",
            "- Blind/batch/family artifacts are verbatim copies; `human-recheck.jsonl`\n",
            "  is omitted by design (see `human-recheck.STUB.md`) and regenerates later.\n",
            "- Reruns never delete or overwrite differing destination artifacts or\n",
            "  owner decisions; unknown entries such as `triage/` are left alone.\n",
        ].joined(separator: "\n")
    }

    private static func parentJSONData(outputName: String, sourceDirName: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode([
            "canonical_path": "content/reviews/\(outputName)",
            "parent_history_path": "content/reviews/\(sourceDirName)",
            "parent_note": "raw original path remains history (read-only); this canonical directory is the current review collection",
        ])
    }
}
