# Prompts v2 (2026-11-07)

v1 stays frozen as history. v2 replaces `author.md`, `check-author.md` and
`question-review.md` for all new authoring and revision work; the other v1
prompts (`blind-solve`, `family-review`, `language-review`) are unchanged and
still current.

Why: `content/reports/PASS-RATE-ANALYSIS.md`. In short, v1 asked for "at least
two options" while the v3 policy serves only four-option questions, so 418 of
the 424 rejected multiple-choice questions were rejected for option count
alone. Reading a 40-question, 20-teaching sample also found authoring habits that
pass the gates but hurt learners. v2 adds rules for each.

| Problem seen | v2 rule |
| --- | --- |
| 2 or 3 options (v1 allowed it; v1 examples showed 2) | Exactly four options for every train and check question. |
| Distractors that are unrelated easy words (`law/war/aid`, `map/bet/toy`) | Each distractor fits the sentence grammatically and is credible in that context; a learner must not be able to eliminate it without knowing the target word. |
| Stems padded with exclusion clauses (`nonmilitary`, `not merely`, `rather than preventing it`) | The context must determine the answer naturally. If a distractor needs an exclusion clause to be wrong, replace the distractor. |
| Feedback that talks about other items, teaching examples or reviews ("不是保護環境口號或仙人掌棲地定義") | Feedback is for the learner: why the key fits this sentence, optionally why the most tempting distractor does not. Nothing about other items, examples, revisions or reviewers. |
| Teaching text written for reviewers ("不把與夜晚相對的白天義列為本目標的證據"); 104 of 360 teachings contain such phrases | Teaching explains meaning and usage to the learner; no notes about targets, evidence or separately recorded senses. |
| Stems that gloss the key (`paid position` for job) | Do not put a synonym or definition of the key in the stem. |
| Revision loops that answer a finding by adding defensive text | Fix a finding by changing the content, never by adding explanations aimed at the reviewer. |

Checklist item IDs in `question-review.md` are bound to code
(`ReviewCoverage.checklistIDs`) and are unchanged; v2 only makes the pass
criteria for existing items stricter.
