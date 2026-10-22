import ContentModel
import Foundation

struct QualityFailure: Error, Equatable, CustomStringConvertible {
    let reason: String
    var description: String { "QualityFailure(reason=\(reason))" }
}

struct QualityMinimum: Codable {
    var trainFamilies: Int
    var independentCheckFamilies: Int
}
struct HumanSamplePolicy: Codable {
    var seed: Int
    var denominator: Int
    var highRiskCount: Int
    var strata: [String: Int]
    var maximum: Int
}
struct QualityProfile: Codable {
    var profile: String
    var activeAbilities: [TestedAbility]
    var excludedTargetIds: [String]
    var perAbilityMinimums: [String: QualityMinimum]
    var humanSamplePolicy: HumanSamplePolicy
    var batchSizes: [String: Int]
    var hardRejectDefects: [String]
    var unresolvedCriticalMaximum: Int
    var recommendation: ExpansionRecommendation
}
enum ExpansionRecommendation: String, Codable {
    case blocked = "blocked-on-writing-contract"
    case proceed = "proceed-to-T007"
}
struct TrialQualityMetrics: Codable {
    var sampleDenominator: Int
    var sampleSeed: Int
    var costStatus: CostStatus
    var costAmount: Double?
    var unresolvedCriticalFindings: Int
    var unresolvedBlockingFindings: Int
    var activeTargetSupply: [TargetSupply]
}
enum CostStatus: String, Codable { case unknown, measured }
struct TargetSupply: Codable {
    var targetId: String
    var ability: TestedAbility
    var trainFamilies: Int
    var independentCheckFamilies: Int
}
struct QualityAuditReport: Codable {
    let valid: Bool
    let expansionEligible: Bool
    let recommendation: ExpansionRecommendation
    let shortages: [String]
    let releaseEligible: Bool
    let humanReviewPending: Bool
}

enum QualityAudit {
    static func audit(profile: QualityProfile, trial: TrialQualityMetrics) throws -> QualityAuditReport {
        guard !profile.activeAbilities.isEmpty,
              Set(profile.activeAbilities.map(\.rawValue)).count == profile.activeAbilities.count,
              Set(profile.perAbilityMinimums.keys) == Set(profile.activeAbilities.map(\.rawValue)) else {
            throw QualityFailure(reason: "active_ability_minimums")
        }
        for minimum in profile.perAbilityMinimums.values {
            guard minimum.independentCheckFamilies > 0 else { throw QualityFailure(reason: "zero_check_supply") }
            guard minimum.trainFamilies > 0 else { throw QualityFailure(reason: "zero_train_supply") }
        }
        guard profile.unresolvedCriticalMaximum == 0, trial.unresolvedCriticalFindings >= 0,
              trial.unresolvedBlockingFindings >= 0 else { throw QualityFailure(reason: "critical_rule_must_be_zero") }
        if trial.unresolvedCriticalFindings > 0 && profile.recommendation == .proceed {
            throw QualityFailure(reason: "unresolved_critical_blocks_expansion")
        }
        switch trial.costStatus {
        case .unknown:
            guard trial.costAmount == nil else { throw QualityFailure(reason: "unknown_cost_not_zero") }
        case .measured:
            guard let amount = trial.costAmount, amount.isFinite, amount >= 0 else { throw QualityFailure(reason: "measured_cost_required") }
        }
        let human = profile.humanSamplePolicy
        guard human.denominator > 0, human.maximum > 0, !human.strata.isEmpty,
              human.strata.values.allSatisfy({ $0 > 0 }) else { throw QualityFailure(reason: "human_sampling_not_zero") }
        guard human.denominator == trial.sampleDenominator, human.seed == trial.sampleSeed,
              human.highRiskCount >= 0, human.highRiskCount <= human.maximum,
              human.maximum <= human.denominator,
              human.strata.values.reduce(0, +) <= human.maximum else { throw QualityFailure(reason: "sampling_binding") }
        guard !profile.batchSizes.isEmpty, profile.batchSizes.values.allSatisfy({ (1...25).contains($0) }),
              Set(["answer", "sense", "authorization", "missing_review"]).isSubset(of: Set(profile.hardRejectDefects)) else {
            throw QualityFailure(reason: "hard_gates_required")
        }
        let supply = trial.activeTargetSupply
        guard !supply.isEmpty, Set(supply.map(\.targetId)).count == supply.count,
              Set(profile.excludedTargetIds).isDisjoint(with: Set(supply.map(\.targetId))) else {
            throw QualityFailure(reason: "active_target_inventory")
        }
        var shortages: [String] = []
        for target in supply {
            guard let minimum = profile.perAbilityMinimums[target.ability.rawValue],
                  target.trainFamilies >= 0, target.independentCheckFamilies >= 0 else {
                throw QualityFailure(reason: "target_ability_inventory")
            }
            if target.trainFamilies < minimum.trainFamilies || target.independentCheckFamilies < minimum.independentCheckFamilies {
                shortages.append(target.targetId)
            }
        }
        let eligible = shortages.isEmpty && trial.unresolvedCriticalFindings == 0 && trial.unresolvedBlockingFindings == 0
        if profile.recommendation == .proceed && !eligible { throw QualityFailure(reason: "unresolved_supply_or_blocker") }
        return QualityAuditReport(valid: true, expansionEligible: eligible && profile.recommendation == .proceed,
            recommendation: profile.recommendation, shortages: shortages.sorted(), releaseEligible: false, humanReviewPending: true)
    }
}

