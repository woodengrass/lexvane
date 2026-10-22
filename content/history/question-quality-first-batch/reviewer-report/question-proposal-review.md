# Independent re-review: corrected three proposals

Reviewed 2026-10-23. This replaces the previous proposal judgments.

- Author session: `ses_e9bb16cadffeuVCQNDBplNY1xX`.
- Actual evaluator session: `ses_e9bc60208ffegwAOliKMGqzTpX` (different from author).
- Input only: `.omo/drafts/question-quality-replacements.json`; no code or bank sweep.
- Exact input-file SHA256: `d1c11da4ba9780688dbd405b26e814d3f1dbafac844db6ec92f46343e6f58c8c`.
- Per-proposal SHA256 below hashes the entire proposal object, including editorial
  note and original binding, serialized with Python
  `json.dumps(p, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")`,
  with no trailing newline. Array order is preserved. These are **proposal
  digests**, not future sealed question `content_sha256` values.

**Current decisions: 3 APPROVE / 0 REJECT for linguistic proposal suitability.**
No proposal is thereby approved for serving, release, or qualified family supply.
No live content, assessments, or provenance were edited.

## 1. hospital — APPROVE

Question: `lx:question:a951d963-098c-46fe-a63c-04e5b56e8b3a`  
Proposal SHA256: `e54cfa3883057e80ebfe91a60dc51158cdb2b553fdb79e376172f70892c08e2f`

**Unique answer: PASS.** `option-a` / `hospital` is the single best completion in
ordinary beginner English. The decisive evidence is “an emergency department and
full inpatient wards” together with three nights after a major operation—not
building size alone. This supplies the hospital-level service distinction missing
from the previous version. Broad institutional names or specialist uses of
“clinic” are not equivalent ordinary completions of this full description.

**Per-distractor plausibility: PASS.** All three fit `stayed in the ___`
syntactically and belong to a confusable health-facility vocabulary set:

- `option-b` / `clinic`: credible confusion with a treatment facility; ordinary
  outpatient clinic does not fit the combined emergency-department/full-ward
  description. The corrected rationale explicitly limits its claim to this
  ordinary sense instead of claiming no clinic can ever admit a patient.
- `option-c` / `pharmacy`: credible medical-place confusion; dispensing medicines
  is not the described postoperative inpatient/emergency service.
- `option-d` / `laboratory`: credible testing-facility confusion; laboratory work
  is not the ward-based accommodation described here.

**No leakage: PASS.** The stem neither spells `hospital` nor embeds it in a
compound. Medical-service clues test meaning rather than reveal the answer's
letters. Feedback follows the answer and matches the supplied distinguishing
context. “Full inpatient wards” is slightly less idiomatic than “inpatient wards,”
but remains understandable and is not a blocking defect.

Evidence inspected: `proposals[0].stem`, all four `options`, `accepted_answers`,
each `distractor_rationales` entry, and `post_answer_feedback`. Approval applies
only to the exact digest above and the ordinary lexical interpretation stated.

## 2. fire — APPROVE

Question: `lx:question:2ade7b81-9020-42bd-80f9-5d4a2e4b3296`  
Proposal SHA256: `b6f3f4a9e72b822164f3743ffc317729e1e3c8e0412c2ff07b76b6b2d1876d6d`

**Unique answer: PASS.** `option-a` / `fire` identifies the exposed wood combustion:
“piled dry wood inside a circle of stones outdoors” and “flames rose from the
burning wood.” `gathered around the ___` naturally permits all four nouns, so a
verb-selection mismatch does not give away the key.

**Per-distractor plausibility: PASS.** These are related light/heat sources:

- `option-b` / `candle`: campers might gather around its light, but its wax/wick
  combustion is not the depicted stone-ring pile of burning dry wood.
- `option-c` / `lamp`: plausible campsite illumination; a lamp is a lighting
  device, not the described open wood combustion. The correction does not claim
  that all lamps are flameless.
- `option-d` / `heater`: plausible warmth source on a cold night; the text
  depicts open burning wood rather than a heating appliance. The corrected
  rationale no longer wrongly limits heaters to electricity or gas.

**No leakage: PASS.** `fireplace` has been removed; neither `fire` nor a compound
containing it appears in the stem. Flames, wood and heat are legitimate semantic
evidence. The feedback now distinguishes the particular depicted event rather
than making universal claims that other light/heat sources cannot burn.

Evidence inspected: `proposals[1].stem`, all four `options`, `accepted_answers`,
each corrected `distractor_rationales` entry, and `post_answer_feedback`. These
changes address the prior review's explanation defects; no additional condition
on the linguistic approval is outstanding.

## 3. night — APPROVE (unchanged)

Question: `lx:question:46a35e8b-d76b-46e8-b899-45b30fd9534d`  
Proposal SHA256: `1d477b9c7f8c94f8b228e2d09b8ed92c656c255172c82f50a6479c3ba3d7cf92`

**Unique answer: PASS.** `option-c` / `night` is the single best completion of
“work through the ___” for the explicit `12 a.m.`–`5 a.m.` interval while still
dark. It names the relevant time-of-day sense, not a full twenty-four-hour day.

**Per-distractor plausibility: PASS.** All are parallel time-of-day expressions:

- `option-a` / `daytime`: a plausible work-period label in isolation, excluded by
  the specified overnight hours and darkness.
- `option-b` / `evening`: a close dark-hours confusion, excluded by the midnight-
  to-five interval, **not darkness alone**; evenings can also be dark.
- `option-d` / `afternoon`: a plausible bakery work period in isolation, excluded
  by the explicit a.m. interval.

**No leakage: PASS.** The stem contains neither `night` nor `midnight`.
“Still dark” is a meaning clue, not an embedded answer. Clock notation adds a
modest reading demand but does not introduce an alternative correct option.
The learner-facing rationale and feedback correctly use the clock interval.
The editorial note still overstates darkness as excluding evening; do not reuse
that assertion as review evidence. It is not a learner-facing item defect here.

Evidence inspected: `proposals[2].stem`, all four `options`, `accepted_answers`,
each `distractor_rationales` entry, `post_answer_feedback`, and `editorial_reason`.

## Integration boundary

The exact proposal digests permit parent to identify these reviewed texts when
integrating them. They do **not** transfer an assessment to an unknown future
revision/hash. Parent must seal each integrated candidate, verify that the
reviewed learner-facing content is unchanged, and obtain/record the new current
revision/hash-bound evaluation through the existing workflow. Current review,
all v3 quality gates, source/provenance requirements, family/teaching-independence
evidence and release/human-review gates still apply. Four options alone is not
quality; these three linguistic approvals do not qualify the remaining bank.
