import ContentModel
import Foundation

/// A pending review packet, not an acceptance gate. Audit recomputes the entire
/// packet from input bytes, rather than trusting a revision or a supplied seal.
public enum HumanReportCommands {
    private typealias Row = [String: Any]
    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ reason: String) { description = "HumanReportFailure(\(reason))" }
    }
    private struct Located {
        let row: Row
        let file: URL
        let line: Int
    }
    private static func bytes(_ value: Any, pretty: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes])
    }
    private static func text(_ value: Any, pretty: Bool = false) throws -> String {
        String(decoding: try bytes(value, pretty: pretty), as: UTF8.self)
    }
    private static func payload(_ row: Row) -> Row { row["payload"] as? Row ?? row }
    private static func files(_ directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private static func rows(_ file: URL) throws -> [Located] {
        let data = try Data(contentsOf: file)
        guard let string = String(data: data, encoding: .utf8), !data.contains(13), string.isEmpty || string.hasSuffix("\n") else {
            throw Failure("invalid_jsonl:\(file.path)")
        }
        return try string.split(separator: "\n").enumerated().map { index, line in
            guard let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? Row else { throw Failure("invalid_object") }
            return Located(row: row, file: file, line: index + 1)
        }
    }
    private static func relative(_ file: URL, from directory: URL) -> String {
        let a = directory.standardizedFileURL.pathComponents, b = file.standardizedFileURL.pathComponents
        var common = 0
        while common < min(a.count, b.count), a[common] == b[common] { common += 1 }
        return (Array(repeating: "..", count: a.count - common) + b.dropFirst(common)).joined(separator: "/")
    }
    private static func check(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw Failure(reason) }
    }
    private static func canonical(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    }

    public static func run(_ arguments: [String]) -> Int32 {
        do {
            let required = ["--dataset", "--reviews", "--profile", "--seed", "--out", "--evidence"]
            guard let mode = arguments.first, ["human-recheck", "audit-human-recheck"].contains(mode), arguments.count == 13 else {
                throw Failure("required_flags:dataset,reviews,profile,seed,out,evidence")
            }
            var flags: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) {
                let key = arguments[index], value = arguments[index + 1]
                try check(required.contains(key) && flags[key] == nil && !value.isEmpty && !value.hasPrefix("--"), "invalid_or_duplicate_flag")
                flags[key] = value
            }
            guard let datasetPath = flags["--dataset"], let reviewsPath = flags["--reviews"],
                  let profilePath = flags["--profile"], let seedText = flags["--seed"], let seed = Int(seedText),
                  let outPath = flags["--out"], let evidencePath = flags["--evidence"] else { throw Failure("missing_flags") }
            let dataset = canonical(datasetPath), reviews = canonical(reviewsPath), profileURL = canonical(profilePath)
            let out = canonical(outPath), evidence = canonical(evidencePath), base = out.deletingLastPathComponent()
            try check(!FileManager.default.fileExists(atPath: evidence.path) || mode == "audit-human-recheck", "evidence_already_exists_use_fresh_path")
            let decisions = reviews.appendingPathComponent("human-decisions.jsonl")
            // Never erase, rewrite, or impersonate an existing human decision.
            if FileManager.default.fileExists(atPath: decisions.path) {
                try check(Data(contentsOf: decisions).isEmpty, "pending_packet_has_existing_human_decisions")
            }
            let packet = reviews.appendingPathComponent("human-recheck.jsonl"), sampleURL = reviews.appendingPathComponent("sample.json")
            let datasetFiles = try files(dataset)
            let reviewFiles = try files(reviews).filter { ![packet.lastPathComponent, decisions.lastPathComponent].contains($0.lastPathComponent) }
            let historyFiles = dataset.lastPathComponent == "merged" ? try files(dataset.deletingLastPathComponent()) : []
            let inputs = datasetFiles + reviewFiles + historyFiles + [profileURL]
            for output in [out, evidence, packet, sampleURL, decisions] {
                try check(output != dataset && !output.path.hasPrefix(dataset.path + "/"), "output_overlaps_dataset")
                for input in inputs {
                    try check(output != input, "output_overlaps_input")
                    if FileManager.default.fileExists(atPath: output.path) {
                        let a = try FileManager.default.attributesOfItem(atPath: input.path)
                        let b = try FileManager.default.attributesOfItem(atPath: output.path)
                        try check(a[.systemFileNumber] as? NSNumber != b[.systemFileNumber] as? NSNumber, "output_aliases_input")
                    }
                }
            }
            try check(Set([out.path, evidence.path, packet.path, sampleURL.path, decisions.path]).count == 5, "colliding_outputs")
            guard let profile = try JSONSerialization.jsonObject(with: Data(contentsOf: profileURL)) as? Row,
                  let policy = profile["human_sample_policy"] as? Row,
                  let strata = policy["strata"] as? [String: Int], !strata.isEmpty,
                  strata.values.allSatisfy({ $0 > 0 }), policy["seed"] as? Int == seed else { throw Failure("invalid_sampling_policy") }
            let located = try datasetFiles.flatMap { try rows($0) }
            var records: [String: Row] = [:], locations: [String: Located] = [:]
            for item in located {
                guard let id = item.row["record_id"] as? String, let revision = item.row["revision"] as? Int else { throw Failure("missing_record_binding") }
                if let old = records[id] {
                    let prior = old["revision"] as? Int ?? 0
                    try check(prior != revision, "duplicate_revision:\(id)")
                    if prior > revision { continue }
                }
                records[id] = item.row; locations[id] = item
            }
            try check(!records.isEmpty, "empty_dataset")
            let history = try historyFiles.flatMap { try rows($0) }
            let reviewRows = try reviewFiles.flatMap { try rows($0) }
            var bySubject: [String: [Located]] = [:]
            var risks: [String: Set<String>] = [:]
            for id in policy["high_risk_ids"] as? [String] ?? [] where records[id] != nil {
                risks[id, default: []].insert("profile_high_risk")
            }
            // Retain historical findings, including resolved errors and stale revisions.
            for item in reviewRows {
                let p = payload(item.row)
                var ids = [p["subject_id"] as? String, p["question_id"] as? String].compactMap { $0 }
                if let target = p["target_id"] as? String {
                    ids += records.keys.filter { payload(records[$0] ?? [:])["primary_target_id"] as? String == target }
                }
                let findings = p["findings"] as? [Row] ?? []
                let verdict = p["verdict"] as? String
                let flagged = !findings.isEmpty || (verdict != nil && !["passed", "independent"].contains(verdict ?? ""))
                    || p["answerable"] as? Bool == false || p["disagreement"] as? Bool == true
                for id in Set(ids) where records[id] != nil {
                    bySubject[id, default: []].append(item)
                    if flagged {
                        risks[id, default: []].insert("review_flag_or_fixed_error")
                    }
                    if let question = records[id], question["kind"] as? String == "question",
                       let chosen = p["chosen_option_id"] as? String,
                       let answers = payload(question)["accepted_answers"] as? [String], !answers.contains(chosen) {
                        risks[id, default: []].insert("blind_answer_disagreement")
                    }
                }
            }
            for (id, items) in bySubject {
                let verdicts = Set(items.compactMap { payload($0.row)["verdict"] as? String })
                if verdicts.count > 1 { risks[id, default: []].insert("agent_verdict_disagreement") }
            }
            // Explicit second senses and nonempty aliases remain visible even when a
            // later favourable review no longer repeats their original warning.
            for (id, row) in records {
                let p = payload(row)
                if row["kind"] as? String == "entry", !(p["aliases"] as? [Any] ?? []).isEmpty {
                    risks[id, default: []].insert("alias_flagged")
                }
                if row["kind"] as? String == "entry", let senses = p["sense_ids"] as? [String], senses.count > 1 {
                    for sense in senses { risks[sense, default: []].insert("second_sense") }
                }
            }
            var reasons = risks
            var draws: [String: [String]] = [:], populations: [String: Int] = [:]
            for stratum in strata.keys.sorted() {
                let population = records.keys.filter { id in
                    let row = records[id] ?? [:]
                    return "\(row["kind"] as? String ?? ""):\(payload(row)["tested_ability"] as? String ?? "")" == stratum && risks[id] == nil
                }.sorted { left, right in
                    let a = CKHash.sha256Hex(of: Data("\(seed)|\(stratum)|\(left)".utf8))
                    let b = CKHash.sha256Hex(of: Data("\(seed)|\(stratum)|\(right)".utf8))
                    return a == b ? left < right : a < b
                }
                populations[stratum] = population.count
                draws[stratum] = Array(population.prefix(strata[stratum] ?? 1))
                for id in draws[stratum] ?? [] { reasons[id, default: []].insert("stratified_random") }
            }
            var entries: [Row] = []
            for id in reasons.keys.sorted() {
                guard let row = records[id], let location = locations[id] else { throw Failure("unknown_selected_subject:\(id)") }
                let p = payload(row), target = records[p["primary_target_id"] as? String ?? ""] ?? (row["kind"] as? String == "target" ? row : [:])
                let tp = payload(target)
                let sense = records[tp["sense_id"] as? String ?? ""] ?? (row["kind"] as? String == "sense" ? row : [:])
                let entry = records[tp["entry_id"] as? String ?? payload(sense)["entry_id"] as? String ?? ""] ?? (row["kind"] as? String == "entry" ? row : [:])
                let entryID = entry["record_id"] as? String
                let contextSenses = records.values.filter { other in
                    other["kind"] as? String == "sense" && entryID != nil && payload(other)["entry_id"] as? String == entryID
                }.sorted { ($0["record_id"] as? String ?? "") < ($1["record_id"] as? String ?? "") }
                let senseIDs = Set(contextSenses.compactMap { $0["record_id"] as? String } + [sense["record_id"] as? String].compactMap { $0 })
                let contextTargets = records.values.filter { other in
                    other["kind"] as? String == "target" && (senseIDs.contains(payload(other)["sense_id"] as? String ?? "")
                        || entryID != nil && payload(other)["entry_id"] as? String == entryID)
                }.sorted { ($0["record_id"] as? String ?? "") < ($1["record_id"] as? String ?? "") }
                let targetIDs = Set(contextTargets.compactMap { $0["record_id"] as? String } + [target["record_id"] as? String].compactMap { $0 })
                let related = records.values.filter { other in
                    let op = payload(other)
                    return ["question", "teaching"].contains(other["kind"] as? String ?? "")
                        && (targetIDs.contains(op["primary_target_id"] as? String ?? "")
                            || (payload(sense)["usage_ids"] as? [String] ?? []).contains(other["record_id"] as? String ?? ""))
                }.sorted { ($0["record_id"] as? String ?? "") < ($1["record_id"] as? String ?? "") }
                let reviewsForID = bySubject[id] ?? []
                let findingRows = reviewsForID.flatMap { payload($0.row)["findings"] as? [Row] ?? [] }
                let before = history.filter { $0.row["record_id"] as? String == id && ($0.row["revision"] as? Int ?? 0) < (row["revision"] as? Int ?? 0) }
                entries.append([
                    "record_id": id, "revision": row["revision"] ?? NSNull(), "content_sha256": row["content_sha256"] ?? NSNull(),
                    "actual_record_sha256": CKHash.sha256Hex(of: try bytes(row)), "kind": row["kind"] ?? NSNull(),
                    "word_or_phrase": entry, "sense": sense, "ability": p["tested_ability"] ?? tp["tested_ability"] ?? NSNull(),
                    "subject": row, "target": target, "context_senses": contextSenses, "context_targets": contextTargets,
                    "complete_teaching_and_questions": related,
                    "selection_reasons": Array(reasons[id] ?? []).sorted(), "severity": Array(Set(findingRows.compactMap { $0["severity"] as? String })).sorted(),
                    "agent_verdicts_and_disagreements": reviewsForID.map { item -> Row in
                        ["source": relative(item.file, from: base), "line": item.line, "review": item.row]
                    },
                    "before_fixes": before.map { ["source": relative($0.file, from: base), "line": $0.line, "record": $0.row] as Row },
                    "before_fixes_status": before.isEmpty ? "No earlier subject snapshot in source files; historical findings and review evidence retained, no reconstruction invented." : "Earlier source snapshots retained; compare revisions, not a claim that every change is accepted.",
                    "after_fixes": row, "source_ref": relative(location.file, from: base), "source_line": location.line,
                    "what_to_check": ["Check lemma/phrase, aliases, POS and intended sense against the complete teaching.", "Solve each question; check all options, accepted answers, distractor rationales and feedback.", "Compare historical findings and before/after revisions; confirm fixes do not hide prior critical errors.", "Check provenance and pending source rights; independent agent verdicts are not human approval."],
                    "human_status": "pending", "human_decision": NSNull()
                ])
            }
            let bindings = try inputs.map { file -> Row in
                ["path": relative(file, from: base), "sha256": CKHash.sha256Hex(of: try Data(contentsOf: file))]
            }
            let sample: Row = ["seed": seed, "algorithm": "SHA256(seed|stratum|record_id), ID tie-break", "strata": strata,
                "unflagged_populations": populations, "unflagged_draws": draws, "high_risk_count": risks.count,
                "selected_count": entries.count, "inputs": bindings, "human_review_pending": true, "release_eligible": false]
            var artifacts: [URL: Data] = [:]
            artifacts[packet] = Data(try entries.map { try text($0) + "\n" }.joined().utf8)
            artifacts[sampleURL] = try bytes(sample, pretty: true)
            let pageDirectory = base.appendingPathComponent("owner-recheck-pages")
            var index = "# Owner recheck — PENDING\n\nNo human decisions have been made. This packet grants no approval or release permission. Source rights pending; costs unknown.\n\nSeed: \(seed). Selected subjects: \(entries.count); high-risk census: \(risks.count). Historical risks are never capped by the trial-era maximum.\n\n[Selection and input hashes](\(relative(sampleURL, from: base))) · [Full JSONL](\(relative(packet, from: base))) · [Human decisions (empty)](\(relative(decisions, from: base)))\n\n## Unflagged random strata\n\n"
            for stratum in strata.keys.sorted() {
                index += "- \(stratum): population \(populations[stratum] ?? 0), drawn \(draws[stratum]?.count ?? 0) (minimum \(strata[stratum] ?? 1) when population exists).\n"
            }
            index += "\n## Full entries\n\nEach page contains complete source records, teaching, questions, answers/feedback, historical review evidence and pending owner fields. JSON is shown verbatim without summarizing away content.\n\n"
            for start in stride(from: 0, to: entries.count, by: 20) {
                let page = pageDirectory.appendingPathComponent(String(format: "page-%04d.md", start / 20 + 1))
                var markdown = "# Pending owner recheck \(start + 1)–\(min(start + 20, entries.count))\n\n[Back to index](../\(out.lastPathComponent))\n\n"
                for item in entries[start..<min(start + 20, entries.count)] {
                    let id = item["record_id"] as? String ?? ""
                    markdown += "## \(id) · revision \(item["revision"] ?? "") · PENDING\n\n"
                    if let source = item["source_ref"] as? String { markdown += "[Current source](../\(source)) (line \(item["source_line"] ?? ""))\n\n" }
                    markdown += "<pre>\n\(try text(item, pretty: true).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))\n</pre>\n\nHuman decision: **pending**. Owner signature: —\n\n"
                }
                artifacts[page] = Data(markdown.utf8)
                index += "- [Subjects \(start + 1)–\(min(start + 20, entries.count))](\(relative(page, from: base)))\n"
            }
            artifacts[out] = Data(index.utf8)
            if mode == "audit-human-recheck" {
                try check(FileManager.default.fileExists(atPath: decisions.path), "missing_pending_decisions")
                for (file, expected) in artifacts {
                    try check(Data(contentsOf: file) == expected, "stale_or_incomplete_packet:\(file.lastPathComponent)")
                }
            } else {
                for (file, data) in artifacts {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: file, options: .atomic)
                }
                if !FileManager.default.fileExists(atPath: decisions.path) { try Data().write(to: decisions, options: .withoutOverwriting) }
            }
            let report: Row = ["valid": true, "mode": mode, "selected_count": entries.count, "high_risk_count": risks.count,
                "sample": sample, "human_review_pending": true, "human_accepted_count": 0, "release_eligible": false,
                "artifacts": artifacts.keys.sorted { $0.path < $1.path }.map { file -> Row in
                    ["path": relative(file, from: base), "sha256": CKHash.sha256Hex(of: artifacts[file] ?? Data())]
                }]
            try FileManager.default.createDirectory(at: evidence.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Audit may use the same evidence flag as generation (the public CLI
            // contract); preserve that original evidence instead of replacing it.
            if !FileManager.default.fileExists(atPath: evidence.path) { try bytes(report, pretty: true).write(to: evidence, options: .withoutOverwriting) }
            print("valid=true selected=\(entries.count) high_risk=\(risks.count) human_review_pending=true release_eligible=false")
            return 0
        } catch {
            fputs("\(error)\n", stderr)
            return 65
        }
    }
}
