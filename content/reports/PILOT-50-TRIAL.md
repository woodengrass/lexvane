# 50-word trial: frozen quality, supply and sampling profile

**Recommendation: `blocked-on-writing-contract`. Coordinator ruling remains final.**

Private pilot; unpublished; human review pending. This freezes a policy and reports trial evidence; it does **not** pass T007, T035, private-pack/distribution gates, or authorize T025 mass production. No learner effectiveness, SRS benefit, or independent-model validation is inferred.

## 1. Inputs, denominators and acceptance boundaries

The machine-readable companion is [`pilot-50-metrics.json`](pilot-50-metrics.json). The policy is [`pilot-quality-v1.json`](../policies/pilot-quality-v1.json); fixed demand cases are [`pilot-supply-scenarios.json`](../policies/pilot-supply-scenarios.json).

Read-only final inputs:

- `content/jobs/pilot-50/receipts/merge-acceptance-r8.json`: 666 current records, 100 questions, raw question verdicts 98 passed / 2 quarantined, 49 independent / 1 contaminated family pairs; candidate exit 0, both acceptance gates exit 65.
- `content/jobs/pilot-50/receipts/reverify-round8.json`: independently reviewed light pair; 49 carried pairs plus one fresh pair, current editorial questions 98/2; no new unresolved findings. The originally requested evidence-directory copy does not exist; this receipt is the authoritative path referenced by the merge.
- `content/reviews/pilot-50/family-verdicts-r8.jsonl` is a **one-pair delta**, not the full denominator. Prior family verdict files plus this delta supply all 50 pairs; round8 carry-forward bindings are retained.
- `.omo/evidence/m1-content-pilot/a1-task9/writing-isolation.jsonl`: two isolated questions, one isolated target/word; coordinator editorial word-acceptance claim 49/50.
- `.omo/HANDOFF-m1-task9.md` §8 and `.omo/notepads/m1-content-pilot/learnings.md:269–275`: rounds 4–8 lineage, zero divergent trial-wide blind results, ledger stability, rights/human pending.
- Frozen selection facet tags: `content/pilot/selection.json`, restricted to its 50 subset IDs. Current records: `content/records/pilot-50/merged`.

**Do not equate editorial passed with accepted.** Both native acceptance attempts report accepted/quarantine counts as **null**. Confirmed accepted by those attempts is **0**, not 98 questions or 49 words. The isolation receipt's “49 accepted words” is retained explicitly as a coordinator editorial claim. Isolation never enters accepted supply. All legal private-pack, human accepted and public-distribution counts remain 0; official mapping is not established by these candidate records.

### Word facets (measured selection membership; not all-sense mastery)

| Facet | Candidate words | Editorial accepted-word claim | Isolated words | Native accepted count |
|---|---:|---:|---:|---|
| Entire trial | 50 | 49 | 1 | null; confirmed 0 |
| polysemy | 1 | 1 | 0 | null; confirmed 0 |
| second_sense | 1 | 1 | 0 | null; confirmed 0 |
| morphology | 1 | 1 | 0 | null; confirmed 0 |
| collocation | 1 | 1 | 0 | null; confirmed 0 |
| spelling_hyphen | 1 | 0 | 1 | null; confirmed 0 |
| general (explicit selection tag) | 1 | 1 | 0 | null; confirmed 0 |
| No selection facet tag | 44 | 44 | 0 | null; confirmed 0 |

Facet tags are candidate risk anchors; supplementary senses are not additional active ability targets. No quarantine has been silently promoted. The “isolated” column is specifically the writing contract isolation, **not** a substitute for the larger historical/raw quarantine accounting below.

### Current records and strict raw review accounting

| Kind | Current candidate records | Raw exact-revision passed | Raw exact-revision quarantined |
|---|---:|---:|---:|
| entry | 50 | 32 | 18 |
| sense | 83 | 50 | 33 |
| target | 50 | 26 | 24 |
| teaching | 50 | 33 | 17 |
| question | 100 | 98 | 2 |
| provenance | 333 | 154 | 92 |

