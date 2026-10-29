import Foundation
import XCTest
@testable import ContentModel

/// Review-ID disambiguation: imported identities, never reviewer judgment.
///
/// - Conflicting rows sharing one old ID each get a distinct derived ID that
///   is a pure function of (oldID, canonicalHash): no oldest/latest/passing
///   winner, and input file/line order cannot change the result.
/// - Byte-identical rows collapse to one output row with all locations kept.
/// - Payloads are asserted byte-identical through the reseal; verdict
///   disagreements stay present and still fail the all-current aggregate.
/// - Re-running on an output directory is an identity pass; raw inputs are
///   never modified.
/// - Destination safety: same-path/ancestor/descendant overlap and symlinked
///   source/output are rejected before any read or write; empty review input
///   is rejected; a differing same-named destination artifact (including a
///   later owner decision) fails before any write, so nothing is erased;
///   unknown existing output entries such as a triage subdirectory are left
///   alone; derived IDs must be globally unique or the run fails loudly.
final class ReviewDisambiguationTests: XCTestCase {
    private static var packageRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }
    private static var validRoot: URL {
        URL(fileURLWithPath: packageRoot)
            .appendingPathComponent("Tests/ContentKitTests/Fixtures/reviews/valid")
    }

    private func h64(_ byte: String) -> String { String(repeating: byte, count: 64) }

    private func sealedReview(recordId: String, subjectId: String, verdict: String,
                              session: String, reason: String) throws -> Data {
        let raw: [String: Any] = [
            "schema": "lexvane.content.v1", "kind": "review", "record_id": recordId,
            "revision": 1, "content_sha256": h64("0"),
            "payload": [
                "subject_id": subjectId, "subject_kind": "sense", "subject_revision": 1,
                "subject_content_sha256": h64("a"),
                "reviewer_session": session, "reviewer_model": "model-x-separate-session",
                "input_hash": h64("1"), "prompt_hash": h64("2"),
                "checklist": [
                    ["item": "gloss-precision", "result": "passed",
                     "reason": reason, "source_evidence": ["evidence-1"]],
                    ["item": "priority-evidence", "result": "passed",
                     "reason": reason, "source_evidence": ["evidence-1"]],
                ],
                "verdict": verdict, "findings": [], "receipt_refs": ["receipt-1"],
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        return try ContractJSON.line(ContractJSON.seal(data))
    }

    private func sourceDir(with files: [String: [Data]]) throws -> (URL, URL) {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = temp.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for (name, lines) in files {
            var out = Data()
            for line in lines {
                var bare = line
                if bare.last == 10 { bare.removeLast() }
                out.append(bare); out.append(10)
            }
            try out.write(to: source.appendingPathComponent(name), options: .atomic)
        }
        return (temp, source)
    }

    private func decodeMappings(_ dir: URL) throws -> [ReviewIdentityMapping] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([ReviewIdentityMapping].self,
            from: Data(contentsOf: dir.appendingPathComponent("mapping.json")))
    }

    private func payloadOf(_ line: Data) throws -> [String: Any] {
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        return try XCTUnwrap(raw["payload"] as? [String: Any])
    }

    func testConflictingSameIDVariantsGetDistinctDerivedIds() throws {
        let pass = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "passed", session: "ses-a", reason: "thorough")
        let fail = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "changes_requested", session: "ses-b", reason: "thorough")
        let (temp, source) = try sourceDir(with: ["review-a.jsonl": [pass, fail]])
        defer { try? FileManager.default.removeItem(at: temp) }
        let out = temp.appendingPathComponent("out")
        let report = try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out)
        XCTAssertEqual(report.totalRows, 2)
        XCTAssertEqual(report.distinctOldIds, 1)
        XCTAssertEqual(report.conflictIds, 1)
        XCTAssertEqual(report.verdictConflictIds, 1)
        XCTAssertEqual(report.outputRows, 2)
        XCTAssertEqual(report.outputDistinctIds, 2)

        let mappings = try decodeMappings(out)
        XCTAssertEqual(mappings.count, 2)
        let newIds = mappings.map(\.newRecordId)
        XCTAssertEqual(Set(newIds).count, 2, "no passing winner may be chosen; both variants survive")
        for m in mappings {
            XCTAssertTrue(m.newRecordId.hasPrefix("review/synth~h"), "\(m.newRecordId)")
            XCTAssertEqual(m.oldRecordId, "review/synth")
            XCTAssertTrue(m.derivation.contains("imported-identity"))
        }
        // Payloads byte-identical through the reseal: verdicts preserved, not judged.
        let rawPayloads = try [pass, fail].map { try payloadOf($0) }
        let outLines = try String(contentsOf: out.appendingPathComponent("reviews-disambiguated.jsonl"),
                                  encoding: .utf8).split(separator: "\n").map { Data($0.utf8) }
        XCTAssertEqual(outLines.count, 2)
        for line in outLines {
            guard case .review = try ContractJSON.decode(line) else {
                return XCTFail("output row must reseal cleanly")
            }
            let payload = try payloadOf(line)
            XCTAssertTrue(rawPayloads.contains {
                NSDictionary(dictionary: $0).isEqual(to: payload)
            }, "output payload must equal one imported raw payload")
        }
        // Ambiguity is reported as candidates, never auto-resolved.
        let ambiguityDecoder = JSONDecoder()
        ambiguityDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let ambiguity = try ambiguityDecoder.decode(AmbiguousReferencesReport.self,
            from: Data(contentsOf: out.appendingPathComponent("ambiguous-references.json")))
        XCTAssertEqual(ambiguity.conflicts.count, 1)
        XCTAssertEqual(Set(ambiguity.conflicts[0].candidateNewIds), Set(newIds))
    }

    func testExactDuplicatesCollapseWithAllLocationsRetained() throws {
        let row = try sealedReview(recordId: "review/dup", subjectId: "lx:sense:dup",
                                   verdict: "passed", session: "ses-a", reason: "thorough")
        let (temp, source) = try sourceDir(with: [
            "review-a.jsonl": [row, row], "review-b.jsonl": [row],
        ])
        defer { try? FileManager.default.removeItem(at: temp) }
        let out = temp.appendingPathComponent("out")
        let report = try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out)
        XCTAssertEqual(report.totalRows, 3)
        XCTAssertEqual(report.exactDuplicateRowsCollapsed, 2)
        XCTAssertEqual(report.outputRows, 1)
        let mappings = try decodeMappings(out)
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].newRecordId, "review/dup", "singletons keep their identity")
        XCTAssertEqual(mappings[0].occurrenceCount, 3)
        XCTAssertEqual(mappings[0].sourceLocations,
                       ["review-a.jsonl:1", "review-a.jsonl:2", "review-b.jsonl:1"])
    }

    func testInputReorderingDeterminism() throws {
        let pass = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "passed", session: "ses-a", reason: "thorough")
        let fail = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "changes_requested", session: "ses-b", reason: "thorough")
        let solo = try sealedReview(recordId: "review/solo", subjectId: "lx:sense:solo",
                                    verdict: "passed", session: "ses-c", reason: "thorough")
        let (temp, sourceA) = try sourceDir(with: ["review-a.jsonl": [pass, solo, fail]])
        let sourceB = temp.appendingPathComponent("sourceB")
        try FileManager.default.createDirectory(at: sourceB, withIntermediateDirectories: true)
        // Same multiset, different file split and line order.
        for (name, lines) in ["review-z.jsonl": [fail, fail, solo], "review-a.jsonl": [pass]] {
            var out = Data()
            for line in lines {
                var bare = line
                if bare.last == 10 { bare.removeLast() }
                out.append(bare); out.append(10)
            }
            try out.write(to: sourceB.appendingPathComponent(name), options: .atomic)
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        let outA = temp.appendingPathComponent("outA")
        let outB = temp.appendingPathComponent("outB")
        try ReviewDisambiguation.disambiguate(sourceDir: sourceA, outputDir: outA)
        try ReviewDisambiguation.disambiguate(sourceDir: sourceB, outputDir: outB)
        // Canonical rows and derived IDs must not depend on input order.
        // (Mapping locations legitimately differ, so compare the review rows
        // plus the old->new identity pairs.)
        let rowsA = try Data(contentsOf: outA.appendingPathComponent("reviews-disambiguated.jsonl"))
        let rowsB = try Data(contentsOf: outB.appendingPathComponent("reviews-disambiguated.jsonl"))
        XCTAssertEqual(rowsA, rowsB)
        func identities(_ dir: URL) throws -> [(String, String)] {
            let mappings = try decodeMappings(dir)
            return mappings.map { ($0.oldRecordId, $0.newRecordId) }.sorted { $0.0 < $1.0 }
        }
        let idA = try identities(outA)
        let idB = try identities(outB)
        XCTAssertTrue(idA.elementsEqual(idB) { $0.0 == $1.0 && $0.1 == $1.1 })
    }

    func testDisagreementPreservedAndStillBlocked() throws {
        // Migrate a genuine conflict for the fixture sense subject, then prove
        // the migrated pair still fails the all-current aggregate: the
        // disagreement is preserved, and a passing winner is never chosen.
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let dataset = temp.appendingPathComponent("dataset")
        let reviews = temp.appendingPathComponent("reviews")
        try fm.copyItem(at: Self.validRoot.appendingPathComponent("dataset"), to: dataset)
        try fm.copyItem(at: Self.validRoot.appendingPathComponent("reviews"), to: reviews)

        let senseId = "lx:sense:22222222-2222-2222-2222-222222222222"
        let reviewFile = try fm.contentsOfDirectory(at: reviews, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .first { url in
                (try? String(contentsOf: url, encoding: .utf8))?.contains(senseId) ?? false
            }.unwrap(or: ContractFailure("no_review_for:\(senseId)"))
        let all = try String(contentsOf: reviewFile, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true).map { Data($0.utf8) }
        let base = try XCTUnwrap(all.first { line in
            ((try? JSONSerialization.jsonObject(with: line) as? [String: Any])
                .flatMap { $0["payload"] as? [String: Any] }
                .flatMap { $0["subject_id"] as? String }) == senseId
        })
        let baseRaw = try XCTUnwrap(JSONSerialization.jsonObject(with: base) as? [String: Any])
        let oldId = try XCTUnwrap(baseRaw["record_id"] as? String)
        // Raw history conflict: same old ID, one passed row and one
        // changes_requested row.
        let conflict = try resealed(base) { edited in
            var payload = edited["payload"] as! [String: Any]
            payload["verdict"] = "changes_requested"
            edited["payload"] = payload
        }
        let migSource = temp.appendingPathComponent("migSource")
        try fm.createDirectory(at: migSource, withIntermediateDirectories: true)
        try ([base, conflict] + [base]).map { line -> Data in
            var bare = line
            if bare.last == 10 { bare.removeLast() }
            return bare + Data([10])
        }.reduce(Data(), +).write(to: migSource.appendingPathComponent("review-m.jsonl"))
        let migOut = temp.appendingPathComponent("migOut")
        let report = try ReviewDisambiguation.disambiguate(sourceDir: migSource, outputDir: migOut)
        XCTAssertEqual(report.conflictIds, 1)
        XCTAssertEqual(report.verdictConflictIds, 1)
        XCTAssertEqual(report.outputRows, 2)

        // Replace the fixture subject's review with the migrated pair and
        // confirm the gate still rejects: disagreement blocks, never passes.
        let migrated = try String(contentsOf: migOut.appendingPathComponent("reviews-disambiguated.jsonl"),
                                  encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true).map { Data($0.utf8) }
        XCTAssertEqual(migrated.count, 2)
        let kept = all.filter { line in
            ((try? JSONSerialization.jsonObject(with: line) as? [String: Any])
                .flatMap { $0["payload"] as? [String: Any] }
                .flatMap { $0["subject_id"] as? String }) != senseId
        }
        var combined = Data()
        for line in kept + migrated {
            var bare = line
            if bare.last == 10 { bare.removeLast() }
            combined.append(bare); combined.append(10)
        }
        try combined.write(to: reviewFile, options: .atomic)
        XCTAssertNotEqual(oldId, (try? JSONSerialization.jsonObject(with: migrated[0]) as? [String: Any])
            .flatMap { $0["record_id"] as? String }, "conflicting IDs must be derived, never reused")
        XCTAssertThrowsError(try ReviewCoverage.audit(dataset: dataset, reviews: reviews, profile: nil)) {
            XCTAssertTrue(String(describing: $0).contains("review_not_passed:\(senseId)"), "\($0)")
        }
    }

    func testRepeatRunSafety() throws {
        let pass = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "passed", session: "ses-a", reason: "thorough")
        let fail = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "changes_requested", session: "ses-b", reason: "thorough")
        let (temp, source) = try sourceDir(with: ["review-a.jsonl": [pass, fail]])
        defer { try? FileManager.default.removeItem(at: temp) }
        let out1 = temp.appendingPathComponent("out1")
        let out2 = temp.appendingPathComponent("out2")
        try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out1)
        // Re-running the same migration is byte-identical.
        try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out2)
        for name in ["reviews-disambiguated.jsonl", "mapping.json", "ambiguous-references.json"] {
            XCTAssertEqual(try Data(contentsOf: out1.appendingPathComponent(name)),
                           try Data(contentsOf: out2.appendingPathComponent(name)), name)
        }
        // Re-running ON the output is an identity pass: no stacked suffixes.
        let out3 = temp.appendingPathComponent("out3")
        let rerun = try ReviewDisambiguation.disambiguate(sourceDir: out1, outputDir: out3)
        XCTAssertEqual(rerun.conflictIds, 0)
        XCTAssertEqual(try Data(contentsOf: out1.appendingPathComponent("reviews-disambiguated.jsonl")),
                       try Data(contentsOf: out3.appendingPathComponent("reviews-disambiguated.jsonl")))
        let mappings = try decodeMappings(out3)
        XCTAssertTrue(mappings.allSatisfy { $0.oldRecordId == $0.newRecordId })
        XCTAssertFalse(mappings.flatMap { [$0.oldRecordId, $0.newRecordId] }.joined()
            .contains("~h~h"), "derived IDs must never stack")
    }

    func testCurrentRawInputsStayReadonly() throws {
        let pass = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "passed", session: "ses-a", reason: "thorough")
        let (temp, source) = try sourceDir(with: ["review-a.jsonl": [pass]])
        func hashes(of dir: URL) throws -> [String: String] {
            var result: [String: String] = [:]
            for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                result[file.lastPathComponent] = CKHash.sha256Hex(of: try Data(contentsOf: file))
            }
            return result
        }
        let before = try hashes(of: source)
        defer { try? FileManager.default.removeItem(at: temp) }
        try ReviewDisambiguation.disambiguate(
            sourceDir: source, outputDir: temp.appendingPathComponent("out"))
        XCTAssertEqual(try hashes(of: source), before, "raw history must stay byte-identical")
    }

    func testRerunSameDestinationIsByteIdempotent() throws {
        let pass = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "passed", session: "ses-a", reason: "thorough")
        let fail = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "changes_requested", session: "ses-b", reason: "thorough")
        let decisions = Data("\n".utf8)
        let (temp, source) = try sourceDir(with: ["review-a.jsonl": [pass, fail]])
        try decisions.write(to: source.appendingPathComponent("human-decisions.jsonl"))
        // An existing triage subdirectory must survive reruns untouched.
        let triage = temp.appendingPathComponent("out/triage")
        try FileManager.default.createDirectory(at: triage, withIntermediateDirectories: true)
        try Data("owner triage".utf8).write(to: triage.appendingPathComponent("notes.md"))
        func snapshot(_ dir: URL) throws -> [String: Data] {
            var result: [String: Data] = [:]
            if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                       !isDir.boolValue {
                        result[url.path] = try Data(contentsOf: url)
                    }
                }
            }
            return result
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        let out = temp.appendingPathComponent("out")
        try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out)
        let first = try snapshot(out)
        XCTAssertGreaterThan(first.count, 0)
        try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out)
        XCTAssertEqual(try snapshot(out), first, "rerun must not change a single byte")
        XCTAssertEqual(try Data(contentsOf: triage.appendingPathComponent("notes.md")),
                       Data("owner triage".utf8))
    }

    func testNonemptyOwnerDecisionsPreservedAndRefused() throws {
        let pass = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "passed", session: "ses-a", reason: "thorough")
        let (temp, source) = try sourceDir(with: ["review-a.jsonl": [pass]])
        try Data("\n".utf8).write(to: source.appendingPathComponent("human-decisions.jsonl"))
        defer { try? FileManager.default.removeItem(at: temp) }
        let out = temp.appendingPathComponent("out")
        try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out)
        // A later owner decision lands in the canonical directory.
        let ownerLine = Data("{\"human_status\":\"accepted\"}\n".utf8)
        try ownerLine.write(to: out.appendingPathComponent("human-decisions.jsonl"))
        let triage = out.appendingPathComponent("triage")
        try FileManager.default.createDirectory(at: triage, withIntermediateDirectories: true)
        try Data("triage".utf8).write(to: triage.appendingPathComponent("t.md"))
        let reviewsBefore = try Data(contentsOf: out.appendingPathComponent("reviews-disambiguated.jsonl"))
        XCTAssertThrowsError(try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out)) {
            XCTAssertTrue(String(describing: $0).contains("disambiguation_output_conflict"),
                          "must refuse, never erase: \($0)")
        }
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("human-decisions.jsonl")),
                       ownerLine, "owner decisions must be preserved byte-exact")
        XCTAssertEqual(try Data(contentsOf: triage.appendingPathComponent("t.md")), Data("triage".utf8))
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("reviews-disambiguated.jsonl")),
                       reviewsBefore)
    }

    func testSourceOutputOverlapAndSymlinkRejected() throws {
        let pass = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "passed", session: "ses-a", reason: "thorough")
        let (temp, source) = try sourceDir(with: ["review-a.jsonl": [pass]])
        defer { try? FileManager.default.removeItem(at: temp) }
        XCTAssertThrowsError(try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: source)) {
            XCTAssertTrue(String(describing: $0).contains("disambiguation_source_is_output"), "\($0)")
        }
        let nested = source.appendingPathComponent("new-out")
        XCTAssertThrowsError(
            try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: nested)) {
            XCTAssertTrue(String(describing: $0).contains("disambiguation_output_inside_source"), "\($0)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path),
                       "failed runs must not create output")
        let outer = temp.appendingPathComponent("outer")
        let inner = outer.appendingPathComponent("inner")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source.appendingPathComponent("review-a.jsonl"),
                                         to: inner.appendingPathComponent("review-a.jsonl"))
        XCTAssertThrowsError(
            try ReviewDisambiguation.disambiguate(sourceDir: inner, outputDir: outer)) {
            XCTAssertTrue(String(describing: $0).contains("disambiguation_source_inside_output"), "\($0)")
        }
        let link = temp.appendingPathComponent("source-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(
            try ReviewDisambiguation.disambiguate(sourceDir: link,
                                                 outputDir: temp.appendingPathComponent("out-link"))) {
            XCTAssertTrue(String(describing: $0).contains("disambiguation_symlink"), "\($0)")
        }
        let outLink = temp.appendingPathComponent("out-link2")
        try FileManager.default.createSymbolicLink(at: outLink, withDestinationURL: temp)
        XCTAssertThrowsError(
            try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: outLink)) {
            XCTAssertTrue(String(describing: $0).contains("disambiguation_symlink"), "\($0)")
        }
    }

    func testDerivedIdCollisionFails() throws {
        let pass = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "passed", session: "ses-a", reason: "thorough")
        let fail = try sealedReview(recordId: "review/synth", subjectId: "lx:sense:synth",
                                    verdict: "changes_requested", session: "ses-b", reason: "thorough")
        var bare = fail
        if bare.last == 10 { bare.removeLast() }
        let predicted = "review/synth~h\(CKHash.sha256Hex(of: bare).prefix(12))"
        let squatter = try sealedReview(recordId: predicted, subjectId: "lx:sense:other",
                                        verdict: "passed", session: "ses-c", reason: "thorough")
        let (temp, source) = try sourceDir(with: ["review-a.jsonl": [pass, fail, squatter]])
        defer { try? FileManager.default.removeItem(at: temp) }
        let out = temp.appendingPathComponent("out")
        XCTAssertThrowsError(try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out)) {
            XCTAssertTrue(String(describing: $0).contains("disambiguation_id_collision"),
                          "colliding derived ID must fail loudly: \($0)")
            XCTAssertTrue(String(describing: $0).contains(predicted), "\($0)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path),
                       "colliding runs must not create output")
    }

    func testEmptyReviewInputsRejected() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = temp.appendingPathComponent("source")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try Data("{\"batch_id\":\"b\"}\n".utf8)
            .write(to: source.appendingPathComponent("family-verdicts.jsonl"))
        let out = temp.appendingPathComponent("out")
        XCTAssertThrowsError(try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out)) {
            XCTAssertTrue(String(describing: $0).contains("disambiguation_empty_reviews"), "\($0)")
        }
        XCTAssertFalse(fm.fileExists(atPath: out.path), "empty runs must not create output")
    }

    func testMissingSourceFailsActionablyWithoutCreatingOutput() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let missing = temp.appendingPathComponent("no-such-raw-history")
        let out = temp.appendingPathComponent("out")
        XCTAssertThrowsError(try ReviewDisambiguation.disambiguate(sourceDir: missing, outputDir: out)) {
            let text = String(describing: $0)
            XCTAssertTrue(text.contains("disambiguation_missing_source"), "\(text)")
            XCTAssertFalse(text.contains("NSCocoaErrorDomain"), "typed message, not a Cocoa traceback: \(text)")
        }
        XCTAssertFalse(fm.fileExists(atPath: out.path), "missing input must not create output")
        XCTAssertFalse(fm.fileExists(atPath: missing.path))
    }

    func testSyntheticSingleRowPrepWorks() throws {
        let row = try sealedReview(recordId: "review/synth-preflight", subjectId: "lx:sense:synth",
                                   verdict: "passed", session: "ses-a", reason: "thorough")
        let (temp, source) = try sourceDir(with: ["review-a.jsonl": [row]])
        defer { try? FileManager.default.removeItem(at: temp) }
        let out = temp.appendingPathComponent("out")
        let report = try ReviewDisambiguation.disambiguate(sourceDir: source, outputDir: out)
        XCTAssertEqual(report.totalRows, 1)
        XCTAssertEqual(report.outputRows, 1)
        let outRow = try Data(contentsOf: out.appendingPathComponent("reviews-disambiguated.jsonl"))
        guard case .review = try ContractJSON.decode(Data(outRow.dropLast())) else {
            return XCTFail("synthetic prep must reseal cleanly")
        }
    }

    // MARK: - Helpers

    private func resealed(_ data: Data, mutate: (inout [String: Any]) -> Void) throws -> Data {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&raw)
        let edited = try JSONSerialization.data(
            withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        var sealed = try ContractJSON.line(ContractJSON.seal(edited))
        sealed.removeLast()
        return sealed
    }
}

private extension Optional {
    func unwrap(or error: Error) throws -> Wrapped {
        guard let value = self else { throw error }
        return value
    }
}
