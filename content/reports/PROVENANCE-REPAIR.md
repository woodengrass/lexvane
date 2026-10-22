# Provenance/source repair outcome — 2026-10-23

**Implemented and migrated; not content approval or release authorization.**

## Contract and lineage

- Added provenance-only `lexvane.provenance.v2`. Frozen `lexvane.content.v1`
  still rejects empty field `source_refs`; other kinds cannot use v2.
- V2 distinguishes `external_source_refs`, `internal_evidence_refs`, and
  `unverified_refs`, with explicit external/generated/unverified origin.
  Internal artifacts require safe local paths, exact hashes and valid optional
  line numbers. Missing artifacts are unresolved, not proof. Unknown external
  IDs still fail; unverified origins explicitly block evidence closure.
- Inspected **82 unregistered IDs across 460 pilot-230 provenance rows**:
  5 internal order-file paths (2,073 field occurrences), 15 sanitized work labels
  (2,121), and 62 internal file/line citations (440). All 4,634 original strings
  and operation arrays survive verbatim in unverified evidence. The helper's
  explicit allowlist and exact order-set checks encode the inspected lineage.
- The earlier “225” count did not reproduce against current merged inputs;
  460 affected rows / 82 distinct IDs / 4,634 occurrences is the verified scope.
- Registered S01 citations were preserved, not substituted for bad IDs. No
  source was registered and no permission changed. Registry SHA-256 remains
  `93c5b522bf483a985826164578c6c69486cd60ca05a55569e04f79220bce44ab`.
  S01 reference permission does not grant extraction, adaptation or distribution.

Schema details and rerun commands: `tools/ProvenanceRepair/README.md`.

## Applied changes and history

| Merged pilot | Sense rows revised | Provenance rows revised |
| --- | ---: | ---: |
| pilot-50 | 2 | 2 |
| pilot-230 | 2 | 462 (460 source cleanup + 2 sense bindings) |

**468 rows total**, each revision +1 and sealed with `ContractJSON.seal`.
Only current sense/provenance JSONL files were written by this migration.
Targets, teachings, questions, identity ledger, source registry, original
reviews and `CURRENT-QUALITY.md` were not edited by this task.

In both pilots, removed only the quarantined writing-teaching dependencies:

- sense `lx:sense:4ce7d12e-49f7-4135-a134-3aac1dc30b60` → usage
  `lx:usage:07c3df26-12fb-484b-bfa6-efd11f402277`;
- sense `lx:sense:3b4b445f-4e73-4163-bfe4-91d14615380c` → usage
  `lx:usage:2aab3654-b856-4c3d-a8e5-8fa5003a36ea`.

These senses remain candidate, now revision 2. Their provenance binds the exact
new revision/hash, preserves original pilot-50 batch-author-1/-2 work and receipt
refs, and has no claimed current review. Other historical subject bindings were
not upgraded. Model, prompt, transform and human-modification refs remain intact.
Migration metadata is maintenance history, never author/reviewer execution.

Four complete, byte-exact pre-migration input files are added under
`content/history/provenance-repair-v2/{pilot-50,pilot-230}/` (sense and provenance
per pilot). They are repository-visible new files, **not git-ignored**;
`git check-ignore` returned no matches. No staging or commit was performed.
Each migrated provenance row binds the archived provenance file's hash;
the two changed usage fields also cite archived sense history as internal evidence.

## Verification

- SwiftPM builds pass. **ContentKit: 271 tests, zero failures**, retaining the
  existing suite; **ProvenanceRepair: 3 tests, zero failures**.
- Added tests cover frozen v1 rejection, v2-only kinds/fields, honest no-external
  origins, unknown external IDs, unsafe/missing/tampered local artifacts, history
  hash/revision binding, exact original claim/operation preservation, unchanged
  registry, unknown-ID fail-before-write, and byte-identical rerun.
- Native candidate CLI: **pilot-50 666 / pilot-230 4,370 records pass**.
- Native private-pack graph: **zero quarantine dependencies and zero source-ref
  dangling/permission defects in both pilots**. Scanning every current
  `source_id` also found **zero unregistered IDs**. Pilot-230 retains all 82
  unverified IDs / 4,634 occurrences and 298 pre-existing stale subject bindings.
- Local internal artifacts were available at migration time; missing-artifact
  classification is exercised in the isolated migration tests. Ignored local
  work files are not promised to exist in another checkout; absence must fail
  evidence closure, never become external verification.
- Actual helper rerun: `changed_rows=0`; hashes of both current file pairs,
  all four archives, and registry remained byte-identical.
- Changed Swift files have clean SourceKit diagnostics. The persistent workspace
  client timed out on the newly created helper core; a fresh SourceKit session
  rooted at that Swift package returned an empty diagnostics array for it.

Local native receipts: `.omo/evidence/provenance-repair-v2/`
(`candidate-50.json`, `candidate-230.json`, `graph-50.json`, `graph-230.json`).
Graph runs used registry/identity ledger, quality-v2, pilot-50 reviews and
pilot-230-current reviews respectively. Full private-pack validation remains
**blocked**: 2,174 / 19,350 defect observations, including unverified origins,
missing/stale review and execution evidence, and other existing gates. These
totals are not a source-cleanup-only comparison with older review inputs.
`human_review_pending=true`, `release_eligible=false`; no approval fabricated.
