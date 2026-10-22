# Quality defects: observed trial evidence, unresolved gates

## Accounting rules

These are real trial artifacts, not invented production quality or learner metrics. Sources: `pilot-50-metrics.json`, `PILOT-50-TRIAL.md`, and `content/jobs/pilot-50/receipts/merge-acceptance-r8.json`. Repeated historical checklist observations are **not unique unresolved defects**. Raw review passes are **not accepted records**. Rights remain pending, human review pending, costs unknown; release eligibility false and accepted confirmed by the trial attempt **0**. Missing tool acceptance counts stay null.

## Current pilot-50 trial snapshot

| Kind | Current records | Raw passed | Raw quarantined |
|---|---:|---:|---:|
| entry | 50 | 32 | 18 |
| sense | 83 | 50 | 33 |
| target | 50 | 26 | 24 |
| teaching | 50 | 33 | 17 |
| question | 100 | 98 | 2 |
| provenance | 333 | 154 | 92 |

Total current records: 666. Provenance verdicts cover 246 rows; the other 87 do not have optional reviews. Do not substitute historical/all-exact-revision verdict totals for these current totals. Family verdicts: 49 independent, one contaminated. The two quarantined writing questions and shortage target are identified in `PILOT-SUPPLY.md`; frozen supply bindings omit both.

Historical native gates recorded in the r8 receipt/metrics: candidate exit **0**, content exit **65**, coverage exit **65**. Content first fails `review_not_passed` for sense `4ce7d12e-49f7-4135-a134-3aac1dc30b60`; coverage first fails for sense `ce1d84ba-b62b-4a3f-98da-b02eaf0ed95b`. Excluding writing alone has not been demonstrated to make all gates green. Trial metrics report unresolved critical findings 0 and blocking findings 2; that is not a waiver of native gate failures.

## Historical failed-checklist observations

From `pilot-50-metrics.json.historical_failed_checklist_observations`:

| Check | Observations |
|---|---:|
| ability-target-match | 9 |
| alias-variant-boundaries | 1 |
| case-variant-boundaries | 2 |
| distractor-rationale-option-a | 2 |
| distractor-rationale-option-b | 2 |
| distractor-rationale-option-c | 3 |
| distractor-rationales | 12 |
| example-3-alignment | 2 |
| example-alignment | 17 |
| family-independence | 164 |
| feedback-answer-explanation | 3 |
| feedback-consistency | 6 |
| gloss-precision | 6 |
| lemma-pos-alias | 1 |
| no-pre-answer-hint | 18 |
| option-option-b-assessment | 1 |
| option-option-c-assessment | 2 |
| options-no-leak | 8 |
| revision-lineage | 15 |
| sense-coverage | 16 |
| session-independence-evidence | 274 |
| single-answer-or-listed | 20 |
| stem-tests-sense | 26 |
| target-ability-match | 6 |
| train-check-noncontamination | 14 |

Historical severity observations: **648 major, 2 minor**. These are repeated observations across review/fix history, not 650 currently open unique defects. Session-independence evidence failures are evidence failures, not automatically linguistic faults. Agent blind coverage is 100/100; 98 multiple-choice agreements and two protocol-only writings are not human efficacy evidence. The human sample policy covers 150 question/teaching records, seed 111; an actual human response is still absent.

## Separate pilot-230 gates: not trial supply or pack success

Task16's retained `a1-task16/VERIFICATION.md` and `task-16-graph.json` report **4,370 candidate records**, gate exit **65**, **146,767 typed defects**:

| Code | Task16 observations |
|---|---:|
| source_permission | 115071 |
| evidence_closure | 16798 |
| duplicate_id | 7446 |
| identity_binding | 2466 |
| missing_review | 2162 |
| provenance_fields | 1526 |
| review_rejected | 595 |
| provenance_binding | 298 |
| review_binding | 226 |
| human_closure | 150 |
| target_sense_mismatch | 28 |
| family_mismatch | 1 |

These are graph defect observations, not counts of distinct faulty content records. Task18's retained `a1-task18/VERIFICATION.md` separately reports build exits 65, including `invalid_record=2800`, and no real pack to compare or verify. Task16 and Task18 ran different gate surfaces; do not add their defect counts together or silently reconcile away their differences. No real-pilot gate was rerun or repaired in Task19.

## Regression boundary and remediation

Task19 adds six fixture regressions: payload corruption, truncated JSON with a rebound transport hash, newer schema without file mutation, check exhaustion under increasing demand, interrupted job receipt reconciliation/no-double-accept, and verified fixture index→search. The first red run is a compile-red before test support existed, not an assertion-level production bug. Full suite: **185 tests, zero failures**; no production builder edit was needed. See `.omo/evidence/m1-content-pilot/a1-task19/`.

Fixes to real content require new revisions, exact-hash independent reviews, evidence/identity reconciliation, authorization and human closure, followed by passing Task16 and complete lock-input builds. Exhausted checks remain exposed; extra demand must become shortfall or use genuinely new independently reviewed families, never relabel used stock as unseen. No SRS or real-human benefit is inferred.