public enum QualityCommands {
    public static func run(_ arguments: [String]) -> Int32 {
        do {
            guard let mode = arguments.first, ["audit-profile", "simulate"].contains(mode) else {
                throw QualityFailure(reason: "unknown_quality_or_supply_command")
            }
            let required = mode == "audit-profile" ? ["--profile", "--trial", "--evidence"] : ["--dataset", "--profile", "--scenario", "--seed", "--out"]
            guard arguments.count == 1 + required.count * 2 else { throw QualityFailure(reason: "missing_explicit_flags") }
            var flags: [String: String] = [:]
            for index in stride(from: 1, to: arguments.count, by: 2) {
                let flag = arguments[index], value = arguments[index + 1]
                guard required.contains(flag), flags[flag] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                    throw QualityFailure(reason: "invalid_or_duplicate_flag")
                }
                flags[flag] = value
            }
            guard Set(flags.keys) == Set(required), let profilePath = flags["--profile"],
                  let outputPath = flags["--evidence"] ?? flags["--out"] else { throw QualityFailure(reason: "missing_explicit_flags") }
            let output = URL(fileURLWithPath: outputPath).standardizedFileURL.resolvingSymlinksInPath()
            for key in required where key != "--evidence" && key != "--out" && key != "--seed" {
                guard let path = flags[key] else { throw QualityFailure(reason: "missing_explicit_flags") }
                let input = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                guard output != input, !output.path.hasPrefix(input.path + "/") else { throw QualityFailure(reason: "output_overlaps_input") }
                if FileManager.default.fileExists(atPath: output.path) {
                    let source = try FileManager.default.attributesOfItem(atPath: input.path)
                    let destination = try FileManager.default.attributesOfItem(atPath: output.path)
                    guard source[.systemFileNumber] as? NSNumber != destination[.systemFileNumber] as? NSNumber else {
                        throw QualityFailure(reason: "output_overlaps_input")
                    }
                }
            }
            let profile = try read(QualityProfile.self, path: profilePath)
            switch mode {
            case "audit-profile":
                guard let trialPath = flags["--trial"] else { throw QualityFailure(reason: "missing_explicit_flags") }
                let report = try QualityAudit.audit(profile: profile, trial: read(TrialQualityMetrics.self, path: trialPath))
                try JobLedger.write(report, to: output)
                print("valid=true expansion_eligible=\(report.expansionEligible) recommendation=\(report.recommendation.rawValue)")
            case "simulate":
                guard let datasetPath = flags["--dataset"], let scenarioPath = flags["--scenario"],
                      let seedText = flags["--seed"], let seed = Int(seedText) else { throw QualityFailure(reason: "invalid_seed_or_flags") }
                let root = URL(fileURLWithPath: datasetPath)
                let merged = root.appendingPathComponent("merged")
                let directory = FileManager.default.fileExists(atPath: merged.path) ? merged : root
                _ = try ContractDataset.validate(at: directory)
                let records = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                    .flatMap { try CKJSONL.readLines(at: $0).map { try ContractJSON.decode(Data($0.utf8)) } }
                let questions = records.compactMap { record -> Question? in
                    if case .question(let question) = record { return question }; return nil
                }
                let scenarios = try read(SupplyScenarios.self, path: scenarioPath)
                let targets = records.compactMap { record -> String? in
                    if case .target(let target) = record, target.payload.activation == .active,
                       profile.activeAbilities.contains(target.payload.testedAbility), !profile.excludedTargetIds.contains(target.recordId) { return target.recordId }
                    return nil
                }
                guard Set(targets) == Set(scenarios.targetIds) else { throw QualityFailure(reason: "scenario_target_coverage") }
                let report = try SupplySimulation.simulate(questions: questions, request: SupplyRequest(profile: profile, scenarios: scenarios, seed: seed))
                try JobLedger.write(report, to: output)
                print("valid=true seed=\(seed) allocations=\(report.allocations.count) acceptance_evaluated=false")
            default: throw QualityFailure(reason: "unknown_quality_or_supply_command")
            }
            return 0
        } catch {
            fputs("\(error)\n", stderr)
            return 65
        }
    }
    private static func read<T: Decodable>(_ type: T.Type, path: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }
}
