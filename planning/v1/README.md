# lexvane｜開發計畫 v1

狀態：**V1.6 規格基線，可開始 M0**。這是規格、資料契約與任務包，不是已完成的 App 或詞庫。正式 V1 至少完整涵蓋鎖定版本的大考中心高中英文參考詞表；M3 最小學習循環後用 T035 做**不需招募真人的工程與內容品質檢查**，再擴充內容。**Beta（可選）不建缺詞回報／研究聚合伺服器；正式 V1 才經 T033、T036、T037 發布後端。** 真人學習效果研究可延後，但不得未經驗證宣稱更有效。

這些文件主要給 agent 讀。閱讀順序：

1. `agent/AGENTS.md`：工作規則，以及每個 milestone 要讀哪些文件。
2. `PLAN.md`：產品目標、核心規則、文件索引。
3. 當前 milestone 的 `agent/START-*.md`（目前是 `START-M0.md`）與 `contracts/tasks.json` 中該 milestone 的任務。

`agent/AGENTS.md` 要合併進專案既有的規則，不直接覆蓋。產品與 App 顯示名稱統一為 `lexvane`；新建 Xcode 專案與 Target 使用 `Lexvane`，Swift 型別依命名慣例使用 `LexvaneApp`。
