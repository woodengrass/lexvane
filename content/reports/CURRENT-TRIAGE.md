# Current human triage

The regenerated packet is pending, not approval. The original 112 MB packet and
raw reviews remain history; no human decision has been overwritten or invented.

## Reproduce

Run from the repository root; use a fresh evidence path for each generation:

```sh
swift run --package-path tools/QuestionQualityAudit QuestionQualityAudit \
  --datasets content/records/pilot-230/merged \
  --reviews content/reviews/pilot-230-current \
  --profile content/policies/pilot-quality-v3.json \
  --out content/reports/question-quality-current.json
swift run --package-path tools/ContentKit contentkit reports current-recheck \
  --dataset content/records/pilot-230/merged \
  --reviews content/reviews/pilot-230-current \
  --out content/reviews/pilot-230-current/triage/current-triage.json \
  --evidence /tmp/lexvane-triage-fresh.json \
  --policy content/reports/question-quality-current.json \
  --quality-profile content/policies/pilot-quality-v3.json
```

Use `audit-current-recheck` with the same inputs to verify byte-identical outputs.
Dataset, review and profile file sets/hashes must all match before quality-audit
items are used; stale data cannot silently enter the current queue.

Canonical collection bootstrap: the `content/reviews/pilot-230-current/`
directory is generated local state (see
`tools/ReviewDisambiguate/README.md` for the private-input prep command,
preflight, and `provenance.json` hash verification).

## Latest verified packet

4,370 subjects; 7,041 unique reviews; 720/720 question bindings current.
8,718 issues: 2,502 machine/author, 1,129 current human judgment, 5,087 historical.

| Action | Issue count |
| --- | ---: |
| Author revision | 418 |
| Excluded from supply (writing; no reauthoring requested) | 4 |
| Independent review needed | 1,619 |
| Machine/evidence fix | 1,590 |
| Historical context | 5,087 |

Action counts and bucket counts are different classifications of the same
issues. They are not unique-subject counts and must not be summed together.
The separate explicit high-risk MCQ census contains 61 current questions, each
with concrete adverse review evidence. Missing assessments alone do not make
the entire bank high-risk. Four excluded writing items are not queued for
four-option authoring or semantic assessment.

Historical unresolved findings preserve their severity and source references,
even when the current revision lacks a review. They are context, not proof that
the current revision failed or that a prior defect was fixed. Identical review
copies are deduplicated while all locations remain inspectable.

Current `changes_requested` and `quarantined` verdicts with empty findings do not
disappear: failed checklist items remain actionable, and a non-passed verdict
without a specific reason is marked incomplete evidence. Checklist reasons that
repeat an existing finding share that issue while retaining both review locations.

Read `content/reviews/pilot-230-current/triage/OWNER-RECHECK-CURRENT.md`;
machine tasks can be handled before owner judgments. Generation never changes
`human_review_pending=true` or `release_eligible=false`.
