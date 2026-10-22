# M1 handoff: private pilot, human review pending

Private pilot. Unpublished. Nothing below is approved for release.

## Start here: your recheck packet

Read this first: [OWNER-RECHECK.md](../reviews/pilot-230/OWNER-RECHECK.md). It holds every subject flagged for your eyes, with full content, agent verdicts and disagreements, before and after fixes, sources, and what to check. Supporting files sit next to it: `human-recheck.jsonl` (full rows), `sample.json` (selection and input hashes), `human-decisions.jsonl` (empty, that is correct), and `owner-recheck-pages/` (140 paged files).

Reviewer guidance for you:

- The packet header says PENDING and every row says pending. Generating the packet is not an approval. Your reply is the only thing that can change a row, and no agent may write it for you.
- Each row shows the lemma or phrase, sense, tested ability, complete teaching and questions with answers and feedback, why it was selected, how severe the finding is, where agents disagreed, what changed across revisions, source links, and a checklist of what to look at.
- High-risk rows (answer or feedback fixes, multiple valid answers, reviewer splits, second-sense or alias trouble, rights warnings) come as a full census. The general random sample sits in its own section.
- To record a decision, append rows to `human-decisions.jsonl`. Do not edit the packet in place. Leave anything you have not read as pending.

Still to review: all 2,800 selected subjects are pending, including the full 2,800 high-risk census. The unflagged random strata honestly report zero population (no unflagged records exist in the merged set), so zero were drawn. That gap is recorded, not hidden. Until you reply, `human_review_pending` stays true and `release_eligible` stays false.

Implementers: the per-item agent review evidence you must consult before touching content is `content/reviews/pilot-230/` (review rows, blind solves, family verdicts) plus the trial lineage in `content/jobs/pilot-50/receipts/`. You rerun the audits below; you never mark plan checkboxes yourself.

## What exists, in numbers

Counts are candidates, not acceptances. Confirmed accepted count is 0 across the board.

| Item | Count | Source |
|---|---:|---|
| Words selected | 200 | `content/pilot/selection.json` |
| Phrases selected | 30 | `content/pilot/selection.json` |
| Trial subset (inside the 200) | 50 | `content/pilot/selection.json` subset list |
| Merged candidate records | 4,370 | `content/records/pilot-230/merged` |
| Entries / senses / targets | 230 / 363 / 363 | merged entry, sense, target files |
| Teachings / questions / provenance | 360 / 720 / 2,334 | merged teaching, question, provenance files |
| Search index | 230 entries, 234 terms | `content/derived/pilot-v1/index.json` |
| Identity ledger events | 290 | `content/ids/ledger.jsonl` |
| Recheck subjects pending | 2,800 | `content/reviews/pilot-230/human-recheck.jsonl` |
| ContentKit tests | 190, all passing | `swift test --package-path tools/ContentKit` |

## Triple status

Authorization: every source operation is pending. No fetch, retain, extract, adapt, or pack grant exists for official materials. Third-party passage rights are separate unresolved placeholders. Costs are unknown.

Agent work: T005 mapping blocked. T006 trial frozen but expansion blocked on the writing contract. T007 candidate content built but acceptance never went green. T008 graph and pack blocked; the index build and trial supply replay are the only green subtasks. Full per-task status with evidence refs lives in [M1-STATUS.json](../reports/M1-STATUS.json).

Human: pending everywhere. No decisions file entries, no approvals, no release.

## Literal commands

Run every command from the repo root. All of them use `set -o pipefail`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, and a private mode-0700 TMPDIR outside the repo. Alias used below: `CK` means `swift run --package-path tools/ContentKit contentkit`. Never install a program called CK.

Full test suite (190 tests, expect exit 0):

```sh
set -o pipefail
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path tools/ContentKit
```

Focused handoff gate (5 tests, expect exit 0; the 4 rejection tests prove dishonest packets fail):

```sh
set -o pipefail
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path tools/ContentKit --filter HandoffStatusTests
```

Read-only search smoke (no pack needed, expect exit 0):

```sh
set -o pipefail
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path tools/ContentKit contentkit search --index content/derived/pilot-v1/index.json --query apple
```

Expected output: `query=apple key=apple match=exact ambiguous=false entries=1 ids=lx:word:0ddd5790-82ca-4902-bbdc-039203ce8eb6`. Any other selection word or phrase works the same way; multi-entry aliases return candidates instead of picking one.

