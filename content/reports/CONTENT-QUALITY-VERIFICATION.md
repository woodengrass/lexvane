# Content quality repair verification

This records completed engineering checks, not blanket linguistic or release
approval. The whole bank was audited; only three question texts were revised.

## Manual QA on the real artifact

| Surface | Observed result | Evidence |
| --- | --- | --- |
| Existing-index search | Padded/fullwidth `apple`, repeated/tab/newline/NBSP/fullwidth-space `according to` return the same exact IDs; whitespace-only returns none | `SearchIndexTests`, actual `contentkit search` probes |
| Identity adoption | 2,756/2,756 resolve; 2,466 retries append zero bytes; original 290-event prefix unchanged | `content/ids/registration-20261022.json`, native `ids audit`, migration `--verify` |
| Review materialization | 7,041 unique output IDs from 13,773 occurrences; all 548 conflicts and 112 verdict disagreements retained | canonical `mapping.json`, `ambiguous-references.json`, `provenance.json`; 11 regression tests |
| Source repair | Every actual external source ID registered; all 82 unresolved identifiers remain unverified; no new permissions | `PROVENANCE-REPAIR.md`, original snapshots, three repair tests |
| Writing isolation | No active writing targets, no writing supply; both introduced quarantine dependencies eliminated | `WritingExclusionTests`, native graph |
| Three revised questions | Four options, single key, no embedded answer; same IDs, new revisions and hashes, matching provenance, no inherited review refs | `QuestionRevisionTests`, tracked first-batch proposals/reviewer/history |
| Whole-bank eligibility | 716 MCQs audited: 292 pending, 424 rejected, zero qualified; 418 author work / 716 review work | `question-quality-current.json` |
| Real v3 supply | 716 target/scenario allocation rows (358 targets times two scenarios); no consumed check or train families | native `supply simulate` with v3 inputs; allocations are not questions served |
| Human triage | Fresh dataset/review/profile binding; audit reproduces 8,717 issue rows, original severity/history preserved | `CURRENT-TRIAGE.md`, current triage JSON/JSONL |
| Candidate decoding | Both pilots pass: 666 and 4,370 records | native `validate --stage candidate` |
| Private-pack graph | Still blocked: 19,214 observations; zero targeted identity/duplicate/source/quarantine/dangling/profile defects | native `validate --stage private-pack` |

## Automated checks

- `swift test --package-path tools/ContentKit`: 295 tests, zero failures.
- `swift test --package-path tools/ProvenanceRepair`: three tests, zero failures.
- `swift run --package-path tools/QuestionRevision qr-seal check --in ...` uses
  the official `ContractJSON.decode`, not a duplicate hashing implementation.
- `git diff --check`: clean.
- Independent integrated safety review: APPROVE for the implemented repairs and
  fail-closed gates. The reviewer reconciled the reports with current artifacts;
  this approval is not linguistic approval of the whole bank or release approval.
- Main edited sources have clean LSP diagnostics. SourceKit reports an unresolved
  module on the newly added `QuestionRevisionTests.swift` in its persistent
  session, while SwiftPM compiles and runs that test successfully; this tooling
  discrepancy is disclosed rather than reported as a clean LSP result.

Local raw verification logs/receipts are in
`/var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/`:
`quality-final-tests.log`, `quality-repair-tests.log`,
`quality-final-graph.json`, `quality-final-supply.json`, and
`quality-final-triage-evidence.json`. These are local artifacts; rerun the
documented commands rather than assuming those temporary paths exist elsewhere.

## Remaining content acceptance

Review disagreements, unavailable execution/source evidence, missing current
reviews, 298 historical provenance-binding defects and other graph gates remain
explicit blockers. Importing review identities or recording three linguistic
assessments does not resolve them. No owner signature, source permission, passed
full review or family qualification was fabricated. The current bank must not
be presented as fully rewritten, qualified or publishable.
