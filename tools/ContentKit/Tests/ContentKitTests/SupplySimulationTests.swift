import Foundation
import XCTest
import ContentModel
@testable import ContentCLI

final class SupplySimulationTests: XCTestCase {
    private func questions() throws -> [Question] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = root.appendingPathComponent("Fixtures/PilotFifty/dataset")
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "jsonl" }.flatMap { file in
            try CKJSONL.readLines(at: file).compactMap { line in
                if case .question(let q) = try ContractJSON.decode(Data(line.utf8)) { return q }
                return nil
            }
        }
    }
    private func request(_ questions: [Question], seed: Int) -> SupplyRequest {
        var (profile, _) = QualityProfileTests.baseline()
        profile.activeAbilities = TestedAbility.allCases
        let bindings = questions.map { SupplyBinding(questionId: $0.recordId, revision: $0.revision, contentSha256: $0.contentSha256) }
        return SupplyRequest(profile: profile, scenarios: SupplyScenarios(targetIds: Array(Set(questions.map { $0.payload.primaryTargetId })), scenarios: [SupplyScenario(id: "burn", trainPresentationsPerTarget: 1, checkPresentationsPerTarget: 2)], eligibleQuestions: bindings), seed: seed)
    }
    func testSeedDeterminismSurvivesInputReordering() throws {
        // Given: actual trial-derived regression questions and explicit seed 111.
        let input = try questions()
        XCTAssertFalse(input.isEmpty)
        let configuration = request(input, seed: 111)
        // When: simulate identical inventory in opposite traversal orders.
        let first = try SupplySimulation.simulate(questions: input, request: configuration)
        let second = try SupplySimulation.simulate(questions: input.reversed(), request: configuration)
        // Then: serialized output is byte-identical and meaningful.
        XCTAssertEqual(try ContractJSON.bytes(first), try ContractJSON.bytes(second))
        XCTAssertFalse(first.allocations.isEmpty)
    }
    func testConsumedCheckFamilyCannotBeReusedAsUnseen() throws {
        // Given: trial-derived targets have only one check family each.
        let input = try questions()
        // When: request two unseen checks for each target.
        let result = try SupplySimulation.simulate(questions: input, request: request(input, seed: 111))
        // Then: the second request is a shortage, never invented fresh supply.
        XCTAssertTrue(result.allocations.contains { $0.checkShortfall > 0 })
        XCTAssertTrue(result.allocations.allSatisfy { Set($0.consumedCheckFamilyIds).count == $0.consumedCheckFamilyIds.count })
    }
}
