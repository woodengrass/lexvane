import Foundation
import XCTest
@testable import ContentCLI
import ContentModel

final class QualityProfileTests: XCTestCase {
    static func baseline() -> (QualityProfile, TrialQualityMetrics) {
        let profile = QualityProfile(profile: "unit-test", activeAbilities: [.contextualChoice],
            excludedTargetIds: [], perAbilityMinimums: ["contextual_choice": QualityMinimum(trainFamilies: 1, independentCheckFamilies: 1)],
            humanSamplePolicy: HumanSamplePolicy(seed: 111, denominator: 2, highRiskCount: 1, strata: ["ordinary": 1], maximum: 2),
            batchSizes: ["author": 25], hardRejectDefects: ["answer", "sense", "authorization", "missing_review"],
            unresolvedCriticalMaximum: 0, recommendation: .proceed)
        let trial = TrialQualityMetrics(sampleDenominator: 2, sampleSeed: 111, costStatus: .unknown,
            costAmount: nil, unresolvedCriticalFindings: 0, unresolvedBlockingFindings: 0,
            activeTargetSupply: [TargetSupply(targetId: "test-target", ability: .contextualChoice, trainFamilies: 1, independentCheckFamilies: 1)])
        return (profile, trial)
    }
    func testZeroCheckSupplyRejected() throws {
        // Given: an active ability with a zero independent-check minimum.
        var (profile, trial) = Self.baseline()
        profile.perAbilityMinimums["contextual_choice"]?.independentCheckFamilies = 0
        // When / Then: the exact policy defect must reject.
        XCTAssertThrowsError(try QualityAudit.audit(profile: profile, trial: trial)) {
            XCTAssertEqual($0 as? QualityFailure, QualityFailure(reason: "zero_check_supply"))
        }
    }
    func testUnresolvedCriticalFindingBlocksExpansion() throws {
        // Given: one unresolved critical finding and a request to proceed.
        var (profile, trial) = Self.baseline()
        trial.unresolvedCriticalFindings = 1
        // When / Then: expansion cannot pass.
        XCTAssertThrowsError(try QualityAudit.audit(profile: profile, trial: trial)) {
            XCTAssertEqual($0 as? QualityFailure, QualityFailure(reason: "unresolved_critical_blocks_expansion"))
        }
    }
    func testUnknownCostCannotBecomeZero() throws {
        // Given: unknown cost incorrectly encoded as a measured zero.
        var (profile, trial) = Self.baseline()
        trial.costAmount = 0
        // When / Then: unknown must retain null, not a zero-dollar claim.
        XCTAssertThrowsError(try QualityAudit.audit(profile: profile, trial: trial)) {
            XCTAssertEqual($0 as? QualityFailure, QualityFailure(reason: "unknown_cost_not_zero"))
        }
    }
    func testHumanSamplingCannotBeZero() throws {
        // Given: an ordinary stratum disabled despite a positive denominator.
        var (profile, trial) = Self.baseline()
        profile.humanSamplePolicy.strata["ordinary"] = 0
        // When / Then: human sampling cannot be disabled.
        XCTAssertThrowsError(try QualityAudit.audit(profile: profile, trial: trial)) {
            XCTAssertEqual($0 as? QualityFailure, QualityFailure(reason: "human_sampling_not_zero"))
        }
    }
    func testValidMeasuredSupplyCanProceedWithoutReleaseApproval() throws {
        // Given: separate train/check supply, unknown-null costs, positive sampling.
        let (profile, trial) = Self.baseline()
        // When: audit the profile.
        let result = try QualityAudit.audit(profile: profile, trial: trial)
        // Then: engineering expansion is distinct from release and human approval.
        XCTAssertTrue(result.expansionEligible)
        XCTAssertFalse(result.releaseEligible)
        XCTAssertTrue(result.humanReviewPending)
    }
}
