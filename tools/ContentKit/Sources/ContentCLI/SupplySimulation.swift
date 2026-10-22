import ContentModel
import Foundation

struct SupplyBinding: Codable {
    let questionId: String
    let revision: Int
    let contentSha256: String
}
struct SupplyScenario: Codable {
    let id: String
    let trainPresentationsPerTarget: Int
    let checkPresentationsPerTarget: Int
}
struct SupplyScenarios: Codable {
    let targetIds: [String]
    let scenarios: [SupplyScenario]
    let eligibleQuestions: [SupplyBinding]
}
struct SupplyRequest {
    let profile: QualityProfile
    let scenarios: SupplyScenarios
    let seed: Int
}
struct SupplyAllocation: Codable {
    let scenario: String
    let targetId: String
    let trainFamilyIds: [String]
    let consumedCheckFamilyIds: [String]
    let trainShortfall: Int
    let checkShortfall: Int
    let remainingUnseenCheckFamilies: Int
}
struct SupplySimulationReport: Codable {
    let seed: Int
    let allocations: [SupplyAllocation]
    let inventoryBasis: String
    let acceptedCount: Int
    let releaseEligible: Bool
}
enum SupplySimulation {
    static func simulate(questions: [Question], request: SupplyRequest) throws -> SupplySimulationReport {
        let scenarios = request.scenarios
        guard !scenarios.scenarios.isEmpty, !scenarios.targetIds.isEmpty,
              Set(scenarios.targetIds).count == scenarios.targetIds.count,
              Set(scenarios.scenarios.map(\.id)).count == scenarios.scenarios.count,
              Set(questions.map(\.recordId)).count == questions.count,
              Set(scenarios.eligibleQuestions.map(\.questionId)).count == scenarios.eligibleQuestions.count else {
            throw QualityFailure(reason: "duplicate_or_empty_supply_inventory")
        }
        let byId = Dictionary(uniqueKeysWithValues: questions.map { ($0.recordId, $0) })
        let eligible = try scenarios.eligibleQuestions.map { binding -> Question in
            guard let question = byId[binding.questionId], question.revision == binding.revision,
                  question.contentSha256 == binding.contentSha256,
                  question.payload.status != .quarantined else { throw QualityFailure(reason: "stale_or_quarantined_supply_binding") }
            return question
        }
        var allocations: [SupplyAllocation] = []
        for scenario in scenarios.scenarios.sorted(by: { $0.id < $1.id }) {
            guard scenario.trainPresentationsPerTarget > 0, scenario.checkPresentationsPerTarget > 0 else {
                throw QualityFailure(reason: "zero_scenario_demand")
            }
            for target in scenarios.targetIds.sorted() where !request.profile.excludedTargetIds.contains(target) {
                let pool = eligible.filter { $0.payload.primaryTargetId == target && request.profile.activeAbilities.contains($0.payload.testedAbility) }
                let train = Set(pool.filter { $0.payload.split == .train }.map { $0.payload.familyId })
                let check = Set(pool.filter { $0.payload.split == .check }.map { $0.payload.familyId })
                guard train.isDisjoint(with: check) else { throw QualityFailure(reason: "shared_train_check_family") }
                let ordered = check.sorted { left, right in
                    let prefix = "\(request.seed)|\(scenario.id)|\(target)|"
                    let l = CKHash.sha256Hex(of: Data((prefix + left).utf8)), r = CKHash.sha256Hex(of: Data((prefix + right).utf8))
                    return l == r ? left < right : l < r
                }
                let consumed = Array(ordered.prefix(scenario.checkPresentationsPerTarget))
                allocations.append(SupplyAllocation(scenario: scenario.id, targetId: target,
                    trainFamilyIds: train.sorted(), consumedCheckFamilyIds: consumed,
                    trainShortfall: train.isEmpty ? scenario.trainPresentationsPerTarget : 0,
                    checkShortfall: max(0, scenario.checkPresentationsPerTarget - consumed.count),
                    remainingUnseenCheckFamilies: check.count - consumed.count))
            }
        }
        return SupplySimulationReport(seed: request.seed, allocations: allocations,
            inventoryBasis: "editorial-only-hypothetical-unseen", acceptedCount: 0, releaseEligible: false)
    }
}
