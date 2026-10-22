# T005 — identity tooling ready; CEEC mapping blocked

**Status: rights_pending / T005 mapping-blocked.** Structural audit success is not authorization, extraction success, official coverage completion, or qualified learning content. No official PDF was downloaded, retained, or parsed for Task4. Official item count and denominator are **unknown**, not zero. The two pending rows describe sources, not invented word items.

## Edition metadata lock

- Cutoff: **2026-10-11**; Task3 observed annual-paper upper bound 115. The three remaining Task3 gaps concern special-paper/corrections, not the wordlist metadata.
- Selected edition label: `ceec-wordlist:109-07-31-published:111-effective`. Publication: **109-07-31 / 2020-07-31**; effective from **111**. This is the single actual wordlist edition discovered before cutoff, not an annually regenerated wordlist.
- Selected inventory row: `content/sources/inventory.jsonl#vocab-111-plus` (line 70 in current inventory).
- Official wordlist index: <https://www.ceec.edu.tw/xmdoc?xsmsid=0K213553204833715309>.
- Selected URL: <https://www.ceec.edu.tw/files/file_pool/1/0k213571061045122620/%e9%ab%98%e4%b8%ad%e8%8b%b1%e6%96%87%e5%8f%83%e8%80%83%e8%a9%9e%e5%bd%99%e8%a1%a8%28111%e5%ad%b8%e5%b9%b4%e5%ba%a6%e8%b5%b7%e9%81%a9%e7%94%a8%29.pdf>.
- Original-byte SHA-256: **null / unavailable**. `content_hash` in the coverage header is reserved for that byte hash; this edition label is metadata, not a verified byte version.
- Parse-rule reservation: `ceec-pdf-layout-unverified-v1`; **blocked, not an executable verified official-layout rule**. Page layout, original-item boundaries, POS/level fields, aliases, duplicates, and full extraction counts cannot be confirmed without lawful bytes. Do not substitute the synthetic fixture rule for this edition.

## Inventory and diff retention

`content/sources/inventory.jsonl#vocab-111-plus-copy-specpage` (line 71) retains the alternate file-pool URL `0K213612821879129835` and its specification-detail index. Its same publication date and displayed effective period are **not** evidence of a newer edition, nor proof of byte equality. `duplicate_of` stays null, and comparison is `pending_authorized_bytes_hash_compare`.

Alternate URL: <https://www.ceec.edu.tw/files/file_pool/1/0K213612821879129835/%E9%AB%98%E4%B8%AD%E8%8B%B1%E6%96%87%E5%8F%83%E8%80%83%E8%A9%9E%E5%BD%99%E8%A1%A8%28111%E5%AD%B8%E5%B9%B4%E5%BA%A6%E8%B5%B7%E9%81%A9%E7%94%A8%29.pdf>.

Registry `S01` cites a third pool, `0K213635079130230766`, with version `111-effective-original-unhashed`; it is not silently equated to either live URL. Keep the original registry and inventory references unchanged. No other actual wordlist edition was found in this inventory; no fictional older version/diff is created. Future lawful comparisons must retain each URL/version/hash, compare bytes first, and then preserve item-level additions/removals/POS/level changes in a separate versioned audit rather than overwriting older identity history.

## Why mapping is blocked, and what unblocks it

`content/sources/licenses/S01.md` and `content/sources/registry.jsonl#S01` leave all operations pending. A visible public locator, planning citation, private-pilot intent, or agent judgment is not a permission grant. No lawful original bytes are supplied. Consequently there are no original-item rows, entry IDs, authored targets, or official totals.

To unblock: the coordinator must record operation-specific authorization with actual evidence for the exact locator/version and relevant ancestors; lawfully obtain and hash the local bytes outside tracked content; confirm whether alternate URLs are identical; review the actual page layout and freeze a versioned local parse-rule JSON. Run the local extractor with explicit `--file`, `--rule`, `--registry`, `--source-id`, and `--evidence`. It performs no network requests or OCR and rejects empty/garbled pages. Any unclassified line produces non-zero exit and a retained manual-review audit, not complete-list success. After every nonblank line is accounted for by reviewed parsing/ignore rules, preserve the complete extraction audit and verify it against every mapping row.

The authorized source registry row must bind `content_sha256` to the exact supplied file before CLI extraction. Each legal original item then receives source version, page/line, original text, POS, level, nullable `entry_id`, status, reason, and evidence references. **Unwritten items use `not_yet_authored`, no entry target and no qualified active target.** Aliases map only to the same canonical entry and never add a headword. The denominator is derived from the locked extraction, never a remembered published total; a truncated map or contradictory denominator fails.

## Coordinator decision: production ledger stays empty

`content/ids/ledger.jsonl` is an intentionally empty append-only issuance log. Pending notes belong in this report/coverage metadata, not malformed identity rows. No fixture identities are issued into production. Synthetic fixtures live only in XCTest temporary directories and are removed by teardown; the local synthetic PDF test is independently authored, not an official-document excerpt.

Coordinator issuance uses an explicit stable request key solely for idempotency and random UUID opaque IDs, independent of text, translation, input order, and vendor identifiers. Text/vendor changes retain ID with a new revision/hash. A changed semantic fingerprint is rejected by revision and requires an explicit split/merge event with predecessor IDs, new independent successor identities, reason and evidence. Old identities/history remain, predecessors become retired, and no learner success state is stored/copied. The caller/coordinator is responsible for truthful semantic fingerprints and for preserving stable request keys across retries.

The ledger stores ordered events linked by canonical event hashes. Audits reject duplicate issuance/revision errors or broken chains. Saved evidence binds file hash, terminal event hash and event count; compare with prior receipts to detect suffix deletion or wholesale rewritten history. A current ledger alone cannot prove that a removed historical suffix never existed. The API serializes appends with a file lock; coordinator-only issuance remains the plan contract.

## Verification entry point

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run --package-path tools/ContentKit contentkit ids audit \
  --ledger content/ids/ledger.jsonl --coverage content/coverage/ceec-map.jsonl \
  --evidence .omo/evidence/m1-content-pilot/a1-task4/task-4-identity.json
```

Expected outcome: exit 0, structurally valid empty ledger and two `source_pending` rows, `mappingBlocked=true`, `denominator=null`, `denominatorState=rights_pending-unknown`, zero authored/qualified targets. This unblocks downstream use of identity mechanics, **not** official mapping, qualified selection, or release gates. Task4 engineering evidence is in `.omo/evidence/m1-content-pilot/a1-task4/`; source inventory completion remains an independent Task3 blocker.
