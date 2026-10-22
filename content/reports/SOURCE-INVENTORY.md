# 官方學測英文來源盤點 — 固定截止 2026-10-11

**狀態：partial / blocked，不能宣稱 task 3 complete。** 一般年度試題與選擇題答案的 111–115 索引連結已找到，但 111 特殊英文試題、更正公告判定及原檔核驗仍有未解項。`found` 僅表示官方索引觀察到附件 href，不表示下載成功、內容可靠、授權通過或可進包。

## 固定 corpus 與證據

- 年度分母固定為 **111–115**：一般試題官方索引最新年度為 115；第 4 頁仍含 111 英文，第 5 頁已低於 111，第 19 頁為歷年尾端。115 列公布日期為民國 115-02-23。
- `discovery.json` 記錄 `cutoff_date`、各索引 `retrieved_at`、metadata projection SHA-256、href 全集與排除理由。日期固定，不由 CLI 的即時時鐘擴張。
- 116 行事曆／簡章／通用說明不等於 116 英文年度試題。這次英文考試說明索引仍列 111–114 與 115 適用版；未另找到 116 英文專屬版本，不能因而宣稱「未出版」。後續新公布資料須另建版本。
- 網路回執：`.omo/evidence/m1-content-pilot/a1-task3/task-3-pages.jsonl`。保留原 discovery 與修正回執以追溯轉錄錯誤，合併採修正後的實際 href。
- Task3-repair 合併產物為 **106 rows（102 found、4 not_found_after_search）、46 active metadata snapshots、1092 個 href 排除理由**。其中 44 是官方 HTML 頁面回執，2 是官方 PDF 的搜尋結果 metadata 回執，明示沒有直接 fetch PDF；不能把搜尋結果當原檔核驗。原先 103 rows／37 snapshots 的基線雜湊在 repair.log，被重新抓取頁的舊 snapshots 保留於 discovery.prior_snapshots；原回執不覆寫。
- 修正回執有 worker 填寫的未來時間（15:00 或四捨五入超過 session 完成時間）。原回執留存，合併使用記錄的 session 完成時間作 **fetch upper bound** 並記 `timestamp_basis`，不冒充精確逐頁抓取時間。
- **hash 是 URL、title、hrefs、retrieved_at 的 metadata projection，不是完整 HTML 或 PDF bytes 的 hash。** 原卷、全文、PDF/DOCX/ZIP/BRL 皆未下載或存入本 repo；`content_sha256=null`，題號與原頁數可靠性旗標均為 false。

入口：

| 類別 | 官方入口 |
|---|---|
| 高中英文參考詞彙表 | https://www.ceec.edu.tw/xmdoc?xsmsid=0K213553204833715309 |
| 一般試題 | https://www.ceec.edu.tw/xmfile?xsmsid=0J052424829869345634 |
| 特殊試題（由官方導航發現） | https://www.ceec.edu.tw/xmfile?xsmsid=0J052392083839398563 |
| 特殊答題卷 | https://www.ceec.edu.tw/xmfile?xsmsid=0M111357021798465239 |
| 考試說明 | https://www.ceec.edu.tw/xmdoc?xsmsid=0J018585845010094026 |
| 參考試卷 | https://www.ceec.edu.tw/xmdoc?xsmsid=0J018586101460336585 |

## 每年度 kind / variant

以下日期為索引的民國年月日；不是據檔名推測發布時間。完整 URL、revision、index_ref 在 `content/sources/inventory.jsonl`。

