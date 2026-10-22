import Foundation
import XCTest
@testable import ContentCLI

/// M1 handoff status audit gate (Task20).
///
/// Scope constraint: Swift changes for Task20 are confined to this single new
/// test file, so the audit validator under test is defined below in the same
/// file and exercised in-process on fixture dictionaries. There is deliberately
/// no `reports audit-handoff` CLI subcommand; the real-file audit is performed
/// by the mirrored python3 check recorded in the Task20 evidence directory.
/// A passing audit never grants release; it only confirms the status packet is
/// honest (pending stays pending, blocked stays blocked).
final class HandoffStatusTests: XCTestCase {
    private func baseStatus() -> [String: Any] {
        ["schema": "lexvane.m1-status.v1",
         "cutoff_date": "2026-10-11",
         "human_review_pending": true,
         "release_eligible": false,
         "tasks": [
            "T005": ["status": "blocked",
                     "evidence_refs": ["content/sources/inventory.jsonl",
                                       "content/reports/SOURCE-INVENTORY.md",
                                       "content/coverage/ceec-map.jsonl",
                                       "content/reports/T005-MAPPING-STATUS.md"]],
            "T006": ["status": "blocked",
                     "evidence_refs": ["content/reports/PILOT-50-TRIAL.md",
                                       "content/reports/pilot-50-metrics.json"]],
            "T007": ["status": "blocked",
                     "evidence_refs": ["content/records/pilot-230/merged",
                                       "content/reviews/pilot-230/OWNER-RECHECK.md"]],
            "T008": ["status": "blocked",
                     "evidence_refs": ["content/derived/pilot-v1/index.json",
                                       "content/reports/PILOT-SUPPLY.md",
                                       "content/reports/QUALITY-DEFECTS.md"]]
         ],
         "suite": ["command": "swift test --package-path tools/ContentKit",
                   "test_count": 185, "failures": 0, "all_passed": true]]
    }

    private func handoffLinkingRecheck() -> String {
        "# M1 handoff\n\nRead [OWNER-RECHECK.md](../reviews/pilot-230/OWNER-RECHECK.md) before anything else.\n"
    }

    private func pendingRecheck() -> String {
        "# Owner recheck - PENDING\n\nNo human decisions have been made. human_status=pending throughout.\n"
    }

    func testPendingHumanCannotClaimRelease() {
        var status = baseStatus()
        status["release_eligible"] = true
        let violations = HandoffAudit.audit(status: status, handoff: handoffLinkingRecheck(), recheck: pendingRecheck())
        XCTAssertTrue(violations.contains("pending_human_claims_release"),
                      "human_review_pending=true with release_eligible=true must be rejected, got: \(violations)")
    }

    func testMissingSourceYearCannotClaimT005Done() {
        var status = baseStatus()
        var tasks = status["tasks"] as? [String: [String: Any]] ?? [:]
        tasks["T005"] = ["status": "done", "evidence_refs": ["content/pilot/selection.json"]]
        status["tasks"] = tasks
        let violations = HandoffAudit.audit(status: status, handoff: handoffLinkingRecheck(), recheck: pendingRecheck())
        XCTAssertTrue(violations.contains("t005_done_without_mapping_evidence"),
                      "T005 done backed only by candidate selection, without inventory+mapping refs, must be rejected, got: \(violations)")
    }

    func testFakeAllTestsPassedWithZeroTestsRejected() {
        var status = baseStatus()
        status["suite"] = ["command": "swift test --package-path tools/ContentKit",
                           "test_count": 0, "failures": 0, "all_passed": true]
        let violations = HandoffAudit.audit(status: status, handoff: handoffLinkingRecheck(), recheck: pendingRecheck())
        XCTAssertTrue(violations.contains("zero_tests_claim_all_passed"),
                      "all_passed=true with test_count=0 must be rejected, got: \(violations)")
    }

    func testMissingOwnerReportLinkRejected() {
        let violations = HandoffAudit.audit(status: baseStatus(),
                                           handoff: "# M1 handoff\n\nNo links here.\n",
                                           recheck: pendingRecheck())
        XCTAssertTrue(violations.contains("missing_owner_recheck_link"),
                      "Handoff without an OWNER-RECHECK.md link must be rejected, got: \(violations)")
    }

    func testHonestBlockedPacketPasses() {
        let violations = HandoffAudit.audit(status: baseStatus(), handoff: handoffLinkingRecheck(), recheck: pendingRecheck())
        XCTAssertTrue(violations.isEmpty, "Honest all-blocked packet with owner link must pass, got: \(violations)")
    }
}

/// In-test handoff status validator.
///
/// Kept in this test file because Task20 confines Swift edits to one new test
/// file. Rules mirror the python3 real-file audit in the Task20 evidence
/// directory. Returns violation codes; empty means the packet is honest.
/// Honesty only, never approval: a pass does not release anything.
enum HandoffAudit {
    static func audit(status: [String: Any], handoff: String, recheck: String) -> [String] {
        var violations: [String] = []
        guard let tasks = status["tasks"] as? [String: [String: Any]] else {
            return ["status_tasks_missing"]
        }
        for id in ["T005", "T006", "T007", "T008"] {
            guard let entry = tasks[id],
                  let state = entry["status"] as? String,
                  ["done", "blocked", "engineering_ready_human_pending"].contains(state) else {
                violations.append("task_\(id.lowercased())_status_unknown")
                continue
            }
            let refs = entry["evidence_refs"] as? [String] ?? []
            if refs.isEmpty { violations.append("task_\(id.lowercased())_evidence_missing") }
            _ = state
        }
        let humanPending = (status["human_review_pending"] as? Bool) ?? true
        let releaseEligible = (status["release_eligible"] as? Bool) ?? false
        if humanPending && releaseEligible {
            violations.append("pending_human_claims_release")
        }
        if let t005 = tasks["T005"], (t005["status"] as? String) == "done" {
            let refs = ((t005["evidence_refs"] as? [String]) ?? []).joined(separator: " ").lowercased()
            let hasInventory = refs.contains("inventor")
            let hasMapping = refs.contains("mapping") || refs.contains("coverage") || refs.contains("ceec-map")
            if !(hasInventory && hasMapping) {
                violations.append("t005_done_without_mapping_evidence")
            }
        }
        if let suite = status["suite"] as? [String: Any] {
            let count = (suite["test_count"] as? Int) ?? 0
            let failures = (suite["failures"] as? Int) ?? 0
            let allPassed = (suite["all_passed"] as? Bool) ?? false
            if allPassed && count <= 0 {
                violations.append("zero_tests_claim_all_passed")
            }
            if allPassed && failures != 0 {
                violations.append("failures_claim_all_passed")
            }
        } else {
            violations.append("suite_evidence_missing")
        }
        if !handoff.contains("OWNER-RECHECK.md") {
            violations.append("missing_owner_recheck_link")
        }
        if !recheck.lowercased().contains("pending") {
            violations.append("recheck_not_marked_pending")
        }
        return violations
    }
}
