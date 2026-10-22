# Content contract v1 — frozen pure-data boundary

Schema: `lexvane.content.v1`. Eight kinds: entry, sense, target, teaching,
question, provenance, review, manifest. `ContentDocument<Payload>` is the common
typed Codable envelope; each payload lives in its own ContentModel file.
Unknown schema versions, record kinds, enum values and fields (including nested
fields) fail closed. Missing required fields and null instead of a required value
are rejected. There is no optional catch-all metadata dictionary.

## Envelope and wire format

Every document has **schema, kind, record_id, revision, content_sha256, payload**.
Revision is a positive integer. Word/phrase/sense/usage/target/question/family
references use task4's `lx:<kind>:<opaque UUID>` identity format. The fixture UUIDs
are synthetic and never issued into the production ledger. Entry kinds reuse
`IdentityKind` and admit only word/phrase. Teaching records identify a usage;
provenance, review and manifest documents have explicit relative document refs,
not invented new ledger identity kinds. Their subject references preserve the
content identity, revision and hash separately.

JSONL is UTF-8 without BOM, one compact object per line, LF including the final
line terminator, no blank records. Encoding is JSONEncoder sorted keys,
withoutEscapingSlashes, convertToSnakeCase. Arrays preserve authored order. No
case folding, Unicode normalization or reordering arrays occurs in this codec.
The validator tolerates key order/insignificant JSON whitespace on input;
canonical output always uses the fixed encoding. CRLF and invalid UTF-8 reject.

`content_sha256` is SHA-256 of the canonical **whole envelope**, with only its own
content_sha256 set to the empty string and **without the JSONL LF**. Subject hashes
inside provenance/review remain included. This avoids recursive self-hashing and
keeps identity, revision, schema and every authored field in the digest. There is
no wall-clock call or absolute-path input. Manifest `fixed_input_time` is required,
explicit immutable input metadata and is included in its revision hash. Changing
that field changes the hash; time is not silently discarded. `ContractJSON.seal`
validates structure before computing a new declared hash; ordinary decode always
verifies the declared hash. Canonical JSONL round-trips byte-for-byte.

The supported entry point is `ContractJSON.decode`; direct typed Codable decoding
also validates the envelope, enums, shape and hash when using the contract's
snake-case strategy. Use the codec rather than configure a different strategy.

## Required payload fields

All six content payloads require status **candidate / approved / quarantined**
and nonempty provenance_refs. Status is editorial data, not CLI authorization.

| Kind | Required fields and meaning |
| --- | --- |
| entry | entry_kind (word/phrase), lemma, aliases and variants (explicit text + same entry_id), sense_ids, provenance_refs, status |
| sense | entry_id, pos, core_meaning_zh_hant, priority_tier, priority_reason, source_refs, usage_ids, provenance_refs, status |
| target | entry_id, sense_id, usage_ids, tested_ability, activation (active/inactive), priority_tier, priority_reason, source_refs, provenance_refs, status |
| teaching | primary_target_id, tested_ability, explanation_zh_hant, usage, examples (english + zh_hant), pronunciation_text, source_refs, provenance_refs, status |
| question | primary_target_id, tested_ability, family_id, split, stem, options (option_id + english), accepted_answers, correct_sense_id, correct_usage_ids, post_answer_feedback (answer + explanation), distractor_rationales (option_id + reason), provenance_refs, status |
| provenance | subject_id/kind/revision/content_sha256, fields (field + source_refs + method), model, prompt_hash, work_unit_ref, run_receipt_ref, transform_chain, review_refs, human_modification_refs |
| review | subject_id/kind/revision/content_sha256, reviewer_session/model, input_hash, prompt_hash, checklist (item + result + reason + source_evidence), verdict, findings (finding_id + severity + state + reason), receipt_refs |
| manifest | schema_version, content_version, policy_version, prompt_version, source_versions (source_id + source_version), input_hashes and file_hashes (relative ref + sha256), counts (kind + count), build_mode, release_eligible, human_review_pending, license_summary, index_format, check_bank_hash, fixed_input_time |