| 年度 | 一般英文（索引页／公布日） | 試題 | 官方答案 | 一般答題卷／非選評分 | 特殊英文附件 | 特殊答題卷 |
|---|---|---|---|---|---|---|
| 111 | p4／111-02-23 | PDF、DOCX found | 選擇題答案 PDF found | 答題卷 PDF、非選評分 PDF found | `not_found_after_search`，替代來源待查 | 五版 found；111-04-22、p3 |
| 112 | p3／112-02-20 | PDF、DOCX found | 選擇題答案 PDF found | 答題卷 PDF、非選評分 PDF found | 文字／圖文 ZIP、各音軌對照 PDF、NVDA DOC：五件 | 五版 found；112-02-22、p2 |
| 113 | p2／113-02-23 | PDF、DOCX found | 選擇題答案 PDF found | 答題卷 PDF、非選評分 PDF found | 文字 ZIP、音軌對照 PDF、NVDA DOC：三件 | 五版 found；113-01-26、p2 |
| 114 | p1／114-02-26 | PDF、DOCX found | 選擇題答案 PDF found | 答題卷 PDF、非選評分 PDF found | 文字／點字 ZIP、各音軌對照 PDF、NVDA DOC：五件 | 五版 found；114-01-22、p2 |
| 115 | p1／115-02-23 | PDF、DOCX found | 選擇題答案 PDF found | 答題卷 PDF、非選評分 PDF found | 文字／圖文 ZIP、各音軌對照 PDF、NVDA DOC：五件 | 五版 found；115-01-19、p1 |

特殊答題卷五版：A4 選項劃記、A3 放大選項劃記、A4 選項自填、A3 放大選項自填、一般電腦作答。**答題卷不能滿足 answer_key；音軌對照表也不是原卷本文。** 不同 variant 不因同一年度被合併。

一般類共 25 個附件 href；特殊年度附件 18 個；特殊答題卷 25 個。特殊頁某版沒有 href 僅表示該索引未列，不代表該版從未出版。111 缺件保留具體 search_evidence，不填合成原卷。

## 非年度資料：publication 與 effective 分離

| 資料 | 官方索引證據 | 適用／版本 |
|---|---|---|
| 詞表 | 單一列 109-07-31；另在說明頁有同名連結 | 111 起適用，非每年一份詞表 |
| 英文考試說明舊版 | sid=`0J270516560005218952`，標示 109.07.31 更新 | effective 111–114 |
| 英文考試說明新版 | 同頁標示 113.07.29 更新 | effective 115 起，舊版保留；適用版本接續不等於年度試題 |
| 111 一般參考卷 | sid=`0J344403835063802563`，109-01-22 發布 | 六件：說明、試卷、A3 答題卷、A4 答題卷、答案／評分原則、解析 |
| 111 特殊參考卷 | sid=`0K269547065945170388`，109-09-30 發布 | 八件：說明／文字／圖文／點字／答案／解析 ZIP，BRL，NVDA DOC |
| 115 英文參考卷 | sid=`0O211573150658099894`，113-07-29 發布 | 七件：說明新版、參考說明、試卷、A3、A4、答案及評分原則、解析 |

111 參考卷公告標題明載 **111-09-26 答題卷作答說明文字更新**。A3「正式考試版」、A4「校園列印版」依官方表頭辨識，不只依檔名。修訂事件記於各答題卷 revision；未觀察到舊版 href／bytes，不虛構 predecessor 檔案。這是答題卷修訂，不是選擇題答案更正。

## 去重、排除與權利

