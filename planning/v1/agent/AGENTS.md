# 此專案的 Agent 實作規則

本檔是專案專用規則範本。與既有 AGENTS.md 合併，不覆蓋使用者其他通用開發規則。

## 怎麼讀規劃文件

- 每件事只有一個唯一來源（見 `planning/v1/PLAN.md` 的表）。其他地方只放指向，不重複內容；發現不一致時以唯一來源為準，並回報。
- docs 01–06 寫的是**要達成什麼**與驗收，必須遵守；**怎麼做由你決定**，並在 decision note 記錄理由。
- `docs/08`「可參考的做法」與 `policy-v1.json` 的 `reference_starting_points` 是參考，不是要求；可以採用、修改或替換。
- `policy-v1.json` 的 `product` 是產品規則，必須遵守。所有數值（含你自己選的）都要能不改程式碼就調整，因為 beta 後會校準；改值要版本化，並跑回歸測試和受影響事件的 replay。
- 寫成「為什麼」、引用 [Sxx] 的段落是背景，完整理由在 `docs/08`。
- 只讀當前 milestone 需要的文件（下表），不要提前實作後面階段的內容。

| Milestone | 必讀 | 需要時再查 |
|---|---|---|
| M0 | `PLAN.md`、`agent/START-M0.md`、`docs/02`、tasks.json 的 M0 | — |
| M1 | `docs/05`、`docs/03` §2–§6、`contracts/sources.json` | `docs/08` |
| M2 | `docs/01`、`docs/02`、`docs/06` §2 與 §6 | `docs/03` §6 |
| M3 | `docs/03`、`docs/01` §5–§7、`contracts/policy-v1.json` 的 `product`、`docs/06` §2–§5（**T035 小型工程與內容 QA**） | `docs/05` 的題目來源與審查要求、`docs/08` 可參考的做法 |
| M4 | `docs/04`（含 §9 模擬驗收門檻）、`docs/03` §6、`docs/01` §4–6、`contracts/policy-v1.json` 的 `product` | `docs/08` 可參考的做法 |
| M5 | `docs/05`、`docs/06`、`docs/01` R03／R16、`docs/privacy-data-collection.md` 的單次內容回報邊界 | 前面各階段的文件 |
| M6 | `docs/06` §5–§8、`docs/privacy-data-collection.md` | `docs/08` |

每個 milestone 的任務與驗收條件一律以 `contracts/tasks.json` 為準。`optional_for_v1: true` 的 T029–T031 是有測試者時才執行的自願真人研究任務；未執行時標記為**延後／未驗證**，不把它們當正式 V1 發布依賴，也不能宣稱已證明真人學習效果。

## 範圍
- 專案品牌與 App 顯示名稱為 `lexvane`；新建 Xcode 專案／Target 使用 `Lexvane`、Swift App 入口使用 `LexvaneApp` 命名。勿再使用過去的暫用名稱或專案舊名稱。
- iOS-first、完全離線核心。不要自行新增登入、OCR、照片解析、runtime LLM、廣告或付費。研究用 backend 只有在對應 milestone 明確要求時才可加入，且必須遵守 `docs/privacy-data-collection.md`，不能變成 user-level telemetry。
- 日常由系統排程，不能用「選 deck / 選模式 / 自評熟悉度」繞過需求。
- 學生表現是最終目的：有考試時尊重完整指定範圍、期限與每日時間，優先看未見語境選詞能力；無期限時重視長期有用性。不要為了固定 retention、完成打卡或清空 backlog 機械地加工作業。
- 未加入詞的查詢不會自動 enrollment，大小寫永不扣分。
- 只實作被指定的 milestone；完成後報驗收，不順手展開全部後續系統。**M3 的 T035 在 T017、T012、T007 完成後即可執行自動化與內容 QA，不需真人參與**；T025 的大量擴充須先處理 T035 發現的重大錯題、資料或內容問題。**T029–T031 真人 beta 與教學成效比較為可延後事項，不能要求開發者現在招募測試者才允許繼續開發或發布。**