Provenance also has 87 without an optional exact current review. These columns reproduce the merge receipt, not a newly adjudicated count. Old exact-revision quarantine rows coexist with later current-checklist passes under the coordinator's obsolete-session-item ruling; multiple exact bindings are disclosed in that receipt. Native content validation still stopped at sense `4ce7d12e…`; review audit stopped at sense `ce1d84ba…`. Therefore this report does **not** claim that native gates fail only on writings or that excluding writing alone makes them green. No gate tuning or trial edits were performed.

## 2. Defects and repair history

Historical failed-checklist observations are counted directly across preserved `review-*.jsonl` rows. They are repeated observations across rounds, **not unique unresolved defects or human defect rates**. The metrics preserve all exact item counts.

| Defect taxonomy | Historical failed observations / examples |
|---|---|
| Missing/merged sense or target alignment | sense-coverage 16; gloss-precision 6; stem-tests-sense 26; ability-target-match 9; target-ability-match 6 |
| Answer ambiguity / answer contract | single-answer-or-listed 20; writing alternatives below remain isolated |
| Answer/option cues | no-pre-answer-hint 18; options-no-leak 8 |
| Family contamination / near-renamed mechanism | family-independence 164; train-check-noncontamination 14 |
| Teaching/example alignment | example-alignment 17; example-3-alignment 2 |
| Feedback and distractor explanation | feedback-consistency 6; distractor-rationales 12; per-option observations separately in JSON |
| Revision/provenance and evidence | revision-lineage 15; obsolete session-independence-evidence 274 (not all content faults) |
| Alias/case/variant boundaries | lemma-pos-alias 1; alias-variant-boundaries 1; case-variant-boundaries 2 |

Hard rejects in v1 include unresolved answer/sense/authorization/missing-review defects, leaks, family contamination, stale revisions and the writing-contract block. The critical maximum is explicitly zero. Round8 reported no *new* unresolved critical finding; that does not erase the two carried blocking writing defects or imply all historical findings are closed. Severity labels cannot override semantic blocking rules.

| Repair round | Questions passed / quarantine | Families independent / contaminated | Current blind coverage | New solve bindings | Candidate / content / coverage exits |
|---|---:|---:|---:|---:|---|
| Before round4 (handoff §7) | 42 / 58 | 32 / 18 | 100 / 100 | — | 0 / 65 / 65 |
| 4 | 75 / 25 | 40 / 10 | 100 / 100 | 57 | 0 / 65 / 65 |
| 5 | 86 / 14 | 44 / 6 | 100 / 100 | 24 | 0 / 65 / 65 |
| 6 | 92 / 8 | 47 / 3 | 100 / 100 | 13 | 0 / 65 / 65 |
| 7 | 96 / 4 | 48 / 2 | 100 / 100 | 7 | 0 / 65 / 65 |
| 8 | 98 / 2 | 49 / 1 | 100 / 100 | 2 | 0 / 65 / 65 |

Counts come from each `merge-acceptance-r{4-8}.json`. New solve bindings include protocol-only writings where applicable; they are not all multiple-choice matches. The coordinator's trial-wide comparison reports **zero divergent** responses. Current multiple-choice agreement is **98/98**; the two current writing responses have protocol coverage, not uniquely validated lexical-answer agreement. Agreement does not close ambiguity or family findings.

Ledger is **244 events** throughout rounds 4–8, SHA-256 `65a3754c3ed3a1251aa8a8d2c50582bb66c45fda86d1d8e04cfa1c21132bef6c`. Current merge remains 666 records. Task10 does not issue identities or alter trial files. Input hash preservation is recorded under the new Task10 evidence directory.

### Permanent writing isolation

- Target `lx:target:bf7b049b-a730-4601-bbb5-66aca9719be1`.
- Train `lx:question:3751e6fa-6dcc-460f-9bb0-66d681bf6b2a`, r3: well-known / well-recognized / well-publicized satisfy the compound constraints; spelling cues or silent alias additions cannot repair the frozen contract.
- Check `lx:question:e0c837c6-9845-4394-bdc5-2fc6b7647d08`, r7: broadly recognized is an unlisted valid alternative; finite transformation repeats teaching procedure.
- Their family pair is contaminated/isolated and never forwarded. Standing A/A1 retains Task6's single-solution contract; A2 contract change was not taken.

