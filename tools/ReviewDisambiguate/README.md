# review-disambiguate: formal collection prep

Builds the canonical current review collection from private raw history.
There is no download URL: the full raw review evidence is private local
input supplied by the data owner or a controlled backup. Nothing here
fetches it.

## Prepare

```sh
swift run --package-path tools/ReviewDisambiguate review-disambiguate --source PATH --output OUT
```

- `--source PATH`: private raw history directory (read-only, never modified).
  Example local value: `content/reviews/pilot-230`.
- `--output OUT`: fresh canonical directory to create (for example
  `content/reviews/pilot-230-current`).

## Preflight

- Missing `--source` fails with typed
  `ReviewCoverageFailure(reason=disambiguation_missing_source:...)`
  naming the expected input and stating nothing was written. No Cocoa
  traceback, no partial output.
- Empty review input fails with typed `disambiguation_empty_reviews`;
  nothing is materialized from zero rows and no output directory is created.
- The destination is validated before any write: a differing same-named
  artifact (including a later owner decision) fails with
  `disambiguation_output_conflict` and the destination is left untouched.
  Unknown existing entries (such as `triage/`) are never deleted.

## Verify hashes

Each run writes `provenance.json` (SHA-256 of every raw input file) plus
`mapping.json`, `ambiguous-references.json`, `PARENT.json`, and
`human-recheck.STUB.md` into the output directory. To verify an available
source snapshot without implying candidate approval:

1. Compare `shasum -a 256 <source-file>` against the matching `path` entry in
   the output `provenance.json` (a source-file hash manifest).
2. Re-run the exact command above to a fresh `--output` directory and
   confirm the second `reviews-disambiguated.jsonl` is byte-identical.
3. Derived `<old>~h<12hex>` IDs are imported identities (first 12 hex of
   the row canonical SHA-256), not reviewer judgments; verdict
   disagreements stay present and still fail the all-current aggregate.

The 3-row `content/history/review-reference-repair/review-candidates.jsonl`
fixture used by `ReviewReferenceRepairTests` holds byte-identical sealed
copies of three canonical rows for clean-checkout testing only.