- 詞表 `file_pool/0k213571061045122620` 與 `0K213612821879129835`：同顯示標題，不同 URL，**suspected duplicate / hash pending**。`duplicate_of` 保持 null。
- 115 說明 `0P091472305863258925` 與參考卷頁的 `0O211559263171214197`：同樣待合法取得 bytes 比對；不同連結仍保留 metadata 列，不自行當新 edition 或已證實 duplicate。
- task 2 registry 的 S01 引用第三個 pool `0K213635079130230766`，不是本次 live 詞表索引的兩個 pool。這是待核對 locator，不改 registry、不將其 bytes identity 認定相同。S02 的 pool 與 live 115 說明索引一致。
- 每個已保存索引的附件 href 應有 inventory row 或 `discovery.exclusions[href]` 的具體理由。修正後 111 一般參考頁為 48 個 unique href（英文 6）、特殊參考頁 89 個（英文 8）、說明 detail 頁 22 個（英文／詞表 3）。同 href 被多表列引用只算 unique href，出現位置留在 receipt。
- 非英文科目、英聽、分科、指考、pre-111 舊適用文件、網站商標／導航附件均排除；補教、個資、佳作／作文範本不納入固定 corpus，也未抓取全文。
- `reference/fetch/retain/extract/adapt/local_analysis/private_pack/distribution` 全部 pending；與 task 2 vocabulary 一致。已唯讀觀察 S01/S02 的全部狀態為 pending，未將 citation 當成授權。其餘每個附件仍需 task 2 按來源／operation 分別 gate。
- metadata found 不授權 fetch、parse、retain、adapt 或 package；第三方 passage 的權利更不能由官方索引存在推得。此 inventory 不可當任何來源進 `content/builds` 的許可證。

## Task3-repair：五個 gap 的逐列處理（仍有三個必要缺件）

固定 cutoff 仍是 **2026-10-11／115 年度**。本次所有新抓取皆保留實際 `retrieved_at=2026-10-11…`；沒有延伸 corpus。證據目錄：`.omo/evidence/m1-content-pilot/a1-task3-repair/`，`pages.jsonl` 保存 anchor href、顯示文字、必要短摘錄及日期，不保留完整 HTML 或原檔。

