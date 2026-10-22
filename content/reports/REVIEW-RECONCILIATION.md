# Review reconciliation: pilot-230 → pilot-230-current

Canonical current review collection: `content/reviews/pilot-230-current/`
Raw history (read-only, never edited): `content/reviews/pilot-230/`
Parent pointer: `content/reviews/pilot-230-current/PARENT.json`

No review approval is fabricated here. No histories were deleted, no
oldest/latest/passing winner was chosen, and no dataset, provenance,
payload verdict, checklist, session, model, or timestamp was changed.
Derived IDs are **imported identities**, not new reviewer judgments:
payload bytes are identical to the raw rows; only `record_id` changed and
`content_sha256` was resealed with `ContractJSON.seal`.

## Exact counts

| Measure | Count |
|---|---|
| Raw sealed review rows (`review-*.jsonl`) | 13773 |
| Distinct raw review IDs | 6327 |
| Singleton IDs (kept as-is) | 5779 |
| Conflict IDs (same ID, differing bytes) | 548 |
| of which with disagreeing verdicts | 112 |
| Exact-duplicate rows collapsed | 6732 |
| Canonical output rows | 7041 |
| Canonical distinct review IDs (zero duplicates) | 7041 |
| Mapping entries (`mapping.json`) | 7041 |
| Ambiguity entries (`ambiguous-references.json`) | 548 |

## Current vs stale (against `content/records/pilot-230/merged/`)

| Binding | Rows |
|---|---|
| Content-subject rows binding the current revision+hash | 2180 |
| Content-subject rows on historical revision/hash (preserved, never approving) | 1704 |
| Provenance-subject rows (extras; never widen the denominator) | 3157 |

Merged dataset: 363 sense, 363 target, 230 entry, 360 teaching,
720 questions, 2334 provenance. Stale rows stay visible for history and
still fail closed as non-current under `ReviewCoverage`.

## Identity derivation

- Singleton ID: new ID = old ID, bytes unchanged.
- Conflict group with N distinct canonical rows: each row gets
  `<old>~h<hex12+>`, where hex is a prefix of
  SHA-256(canonical sealed bytes), extended only on an intra-group
  prefix collision. Derivation is a pure function of
  (old ID, canonical hash): input file/line order cannot change it,
  and re-running on the canonical directory is an identity pass
  (verified byte-identical, no `~h~h` stacking).
- Every verdict survives, including all 112 disagreements: the
  all-current aggregate still rejects (`review_not_passed`). The
  downstream check confirming this is
  `ReviewDisambiguationTests/testDisagreementPreservedAndStillBlocked`.

## Ambiguous references (conservative: candidates reported, nothing resolved)

`ambiguous-references.json` lists all 548 conflicting old IDs with ALL
derived candidate new IDs. Exactly one conflict ID is referenced
downstream today; it is NOT rebound here (dataset/provenance belong to
another worker):

- `review/pilot-230/review-rereview1-b/0464` (both variants `quarantined`,
  subject `lx:word:e5348033-80df-4c28-8b4a-d40ffab03635` rev 3):
  - `…/0464~h08c36e50d5e2` → `reviews-disambiguated.jsonl:6410`
    (from `review-rereview1-b-delta4.jsonl:78`, `review-rereview1-b.jsonl:464`)
  - `…/0464~hd7ec8f388e7c` → `reviews-disambiguated.jsonl:6411`
    (from `review-rereview1-b2-delta3.jsonl:414`, `review-rereview1-b2.jsonl:464`)
  - Referenced by `pilot-230-provenance.jsonl:1904`
    (`provenance/teachfix-fix1/e5348033-80df-4c28-8b4a-d40ffab03635-r2`)
    and by one `human-recheck.jsonl` row. Both references are ambiguous
    until the owning workers rebind them explicitly.

## Resolved downstream binding: provenance r4 → r5 (explicit, current pending)

- `provenance/teachfix-fix1/e5348033-80df-4c28-8b4a-d40ffab03635-r2`
  r4 → r5 (resealed `a453853b…`, schema stays `lexvane.content.v1`):
  current `review_refs` is now `[]`. No verdict was picked.
- Binding check that forced the emptying (subject is entry r5
  `eee37a28…`): `review/pilot-230/review-230-b/0573` is a singleton
  binding entry r1 (`4ec7e8ef…`), and both preserved `0464` candidates
  (`…0464~h08c36e50d5e2`, `…0464~hd7ec8f388e7c`) bind entry r3
  (`57da849a…`) — all `quarantined`, none an exact-current
  (kind/id/revision/hash) match for r5, so none is retained.
