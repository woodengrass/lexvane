# Current content quality status

Engineering repairs are applied. **The candidate bank is not approved or ready
to serve:** v3 currently qualifies zero questions. No human approval, source
permission, historical execution receipt or release eligibility was invented.

## Effective inputs

- Content: `content/records/pilot-230/merged/`.
- Reviews: `content/reviews/pilot-230-current/`; original `pilot-230/` is history.
- Policy: `content/policies/pilot-quality-v3.json`.
- Whole-bank scenario: `content/policies/pilot-supply-scenarios-v3.json`.
- Current question census: `content/reports/question-quality-current.json`.
- Owner triage: `content/reviews/pilot-230-current/triage/OWNER-RECHECK-CURRENT.md`.

Frozen v1/v2 policies and trial scenarios remain historical inputs. In v3,
`eligible_questions` in the scenario retains its legacy field name but means
offered candidate bindings, not a quality grant. The actual supply evaluator
filters them through current quality and family evidence.

## Applied outcomes

- All 2,756 required identities resolve. The 2,466 appended registrations preserve
  the original 290-event ledger prefix byte-for-byte; exact retries append nothing.
- 13,773 raw review occurrences are represented by 7,041 unique canonical reviews.
  All variants of 548 conflicting old IDs and all 112 verdict disagreements are
  preserved. Naming repair is not adjudication; current negative reviews block.
- 460 provenance records separate external citations from internal work evidence
  and unverified claims. All 82 unregistered identifiers and 4,634 occurrences
  survive explicitly as unverified evidence; registered source rights are unchanged.
- Writing is inactive/excluded in both pilots. Four writing questions and two
  teachings per pilot are quarantined. Both affected senses no longer depend on
  those teachings; original bytes and revision histories remain available.
- The hospital, fire and night examples were substantively revised to four
  choices and separately reviewed for linguistic suitability. Their IDs persist,
  revisions/hashes changed, and old reviews are not reused. Full current-review,
  execution and family gates still apply.
- Check requires four choices and one correct option. Train defaults to four;
  two-choice contrast requires current independent justification. Three-choice
  questions, stale/incomplete/self reviews and unresolved findings cannot qualify.
- Query padding and repeated whitespace are normalized without changing persisted
  index bytes, hyphen distinctions or phrase boundaries.

## Current counts, not approval

The 720 questions comprise 716 MCQs and four excluded writing questions.
For MCQs, 292 are pending and 424 rejected under v3; **zero are currently usable**.
418 need author work and all 716 still need complete current review work; these
worklists overlap. Only three linguistic revisions were made, not a claim that
all 716 questions have been rewritten. No filler options were bulk-added.

The explicit high-risk MCQ census is 61 of 716, selected from current adverse
review evidence, not from absence of an assessment. All remain pending.
See `content/reports/v3-human-risk-selection.json` for per-ID reasons and hashes.
The broader triage contains 2,502 machine/author issues, 1,129 current judgment
issues and 5,087 historical-context issues. These are issue counts, not distinct
people's review assignments; history retains its original severity separately.

## Verification and remaining gates

- ContentKit: 314 tests pass in an isolated checkout with the current fixes and
  without the private review archive; ProvenanceRepair's prior run passed three tests.
- Native candidate decoding passes both pilots (666 / 4,370 records).
- Native graph reports zero identity-binding, duplicate-ID, unregistered-source,
  quarantine-dependency, dangling-reference and profile-decoding defects.
- Full private-pack validation remains blocked by 19,572 defect observations:
  missing/stale review and execution evidence, unresolved provenance, field
  coverage and target/sense issues. These are not distinct faulty-record counts.
- This total includes 358 family-supply shortages now propagated by the validation
  entrypoint. A returned `valid=false` family audit also stops package creation.
- Actual v3 simulation offers 358 targets but supplies no qualified question
  families; positive minimums and shortages remain visible.
- Current triage audit reproduces output bytes with fresh dataset/review/profile
  bindings. It does not sign for the owner.

Details: `content/reports/CONTENT-QUALITY-VERIFICATION.md`,
`content/reports/PROVENANCE-REPAIR.md`,
`content/reports/REVIEW-RECONCILIATION.md`, and
`content/reports/CURRENT-TRIAGE.md`.