## 3. Model, prompt, session, time, tokens and cost accounting

Source provenance labels use `openai/gpt-6.1-sol`; reviewer receipts label same-model separate-session execution (round8 `S-D9-review-reverify-round8`, distinct from generator labels S-C8/S-F8). Author/check prompts are separately frozen; blind solvers received five-field opaque projections, not keys or review commentary. All measured provenance model/prompt-hash/receipt triples and receipt session-identity fields are preserved in `model_prompt_session_labels`; all historical reviewer labels are in `reviewer_labels`. Original train/check generator receipt references and SHA-256 hashes are included. Null platform IDs remain null: task-local labels are **not** authenticated provider IDs or independent-model cross-validation.

Round8's check-author scope incident remains disclosed: one unassigned check question was accidentally read; no train exposure is claimed, upstream `receipt_clean=false`, coordinator acknowledgment pending. Round8 merge records three carried family hash-binding gaps; the latest-row/current-question comparison for this freeze found zero mismatched member tuples. Neither fact overwrites the other or authenticates psychological independence.

| Quantity | Frozen total | Basis |
|---|---|---|
| Trial elapsed seconds | **unknown / null** | No trustworthy complete elapsed-time measurement; timestamps/receipt labels are not an additive workload meter |
| Input / output tokens | **unknown / null** | No complete metered trial token total |
| Monetary cost | **unknown / null**, never zero | Subscription/quota execution, not an unlimited API allowance; no billing meter |
| Human defect rate / review time | **unknown** | Human review still pending; no responses forged |

Receipt-declared cost/token/time fields are preserved under `accounting.receipt_declared_fields`; no unsupported total or zero-dollar estimate is derived. Swift test durations measure tooling runs only, not content authoring cost. All counts above are artifact measurements/claims as labeled. The next-check demand scenario is explicitly counterfactual; no best-practice teaching values or efficacy estimates are invented.

## 4. Frozen family minimums and supply burn

| Active ability (blocked v1 scope) | Targets | Train families editorial-usable | Separately authored check families editorial-usable | Minimum per active target |
|---|---:|---:|---:|---|
| contextual_choice | 42 | 42 | 42 | 1 train + 1 independent check |
| meaning_recognition | 6 | 6 | 6 | 1 train + 1 independent check |
| writing | 2 | 1 | 1 | 1 train + 1 independent check |
| Total | 50 | 49 | 49 | Nonzero for every active ability |

These are different family IDs and editorial evidence, **not accepted release inventory**. One writing target is under-supplied after isolation; v1 records the shortage rather than lowering its minimum to zero. The present recommended-blocked profile retains all three active abilities so it cannot hide that shortage. The minimum of one per split is the measured trial floor mandated by the active-target contract; no larger mastery requirement is inferred. Author/review/check/blind caps remain the actually used 25-unit batch size; independent prompts and current-revision rechecks remain required.

Two fixed scenarios reset hypothetical inventory independently:

1. **trial-one-train-one-check**: observed one train and one check request per target. Editorial usable supply supports 49 targets; 49 check families burn once, none remain unseen. The isolated target has one train and one check shortfall.
2. **one-extra-unseen-check**: counterfactual next unseen check after that measured first consumption. Still only 49 check families can be consumed; total check shortfall is 51 (49 second requests plus two requests for the isolated target). Practice may repeat train families; consumed check families cannot be relabeled unseen.

All questions have already been agent blind-solved. “Unseen” here is a **hypothetical consumer's inventory state**, not a claim about actual learner exposure or fresh agent solves. Simulations report `accepted_count=0`, `release_eligible=false`, editorial-only inventory basis, per-target consumption and shortages. This is supply arithmetic, not FSRS scheduling or SRS effectiveness. Exact question ID/revision/hash bindings in the scenario reject stale or quarantined substitution; the CLI selects canonical `merged/` when invoked on the historical pilot root.

## 5. Frozen human sampling profile

