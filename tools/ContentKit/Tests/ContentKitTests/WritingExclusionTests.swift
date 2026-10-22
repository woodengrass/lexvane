import Foundation
import XCTest
import ContentModel
@testable import ContentCLI

/// Writing-exclusion regression gate (DECISIONS-M1 section 7):
/// both writing targets are inactive+quarantined, all writing
/// questions/teachings are quarantined, provenance is rebound to the
/// new subject revisions, and the effective v2 policy/supply excludes
/// writing. Reads the REAL merged pilots (no synthetic fixtures).
final class WritingExclusionTests: XCTestCase {
    private static let writingTargets = [
        "lx:target:bf7b049b-a730-4601-bbb5-66aca9719be1",
        "lx:target:d9b72d9f-9c59-4f79-8a6f-de0c7359d3ec",
    ]
    private static let writingQuestions = [
        "lx:question:3751e6fa-6dcc-460f-9bb0-66d681bf6b2a",
        "lx:question:e0c837c6-9845-4394-bdc5-2fc6b7647d08",
        "lx:question:6d4352b7-7571-41b8-b9f8-ab9c8a91a456",
        "lx:question:dd2d4bbe-0818-4403-b178-e8661a3a762c",
    ]
    private static let writingTeachings = [
        "lx:usage:07c3df26-12fb-484b-bfa6-efd11f402277",
        "lx:usage:2aab3654-b856-4c3d-a8e5-8fa5003a36ea",
    ]
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    private func merged(_ pilot: String) -> URL {
        repoRoot.appendingPathComponent("content/records/\(pilot)/merged")
    }
    private func load(_ dir: URL) throws -> [ContractRecord] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { try CKJSONL.readLines(at: $0).map { try ContractJSON.decode(Data($0.utf8)) } }
    }
    private func read<T: Decodable>(_ type: T.Type, path: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    func testBothPilotMergedDecodeAtCandidate() throws {
        // Given: the two current merged pilots after the exclusion migration.
        // When: candidate validation decodes every row (hash binding enforced).
        let fifty = try ContractDataset.validate(at: merged("pilot-50"))
        let twoThirty = try ContractDataset.validate(at: merged("pilot-230"))
        // Then: both decode clean with unchanged record counts.
        XCTAssertTrue(fifty.valid)
        XCTAssertEqual(fifty.recordCount, 666)
        XCTAssertTrue(twoThirty.valid)
        XCTAssertEqual(twoThirty.recordCount, 4370)
    }

    func testWritingTargetsInactiveAndQuarantined() throws {
        // Given: both current merged pilots.
        for pilot in ["pilot-50", "pilot-230"] {
            let records = try load(merged(pilot))
            let targets = records.compactMap { record -> Target? in
                if case .target(let v) = record { return v }; return nil
            }
            // When: inspecting the two writing targets.
            for id in Self.writingTargets {
                let matches = targets.filter { $0.recordId == id }
                // Then: exactly one row, inactive, quarantined, revision-bumped.
                XCTAssertEqual(matches.count, 1, "\(pilot) \(id)")
                XCTAssertEqual(matches.first?.payload.activation, .inactive)
                XCTAssertEqual(matches.first?.payload.status, .quarantined)
                XCTAssertEqual(matches.first?.revision, 2)
            }
            // And: no active writing target remains eligible anywhere.
            XCTAssertFalse(targets.contains {
                $0.payload.testedAbility == .writing && $0.payload.activation == .active
            }, "\(pilot) has an active writing target")
        }
    }

    func testWritingQuestionsAndTeachingsQuarantined() throws {
        // Given: both current merged pilots.
        for pilot in ["pilot-50", "pilot-230"] {
            let records = try load(merged(pilot))
            var questions: [Question] = []
            var teachings: [Teaching] = []
            for record in records {
                if case .question(let v) = record { questions.append(v) }
                if case .teaching(let v) = record { teachings.append(v) }
            }
            // When: inspecting the writing supply rows.
            let expectedRevisions = [4, 8, 6, 4]
            for (id, revision) in zip(Self.writingQuestions, expectedRevisions) {
                let matches = questions.filter { $0.recordId == id }
                XCTAssertEqual(matches.count, 1, "\(pilot) \(id)")
                XCTAssertEqual(matches.first?.payload.status, .quarantined)
                XCTAssertEqual(matches.first?.revision, revision)
            }
            for id in Self.writingTeachings {
                let matches = teachings.filter { $0.recordId == id }
                XCTAssertEqual(matches.count, 1, "\(pilot) \(id)")
                XCTAssertEqual(matches.first?.payload.status, .quarantined)
                XCTAssertEqual(matches.first?.revision, 2)
            }
            // Then: zero writing records remain eligible.
            XCTAssertFalse(questions.contains { $0.payload.status != .quarantined && $0.payload.testedAbility == .writing })
            XCTAssertFalse(teachings.contains { $0.payload.status != .quarantined && $0.payload.testedAbility == .writing })
        }
    }

    func testWritingProvenanceReboundHonestly() throws {
        // Given: both current merged pilots.
        for pilot in ["pilot-50", "pilot-230"] {
            let records = try load(merged(pilot))
            var subjects: [String: (Int, String)] = [:]
            var provenances: [Provenance] = []
            for record in records {
                subjects[record.recordId] = (record.document.revision, record.document.contentSha256)
                if case .provenance(let v) = record { provenances.append(v) }
            }
            // When: inspecting provenance for the eight writing subjects.
            let subjectsUnderTest = Self.writingTargets + Self.writingQuestions + Self.writingTeachings
            var rebound = 0
            for provenance in provenances where subjectsUnderTest.contains(provenance.payload.subjectId) {
                rebound += 1
                // Then: the binding tracks the current subject revision/hash ...
                let current = try XCTUnwrap(subjects[provenance.payload.subjectId])
                XCTAssertEqual(provenance.payload.subjectRevision, current.0, provenance.recordId)
                XCTAssertEqual(provenance.payload.subjectContentSha256, current.1, provenance.recordId)
                // ... and no review is forged: obsolete refs stay cleared.
                XCTAssertTrue(provenance.payload.reviewRefs.isEmpty, provenance.recordId)
            }
            XCTAssertEqual(rebound, 8, pilot)
        }
    }

    func testV2PolicyExcludesWriting() throws {
        // Given: the effective versioned quality policy.
        let url = repoRoot.appendingPathComponent("content/policies/pilot-quality-v2.json")
        let profile: QualityProfile = try read(QualityProfile.self, path: url.path)
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        // When / Then: writing is excluded from scope, gates stay frozen-blocked.
        XCTAssertEqual(profile.profile, "pilot-quality-v2")
        XCTAssertEqual(Set(profile.activeAbilities), [.contextualChoice, .meaningRecognition])
        XCTAssertEqual(Set(profile.excludedTargetIds), Set(Self.writingTargets))
        XCTAssertEqual(Set(profile.perAbilityMinimums.keys), ["contextual_choice", "meaning_recognition"])
        XCTAssertEqual(raw?["recommendation"] as? String, "blocked-on-writing-contract")
        XCTAssertEqual(raw?["release_eligible"] as? Bool, false)
        let sample = raw?["human_sample_policy"] as? [String: Any]
        XCTAssertEqual(sample?["denominator"] as? Int, 144)
        let strata = sample?["strata"] as? [String: Int]
        XCTAssertFalse(strata?.keys.contains("question:writing") ?? true)
        XCTAssertFalse(strata?.keys.contains("teaching:writing") ?? true)
        let highRisk = (sample?["high_risk_ids"] as? [String]) ?? []
        XCTAssertEqual(highRisk.count, 144)
        XCTAssertTrue(Set(highRisk).isDisjoint(with: Set(Self.writingQuestions + Self.writingTeachings)))
    }

    func testV2SupplySimulateHasZeroWriting() throws {
        // Given: current pilot-50 supply with the effective v2 policy/scenario.
        let records = try load(merged("pilot-50"))
        let questions = records.compactMap { record -> Question? in
            if case .question(let v) = record { return v }; return nil
        }
        let profile: QualityProfile = try read(QualityProfile.self,
            path: repoRoot.appendingPathComponent("content/policies/pilot-quality-v2.json").path)
        let scenarios: SupplyScenarios = try read(SupplyScenarios.self,
            path: repoRoot.appendingPathComponent("content/policies/pilot-supply-scenarios-v2.json").path)
        // When: simulating the current supply scenario.
        XCTAssertEqual(scenarios.targetIds.count, 48)
        XCTAssertFalse(scenarios.targetIds.contains(Self.writingTargets))
        XCTAssertEqual(scenarios.eligibleQuestions.count, 96)
        XCTAssertTrue(Set(scenarios.eligibleQuestions.map(\.questionId))
            .isDisjoint(with: Set(Self.writingQuestions)))
        let report = try SupplySimulation.simulate(questions: questions,
            request: SupplyRequest(profile: profile, scenarios: scenarios, seed: 111))
        // Then: every allocation binds a fresh non-writing question; none cover writing.
        XCTAssertEqual(report.allocations.count, 96)
        XCTAssertFalse(report.allocations.contains {
            Self.writingTargets.contains($0.targetId)
        })
        XCTAssertFalse(report.releaseEligible)
    }

    func testHistorySnapshotsPreserved() throws {
        // Given: the byte-exact pre-exclusion writing rows pinned as tracked
        // fixtures (the on-disk history dir is git-ignored by repo rules).
        for pilot in ["pilot-50", "pilot-230"] {
            let url = repoRoot.appendingPathComponent(
                "tools/ContentKit/Tests/ContentKitTests/Fixtures/WritingExclusion/\(pilot)-writing-rows.jsonl")
            let records = try CKJSONL.readLines(at: url).map { try ContractJSON.decode(Data($0.utf8)) }
            // When / Then: all 16 affected rows survive frozen and valid.
            XCTAssertEqual(records.count, 16, pilot)
            for id in Self.writingTargets {
                let matches = records.compactMap { record -> Target? in
                    if case .target(let v) = record, v.recordId == id { return v }; return nil
                }
                XCTAssertEqual(matches.count, 1, "\(pilot) \(id)")
                XCTAssertEqual(matches.first?.revision, 1)
                XCTAssertEqual(matches.first?.payload.activation, .active)
                XCTAssertEqual(matches.first?.payload.status, .candidate)
            }
            for id in Self.writingQuestions {
                let matches = records.compactMap { record -> Question? in
                    if case .question(let v) = record, v.recordId == id { return v }; return nil
                }
                XCTAssertEqual(matches.count, 1, "\(pilot) \(id)")
                XCTAssertEqual(matches.first?.payload.status, .candidate)
            }
            for id in Self.writingTeachings {
                let matches = records.compactMap { record -> Teaching? in
                    if case .teaching(let v) = record, v.recordId == id { return v }; return nil
                }
                XCTAssertEqual(matches.count, 1, "\(pilot) \(id)")
                XCTAssertEqual(matches.first?.payload.status, .candidate)
            }
        }
    }

    func testRerunRefusedUnchangedHashes() throws {
        // Given: temp copies of the CURRENT post-exclusion merged files
        // (live data is never touched by this test).
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WritingExclusionRerun-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let live = repoRoot.appendingPathComponent("content/records/pilot-50/merged")
        let names = ["pilot-50-target.jsonl", "pilot-50-question.jsonl",
                     "pilot-50-teaching.jsonl", "pilot-50-provenance.jsonl"]
        for name in names {
            try FileManager.default.copyItem(at: live.appendingPathComponent(name),
                                             to: tmp.appendingPathComponent(name))
        }
        func sha256(_ url: URL) throws -> String {
            try CKHash.sha256Hex(of: Data(contentsOf: url))
        }
        let before = try names.map { try sha256(tmp.appendingPathComponent($0)) }
        // When: the migration helper is rerun against the migrated copies.
        let helper = repoRoot.appendingPathComponent("tools/WritingExclusion")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["swift", "run", "--package-path", helper.path,
                          "WritingExclusion", tmp.path] + names
        let errors = Pipe()
        task.standardError = errors
        try task.run()
        task.waitUntilExit()
        // Then: reapplication is refused and every byte is unchanged.
        XCTAssertNotEqual(task.terminationStatus, 0)
        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(message.contains("already_applied"), message)
        let after = try names.map { try sha256(tmp.appendingPathComponent($0)) }
        XCTAssertEqual(before, after)
    }
}
