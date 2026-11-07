# Owner decisions 2026-11-07

The owner gave these two decisions in a Claude Code session on 2026-11-07
and asked for them to be recorded ("12都同意先幫我放行記錄下來等app做出來以後再處裡").
They are product-owner decisions, not legal opinions and not grants from any
third party. They cover **private preview only**. Nothing here makes anything
release-eligible.

## D1. Private preview: the owner alone approves

For private preview, the human gate is met when the owner approves an item
personally. No second human reviewer is required.

- Applies to content that ships only in private-preview packs installed on the
  owner's own devices (`build_mode` private-preview, `release_eligible=false`).
- Machine gates are unchanged: schema, sealing, identity, provenance, the v3
  question-eligibility evaluator and family audits all still apply. The
  independent semantic assessment that v3 requires is AI reviewer evidence
  from a session other than the author's. It is separate from owner approval
  and still required by the tools.
- The strict gates come back before any Beta, TestFlight or App Store build.
  Before distribution, `content/policies/pilot-quality-v3.json` (or its
  successor) and the full review protocol in
  `content/reviews/REVIEW-INSTRUCTIONS.md` apply in full.
- Owner approvals are recorded per item, bound to `record_id`, `revision` and
  `content_sha256`. A changed revision needs approval again.
- Generating a review packet is never approval. Only the owner's reply is.

## D2. Rights: private development packs may proceed; the 大考中心 inquiry waits for the app

- S01 (大考中心 高中英文參考詞彙表) `private_pack` is now **allowed**, for packs
  installed on the owner's own devices during development. Recorded in
  `content/sources/registry.jsonl` and `content/sources/licenses/S01.md`.
- `distribution` stays **pending**. TestFlight, any Beta channel and the App
  Store all count as distribution.
- The inquiry to 大考中心 (whether the app may build on the wordlist, and the
  terms and cost) is **deferred until the app works end to end**. It must be
  answered before any distribution. The recorded cover conditions mention
  written authorization for for-profit use, which matters for a future paid
  plan.
- In practice this changes little today: every pilot record cites S01 with
  the `reference` operation only (16,549 of 16,549 citations), and
  `reference` has been allowed since 2026-10-22. No S01 bytes enter any pack.

## What was done on the same day

- 20-word slice defined: `content/pilot/slice-20.json`.
- 40 independent semantic assessments (37 pass, 3 fail):
  `content/policies/question-assessments-slice20.json`, appended to
  `content/policies/pilot-quality-v3.json`, with the report in
  `content/history/question-assessments-slice20/ASSESSMENT.md`.
- Owner review packet: `content/reviews/slice-20/OWNER-REVIEW.md`, with
  unapplied replacement proposals for the 3 failed questions in
  `content/reviews/slice-20/proposals.json`.
- Pass-rate analysis: `content/reports/PASS-RATE-ANALYSIS.md`.
- Authoring rules v2: `content/prompts/v2/`.

## Deferred to the owner (in order)

1. Run the checks on a Mac (this session had no Swift toolchain). The
   commands are in `content/docs/CURRENT-QUALITY.md`, "2026-11-07 update".
2. Review `content/reviews/slice-20/OWNER-REVIEW.md` and reply.
3. After the app works end to end: send the 大考中心 inquiry.