- Old refs moved with all candidates and the reason to
  `content/history/review-reference-repair/migration-manifest.json`;
  the exact r4 row is archived at
  `content/history/review-reference-repair/original-provenance.jsonl`
  — evidence preserved, not discarded. Empty current refs mean pending
  independent review, not a pass; the canonical `dangling_reference` on
  the old `0464` ID from this row is eliminated.
- The `human-recheck.jsonl` row citing the old ID is triage the parent
  regenerates, untouched here.

## Canonical directory contents

- `reviews-disambiguated.jsonl` — 7041 distinct sealed rows, sorted by new ID.
- `mapping.json` — explicit old-ID + old-hash → new-ID + new-hash +
  verdict/subject/occurrence-count/source-locations/output-location.
- `ambiguous-references.json`, `provenance.json` (SHA-256 of every raw
  input file), `README.md`, `PARENT.json`, `human-recheck.STUB.md`.
- Verbatim copies (hash-verified, 1355 files, 0 mismatches): all
  `blind-*.jsonl`, `blind-230-05.json`, `blind-230-06.json`,
  `family-*.jsonl`, `human-decisions.jsonl`, and all seven
  `blind-inputs*/` directories (1325 inputs).
- Deliberately NOT copied: `human-recheck.jsonl` (112MB; the missing
  packet audits as pending, never as approval — regenerate later),
  `owner-recheck-pages/` (142MB), `sample.json` (references raw
  filenames; regenerates with canonical inputs), `OWNER-RECHECK.md`.

## Safety hardening (post-materialization fix, IDs unchanged)

- Reruns validate everything before writing anything: same-path,
  ancestor/descendant overlap, and symlinked source/output are rejected
  before any read; empty review input is rejected; all 7041 output IDs
  must be globally unique or the run fails with
  `disambiguation_id_collision` (fixed `<old>~h<12hex>` derivation, no
  extension/index fallback, no silent duplicate).
- A differing same-named destination artifact fails with
  `disambiguation_output_conflict` BEFORE any write (recursive for
  directories), so later owner decisions are never erased; nothing is
  ever deleted and unknown entries such as `triage/` are left alone.
- Rerun to a fresh directory reproduces `reviews-disambiguated.jsonl`,
  `mapping.json`, and `ambiguous-references.json` byte-identically, so
  current generated IDs are stable.
- Tests: 11/11 pass in `ReviewDisambiguationTests` (5 original + rerun
  idempotence, owner-decision refusal, overlap/symlink rejection,
  collision failure, empty-input rejection; executed in a scratch copy
  with an unrelated worker's in-flight `ContentCLI` breakage reverted
  there only).

## Verification

- `ReviewDisambiguation.swift` (new, `ContentModel`) + 6 tests in
  `ReviewDisambiguationTests.swift`: conflicting same-ID variants,
  exact duplicates, input-reordering determinism, disagreement
  preserved and still blocked, repeat-run safety, raw-input readonly.
  Result: **6/6 pass** (executed in a scratch copy with an unrelated
  worker's in-flight `ContentCLI` breakage reverted there only; the
  repo tree keeps their files untouched).
- `swift build --target ContentModel --package-path tools/ContentKit`:
  **complete**.
- Materializer: new helper package `tools/ReviewDisambiguate`
  (`review-disambiguate --source … --output …`): real run reproduced
  the counts above; re-run on the canonical directory is byte-identical.
- Raw history untouched: `git status` shows no modification under
  `content/reviews/pilot-230/`.
- Full `swift test` in the repo tree is currently blocked by another
  worker's uncommitted `ContentCLI` changes (`QualityInventory`,
  `SupplyRequest.reviews/familyAudit`, `QuestionQualityAudit` type
  errors in `QualityCommands.swift`, `FamiliesCommands.swift`,
  `SupplySimulation.swift`, `QuestionQualityAudit.swift`); none of
  those files were touched here.

## Commands

```sh
swift build --target ContentModel --package-path tools/ContentKit
swift run --package-path tools/ReviewDisambiguate review-disambiguate \
  --source content/reviews/pilot-230 \
  --output content/reviews/pilot-230-current
python3 -c "import json; rows=[l for l in open('content/reviews/pilot-230-current/reviews-disambiguated.jsonl') if l.strip()]; print(len(rows), len({json.loads(l)['record_id'] for l in rows}))"
```