POS: noun, verb, adjective, adverb, pronoun, preposition, conjunction, determiner,
interjection. Priority: foundational / supplementary / deferred, with an explicit
reason and source refs, never precise estimated exam probability.

Ability: **contextual_choice / meaning_recognition / writing**. These are separate
target abilities and never interchangeable evidence. Question split: **train /
check**, with a stable independent family identity. Choice answers contain stable
option IDs; writing answers contain explicit accepted strings, including authored
legal variants. Choice questions need at least two options, and precisely one
rationale per nonaccepted option. Writing has empty options and distractor lists.
Feedback is mandatory and is only post-answer exposure. Extra hint fields at any
depth reject because the schema has no such field.

Aliases/variants explicitly map to their own canonical entry identity. A spelling
belonging to another independently authored entry cannot be imported as a variant.
Collisions between separate headword identities are retained, not unioned. The
validator does not build lookup keys or a search index; NFKC/case-insensitive
lookup belongs to task17. It never strips hyphens or substitutes form/from,
trial/trail or re-sign/resign. Authorship/review must establish whether an asserted
same-identity variant is legitimate; schema alone cannot prove linguistic truth.

Source references carry **source_id** from task2 and reuse exhaustive
`SourceOperation`; `ContractSourceRef.ancestor` bridges directly to its
`SourceAncestor`. Manifest source_versions lock task2's source-version hashes.
Source permission, attribution and legal provenance remain in the registry, not
duplicated as inferred grants. Candidate schema validation does not consult the
registry or prove an allowed operation. Field derivation methods: reference,
extract, adapt, human_authored, ai_generated. For non-AI authorship the model must
explicitly say none with a reason; prompt_hash can identify the frozen authoring
instructions. Empty transform/review/human-modification arrays mean none has
occurred, not fabricated history.

Review checklist: passed / failed / not_applicable, each with reason/evidence.
Verdict: passed / changes_requested / quarantined. Finding severity:
critical / major / minor; state: unresolved / resolved. A passed review cannot
contain failed checklist items or unresolved findings. Review schema success is
not proof that a real reviewer ran. Blind-solve, human replies and job receipts
are separate downstream contracts, not learner-event or SRS design here.

Manifest is private-preview only, release_eligible=false and
human_review_pending=true at this boundary. It records hashes/reserved index and
check-bank metadata without building those artifacts. File existence/hash graph
audit and packaging are downstream work. An explicit fixed timestamp is not a
hidden generation time.

## Trial profile and downstream use

`content/policies/pilot-trial-v0.json` is the **task9** trial profile: each active
target needs at least one train question and at least one check family independent
of train, complete current-revision review/feedback/provenance, and zero unresolved
critical findings. These are trial hard conditions only; no sampling, supply,
optimization or defect-rate threshold is frozen here. **Task10** measures the
trial and creates the later measured profile. Candidate validate does not evaluate
trial acceptance or claim that fixtures satisfy these gates.

## Shared fixtures and CLI

`examples/valid/` contains 13 synthetic records: all eight kinds, three ability
targets/questions, and a check-split question. `examples/invalid/` contains one
missing-payload rejection per kind. XCTest additionally mutates fields to test
schema, required-field, enum, hint, feedback, identity and hash boundaries.
The test fixture directory is a relative symlink to examples/valid so CLI and
XCTest use the same bytes. Sources/review/receipt/hash reservations are explicitly
synthetic; none imply actual authorization, human acceptance or independent review.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run \
  --package-path tools/ContentKit contentkit validate \
  --dataset tools/ContentKit/Tests/ContentKitTests/Fixtures/contracts/valid \
  --stage candidate --evidence .omo/evidence/m1-content-pilot/a1-task6/task-6-contract.json
```

All three flags are required and explicit. Only candidate stage is implemented.
Malformed records return exit 65 with typed reason and file/line context, preserve
dataset bytes and do not replace an existing successful evidence receipt. Evidence
must be outside the dataset. A successful report states acceptance_evaluated=false
and release_eligible=false. Full graph, rights, review coverage, independence and
human gates are not silently inferred from schema success.
