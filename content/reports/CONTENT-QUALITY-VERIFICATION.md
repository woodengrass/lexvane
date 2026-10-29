# Content quality repair verification

This records engineering checks, not whole-bank linguistic or release approval.
Only three question texts have been revised; the bank remains unqualified.

## Review regression fixes (2026-10-26)

A clean checkout of `21508ef` reproduced 296 tests with one missing-private-file
failure. Applying the current fixes and the three-row review fixture yields
**314 tests, zero failures**, without the private canonical review archive.
Missing fixtures are not skipped. The isolated code/fixture snapshot was checked
byte-for-byte against the proposed working-tree changes.

- Both validation and package-build callers now reject a non-throwing
  `FamiliesAudit.valid=false`, retaining the shortages and creating no package.
- Nine caller-boundary tests exercise real disk-backed family audits and pack
  assembly with call-local graph-report fixtures. They isolate this boundary,
  not full evidence closure. Default/public entrypoints separately reject the
  intentionally invalid graph after injected success. No global override exists.
- Review-reference tests use three sealed source fixtures instead of the ignored
  full review archive. Formal private inputs remain owner/backup prerequisites;
  missing input exits 65 with actionable guidance and creates no output.
- Both non-passed review verdicts remain actionable with empty findings. Failed
  checklists retain their reasons; bare rejections remain incomplete evidence.
  Deduplication retains all contributing review locations and historical context.
- Live regeneration restores one omitted checklist issue: 8,717 becomes 8,718.
  Byte-for-byte audit passes with fresh dataset/review/profile bindings.
- Independent follow-up review: APPROVE for these three fixes. This is not
  whole-bank content approval or permission to release.

## Real-surface checks

| Surface | Observed result | Evidence |
| --- | --- | --- |
| Search | Whitespace normalization preserves exact IDs, phrases and hyphens | SearchIndexTests and prior native CLI probes |
| Identity registration | 2,756 required IDs resolve; original 290-event prefix preserved | `content/ids/registration-20261022.json` |
| Review materialization | 7,041 unique records preserve 13,773 occurrences and all conflicts | canonical mapping and reconciliation report |
| Source repair | All external source IDs resolve; 82 unresolved IDs remain explicitly unverified | `PROVENANCE-REPAIR.md` and original snapshots |
| Writing isolation | No writing supply; introduced quarantine dependencies eliminated | WritingExclusionTests and native graph |
| Revised questions | Three four-option revisions, preserved IDs/history, no inherited review pass | QuestionRevisionTests and tracked first-batch evidence |
| Whole-bank quality | 716 MCQs: 292 pending, 424 rejected, zero qualified | `question-quality-current.json` |
| Human triage | 8,718 issues; fresh inputs; pending decisions unchanged | `CURRENT-TRIAGE.md` and current packet |
| Private-pack validation | Exit 65; 19,572 observations, including 358 explicit family shortages | `three-fixes-real-graph.json` |

The prior ProvenanceRepair run passed three tests. This follow-up did not modify
that package. All Swift files changed in this follow-up have clean diagnostics;
SwiftPM builds and executes the complete ContentKit suite. `git diff --check`
is clean. The IDE build service has another project open, so SwiftPM supplied
the actual build validation.

## Reproduction evidence

Local logs and receipts are in
`/var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/`:
`three-fixes-before.log`, `three-fixes-clean-full.log`,
`three-fixes-source-retention-red.log`, `three-fixes-real-graph.json`, and
`three-fixes-triage-audit.json`. These are local temporary artifacts, not inputs
required by tests. Run `swift test --package-path tools/ContentKit` after
including the proposed fixes and new fixture to reproduce the test result.
See `tools/ReviewDisambiguate/README.md` for formal collection preparation.

## Remaining content acceptance

Review disagreements, unavailable execution/source evidence, missing current
reviews, 298 historical provenance-binding defects and other content gates remain
explicit blockers. The additional 358 reported shortages were previously ignored
by callers; they do not represent new authored-content defects. No owner signature,
source permission, passed full review or family qualification was fabricated.
These regression fixes do not make the bank publishable or fully rewritten.
