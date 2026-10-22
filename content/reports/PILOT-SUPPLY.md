# Pilot supply: frozen trial replay, not real-pack acceptance

## Scope and verdict

M1 Task19 replays **real pilot-50 trial inventory** with the frozen quality profile and scenarios, seed **111**. Both fresh runs exited **0** and `cmp` exited **0**. Their identical SHA-256 is `511ed60896af72566567e90f9219ac327f236da24f885c04593a7bb6d0982ef3`.

This is **editorial-only-hypothetical-unseen** supply. Accepted count is **0**, release eligibility is **false**, human review is **pending**, rights remain pending, and cost is **unknown**. No real-human, FSRS, retention, scheduling, or efficacy metric was collected or inferred.

The pilot-230 merged dataset has 4,370 candidate records, not an accepted pack. Task16 remains blocked. Task18's real builds/compare/verify exited 65 and produced no reusable pack outputs. Task19 reader regressions assemble temporary fixtures with Task18's serializer and fixture inputs; they do not authenticate or verify a real pilot pack.

## Frozen inputs and quarantine

- Profile: `content/policies/pilot-quality-v1.json`, SHA-256 `781c6558dd5067c7993371d201776757b58a00b05231b1d8bf30849b49ce2e6e`.
- Scenarios: `content/policies/pilot-supply-scenarios.json`, SHA-256 `90a8adabcd84e8a3cba736b53372b7bd389a2e0f623d73cae37577b62cdf7d00`.
- Dataset actually replayed: `content/records/pilot-50/merged`, 666 records; the frozen scenarios bind 50 targets and 98 question revisions/content hashes. They are not a frozen pilot-230 scenario set. No pilot-230 supply-success claim is made.
- Trial accounting: `content/jobs/pilot-50/receipts/merge-acceptance-r8.json`: 100 questions, 98 raw passed and two quarantined; 49 independent pairs and one contaminated pair. Raw review verdicts are not acceptance counts.
- Permanent writing isolation: `.omo/evidence/m1-content-pilot/a1-task9/writing-isolation.jsonl`, target `lx:target:bf7b049b-a730-4601-bbb5-66aca9719be1`; train `lx:question:3751e6fa-6dcc-460f-9bb0-66d681bf6b2a` r3, check `lx:question:e0c837c6-9845-4394-bdc5-2fc6b7647d08` r7. Neither question enters the 98 bound supply rows.

## Measured supply arithmetic

| Independent scenario | Targets | Train shortfall | Check families consumed | Check shortfall | Remaining unseen checks |
|---|---:|---:|---:|---:|---:|
| trial-one-train-one-check | 50 | 1 | 49 | 1 | 0 |
| one-extra-unseen-check | 50 | 1 | 49 | 51 | 0 |

The second scenario asks for two checks per target from the same starting inventory. It is **not** an additional sequential allocation after the first scenario; inventory resets between scenarios by frozen policy. Counts across the rows must not be summed into 98 distinct available check families. Each row has just 49 available check families, consumed once, with the isolated target supplying none.

### Check-stock ledger and exhaustion invariant

The per-target check-stock accounting is retained verbatim in `.omo/evidence/m1-content-pilot/a1-task19/supply-a.json` (100 allocations): `consumed_check_family_ids`, `remaining_unseen_check_families`, and `check_shortfall`. This is a simulation ledger, **not persisted learner exposure**. The separate identity ledger `content/ids/ledger.jsonl` has 290 events, SHA-256 `c1b5f9c1d26da52d8266fccf225044b21fe14d89fba57810e5d2e83dabe964a6`; supply does not consume or mutate it.

Within a continuous demand horizon, exhausted checks cannot become unseen again: each family is consumed at most once, remaining unseen stays zero, and further demand becomes shortfall. `testExhaustedCheckCannotBecomeUnseenAgain` locks this behavior with increasing demand on trial-derived fixtures. A new call to the stateless simulator starts a counterfactual inventory; it is not evidence that previously exposed checks regained novelty. All 100 trial questions already have agent blind coverage; hypothetical consumer-unseen stock does not mean unseen by reviewers.

## Reproduction and evidence

From the repository root, with `set -o pipefail`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, and the private TMPDIR recorded in the evidence manifest:

```sh
swift run --package-path tools/ContentKit contentkit supply simulate \
  --dataset content/records/pilot-50 \
  --profile content/policies/pilot-quality-v1.json \
  --scenario content/policies/pilot-supply-scenarios.json --seed 111 \
  --out .omo/evidence/m1-content-pilot/a1-task19/supply-a.json
# Repeat with --out .../supply-b.json, then cmp the two outputs.
```

Machine companion: `content/reports/PILOT-SUPPLY.json`. Commands, exits, hashes and test limitations: `.omo/evidence/m1-content-pilot/a1-task19/VERIFICATION.md` and `commands-exits-hashes.json`. Frozen trial quality defects and gate limitations: `QUALITY-DEFECTS.md`. No dataset, review, policy, ledger, plan, App or Xcode edits were required.