Rebuild the deterministic index and compare bytes (expect identical hashes across runs):

```sh
set -o pipefail
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path tools/ContentKit contentkit index build --dataset content/records/pilot-230/merged --out /tmp/m1-verify/index-a.json --evidence /tmp/m1-verify/index-a-evidence.json
set -o pipefail
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path tools/ContentKit contentkit index build --dataset content/records/pilot-230/merged --out /tmp/m1-verify/index-b.json --evidence /tmp/m1-verify/index-b-evidence.json
cmp /tmp/m1-verify/index-a.json /tmp/m1-verify/index-b.json
```

Graph audit showing the real blocker (expect exit 65 with typed defects, not success):

```sh
set -o pipefail
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path tools/ContentKit contentkit validate --dataset content/records/pilot-230/merged --stage private-pack --sources content/sources/registry.jsonl --reviews content/reviews/pilot-230 --ledger content/ids/ledger.jsonl --profile content/policies/pilot-quality-v1.json --evidence /tmp/m1-verify/graph.json
```

Trial supply replay (expect exit 0 twice with identical bytes; trial data only, never pilot-230 claims):

```sh
set -o pipefail
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path tools/ContentKit contentkit supply simulate --dataset content/records/pilot-50/merged --profile content/policies/pilot-quality-v1.json --scenario content/policies/pilot-supply-scenarios.json --seed 111 --out /tmp/m1-verify/supply-a.json
```

M0 app regression via Xcode (fallback because Xcode MCP tooling is unavailable in this session; record honest output, never call a timeout a pass):

```sh
set -o pipefail
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Lexvane.xcodeproj -scheme Lexvane -configuration Debug -destination 'generic/platform=iOS Simulator'
set -o pipefail
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Lexvane.xcodeproj -scheme Lexvane -configuration Debug -destination 'platform=iOS Simulator,id=AA1E0570-12E0-4DCE-B33D-DD8EDD491514' -parallel-testing-enabled NO
```

## Pack schema (planned, not yet built)

No real pack exists: both Task18 build attempts exited 65 at the graph gate and produced no output, and `content/builds/` was never created. When the gate passes, the builder produces a `private-preview` directory with this shape:

- The six merged JSONL payloads plus a regenerated index, byte-compared against `content/derived/pilot-v1/index.json` before publication.
- `manifest.json`: schema, content, quality, and prompt versions, fixed input hashes, payload SHA-256 values with byte and record counts, `build_mode=private-preview`, `release_eligible=false`, `human_review_pending=true`, license summary, index format, check-bank hash. No timestamps or absolute paths feed the hashes.
- `licenses/` and attribution text, a separate check bank, and no exam originals, PDFs, credentials, or review transcripts.
- `pack verify` rechecks hashes, counts, contract decoding, version bounds, and check-bank isolation fully offline. `pack compare` diffs every payload file byte for byte. `--mode production` is rejected outright.

## Audit note: where the gate lives

There is no `reports audit-handoff` CLI subcommand. Task20 scope allowed Swift edits only in one new test file, so the gate is `HandoffAudit` inside `tools/ContentKit/Tests/ContentKitTests/HandoffStatusTests.swift` (5 tests green, red-first evidence retained) plus a mirrored real-file python3 check whose report is `.omo/evidence/m1-content-pilot/a1-task20/task-20-handoff.json`. Both enforce the same five rules: pending humans cannot claim release, T005 done needs inventory plus mapping evidence, zero tests cannot claim all passed, the handoff must link OWNER-RECHECK.md, and the recheck must stay marked pending. An honest packet passes; a dishonest one fails with a named violation. Passing never approves anything.

## M2 next steps (in order)

1. Settle source rights with real evidence, or keep T005 blocked. Lawful wordlist bytes, page and line provenance, and per-item rows are the unblock path.
2. Resolve the writing contract (versioned answer rules) or keep the writing exclusion. That ruling alone gates T006 expansion.
3. Clear the 146,767 graph defects upstream with new revisions and re-reviews, then rebuild the pack twice and compare bytes.
4. Run your human recheck replies into `human-decisions.jsonl`, then run final verifiers F1 through F4 and report back before anyone claims M1 complete.
