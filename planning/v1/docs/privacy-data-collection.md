# Privacy-preserving research data collection

狀態：採用中的產品／架構原則  
目的：在不建立任何可讀的單一使用者研究資料庫下，取得足以改善 lexvane 演算法的群體統計。**這是 V1 正式版持續改善演算法的重要交付能力，但不應成為每個學生使用離線 App 的前提。**

## 核心決策

lexvane 採用「方案 A」：

- 完整作答歷史、學過哪些字、個人記憶曲線、個人化參數、精確時間線與 planner 狀態只留在使用者自己的裝置。
- 個人化學習本身完全在本機運作，不需要把個人模型上傳。
- 跨使用者的演算法改進只使用使用者明確同意後產生的研究 contribution。
- contribution 先在裝置上轉成有限、預先定義的統計或模型更新；不傳 raw events。
- 收集鏈路必須讓研究端無法讀取任何單一使用者的 contribution，也不應取得能把 contribution 與來源裝置／IP 長期連結的識別資訊。
- 只有達到最低群體門檻後的 aggregate 才能被研究端讀取。
- App 不因使用者拒絕研究資料分享而限制任何核心功能；撤回同意後停止未來 contribution。
- 不建立 user-level telemetry、research profile、個人雲端 FSRS 參數或「匿名 user ID + 完整歷史」資料庫。

這個原則獨立於未來的同步功能。即使日後加入 CloudKit 或其他跨裝置同步，同步資料也不能被默認拿來做群體研究。

## 為什麼這樣做

目前演算法真正需要的跨使用者資料主要是群體層級資訊，例如：

- population memory model / initial prior。
- 各題型 predicted vs actual 的 calibration。
- 題型耗時分布。
- planner 預估時間與實際時間的群體誤差。
- item / target difficulty 的 aggregate。
- 不同演算法版本的 aggregate outcome。

這些問題不需要研究端知道「哪一個學生做了什麼」。

## V1 最小可用研究貢獻與發布門檻

優先支持**兩類可驗證的群體校準**：① 不同題型、預測記憶率區間與實際無提示延遲作答之間的偏差；② 新字教學、單句／短文、錯誤補救與 Planner 預計時間相對實際活動時間的偏差。由裝置先計算受限、固定格式的統計，聚合後才可研究；只使用能實際協助校準且群體規模足夠的欄位。

初期不以每個單字／義項建立可回推個人的細粒度統計，也不聲稱一般校準 histogram 足以重訓完整 FSRS-6 參數；若將來要改善族群模型參數，須另驗證適用的安全聚合訓練統計與效果。題型效果的因果比較需要受控評估，不能直接把自選使用者的平均答題率差異視為學習策略優劣。

發布階段明確分開：
- **Beta／TestFlight（可選）**：保留本機完整學習證據、候選模型評估與離線統計；**不建缺詞回報接收伺服器，也不傳任何自動研究 contribution**。單次缺詞以使用者自己操作 iOS 分享／郵件或複製文字回報；TestFlight 的回饋是 Apple 提供、由測試者主動提交的反饋，不是 lexvane 匿名研究。
- **正式 V1**：交付獨立 HTTPS 缺詞／錯題回報接收服務（T036）；以及**經明確 opt-in 與正式安全驗收**、採 DAP／VDAF 多方安全聚合及 OHTTP 或等效來源分離的群體研究管線（T033），聚合方須有實際獨立的營運與金鑰管理。兩者屬 T037 正式發布 gate；若未就緒不得以 Beta 的較弱作法取代，也不能宣稱已完成該正式交付。離線核心仍可使用。
- 不把自願發送內容回報、TestFlight 訊息或使用者可讀個別訊息算成匿名群體研究 contribution；任何研究收集必須獨立通過 privacy gate。

個人的持續個人化則相反：它需要完整歷史，因此最適合留在裝置上處理。

## 資料邊界

### 永遠留在裝置上的資料

研究資料收集不應把下列內容傳到 lexvane 的研究基礎設施：

- raw answer / review events。
- 個人學過或查過的完整 word / phrase 清單。
- 個人 FSRS / memory parameters 或完整 memory curve。
- 自訂考試名稱、批次名稱、自由輸入內容。
- 可重建個人使用時間線的精確 timestamp sequence。
- device ID、Apple ID、CloudKit ID、帳號 ID 或穩定 research ID，除非未來某個研究問題真的不可避免且經過新的 privacy review。

