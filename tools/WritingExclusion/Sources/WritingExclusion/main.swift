import ContentModel
import Foundation

// Narrow one-shot migration: quarantine the two writing targets, the four
// writing questions and the two writing teachings in a merged pilot file set,
// then rebind the eight directly-associated provenance rows to the new
// subject revisions/hashes. Every mutated row is resealed through
// ContractJSON.seal (canonical bytes + real SHA-256), never hand-hashed.
// Provenance review_refs stay empty: there is no new passed review to bind,
// and forging one is forbidden.
//
// Safety order: ALL four input files are decoded and count-checked up front;
// a fully-applied dataset is REFUSED before any write; all outputs are
// prepared in memory first and only dirty files are rewritten atomically,
// preserving line order.
//
// Usage:
//   WritingExclusion <mergedDir> <targetFile> <questionFile> <teachingFile> <provenanceFile>
// All paths except mergedDir are basenames inside mergedDir.

let writingTargets: Set<String> = [
    "lx:target:bf7b049b-a730-4601-bbb5-66aca9719be1",
    "lx:target:d9b72d9f-9c59-4f79-8a6f-de0c7359d3ec",
]
let writingQuestions: Set<String> = [
    "lx:question:3751e6fa-6dcc-460f-9bb0-66d681bf6b2a",
    "lx:question:e0c837c6-9845-4394-bdc5-2fc6b7647d08",
    "lx:question:6d4352b7-7571-41b8-b9f8-ab9c8a91a456",
    "lx:question:dd2d4bbe-0818-4403-b178-e8661a3a762c",
]
let writingTeachings: Set<String> = [
    "lx:usage:07c3df26-12fb-484b-bfa6-efd11f402277",
    "lx:usage:2aab3654-b856-4c3d-a8e5-8fa5003a36ea",
]
let writingSubjects = writingTargets.union(writingQuestions).union(writingTeachings)

func fail(_ message: String) -> Never {
    fputs("WritingExclusion: \(message)\n", stderr)
    exit(65)
}

func readLines(at url: URL) throws -> [String] {
    let text = try String(contentsOf: url, encoding: .utf8)
    guard text.hasSuffix("\n") else { throw ContractFailure("missing_trailing_lf") }
    return text.dropLast().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

func parseDict(_ line: String) throws -> [String: Any] {
    guard let data = line.data(using: .utf8),
          let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ContractFailure("invalid_json")
    }
    return dict
}

func sealDict(_ dict: [String: Any]) throws -> (record: ContractRecord, line: String) {
    let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .withoutEscapingSlashes])
    var sealed = data
    sealed.append(10)
    let record = try ContractJSON.seal(sealed)
    guard let text = String(data: try ContractJSON.line(record), encoding: .utf8) else {
        throw ContractFailure("reseal_encode")
    }
    let line = String(text.dropLast())
    // Candidate decode must pass on the resealed bytes (validates hash binding).
    _ = try ContractJSON.decode(Data((line + "\n").utf8))
    return (record, line)
}

func isFinalContent(_ dict: [String: Any], isTarget: Bool) -> Bool {
    guard let payload = dict["payload"] as? [String: Any],
          payload["status"] as? String == "quarantined" else { return false }
    if isTarget { return payload["activation"] as? String == "inactive" }
    return true
}

let args = CommandLine.arguments
guard args.count == 6 else {
    fail("usage: WritingExclusion <mergedDir> <targetFile> <questionFile> <teachingFile> <provenanceFile>")
}
let mergedDir = URL(fileURLWithPath: args[1])
let targetURL = mergedDir.appendingPathComponent(args[2])
let questionURL = mergedDir.appendingPathComponent(args[3])
let teachingURL = mergedDir.appendingPathComponent(args[4])
let provenanceURL = mergedDir.appendingPathComponent(args[5])

// Phase 1: read and decode ALL input rows up front; nothing is written yet.
let targetLines = try readLines(at: targetURL)
let questionLines = try readLines(at: questionURL)
let teachingLines = try readLines(at: teachingURL)
let provenanceLines = try readLines(at: provenanceURL)
for line in targetLines + questionLines + teachingLines + provenanceLines {
    _ = try ContractJSON.decode(Data((line + "\n").utf8))
}

var targetDicts: [String: [String: Any]] = [:]
for line in targetLines {
    let dict = try parseDict(line)
    guard let id = dict["record_id"] as? String else { throw ContractFailure("missing_record_id") }
    if writingTargets.contains(id) { targetDicts[id] = dict }
}
var questionDicts: [String: [String: Any]] = [:]
for line in questionLines {
    let dict = try parseDict(line)
    guard let id = dict["record_id"] as? String else { throw ContractFailure("missing_record_id") }
    if writingQuestions.contains(id) { questionDicts[id] = dict }
}
var teachingDicts: [String: [String: Any]] = [:]
for line in teachingLines {
    let dict = try parseDict(line)
    guard let id = dict["record_id"] as? String else { throw ContractFailure("missing_record_id") }
    if writingTeachings.contains(id) { teachingDicts[id] = dict }
}
guard targetDicts.count == 2 else { fail("expected 2 writing targets, found \(targetDicts.count)") }
guard questionDicts.count == 4 else { fail("expected 4 writing questions, found \(questionDicts.count)") }
guard teachingDicts.count == 2 else { fail("expected 2 writing teachings, found \(teachingDicts.count)") }

var provenanceDicts: [[String: Any]] = []
for line in provenanceLines {
    let dict = try parseDict(line)
    guard let payload = dict["payload"] as? [String: Any],
          payload["subject_id"] as? String != nil else { throw ContractFailure("missing_provenance_subject") }
    provenanceDicts.append(dict)
}
let writingProvenance = provenanceDicts.filter {
    writingSubjects.contains(($0["payload"] as? [String: Any])?["subject_id"] as? String ?? "")
}
guard writingProvenance.count == 8 else { fail("expected 8 writing provenance rows, found \(writingProvenance.count)") }