Denominator **150 current reviewable records = 100 questions + 50 teachings**, frozen IDs, seed **111**. Word denominator remains 50; question denominator remains 100. Seed 111 is the explicit reproducibility parameter, not a trial-measured optimum.

All 150 question/teaching records reference pending S01 rights metadata, hence the source-warning high-risk rule selects **all 150**, deduplicated, with status **pending**. Answer/feedback revisions, ambiguity, family/reviewer disagreement and important sense/alias/morphology risks remain reasons for the same high-risk records, never grounds to remove one. The ceiling is the measured census size 150, not a cap that discards high-risk findings. Actual human accepted count **0**, response reference **null**.

The six ordinary strata are question/teaching × contextual_choice/meaning_recognition/writing; every stratum has configured minimum **1**. Unflagged population is currently empty because every record has a rights warning, so ordinary *additional* draws are 0, **not a zero sampling policy**. Once nonflagged records exist, take at least one per populated stratum with SHA-256(`seed|stratum|record_id`) ranking and ID tie-break, without replacement; retain all high-risk records first. Any such population change requires a new frozen denominator/profile, not silent resampling of this trial. Census selection here is independent of seed; the seed fixes future ordinary ranking. No OWNER-RECHECK or Task11–20 content is manufactured in this task.

## 6. Decision options and recommendation

**Option A — `blocked-on-writing-contract` (RECOMMENDED).** Retain the frozen single-solution contract and both writing quarantines; do not count the isolated target as accepted. The profile itself can audit successfully while reporting `expansion_eligible=false` and the writing target shortage. Task9's two native gates are still 65, historical exact-review conflicts and source/human/provider-authentication disclosures remain. This is the conservative continuation of handoff §8 and the supplied isolation receipt, not a claim that all pipeline work failed.

**Option B — `proceed-to-T007`, writing ability excluded from v1 active abilities.** This requires an explicit coordinator scope ruling. Exclude **the entire writing ability**, including isolated target `bf7b049b…`; never merely set writing minimums to zero or call the isolated subject passed. There are **two** writing targets in current records, so this scope leaves **48 active non-writing targets**, not 49. The 49/50 editorial word-acceptance claim is a different denominator. Non-writing targets still require at least one train and one separately authored check family each. Before declaring a usable accepted subset, reconcile the native exact-review/carry-forward evidence and audit that scoped subset without waiving legal private-pack/distribution or human gates. This task does not make that ruling or alter activation records.

Only Option A is the recommendation recorded in this frozen profile. A coordinator may choose Option B with new scope evidence; it is not already approved by policy audit exit 0. Neither option closes T035 or permits T025. References: `planning/v1/contracts/tasks.json` T006/T007/T035/T025; docs/05 §§96–110; docs/06 §§118–122; sampling protocol §7 in `.omo/plans/m1-content-pilot.md`.

## 7. Engineering evidence

New directory: `.omo/evidence/m1-content-pilot/a1-task10/`; Task9 evidence is read-only.

- `task-10-failure.log`: real compiled RED, 5 tests / 4 failures; every mandated test failed because the missing guard did not throw, not because of missing symbols or fixtures.
- `task-10-quality-green.log`: QualityProfileTests 5/5; `task-10-supply-green.log`: SupplySimulationTests 2/2; `task-10-suite.log`: **125/125**, zero failures, build succeeded (118 prior + 7 new).
- Five changed Swift files: primary `lsp_diagnostics` returned no diagnostics.
- `task-10-profile.json`: audit exit 0, valid profile, blocked expansion, one target shortage, release false and human pending.
- `task-10-supply.json` and `task-10-supply-repeat.json`: seed111, byte-identical outputs, real current trial data. `verification.json` records commands/exits, hashes, supply totals and input stability.
- `freeze-trial.py` and `derivation.log`: source-only measurement derivation, exclusive-create outputs; no fake trial fixtures.

Swift changes are limited to ContentKit: quality command/audit, a small separated supply simulation implementation, minimal dispatch/usage extension, and tests. Candidate validation behavior is unchanged. No App/Xcode/M0, registry, ledger, plan checkbox or trial edits; no commit/push/PR.
