# Provenance repair v2

Run from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run \
  --package-path tools/ProvenanceRepair ProvenanceRepair "$PWD"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test \
  --package-path tools/ProvenanceRepair
```

The helper prepares all changes before writing, refuses uninspected source IDs,
archives the four original files under `content/history/provenance-repair-v2/`,
and increments each changed row exactly once through `ContractJSON.seal`.
Already-repaired inputs produce `changed_rows=0` without rewriting files.
It never writes source rights, jobs, reviews, identities, targets, teachings or
questions. Parallel writers must not modify the four owned input files while it
runs; concurrent changes detected before replacement fail closed.

## Provenance-only schema

`lexvane.provenance.v2` is accepted only for `kind=provenance`. All other kinds
remain `lexvane.content.v1`. Frozen v1 still requires nonempty `source_refs` on
every derived field; its fixtures, hashes and required fields are unchanged.

V2 replaces each derived field's ambiguous `source_refs` with required arrays:

- `external_source_refs`: registry `source_id` + original operations. Registry
  resolution and permission gates still apply; no rights are inferred.
- `internal_evidence_refs`: relative `ref`, optional positive `line`,
  `availability` (`available` / `unresolved`), optional `sha256`, and `reason`.
  Available artifacts require a matching regular-file hash and valid line;
  unresolved artifacts have no hash and cannot close evidence. Symlink escapes
  reject. Work artifacts are not execution receipts or external verification.
- `unverified_refs`: `original_source_id`, original `operations`, and `reason`.
  These preserve historical claims without masquerading as registered citations.
  Unverified origins remain evidence-closure defects, not newly approved content.

Required `origin` is `external`, `generated`, or `unverified`. External origin
requires actual external refs. No-external generated origin requires an explicit
AI/human generation method and work evidence. Unverified origin requires the
original unresolved identifiers. The original `method` is retained; when origin
is unverified, that method describes the historical claim, not verified extraction.
V2 cannot use the old field key, and v1 cannot use these new fields.

Optional `migration_evidence` contains `history_ref`, `history_sha256`, and
`reason`. Disk-backed validation checks the archived original identity and +1
revision. Histories are cached within a graph-validation invocation, not globally.
Maintenance metadata never substitutes for a generator/reviewer receipt or
upgrades a stale subject claim. Original model, prompt, work-unit, receipt,
transform and human-modification references are preserved by this migration.

The explicit 82-ID allowlist records the inspected lineage. All originals and
operations remain in `unverified_refs`; only available exact order-set matches
are recorded as corresponding internal files. Missing paths or mismatched labels
stay unresolved. The two repaired sense subjects are rebound to revision 2 with
empty current-review refs; no original review is rewritten.