// Current subject bindings straight from the validated input.
func binding(of dict: [String: Any]) throws -> (revision: Int, sha: String) {
    guard let revision = dict["revision"] as? Int,
          let sha = dict["content_sha256"] as? String else { throw ContractFailure("missing_revision_or_hash") }
    return (revision, sha)
}
var currentBindings: [String: (revision: Int, sha: String)] = [:]
for (id, dict) in targetDicts { currentBindings[id] = try binding(of: dict) }
for (id, dict) in questionDicts { currentBindings[id] = try binding(of: dict) }
for (id, dict) in teachingDicts { currentBindings[id] = try binding(of: dict) }

let contentFinal = targetDicts.values.allSatisfy { isFinalContent($0, isTarget: true) }
    && questionDicts.values.allSatisfy { isFinalContent($0, isTarget: false) }
    && teachingDicts.values.allSatisfy { isFinalContent($0, isTarget: false) }
let provenanceBound = writingProvenance.allSatisfy { dict in
    guard let payload = dict["payload"] as? [String: Any],
          let subject = payload["subject_id"] as? String,
          let current = currentBindings[subject] else { return false }
    return payload["subject_revision"] as? Int == current.revision
        && payload["subject_content_sha256"] as? String == current.sha
        && (payload["review_refs"] as? [Any])?.isEmpty == true
}

// Phase 2: refuse reapplication BEFORE ANY writes.
if contentFinal && provenanceBound {
    fail("already_applied: all 8 writing subjects quarantined/inactive and all 8 provenance rows bound; refusing reapplication")
}

// Phase 3: prepare all outputs in memory. Final rows are kept byte-identical;
// only non-final rows are migrated and resealed.
var newBindings = currentBindings
var migrated: [String] = []
let prepareContent: ([String: Any], Bool, String) throws -> String = { dict, isTarget, file in
    guard let id = dict["record_id"] as? String else { throw ContractFailure("missing_record_id") }
    if isFinalContent(dict, isTarget: isTarget) { return try sealDict(dict).line }
    var mutable = dict
    guard var payload = mutable["payload"] as? [String: Any],
          let revision = mutable["revision"] as? Int else { throw ContractFailure("missing_payload_or_revision") }
    payload["status"] = "quarantined"
    if isTarget { payload["activation"] = "inactive" }
    mutable["payload"] = payload
    mutable["revision"] = revision + 1
    let (record, line) = try sealDict(mutable)
    newBindings[id] = (record.document.revision, record.document.contentSha256)
    migrated.append("\(file):\(id)")
    return line
}

let prepareFile: ([String], Set<String>, Bool, String) throws -> ([String], Bool) = { lines, ids, isTarget, file in
    var out: [String] = []
    var dirty = false
    for line in lines {
        let dict = try parseDict(line)
        guard let id = dict["record_id"] as? String, ids.contains(id) else { out.append(line); continue }
        let prepared = try prepareContent(dict, isTarget, file)
        if prepared != line { dirty = true }
        out.append(prepared)
    }
    return (out, dirty)
}

let (targetOut, targetDirty) = try prepareFile(targetLines, writingTargets, true, targetURL.lastPathComponent)
let (questionOut, questionDirty) = try prepareFile(questionLines, writingQuestions, false, questionURL.lastPathComponent)
let (teachingOut, teachingDirty) = try prepareFile(teachingLines, writingTeachings, false, teachingURL.lastPathComponent)

// Prepare provenance against the NEW bindings; keep already-bound rows identical.
var provOut: [String] = []
var rebound = 0
var provDirty = false
for line in provenanceLines {
    let dict = try parseDict(line)
    guard let payload = dict["payload"] as? [String: Any],
          let subject = payload["subject_id"] as? String,
          let binding = newBindings[subject], writingSubjects.contains(subject) else {
        provOut.append(line); continue
    }
    if payload["subject_revision"] as? Int == binding.revision
        && payload["subject_content_sha256"] as? String == binding.sha
        && (payload["review_refs"] as? [Any])?.isEmpty == true {
        provOut.append(line)
        rebound += 1
        continue
    }
    var mutable = dict
    var updated = payload
    updated["subject_revision"] = binding.revision
    updated["subject_content_sha256"] = binding.sha
    // No new passed review exists; keep review_refs empty and report the gap honestly.
    updated["review_refs"] = []
    mutable["payload"] = updated
    guard let revision = mutable["revision"] as? Int else { throw ContractFailure("missing_revision") }
    mutable["revision"] = revision + 1
    let (_, sealed) = try sealDict(mutable)
    provOut.append(sealed)
    rebound += 1
    provDirty = true
    migrated.append("\(provenanceURL.lastPathComponent):\(subject)")
}
guard rebound == 8 else { fail("expected 8 bound provenance rows, found \(rebound)") }

// Phase 4: all outputs prepared and verified; write only dirty files.
if targetDirty { try (targetOut.joined(separator: "\n") + "\n").write(to: targetURL, atomically: true, encoding: .utf8) }
if questionDirty { try (questionOut.joined(separator: "\n") + "\n").write(to: questionURL, atomically: true, encoding: .utf8) }
if teachingDirty { try (teachingOut.joined(separator: "\n") + "\n").write(to: teachingURL, atomically: true, encoding: .utf8) }
if provDirty { try (provOut.joined(separator: "\n") + "\n").write(to: provenanceURL, atomically: true, encoding: .utf8) }

for key in migrated.sorted() { print("migrated \(key)") }
print("rebound_provenance=\(rebound)")