## 架構
- 學習排程、評分與 planner 的核心邏輯不 import SwiftUI、UIKit、CloudKit 或資料庫套件；具體 module 形式由實作決定。
- 資料存取與核心邏輯分離（形式由實作決定）；一般函式注入 clock/calendar/seed，不隱藏讀取 Date.now。
- 保存原始答案／曝光、主要義項與能力、內容必要快照及版本，衍生 FSRS grade／mastery 可更換 adapter 再 replay；答案交易原子且 idempotent。不同義項／拼字不因未測到就連帶升級，沒有獨立回答也不能因沒有錯誤就當作會。
- 不用供應商 sense IDs 當專案主鍵；不可在內容升版時重建所有 ID。
- schema/migrations、lockfile、Xcode project 由當前整合者單一負責，子 agent 不併發修改同一份。
- 建立必要接口即可，不製造尚無需求的 ServiceLocator、插件框架或雙向同步層。

## 研究與參數
- 採用任何記憶模型或第三方實作時，先核對版本、參數數量與 license，不憑記憶猜 API。
- 不把答得快、查字、單次選擇答對直接等同掌握；也不要要求非書寫考試的所有內容通過中英互譯／精確拼字。
- 義項與作答方式需要能力證據隔離，但不必每個維度都建一份獨立、永久的複習義務；同一題不重複計成多次獨立成功。優先度先採有來源的粗分級，不先做完整考古題出題機率模型。
- 無法可靠評分的題目標 unscorable/quarantined，不扣學生分數；未取得獨立作答的項目仍可能是待確認的風險，不以有效答題子樣本的正確率冒充全範圍掌握。
- V1 **不做作答前解題提示**，但每次完成題目必須有正解／當題義項與必要錯因的回饋。FSRS-6 是初始可驗證 adapter；動態目標 retention／持續重新擬合參數須證明有益才預設，資料不足可保留簡單版。
- 不默默改教學效果定義來讓 forecast 看起來可行；沒有學滿設定時間不代表答錯或能力不足。時間是預計安排量，不能強制截題、暗中修改使用者的預算；長期投入不足提醒即使無考試也需適度觸發。

## 工具與驗證
- iOS build/test 以 Xcode 結果為準；可用 Xcode MCP，CLI 作 fallback。
- LSP 幫助導覽與局部診斷，不把它當完整 Xcode target build。
- 跑 coherent change 的 focused tests；跨共用邏輯/資料 migration 再跑相關整合測試。
- 超時是未知，不是通過；缺 Xcode/授權/真機不能寫成已驗證。
- 收到 API 或 symbol 不確定時查官方文件/依賴源碼，再修改。
- 保留既有 OpenCode + OMO 配置，新增 MCP 只 merge 對應欄位。
- 不上傳 raw/private user learning data、不建立個人研究 profile；跨使用者研究只能在明確 opt-in 下依 `docs/privacy-data-collection.md` 取得群體 aggregate。**使用者單次主動回報缺詞／錯題是不同的有限內容報告通道**，不得與研究同意混用，也不可默默附整份詞表或作答歷史。
- 不接受付費合約、不修改正式簽名團隊，除非取得明確授權。

## 內容
- 素材有 source/license/derivation/review lineage；pending 權利不視為已批准。
- AI 審核通過不是法律授權，也不是答案絕對正確。正式 V1 必須以鎖定版本的大考中心官方詞表逐項達成可學 coverage 與授權 gate；不能只計 headword 總數。對於曾教錯的內容，要能向受影響學生提供更正，而非只排除舊 Good。
- 資料表由實作依 docs/02 的資料需求自行設計，並補真實回歸測試。

## 每次交付
報告完成的任務 ID、修改檔案、實際執行與未執行的驗證、政策/資料版本、限制和下一個可實作任務。
