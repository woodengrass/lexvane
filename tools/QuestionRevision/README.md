# Official question record sealer

This helper delegates directly to ContentModel's contract validator and sealer.
It writes only stdout, never overwrites an input file, and rejects unknown
schemas or malformed records rather than merely accepting matching hashes.

```sh
swift run --package-path tools/QuestionRevision qr-seal check --in INPUT.jsonl
swift run --package-path tools/QuestionRevision qr-seal seal --in DRAFT.jsonl
```

Sealing is structural validation only. Revision discipline, history, provenance
bindings and independent reviews are separate obligations. The first migrated
batch is recorded under `content/history/question-quality-first-batch/`.
