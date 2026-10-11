# 02｜技術方向與資料需求

這份文件描述技術上必須達成的性質，以及目前值得優先考慮的技術。它不是 class diagram、SQL schema 或 package 拆分指令。

## V1 技術方向

V1 是原生 iPhone App，因此優先：

- Swift + SwiftUI + Xcode。
- Swift Concurrency。
- 本地資料庫優先考慮 SQLite；GRDB 是成熟且適合 Swift 的候選。[S11]
- Xcode build/test 是 Apple 平台行為的最終驗證來源。
- OpenCode + OMO 可以作主要 agent 介面；Xcode MCP / CLI 作實際平台驗證。[S13][S14]

最低 iOS 版本、具體 package 切法、dependency 版本、migration framework 等由實作時依目前 Xcode、API 支援與 repo 狀態決定並鎖定，不在 planning 階段硬寫死。

## 架構要達成的結果

### 1. UI 與學習邏輯可以獨立演進

學習排程、評分、planner 不應該只能在某個 SwiftUI View 裡運作。它們需要可測試、可在沒有 UI 的情況下重現結果。

具體要做成 module、package、service 或其他形式，由 agent 根據實際專案決定。

### 2. 詞庫與使用者資料的生命週期分開

詞庫會隨內容版本更新；使用者學習歷史不能因詞庫升級而消失。

推薦思路是把「內容資料」和「使用者資料」在資料責任上分離。是否用兩個 SQLite 檔、同庫不同 schema/表或其他設計，由實作時評估，但必須驗證：

- 詞庫更新不重置學習紀錄。
- 使用者備份不需要複製整個內建詞庫才能恢復，但還原所需的重要已展示題目快照、對應內容版本／映射不可缺漏。
- 內容來源與使用者事件可以分別版本化。

### 3. 身份穩定

word、phrase、sense、learning target 等需要穩定 ID。

不要讓某一家辭典的 sense 編號、顯示順序或翻譯文字本身成為永久 identity。未來換詞庫來源時，應能映射或明確判定內容已改變。

### 4. 原始學習證據要保留

系統未來會更換 mastery / scheduling 模型，因此不能只存一個「熟悉度 87%」。

至少需要保存足以重新分析的重要事件，例如：

- 當時測了什麼 target / question。
- 使用者實際回答（包括未提交／放棄、是否取得獨立答案等可判定的狀態）。
- 題目的主要教學義項／用法、實際測量能力、語境 family 與已曝光資訊；答案是否先顯示或剛看過解析（即使 V1 沒有解題提示 UI）。
- 發生時間與大致耗時。
- 當時內容版本與算法版本。
- 當時排程所用的參數集及**客觀作答轉成模型 grade 的映射版本**，讓歷史決策能被還原；FSRS Good／Again、S／D、mastery 與到期日是衍生資料，不能取代原始回答。

已呈現且影響評分的題目，要保存**還原解讀所必需的不可變快照或具備實際可取得的歷史內容版本**，例如當時的題幹、答案選項、正解、被測目標和必要的內容修訂識別。只存舊題 ID／內容包版本，卻無法取得舊題，不得宣稱備份還原後能完整 replay。備份不必包含整個內建詞庫，應用最小必要歷史材料即可。

哪些事件需要完整保存、哪些可做 compact log，由實作時在可重算性、儲存量與隱私間取捨。對同一題／同一 target，原始 answer、model adapter 結果、目前經壞題撤銷重算的狀態是不同層次。**歷史決策 replay、現在以新證據政策重算、假設換成另一種學習策略的反事實模擬不可互相冒充**。

### 5. 衍生狀態可重建

記憶狀態、mastery、forecast、每日 plan 等最好視為 derived state，而不是唯一真相。

演算法升級時，系統應至少能對重要狀態重新計算或安全遷移。

### 6. 資料安全

必須處理：

- App 被殺掉或中斷時不重複計分、不丟已提交答案。
- migration 失敗不破壞原有學習資料。
- 有明確的備份與還原方法。
- 使用者能刪除自己的學習與查詢資料。
- V1 不暗中上傳學習紀錄。

具體 transaction、WAL、backup API 等做法交由實作 agent依 SQLite/GRDB 官方建議選擇。[S20]

### 7. 跨使用者研究資料不是 user telemetry

完整學習歷史與個人模型留在裝置；研究端只取得群體統計。研究管線與未來的同步完全分離。規則只在 `docs/privacy-data-collection.md`。

## 未來同步的要求

V1 不做同步，但資料模型不要故意讓未來同步變得不可能。

Apple-only 階段可考慮 CloudKit / CKSyncEngine。[S12]  
若未來真的支援 Android/桌面，更合理的方向可能是中立 backend。

現在只需要確保：

- 全域穩定 ID。
- 事件可以去重。
- 明確的更新/刪除語義。
- 使用者資料能被匯出。
- 同一個 target 不因不同裝置產生互相矛盾的多份核心狀態。

不要在 V1 提前建立完整 sync abstraction 或 server protocol，除非實作過程中確實需要。

## 可移植性

未來 Android 不代表現在必須用 Flutter/KMP/Rust。

更有價值的是：

- 資料格式與 ID 不綁死 iOS framework。
- 核心算法行為有測試案例，可以在其他語言重現。
- content pack 可以被其他 client 讀取或轉換。
- 平台專屬 UI 與學習規則的邏輯概念分開。

## 技術決策準則

遇到多個方案時，優先選：

1. 能滿足 V1 實際需求。
2. 容易測試與 debug。
3. 不會把資料鎖在難以遷移的黑箱。
4. 維護成本適合小型專案。
5. 不為尚未存在的 Android、server 或大規模用戶過度設計。

具體 implementation 由 agent 查官方文件、跑小型 prototype 後決定。