| 原 gap | 逐列結果 | 官方證據與不能閉合原因 |
|---|---|---|
| (a) 111 特殊英文替代來源 | `sp-paper-en-111-MISSING`：`not_found_after_search-with-search-evidence`；仍阻擋 | CEEC 導航連至特殊試題索引；重新抓取 p3／p4 未見 111 英文附件。[官方站內搜尋](https://www.ceec.edu.tw/sitesearch?sq=111%20%E8%8B%B1%E6%96%87%20%E7%89%B9%E6%AE%8A%E8%A9%A6%E9%A1%8C) 顯示「約有 0 項符合」。CEEC 另連結華文視障圖書網站且明示視障者資格限制；不繞過資格或把外站入口當已找到年度原卷。未找到官方 alternate locator，不能宣稱未出版。 |
| (b) 111／113／114 更正判定 | `reply-en-111/113/114`：每年 `searched-no-correction-found-verdict-unknown`，status 仍為 `not_found_after_search`；仍阻擋 | [考試訊息](https://www.ceec.edu.tw/xmdoc?xsmsid=0I363352927974766861)、[新聞稿/公告](https://www.ceec.edu.tw/xmdoc?xsmsid=0I363338985390931117) 全三頁，以及逐年「學測英文 更正」官方 sitesearch 均保存回執。當前公告清單沒有相應英文回覆頁；每列 search_evidence 指向實際抓取頁。現行索引與搜尋缺席無法證明歷史上無更正。 |
| (c) 112／115 reply revision | `reply-en-112/115`：PDF `found-with-row`，HTML verdict `not_found_after_search-with-search-evidence`；仍阻擋 | 已知 CEEC PDF locator 保留；官方考試訊息／公告與「112學測／115學測 反映意見回覆」sitesearch 未找回載有「原答案維持」的 HTML metadata 頁。115 的第三方短網址線索只返回現行考試訊息清單，不能當官方判定。PDF fetch／retain／extract 權利 pending；未讀 PDF、不由個別題目搜尋摘要推論整卷答案維持，`revision=verdict_unverified` 與空 supersedes 保持。 |
| (d) 三個 HTML details | **閉合**：原三列加 detail_evidence，另有 `notice-direction-111-pdf`、`notice-rubric-113-pdf`、`explanation-paper-112-pdf` | 111 命題方向 detail：131 unique anchor href、命題方向 PDF 與相關影音；113 rubric detail：136 href、七科 PDF 中英文独立 rubric row，其餘科排除；112 explanation detail：132 href、正文一個英文原卷 hyperlink 單獨登記，內嵌圖片不是 attachment href、未抓取。非選評分不是選擇題 answer_key。 |
| (e) 年度 shared chrome href | **閉合**：所有先前抓取過的 19 個年度 xmfile 頁重新抓取，full anchor href 分母合併；各 href 有 row 或具體 exclusions | 一般 p1–p5／p19、特殊試題 p1–p10、特殊答題卷 p1–p3。新 chrome 附件為英聽 FAQ／資安政策／商標，均排除；尾端 pre-111 附件亦列理由。`denominator-diff.log` 保存差異。一般 p6–p18 仍依已證明的 pre-111 年序邊界略過，沒有冒稱逐頁抓取。 |

本次 **沒有官方 not_published 證明，零列改為 not_published**。没有 verified correction/supersede chain 的官方判定，因此不新增猜測鏈；答題卷既有修訂事件與答案更正分開。原卷題號、頁數、byte-hash 與 suspected duplicates 仍未核驗，所有 106 列八項權利全 pending。這些限制不是透過移除 necessary_gaps 來掩蓋；Task3／Task4 仍 blocked。

## 核驗與交接

命令（從 repo root；`CK` 只是下列 `swift run` 的縮寫）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path tools/ContentKit --filter InventoryTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run --package-path tools/ContentKit contentkit sources audit-inventory \
  --inventory content/sources/inventory.jsonl \
  --discovery content/sources/discovery.json --from 111 \
   --evidence .omo/evidence/m1-content-pilot/a1-task3-repair/task-3-repair-inventory.json
```

`audit-inventory` 對必要缺件／open necessary_gaps 回傳 typed reason 與 exit 65；即使一般年度配對已齊，也不能輸出 complete=true。反例測試涵蓋 missing-year、unsupported-unpublished、116 specification≠future paper、answer sheet≠answer key、older-publication-effective111、same-bytes-multiple-links、correction chain/cycle、每 href denominator 與真實 subprocess 拒絕／輸入不變。

證據位於 `.omo/evidence/m1-content-pilot/a1-task3/`：RED、happy/failure logs、網路 metadata receipts、離線 audit JSON。後續任務不得把本報告的 partial inventory 當「官方全集已完整核驗」，也不得跳過 task 2 的 rights gate。

原 Task3 核驗：InventoryTests **12/12**、ToolingSmokeTests **4/4**，Swift build 通過；當時 corpus audit **exit 65／complete=false／5 個 necessary_gap**。本次 repair 的實際測試與 audit 結果記在 repair 證據與下方補記，不混用舊結果。

**Task3-repair 實際核驗（2026-10-11）**：InventoryTests **12/12、exit 0**；完整 Swift package **27/27、exit 0**，build 通過；JSON／JSONL、全 pending permission maps、cutoff 與新回執 metadata hash 檢查 **exit 0**。實際 audit **exit 65／complete=false／3 個 necessary_gap**，沒有其他 typed issues；證據為 `a1-task3-repair/task-3-repair-inventory.json`。未改 Swift audit／commands／tests，因此沒有以放寬邏輯換取 complete。附帶 metadata 工具 `.mjs` 的 LSP 初始化因 workspace 沒有 TypeScript 安裝而不可用，沒有冒稱 diagnostics clean，也未安裝依賴或改設定。

LSP：builtin `lsp_diagnostics` 對 production Swift／metadata merge 零 errors，對 InventoryTests 因既有 hosted-package context 限制報 `No such module 'XCTest'`。重用 task 2 的既有 SourceKit-LSP protocol harness、指定真正 SwiftPM root 後，**四個受改動 package Swift files 全部零 diagnostics／零 errors**（`task-3-lsp.log`，exit 0）。沒有隱藏 diagnostics、條件編譯掩蓋或全域 LSP 設定變動。
