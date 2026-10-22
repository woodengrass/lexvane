# Whole-bank question eligibility (opt-in v3)

Run from the repository root:

```sh
swift run --package-path tools/QuestionQualityAudit QuestionQualityAudit \
  --datasets content/records/pilot-230/merged \
  --reviews content/reviews/pilot-230-current \
  --profile content/policies/pilot-quality-v3.json \
  --out content/reports/question-quality-current.json
```

Multiple dataset/review directories can be comma-separated. Use the current
merged bank, not history-writing-exclusion. The helper overlays revisions by
kind/ID, rejects conflicting same-revision hashes, and evaluates every current
question (including writing, which remains denied). It does not mutate content.
No missing v1/v2 historical directory is required. Inputs are hashed, output is
sorted, and no timestamps or absolute paths enter the manifest. Per-item entries
contain revision/hash, state and missing work. `needs_author` and `needs_review`
overlap; they are not additive. The option histogram is inventory, not a quality
score. Candidate status is retained. Eligibility is editorial usability, never
source authorization, human acceptance, pedagogical efficacy or release approval.

The shipped v3 policy contains three independently reviewed, revision-bound
linguistic assessments. These do not substitute for full current review or
family qualification. Author rationales and legacy checklist passes are not
independent semantic assessment.
Each new `question_eligibility.assessments` entry must contain:

- `question_id`, `revision`, `content_sha256` matching the current sealed question;
- distinct, nonblank `author_session` and `evaluator_session`;
- `distractors`: exactly one `{option_id, plausibility}` per incorrect option;
- `unique_answer` and `no_leakage`;
- for binary **train** only, `binary_contrast` explaining why two-way contrast
  is the intended exercise rather than an under-authored MCQ.

Each semantic facet is `{passed: Bool, reason: String, evidence: [String]}`.
Reasons must describe the actual decision and evidence must reference inspectable
material. Evidence presence is mechanically checked; its truth remains an
independent review obligation. Never copy these fields from an author rationale
or manufacture passing entries to increase supply. Conflicting current negative
assessments block; stale assessments cannot qualify a revision. Current sealed
review findings also block, including minor unresolved findings; old review
passes do not transfer to a new revision. A later current pass does not erase a
current negative row. Resolve findings explicitly in the review workflow.

Check requires four distinct nonblank option texts and one accepted key. Train
also defaults to four, with only the reviewed binary-contrast exception. Three
options never serve. A structural defect is rejected even when semantic work is
still missing; this keeps both author and reviewer backlog visible.

Supply and family integration use the same evaluator:

```sh
swift run --package-path tools/ContentKit contentkit families audit \
  --dataset content/records/pilot-230/merged --reviews content/reviews/pilot-230-current \
  --profile content/policies/pilot-quality-v3.json --evidence /tmp/families-v3.json
swift run --package-path tools/ContentKit contentkit supply simulate \
  --dataset content/records/pilot-230/merged --reviews content/reviews/pilot-230-current \
  --profile content/policies/pilot-quality-v3.json \
  --scenario content/policies/pilot-supply-scenarios-v3.json --seed 111 --out /tmp/supply-v3.json
```

Scenario bindings remain only the offered inventory, not evidence of quality.
The v2 scenario remains the historical pilot-50 trial. The v3 scenario covers
358 current non-writing targets and 716 candidate question bindings; these are
offered inventory, not 716 qualified questions.
V3 supply evaluates the entire bank, intersects the offer with eligible items,
and requires current family qualification before counting check stock. Family
qualification still compares all train exposures and teaching, even ineligible
ones, for contamination. Missing or stale family evidence cannot count. Positive
per-ability minimums remain unchanged; zero qualified supply produces shortages.
V3 `audit-profile` refuses self-reported trial counts; use this census and the
family/supply reports instead. V1/v2 behavior remains explicitly legacy when the
successor policy is absent. Nothing in this helper is a release gate override.