### 可以考慮聚合的資料

資料應先在本機轉成研究真正需要的 bounded contribution，例如：

- calibration bins：某預測區間的 correct count / total count。
- 題型層級的 response-time histogram / quantiles contribution。
- planner forecast error 的統計量。
- 某 target 的 aggregate attempts / correct / prediction residual；必須受最低 cohort 門檻保護。
- population optimizer 所需的 aggregate update / sufficient statistics。

具體統計 schema 由要回答的研究問題決定，不為了「以後也許有用」收集額外欄位。

## 統計可信度：安全聚合不能取代研究設計

每一個 V1 metric 在啟用前，必須明確列出：**估計對象**（一次有效作答、一次安裝／裝置貢獻或典型參與者）、統計單位、每單位貢獻上限、納入／略過條件、模型／題型版本、時間批次（epoch）與結果的實際用途。不能把 report 數量直接說成「獨立學生數」，也不能把自願參與者視為全體學生的無偏樣本。

- **重送去重 ≠ 身分防偽**：同一份 report 重傳不能重複計入（可用有時效的一次性 report ID），但可用不同 report IDs 灌入大量資料是另一種 Sybil／濫用問題。需評估有限、不可連結的貢獻資格／配額或等價防護；用於發行資格的識別資訊不得直接綁到聚合 contribution。**無帳號不能保證每人只能一份**，格式／協定有效也不能證明學生真的作答。
- **限制重度使用者偏差**：若目標是「典型學生／安裝實例」，不得把同一來源無限多個作答當無限獨立貢獻；若目標是「平均一次作答」，可採事件加權，但要清楚標註與限制惡意灌量。裝置本機限額與 server 可驗證的限制是不同保證。
- **保護與有效樣本**：門檻應依能合理確認的獨立貢獻單位定義，不能僅以收到 N 次 POST 自稱有 N 人；無法驗證人數時，不得以「獨立使用者門檻已達」作安全保證。若正式版啟用初期資料不足以支持交叉切分，就減少維度或不發布結果，**不因想拿到統計而降低已承諾的隱私保護**。
- **使用選擇偏差**：直接看解析、退出、反覆無獨立作答、缺席及停止使用者，不會自動成為錯誤；群體研究必須記錄足以辨識樣本缺失／參與偏差的受限摘要或明確承認無法推論，不只報留下的成功者。研究結論不得把預測校準改善當成真人學習策略優於對照。
- **部署的獨立性**：正式版的獨立聚合方需要不同實際營運／信任邊界、無法由單一帳號取得兩側金鑰與原始份額；只在同一控制面下部署兩個容器不代表多方不串通假設成立。啟用前需由 threat model 與測試核實。
- **研究方法可撤回**：候選模型可先在本機 shadow mode 比較下一次預測；要比較學習策略是否有效，需自願且合規的受控研究，保留退回已驗證策略及事先定義的評估指標。未成年參與者的實際研究倫理／同意要求依研究計畫查核，不因安全聚合自行豁免。

## 主動回報缺詞／錯題：與群體研究徹底分開

內容回報是使用者**逐次主動提交的可讀文字**，不屬於「研究端只能看到 aggregate」的研究 contribution，也**不沿用**研究資料 opt-in。App 先顯示單一英文項目（或使用者選擇回報的錯題必要資訊）與內容包／題目版本供確認；不能默默附整份考試清單、個人歷史、其他待背字、學校／姓名或研究 ID。

- **Beta**：App 不建接收後端；把上述項目放入 **iOS 系統分享面板／使用者選擇的郵件／複製文字**，由使用者再確認送出。App 不自動發送、不聲稱對方已收到，且須告知第三方分享服務／電子郵件可能揭露寄件人或其他 metadata。若 Beta 使用 TestFlight，可另外採 Apple 的主動文字、截圖與當機回饋，不把它歸入研究統計。
- **正式版**：只有逐次預覽並確認，才用專用 HTTPS 內容回報服務（T036）接收最小資訊；限制大小、濫用、日誌與存留。此可讀回報跟 T033 安全聚合研究分離，不能用研究同意授權回報、也不能用內容回報同意授權研究。

