# M1 content pilot: decisions

Private pilot. Nothing here grants release. All authorization stays pending until a human with actual authority says otherwise. Costs are unknown. Human review is pending.

## 1. Data requirements: what got bigger, what did not

The original pipeline spec asked for a small representative batch of exam references. This pilot widened that to a full source inventory: every public GSAT English source from school year 111 through the latest published year, plus the official wordlist, explanations, and reference papers. The widening covers listing and legally usable data整理 only. It is not a stats platform, not exam prep for every subject, and not a cross-school system.

Two boundaries hold. First, we never quietly shrink back to a small search; the full 111+ inventory is the denominator and it stays fixed at cutoff 2026-10-11. Second, we never grow into other schools, other subjects, listening tests, or cram-school answers. Those are out of scope and stay out.

Cutoff rule: the run fixes `retrieved_at`, `cutoff_date`, and each official index snapshot and hash at discovery time. Anything published later is reported as a next-version update. The denominator never drifts mid-run.

## 2. Private gate: pending means pending

Every source row carries per-operation permissions (`reference`, `fetch`, `retain`, `extract`, `adapt`, `local_analysis`, `private_pack`, `distribution`), each one `allowed`, `pending`, or `rejected` with evidence. No operation flips from pending to allowed on its own. A public URL is not permission. Rewording a text does not clear its lineage. Agent agreement is not permission.

`private_pack` allowed never implies `distribution` allowed. The pack builder only runs in `private-preview` mode with `release_eligible=false` and `human_review_pending=true`. `--mode production` exits 65, always, in M1. Original exam papers, PDFs, third-party passages, and commercial dictionary text never enter the content pack, the repo, or a PR.

## 3. Tool choice: one isolated Swift package

All content tooling lives in `tools/ContentKit`, a dependency-free Swift Package (XCTest plus Foundation and CryptoKit). Model and validator targets never import SwiftUI, UIKit, or PDFKit. Only the macOS CLI extractor uses system PDFKit, and only on lawfully obtained files with explicit `--file`, `--rule`, `--registry`, `--source-id` flags. It does no network calls and no OCR. Garbled or empty pages are extraction failures, not content. The App target, the Xcode project, and the M0 probe are never touched by content work.

## 4. Format: typed contracts, canonical bytes

`content/contracts/v1` freezes every record shape (entry, sense, target, teaching, question, provenance, review, manifest). Each kind has required fields and exhaustive enums, not freeform dictionaries. JSONL is UTF-8 with sorted keys, compact separators, one LF per line, no blank lines. Unknown schemas are rejected. There is no pre-answer-hint field anywhere; that is deliberate, so no author can sneak hints into the format.

Every record binds `record_id`, `revision`, and `content_sha256`. A review or blind solve that names an old revision is stale and fails. A changed feedback text with an old pass verdict fails. Revision hashes are canonical: same content, same hash, no timestamps or absolute paths inside.

## 5. Identity: stable IDs, honest splits

IDs look like `lx:<kind>:<opaque-id>`. The coordinator issues them once into the append-only ledger and never derives them from text, translation, order, or vendor IDs. Editing copy keeps the ID and bumps the revision. Splitting or merging a meaning needs an explicit event with predecessor and successor IDs, a reason, and evidence. Old history is never rewritten.

Aliases and spelling variants map to the same entry. They never add headwords and never inflate counts. The pilot holds 200 distinct words plus 30 distinct whole phrases, with the 50-word trial subset contained in the 200. An alias-only string is not a word. A phrase never splits on spaces.

## 6. Quality profile: measured, then frozen

The 50-word trial ran first. Its evidence froze `content/policies/pilot-quality-v1.json` and the fixed `pilot-supply-scenarios.json`. Trial-only `pilot-trial-v0.json` held just the hard gates; measured thresholds came later from real trial numbers, never from guesses about ideal teaching.

Frozen minimums: every active target needs at least one train question family and one independently written check family, complete review, feedback, and provenance, with zero unresolved critical findings. Trial costs that could not be read are recorded as `unknown`, never as zero. Sampling uses seed 111 with a fixed high-risk census plus a stratified random draw; cherry-picking pretty samples is forbidden and the sample size is never zero.

## 7. R-writing-excluded: the writing ruling

On 2026-10-13 the coordinator ruled the trial conclusion stays `blocked-on-writing-contract` (`expansion_eligible=false`), and work continues toward T007 with the writing ability excluded from scope. The writing target `bf7b049b` stays quarantined and isolated. No writing questions and no spelling obligations ship in later tasks. Profile minimums apply to active non-writing targets only. The frozen single-solution contract is unchanged. Only your counter-order or a real writing-contract change can reverse this.

## 8. Honest-partial precedents: what never counts as what

These mixups have been tried and rejected before, so they are written down as standing rules:

- A complete metadata inventory is not a complete T005 mapping. Mapping needs lawful bytes, page and line provenance, and per-item rows.
- Candidate records are not accepted records. Self-authored content is a candidate until independent review, blind solves, and family checks all pass at the current revision.
- Raw review passes are not acceptance. The trial showed 98 raw question passes with confirmed accepted count 0.
- A generated recheck packet is not a human approval. `human-decisions.jsonl` is empty and every row stays pending.
- A timeout is not a success. A zero-test run is not "all tests passed." The handoff audit rejects both claims mechanically.

## 9. Frozen inputs (do not edit without a new version)

- Source cutoff 2026-10-11; annual corpus 111 to 115; wordlist edition label `ceec-wordlist:109-07-31-published:111-effective` (metadata only, byte hash unavailable).
- `content/pilot/selection.json` (200 words, 30 phrases, 50-word subset, selection seed pinned).
- `content/contracts/v1`, `content/prompts/v1`, `content/policies/pilot-quality-v1.json`, `content/policies/pilot-supply-scenarios.json`.
- Identity ledger `content/ids/ledger.jsonl` (290 events at last count; append-only, coordinator-owned).
- Search index normalization: NFKC plus English case folding for lookup keys only; hyphens and whole phrases preserved. Index holds 230 entries and 234 terms.

## 10. Where M1 stands and what stays unresolved

T005 source mapping is blocked on rights: no lawful wordlist bytes, so no official denominator and no per-item rows. T006 trial profile is frozen but expansion is blocked on the writing contract. T007 holds 200 words plus 30 phrases as candidates with independent check families drafted, but full current-revision review and acceptance never went green. T008 has a deterministic index and trial-only supply replay, but the cross-reference graph fails (146,767 typed defects at last audit) and no real pack has ever built. Final verifiers F1 through F4 have not run. M1 is not complete, and no one may declare it complete on this evidence.
