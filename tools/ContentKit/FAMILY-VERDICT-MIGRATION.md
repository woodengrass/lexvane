# Family verdict revision bindings (F2-02)

Flat `family-verdicts*.jsonl` rows must include both binding fields:

```json
{
  "current_member_bindings": {
    "train": {"record_id": "<train question ID>", "revision": 1, "content_sha256": "<sealed hash>"},
    "check": {"record_id": "<check question ID>", "revision": 1, "content_sha256": "<sealed hash>"}
  },
  "current_teaching_bindings": [
    {"record_id": "<teaching ID>", "revision": 1, "content_sha256": "<sealed hash>"}
  ]
}
```

These are additional required fields, not a replacement for target/family IDs,
verdict, evidence, and evaluator session. Bindings must match the current train,
check, and every teaching record for the target. Use an empty teaching array only
when that target has no teaching records. Question or teaching revisions/hashes
invalidate older bindings.

Historical pilot-50 and other unbound verdicts now fail closed with
`FamiliesFailure(reason=missing_family_bindings:...)`. Incomplete or stale
bindings cannot satisfy `missing_current_family_verdict` checks. Stable family
IDs and favourable labels are not proof that an evaluator saw current bytes.

Do **not** rewrite historical verdicts or backfill them from today's dataset:
doing so would falsely claim a revision-bound review. Retain the original files
unchanged. A reviewer must compare the frozen current train/check/teaching inputs
again and issue new revision-bound evidence in a separately versioned review
set. Point the audit at that new set; a set still containing legacy unbound
verdict rows remains rejected. This tooling change grants no rights, human
acceptance, or release eligibility.