自由文字即使看起來像「單字」仍可能含姓名等個資，應做好長度限制、格式與風險控管；日誌不存不必要的 body 或來源 metadata，訂定保留／刪除規則。缺詞回報用於詞庫審查，不可未經另一目的同意就轉作記憶模型訓練、與研究統計合併或發布成個人資料。**離線、不回報或研究不同意時，核心學習均可正常進行**；只報送的人才有這筆資料傳輸。

## 正式版 Privacy-preserving aggregation 的結果要求

**Beta 沒有自動研究上傳／單一聚合方過渡服務；以下是正式版 T033 的要求。** 實作技術由 agent 在正式版階段研究與選擇，但最後必須滿足以下性質：

1. **沒有單一使用者可讀資料落在研究 backend。**  
   Application server、資料庫、dashboard 或一般 log 被完整取得時，不應出現某個人的 raw history、個人參數或可讀 contribution。

2. **來源身分與 contribution 分離。**  
   正式版採 OHTTP（或經驗收具有等效來源分離保證的 relay／gateway 架構），使看到來源 IP 的元件看不到可讀 contribution，而可處理 contribution 的元件看不到原始來源 IP。

3. **單一聚合方不足以解出個人 contribution。**  
   正式版採 DAP／VDAF 類多方安全聚合（或經同等威脅模型驗收的協定）；至少兩個具有**真正獨立營運、金鑰與管理權限**的聚合方，在其中一方未被攻破／未串通時，單一 contribution 不可被還原。不能只在同一營運帳號部署兩個服務。

4. **只輸出群體 aggregate。**  
   未達最低 cohort 的統計不釋出。最低門檻屬 privacy parameter，需依預期正式使用量與統計粒度驗證後決定，不在 planning 階段寫死。

5. **不能任意切 cohort。**  
   研究端不應能反覆查詢高度重疊的小群體並以相減方式還原個體。aggregate 應以預先定義的 metric schema / epoch 產生，而不是提供任意 SQL 式分群查詢。

6. **一般 infrastructure log 不得破壞匿名性。**  
   request body、IP、精確接收時間與其他 network metadata 的保留策略必須和 privacy claim 一起驗證；不能 payload 匿名、server log 卻能重新連回來源。

## Beta 階段：不傳送研究 contribution

Beta 只執行本機事件紀錄、模擬、裝置端模型校準與本機診斷；**研究上傳必須在 Beta build 關閉，沒有單一聚合方伺服器，也不以郵件／分享面板手動傳送個人原始歷史或個別統計來冒充匿名群體研究**。Beta 也不顯示可誤導使用者的「研究分享已啟用」開關。

App 的缺詞／錯題主動分享屬上一節的**可讀內容回報**，TestFlight 主動意見回饋屬 Apple 平台功能，均不能取代正式版安全聚合。未來若另開早期真人研究，需獨立檢查同意與研究倫理；本 V1 Beta 範圍不包含自動研究上傳。

## Differential Privacy

正式版 V1 不把 differential-privacy noise 當預設必要條件；Beta 不收集研究貢獻，故不涉及研究聚合加噪。

原因是本產品的第一目標不是公開一個可任意查詢的統計平台，而是取得少量預先定義的群體模型與 calibration 統計。若 secure aggregation、來源分離、最低 cohort 與固定查詢面已足以符合 threat model，引入 noise 可能只會降低演算法校準精度。

但 DP 不是永久排除。如果未來：

- 對外發布高度細分 aggregate；
- 允許大量 cohort slicing；
- 需要抵抗「攻擊者已知其他大部分參與者資料」的 membership / differencing inference；
- 或 privacy threat model 提高；

則重新評估 differential privacy。

## 同意與使用者控制

**正式版研究資料分享**採 **explicit opt-in**（Beta 沒有上傳研究貢獻的功能）：

- 不同意也可完整使用 lexvane。
- 同意畫面要清楚說明：完整學習歷史與個人模型留在裝置上；對外只貢獻無法由研究端讀取的群體統計／模型更新。
- 使用者可以撤回；撤回後不再產生新的研究 contribution。
- 已經完成且無法拆回個人的群體 aggregate，不應宣稱可以再抽出某個人的貢獻；隱私政策要清楚說明這一點。
- App 不需要 ATT，除非未來實際行為符合 Apple 對跨公司 tracking 的定義；本研究架構本身不應做 tracking。

Apple App Review Guideline 5.1.1(ii) 要求收集 user / usage data 時取得使用者同意，即使資料在收集當下或之後立即匿名化；因此匿名化不是省略 consent 的理由。

## 台灣個資法定位

本文件不是法律意見。

個資會目前的正式函釋明確區分「仍可能間接識別的去識別化資料」與「完全匿名且無還原可能性，因此不在個資法保護範圍內的資料」。方案 A 的目標是讓研究端最終只持有後者等級的群體 aggregate，而不是持有假名化的 user-level dataset。

在真正完成實作與 threat-model review 前，仍以較保守方式處理：
- 清楚告知與取得同意。
- 資料最小化。
- 不把研究資料另作其他用途。
- beta 涉及未成年人的同意流程，在公開／大規模使用前依實際發佈方式再次做法律確認。

## Threat model

這個方案要能合理承諾：

- lexvane application backend / database / dashboard 被攻破，不會得到可讀的單一使用者學習資料。
- 正式版任一單一 aggregation party 被攻破，不足以還原 individual contribution；Beta 不建立研究聚合服務或上傳個別 contribution。
- 研究端拿不到「來源 IP ↔ 可讀 contribution」的對應表。
- 最終只有滿足最低群體門檻的預定 aggregate。

這個方案**不**宣稱：
- 使用者自己的 iPhone 已被攻破時仍能保護該裝置內的資料。
- 所有獨立 aggregation parties、relay、gateway 同時串通／被完全攻破時仍有普通 secure aggregation 的同等保證。
- 在沒有 differential privacy 的情況下，能抵抗所有可能結合任意外部資訊的統計推論。

這些限制要反映在真正的 privacy claim 中。

## 驗收重點

**Beta 發布前**：確認研究上傳在所有正常學習、離線恢復及錯誤情境下皆未啟用；內容回報只能交給使用者的系統分享／複製動作，不直接聯絡開發者的接收 API。

**正式版啟用研究 contribution 並通過 T037 發布 gate 前**，至少驗證：

- 關閉 research sharing 時沒有任何研究 contribution 離開裝置，核心學習功能完全正常。
- raw learning events、個人詞彙歷史與 individual memory parameters 沒有研究 upload path。
- 研究 backend 沒有 user-level research table 或穩定 user/research identifier。
- 單一 backend compromise 或單一 aggregation share 無法讀出個人 contribution；不可用單方伺服器或僅有「不保存」營運承諾替代此正式版保證。
- aggregate 未達 privacy threshold 時無法釋出；門檻依實際可保證的獨立貢獻單位定義，不能用重送的 report 數假裝是人數。
- 不能利用合法介面產生兩個高度重疊 aggregate 再相減得到個人 contribution。
- 一般 access/error logs 不保存足以把 contribution 重新連回來源的 metadata。
- consent、withdrawal 與 privacy-policy 文案和實際技術行為一致。
- 同一份 report 重送只計一次，資料格式與配額／濫用防護有驗收；群體指標的計數單位、加權與納入條件明確，失敗／退出樣本不能被默默排除後宣稱全體準備程度。
- 正式版實際兩方的營運、金鑰與管理權限具有可驗證的獨立性；Beta 無聚合服務，不宣稱提供群體研究結果。
- 正式版缺詞／錯題回報只有逐次預覽、主動提交才送可讀內容，且有與群體研究不同的網路路徑、存取權限及 retention；Beta 則只讓使用者自行分享，兩者均不受研究開關影響、不觸發自動回報。

## 可研究的技術

這些是候選，不是預先指定的 implementation：

- IETF Oblivious HTTP (RFC 9458) 用於來源與內容分離。
- DAP / VDAF / Prio 類 multi-party privacy-preserving measurement / secure aggregation。
- 若未來 threat model 需要，再加入 differential privacy。

選型時以實際可審計性、iOS 支援、運維複雜度與 privacy guarantee 為準，而不是為了追求「密碼學很複雜」而過度設計。

## 官方參考

- Apple App Review Guidelines 5.1.1 / 5.1.2: https://developer.apple.com/app-store/review/guidelines/tw/
- Apple User Privacy and Data Use: https://developer.apple.com/app-store/user-privacy-and-data-use/
- 台灣個人資料保護法: https://law.pdpc.gov.tw/LawContent.aspx?id=FL010627
- 個資會函釋（完全匿名且無還原可能性的區分）: https://www.pdpc.gov.tw/News_Content/102/1058/
- IETF Oblivious HTTP, RFC 9458: https://datatracker.ietf.org/doc/rfc9458/
