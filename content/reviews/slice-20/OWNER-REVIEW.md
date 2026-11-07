# Slice-20 owner review（20 詞切片｜待你審）

狀態：**待審**。這份清單本身不是核准。你回覆之前，`human_review_pending` 維持 true。

## 怎麼審

- 20 個詞，每個詞一張卡：教學、練習題（train）、檢查題（check）。★ 是正解。
- 「AI 審查」是我（另一個 Claude Code session，沒有參與出題）依 v3 三個面向做的獨立語意審查：干擾選項是否合理、是否只有一個正解、題幹是否洩題。結果：40 題中 37 題通過。
- 3 題 AI 審查不通過（art 練習題、history 檢查題、job 練習題），我已附上替換干擾選項的提案。
- 「備註」是不影響答對答錯、但建議日後清理的問題，主要是教學和回饋裡夾雜了寫給審查者看的句子。
- **最省事的回覆方式**：直接在對話裡說「全部核准、3 個提案都採用」，或「除了 X、Y 都核准」。下一個 session 會替你寫成正式紀錄。也可以在每題的 `[ ]` 打勾。

依你 2026-11-07 的決定，私人預覽由你一人核准即可（見 `content/docs/DECISIONS-OWNER-2026-11-07.md`）。

## 1. day（noun｜一天；以二十四小時為一個單位的時間｜詞義辨認）

**教學** 本目標的 day 是以二十四小時為一個單位的時間，兩個這樣的單位用 two days。two days old 用這個時間單位表示出生後經過的時間。結構化用法與例句只列時間單位義，不把與夜晚相對的白天義列為本目標的證據。

用法：a day; two days old; age in days；例句：The newly hatched chick is two days old.（這隻剛孵化的小雞出生兩天了。）

備註：教學裡有寫給審查者看的句子（例如「本目標」「不列為證據」「已分開記錄的義項」），學生看了會困惑，建議日後清理。

- [ ] 教學核准

**練習題 train** `lx:question:5ca33009-0859-4c2e-a5cc-750d5675078c` r4

> A wildlife camera ran continuously for three full days without a shutdown. Its service form asks for the total operating hours. Which total should the technician enter?

12 operating hours / 24 operating hours / ★ 72 operating hours / 168 operating hours

回饋：day 在此是一整天的時間單位。三個完整的日子共有七十二小時，所以服務紀錄應填 72 operating hours；這不是租借物品後計算隔日截止時刻。

AI 審查：通過

備註：回饋最後一句「這不是租借物品後計算隔日截止時刻」與本題無關，是出題流程殘留。

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:7b2e4d2b-3d9b-4950-91c6-304d49637cd8` r6

> A phone's photo album is grouped by day. Photos from both the morning and late evening of 8 May share one heading, while photos from 9 May begin another group. What unit does day name here?

A block of seven consecutive calendar dates. / Only the hours between sunrise and sunset. / ★ One calendar date, from midnight to the next midnight. / A complete calendar month.

回饋：day 在此表示一天，也就是一個日曆日期所涵蓋的時間。五月八日早上與深夜的照片同組，五月九日另成一組；這不是只計白晝，也不是一週或一個月。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

## 2. year（noun｜年；十二個月構成的時間單位｜詞義辨認）

**教學** year 是可數名詞，常用來表示一年或人的年齡。a year 是一年；three years 是三年。說明年齡時用 years old，不能把年這個單位與月份混在一起。

用法：a year; three years old; next year；例句：Our reading club will celebrate its first year in December.（我們的讀書會將在十二月慶祝成立滿一年。）

- [ ] 教學核准

**練習題 train** `lx:question:286a2493-4fa2-48f6-836e-c2ca7ffac2a1` r3

> On May 6, 2026, Mina planted a tree and promised to photograph it again exactly one year later. Which date should she put in her reminder?

May 13, 2026 / June 6, 2026 / ★ May 6, 2027 / May 7, 2026

回饋：year 是年。二〇二六年五月六日再過一年，同月同日是二〇二七年五月六日；此處用實際日期檢核年度間隔。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:7e3b09f3-64b5-426d-b2eb-3514cde3a480` r3

> At midnight on December 31, the crowd watches the date change from 2026 to 2027. Which message fits the start of the new year?

Another month remains before the calendar changes. / A second day has begun within the same numbered year. / ★ The next annual cycle has just begun. / One more hour remains before the new calendar date.

回饋：year 是年。十二月三十一日午夜後，日期進入下一個編號的年份；選項描述的是新的一年開始，而不是只過了一小時或同一年中的另一日。

AI 審查：通過

備註：題目很簡單，題幹「the start of the new year」幾乎直接說出答案。

- [ ] 核准　- [ ] 退回（原因：　　）

## 3. science（noun｜科學；藉觀察、測試與證據研究現象的知識活動｜詞義辨認）

**教學** science 指以觀察、測試與可檢驗證據研究現象的科學活動。根據氣壓與風的觀測資料預測暴風雨路徑，是運用資料研究自然現象。此目標只辨認科學義，結構化用法與例句不列其他能力的掌握證據。

用法：study science; a science lesson; evidence in science；例句：Science helps weather researchers predict a storm's path from air-pressure and wind measurements.（科學幫助氣象研究者根據氣壓與風的測量資料預測暴風雨的路徑。）

備註：教學裡有寫給審查者看的句子（例如「本目標」「不列為證據」「已分開記錄的義項」），學生看了會困惑，建議日後清理。

- [ ] 教學核准

**練習題 train** `lx:question:b3c8c6bd-0e1e-40f9-90b7-764421a2654a` r6

> Mara wraps identical ice cubes in different materials and measures how long each takes to melt. She repeats the trials before drawing a conclusion about the materials. Which subject is she applying?

History / Music / Literature / ★ Science

回饋：science 指科學。比較包覆材料、測量冰塊融化所需的時間並重複試驗，是用可檢驗的資料研究物理現象。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:4b5bedbf-92dc-4e2c-aa1c-62e1508ecd31` r6

> At an exhibition of old thermometers, an audio guide says, "These instruments helped science develop." What does science mean in this sentence?

★ The systematic study of the natural world using evidence. / The preservation of a community's inherited customs. / The creation of imagined characters and stories. / The organization of buying and selling goods.

回饋：science 指科學，也就是以證據有系統地研究自然世界。溫度計提供可觀測的資料；題目問的是科學這個領域的意思，而不是挑選活動場次。

AI 審查：通過

備註：回饋「而不是挑選活動場次」與本題無關（流程殘留）。

- [ ] 核准　- [ ] 退回（原因：　　）

## 4. question（noun｜問題；向他人詢問以取得回答的話語｜語境選詞）

**教學** question 是可數名詞，常搭配 ask 或 answer。ask a question 表示提問；answer a question 表示回答問題。question 的重點是索取回答，不等於所有需要修復的 problem。

用法：ask a question; answer a question；例句：Nora asked a question about the bus route.（諾拉問了一個關於公車路線的問題。）

- [ ] 教學核准

**練習題 train** `lx:question:2324b8cf-27f9-451f-a8bf-f57da5ea4844` r2

> During the radio call, Jo said, 'Is anyone still inside the warehouse?' Nobody replied, so she repeated the ___ more loudly.

promise / warning / greeting / ★ question

回饋：question 是為取得回答而提出的問題。Jo 詢問倉庫裡是否有人，因沒有得到回覆而再次詢問；不是公車路線例句或訪談表格。

AI 審查：通過

備註：回饋提到「公車路線例句或訪談表格」，訪談表格正是同一目標檢查題的情境（流程殘留）。

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:40953897-6bc3-4ff7-a0c5-b573f29f0634` r2

> The interview form has a separate box for the applicant's reply beside every ___. Instructions and final decisions are printed on another sheet.

verdict / instruction / ★ question / signature

回饋：question 指向人提出、用來取得回答的問題。表格為每一項詢問配上一個回覆欄，與另一頁的指示或決定分開。

AI 審查：通過

備註：題幹硬加一句排除條件（指示和決定印在另一張），讀起來不自然。

- [ ] 核准　- [ ] 退回（原因：　　）

## 5. market（verb｜行銷；推廣商品以吸引買家｜語境選詞）

**教學** 本目標的 market 是動詞，表示行銷或推廣商品以吸引買家。受詞是被推廣的商品，如 market a product。下列例句只使用動詞行銷義。名詞可指買賣的場所，也可指某商品的買家與需求，這兩種名詞義需要區分記錄，不作本目標的例句或答題依據。

用法：market a product; market backpacks at school events；例句：The company markets its lamps through short online videos.（這家公司透過網路短片行銷它的燈具。）；The team markets its new backpacks at school events.（這個團隊在學校活動中行銷新款背包。）

備註：教學裡有寫給審查者看的句子（例如「本目標」「不列為證據」「已分開記錄的義項」），學生看了會困惑，建議日後清理。

- [ ] 教學核准

**練習題 train** `lx:question:b425e032-b16b-4a5a-8713-a0a94255d436` r4

> A software company let people use its new app free for a week, hoping they would then buy a subscription. It used the trial to ___ the app.

repair / encrypt / archive / ★ market

回饋：market 作動詞指行銷商品以吸引買家。公司提供免費試用，讓使用者體驗後願意付費訂閱，是以試用進行行銷。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:43e7fdc6-57e6-4088-883d-be532a1a2742` r5

> Customers keep mistaking a waterproof notebook for an ordinary one. Rather than change the notebook, the shop decides to ___ it as equipment for divers, using demonstrations held underwater.

assemble / ★ market / recycle / license

回饋：market 在此是動詞「行銷」。商店沒有改造筆記本，而是改變向潛在買家呈現產品的方式：以潛水裝備定位並展示防水用途。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

## 6. business（noun｜商業活動；以商品或服務進行交易的活動，通常不可數｜語境選詞）

**教學** 本目標的 business 指商業交易活動，通常不可數。do business with a supplier 表示與供應商做生意。下列例句都描述交易活動，不作企業個體或非商業事務義的測量證據。

用法：do business with a supplier; do business with nearby cafes；例句：Our shop does business with a local supplier.（我們的店與一家本地供應商做生意。）；The bakery does business with several nearby cafes.（這家麵包店與附近幾家咖啡館做生意。）

備註：教學裡有寫給審查者看的句子（例如「本目標」「不列為證據」「已分開記錄的義項」），學生看了會困惑，建議日後清理。

- [ ] 教學核准

**練習題 train** `lx:question:da532e6d-8034-4d73-a22f-5733409699e4` r3

> Customs officers halted the shipment until an unpaid import duty was settled. The delay interrupted the company's international ___, leaving its contracted deliveries unfinished.

★ business / research / training / mourning

回饋：business 在此是商業活動。進口稅與契約交貨延誤直接影響跨國交易，並非道路通行改變店家客流，也不是可數的公司名稱。

AI 審查：通過

備註：回饋提到題目裡沒有的「道路通行」「可數的公司名稱」（流程殘留）。

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:7d4deea2-bbec-4f9c-a795-6bf368984735` r4

> A furniture studio adds an online ordering page. After six months, online orders account for half its ___, while the other half still comes from sales in the showroom.

★ business / training / research / exercise

回饋：business 在此指生意、商業活動。線上訂單和展示間銷售是工作室的兩種交易管道，各占一半的生意。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

## 7. life（noun｜生命；一個人或生物活著的狀態或期間｜語境選詞）

**教學** 本目標的 life 指生命，包括生物的存活與生命現象。forms of life 是生命形式，support life 是維持生命存在。結構化用法與例句只列生命義；日常生活方式及人生經歷不作此目標的答題證據。

用法：forms of life; support life; sustain life；例句：All known forms of life need a source of energy.（所有已知的生命形式都需要能量來源。）

備註：教學裡有寫給審查者看的句子（例如「本目標」「不列為證據」「已分開記錄的義項」），學生看了會困惑，建議日後清理。

- [ ] 教學核准

**練習題 train** `lx:question:46a50a14-b7bd-43ea-befd-93c0b0486790` r5

> A pension agreement promises Rosa a monthly payment until she dies, even if she lives for another forty years. It guarantees payments for the rest of her ___.

lease / journey / illness / ★ life

回饋：life 在此指一個人活著的期間，也就是生命。付款承諾持續到羅莎死亡，因此 for the rest of her life 是在她餘生期間；不是租約、旅程或疾病的期間。

AI 審查：通過

備註：教學講生物的生命（forms of life），本題考的是一生的期間；兩者都在同一義項定義內。

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:6a8dff44-26b2-43aa-99d8-a4d297a1092e` r7

> A baker mixes yeast into dough. As the yeast cells multiply and consume sugar, they release gas that makes the dough rise. Complete the baker's description of those living cells: 'This recipe puts microscopic ___ to work.'

friction / gravity / electricity / ★ life

回饋：life 在此指生命，microscopic life 指微小的生命體。麵糰中的酵母細胞會繁殖並消耗糖，製麵包的過程利用這些生命體產生的氣體，使麵糰膨起。題目要描述的是酵母細胞，不是另找一種物理作用來解釋麵糰的變化。

AI 審查：通過

備註：「puts microscopic life to work」說法略不自然。

- [ ] 核准　- [ ] 退回（原因：　　）

## 8. answer（verb｜回答；對問題作出回應｜語境選詞）

**教學** 本目標的 answer 是動詞，表示回答。動詞可直接接問題，如 answer the question，不加 to。下列例句都描述回答的動作。名詞 answer 表示答案，可搭配 an answer to a question；那是另一個已分開記錄的義項，不列為本目標的例句。

用法：answer the question; answer a question about the schedule；例句：Please answer the question in one sentence.（請用一句話回答這個問題。）；Nora answered the coach's question about the schedule.（諾拉回答了教練關於時程的問題。）

備註：教學裡有寫給審查者看的句子（例如「本目標」「不列為證據」「已分開記錄的義項」），學生看了會困惑，建議日後清理。

- [ ] 教學核准

**練習題 train** `lx:question:32331447-9db8-4d16-a491-6558eea443c2` r4

> At the quiz table, the host asked, 'Which planet is closest to the Sun?' Lila pressed her buzzer to ___ the question and said, 'Mercury.'

repeat / ★ answer / translate / withdraw

回饋：answer the question 是回答問題。Lila 按下搶答鈴後說出 Mercury，提供主持人要求的資訊。四個動詞都能接 the question，必須依這個行動判斷。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:ca7391b0-e011-409e-856a-86d7fc33d465` r2

> The online form asks, 'Which entrance did you use?' To complete it, you must ___ by selecting the entrance you actually used; leaving the item blank does not count.

★ answer / erase / refuse / sleep

回饋：answer 在此是動詞「回答」。選出實際使用的入口，就是對表格的提問作出回應，並非只談別的主題或留下空白。

AI 審查：通過

備註：題幹硬加「leaving the item blank does not count」來排除選項。

- [ ] 核准　- [ ] 退回（原因：　　）

## 9. art（noun｜藝術；透過創作表達想法與感受的活動或作品，尤其視覺藝術｜語境選詞）

**教學** 本目標的 art 指藝術創作或作品，這裡聚焦視覺藝術，通常不可數。a work of art 是一件藝術作品，不直接用 an art 表示一幅畫。下列例句都談視覺藝術作品。the arts 統稱音樂、戲劇等藝術領域，是另一個已分開記錄的義項，不列為這個目標的用法或例句。

用法：a work of art; display art in a gallery；例句：The gallery displays art made from discarded metal.（這間藝廊展示用廢棄金屬創作的藝術作品。）；The students discussed the art on the gallery walls.（學生們討論藝廊牆上的藝術作品。）

備註：教學裡有寫給審查者看的句子（例如「本目標」「不列為證據」「已分開記錄的義項」），學生看了會困惑，建議日後清理。

- [ ] 教學核准

**練習題 train** `lx:question:8e73bbfc-4af2-4b3b-b9eb-78bf4308c49b` r2

> After a fire threatened the artist's studio, conservators rushed in to protect the original ___, moving the finished portraits out before smoke damaged them.

law / ★ art / war / aid

回饋：art 指藝術作品。保存人員保護工作室中的原創肖像作品，讓創作不被火災破壞；不是藝廊中看圖分類或製作社區拼貼。

AI 審查：**不通過**。干擾選項 law、war、aid 在句中說不通，學生不認識 art 也能用刪去法答對。

提案：選項改為 furniture / ★ art / equipment / paperwork

提案回饋：art 指藝術作品。保存人員從工作室搶救出完成的肖像畫，這些原作就是藝術作品。

備註：三個干擾選項都是無關的短名詞；回饋也有流程殘留（藝廊看圖分類、社區拼貼）。

- [ ] 採用提案　- [ ] 維持退回

**檢查題 check** `lx:question:0cc4903f-f0f0-44f7-8100-0959c63cb7e7` r2

> On an unused wall, residents arrange colored tiles into an image of their memories. The work is meant to express their feelings, not to sell anything, give directions or cover damage. They call it public ___.

transport / advertising / insurance / ★ art

回饋：art 在這裡是藝術作品。居民把共同記憶化為磁磚圖像，以創作傳達感受；不是導引標誌或修補工程。

AI 審查：通過

備註：題幹直接列出排除條件（not to sell anything, give directions or cover damage），刪去法太容易。

- [ ] 核准　- [ ] 退回（原因：　　）

## 10. history（noun｜歷史；某個地方、群體或事物過去的事件與發展歷程｜語境選詞）

**教學** 本目標的 history 指某個地方過去的事件與發展歷程。the history of a town 是一座城鎮的歷史；舊地圖和紀錄能幫助我們了解這段過往。下列例句只談過去的事件與發展。history 指歷史學科時需要另立義項，不把學科和被研究的過去合成這個目標。

用法：the history of a town; the history of a harbor；例句：Old maps helped us understand the history of the harbor.（舊地圖幫助我們了解這座港口的歷史。）

備註：教學裡有寫給審查者看的句子（例如「本目標」「不列為證據」「已分開記錄的義項」），學生看了會困惑，建議日後清理。

- [ ] 教學核准

**練習題 train** `lx:question:b128b18a-c7a1-48a8-99fa-ac88884dc0e5` r2

> Restorers found arrowheads inside the castle's old walls. The discovery revealed a forgotten siege in the castle's ___.

climate / cuisine / ★ history / scenery

回饋：history 在此指過去的事件與發展歷程。城牆內的箭頭使人發現一場被遺忘的圍城事件，揭露這座城堡過去的一部分，不是在辨認研究歷史的學科。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:afecd769-4823-49d5-a519-1ba202128b9c` r9

> The museum traces the ___ of diving equipment, from early metal helmets to the breathing systems used today.

weather / balance / ★ history / flavour

回饋：history 指歷史、過去的發展；博物館呈現潛水裝備從早期到今日的演變。

AI 審查：**不通過**。干擾選項 weather、flavour 在句中說不通，學生不認識 history 也能用刪去法答對。

提案：選項改為 price / balance / ★ history / repair

備註：三個干擾選項中有兩個無關。

- [ ] 採用提案　- [ ] 維持退回

## 11. environment（noun｜環境；周圍的自然條件或事物｜語境選詞）

**教學** the environment 常指自然環境，搭配 protect the environment，表示保護自然環境。an environment 可指某種周遭條件，如 a quiet working environment。冠詞選擇隨指涉改變，不能把所有 environment 都視為同一固定形式。

用法：protect the environment; a working environment；例句：Reducing waste helps protect the environment.（減少廢棄物有助於保護環境。）

- [ ] 教學核准

**練習題 train** `lx:question:cc009b68-552b-4550-992a-af994b1c7d97` r2

> After the eruption, ash coated the island's lake and shoreline, and fish disappeared from the shallows. Researchers returned to assess the damage to the island's ___.

government / employment / ★ environment / invitation

回饋：environment 是環境。火山灰改變湖泊、岸邊與生物生存條件，研究者評估的是這些周圍自然事物所受的損害；不是保護環境口號或仙人掌棲地定義。

AI 審查：通過

備註：回饋提到題目裡沒有的「保護環境口號」「仙人掌棲地定義」（流程殘留）。

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:8f433bea-17e3-4852-b5dd-0fda0ccee31f` r5

> The greenhouse provides a warm, humid ___ in which tropical orchids can survive the winter.

★ environment / experiment / measurement / observation

回饋：environment 指環境；溫室提供適合熱帶蘭花生存的周遭條件。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

## 12. experience（noun｜經驗；因做過某事而累積的知識或熟練程度，不可數｜語境選詞）

**教學** 本目標的 experience 是不可數名詞，指實際做過事情而累積的知識或熟練程度。years of experience 表示多年累積的經驗；experience in interpreting 表示口譯方面的經驗。結構化用法與例句只列此經驗義，不把一次可數的經歷列為本目標的證據。

用法：experience in interpreting; years of experience; gain experience；例句：Years of experience interpreting at conferences have taught Aya how to convey jokes between languages.（多年在會議中擔任口譯的經驗，讓阿雅學會如何跨語言傳達笑話。）

備註：教學裡有寫給審查者看的句子（例如「本目標」「不列為證據」「已分開記錄的義項」），學生看了會困惑，建議日後清理。

- [ ] 教學核准

**練習題 train** `lx:question:13f1b7f1-792a-4cc1-9fc5-30bbc73899d3` r6

> An insurance company requires applicants for a claims examiner position to have at least five years of ___ in reviewing claims. Mara lists the eight years she spent doing that work at another firm.

funding / insurance / publicity / ★ experience

回饋：experience 在此是實際從事工作所累積的經驗。職缺要求理賠審查方面的經驗，瑪拉以八年相關工作年資回應要求；不是在比較理論與反覆練習的手感。

AI 審查：通過

備註：回饋提到「比較理論與反覆練習的手感」，與本題無關（流程殘留）。

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:481aa81a-2490-446a-b4ab-00d4628d2ccf` r10

> The young sailor understood every rule in the handbook, but lacked the ___ that comes from steering a boat through real storms.

permission / equipment / ★ experience / qualification

回饋：experience 指實際經歷所累積的經驗；熟記規則不能取代在風暴中掌舵的實務經歷。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

## 13. problem（noun｜難題；造成困難而需要解決的狀況｜語境選詞）

**教學** problem 指需要處理的困難，是可數名詞。solve a problem 是解決難題；have a problem with the printer 是印表機出了狀況。它不一定是 someone asks a question 那種向人提問。

用法：solve a problem; a problem with the printer；例句：A loose cable caused the problem with our printer.（一條鬆脫的線造成了我們印表機的故障。）

- [ ] 教學核准

**練習題 train** `lx:question:17f16e2b-36bc-42ae-b04d-bc292d86346b` r2

> The cake looked golden outside, but wet batter poured out when Tara cut it. She returned it to the oven to deal with the ___.

★ problem / reward / promise / journey

回饋：problem 是需要處理的問題。蛋糕內部仍未烤熟，Tara 必須採取補救行動；這次情境不是設備故障或場地排程。

AI 審查：通過

備註：回饋提到「設備故障或場地排程」，與本題無關（流程殘留）。

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:c8da43d4-e5a9-463e-a98f-c4afd36db7c6` r5

> A cracked irrigation pipe has become a serious ___ for the greenhouse: the seedlings are drying out before the repair crew can arrive.

success / ★ problem / routine / solution

回饋：problem 指問題、需要處理的困難；水管破裂使幼苗缺水，是溫室必須解決的困難。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

## 14. language（noun｜語言；人們用來表達與溝通的一套符號或聲音系統｜語境選詞）

**教學** language 指語言。談一種特定語言時可數，如 learn a language 或 speak three languages；談語言這種能力或現象時可不加冠詞。不要把會說多種語言寫成 speak three language。

用法：learn a language; speak three languages；例句：Mina is learning a new language so she can talk with her neighbors.（米娜正在學一種新語言，好和鄰居交談。）

- [ ] 教學核准

**練習題 train** `lx:question:39927719-6821-4b14-a3ee-0afc98f81be9` r2

> When Olek changed the application's ___ setting from English to Polish, all the menu labels changed, but the buttons stayed in the same places.

currency / province / ★ language / festival

回饋：language 指語言。這次操作改變選單的文字語言而不改變按鈕配置，是實際的介面操作情境。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:a63621bb-7594-42d7-b594-704fcc6ca1e2` r2

> The twins use signs instead of speech. Their signs form complete sentences with their own grammar; researchers recognize the system as a ___, not merely random gestures.

gesture / noise / ★ language / costume

回饋：language 是語言，可以以符號而非口語聲音來表達。這套手語有自己的文法並能組成完整句子，因此是一套語言，不是隨意比畫。

AI 審查：通過

備註：題幹硬加「not merely random gestures」來排除選項。

- [ ] 核准　- [ ] 退回（原因：　　）

## 15. music（noun｜音樂；有節奏、旋律等組織的聲音藝術｜語境選詞）

**教學** music 通常不可數，可說 listen to music，不說 listen to a music。要數單首作品，可說 a piece of music 或 a song。play music 可指演奏或播放，需看情境。

用法：listen to music; a piece of music；例句：Soft music played while the guests entered the hall.（賓客走進大廳時，現場播放著柔和的音樂。）

- [ ] 教學核准

**練習題 train** `lx:question:23003285-3da0-47fb-b84f-4a6ac70849fe` r2

> The film's chase scene felt strangely empty after its orchestral soundtrack was removed. The director restored the ___, and the rapid notes made the scene tense again.

static / speech / ★ music / silence

回饋：music 指音樂。導演恢復管弦樂配樂後，快速的音符改變了追逐場景的氣氛；不是把鋼琴與鼓的聲音直接分類。

AI 審查：通過

備註：回饋提到「把鋼琴與鼓的聲音直接分類」，與本題無關（流程殘留）。

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:257df3e6-8aba-4ebe-af7a-3aab642e1b2b` r2

> The choir performs without instruments. Its members sing in harmony from a score; the program describes their organized sounds as vocal ___.

noise / ★ music / speech / static

回饋：music 是音樂；人聲也能構成音樂。合唱團按譜以和聲演唱，不需要器樂伴奏仍屬音樂表現。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

## 16. opportunity（noun｜機會；讓人能做某事的有利情況｜語境選詞）

**教學** opportunity 是可數名詞，複數為 opportunities。常接 to 加動詞，如 an opportunity to learn。take the opportunity 或 seize the opportunity 都指把握機會；opportunity 本身不保證成功，而是提供行動的可能。

用法：an opportunity to learn; take the opportunity; seize the opportunity；例句：When a free workshop opened nearby, I took the opportunity to learn pottery.（附近開了免費工作坊時，我把握機會學陶藝。）

- [ ] 教學核准

**練習題 train** `lx:question:4f9b7f34-17d4-4024-a874-1e0e17e3e24a` r2

> When the scheduled soloist withdrew, the conductor invited Amir to perform at the national concert instead. Amir accepted the ___ and began rehearsing that evening.

★ opportunity / disappointment / restriction / disagreement

回饋：opportunity 是機會。臨時的替補邀請讓 Amir 能登上全國音樂會的舞台，他把握這項有利情況。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:ca5dba38-5a71-4965-8a90-fa90c1ee1ae9` r2

> Clouds finally part during the eclipse, letting the astronomers photograph it before it ends. The clear patch gives them a brief ___ to capture the event; it permits action rather than preventing it.

prohibition / delay / failure / ★ opportunity

回饋：opportunity 指讓人能做某事的有利情況或機會。雲層短暫散開使天文學者可以拍下食象；有利窗口短暫，但確實使行動成為可能。

AI 審查：通過

備註：題幹硬加「it permits action rather than preventing it」來排除選項。

- [ ] 核准　- [ ] 退回（原因：　　）

## 17. job（noun｜工作職位；一份受僱從事的工作｜語境選詞）

**教學** job 是可數名詞，可以說 a job 或 two jobs，常指一份職位。work 指一般工作活動時通常不可數，可以說 have a lot of work。找職位是 look for a job；不能用 a work 取代這個職位義。

用法：apply for a job; a full-time job；例句：Tina applied for a job as a library assistant.（蒂娜申請了一份圖書館助理的工作。）

- [ ] 教學核准

**練習題 train** `lx:question:d2e48691-5eb9-4d04-9f10-f8ee05862b2b` r2

> Imani negotiated the salary and paid leave before signing the employment contract. Only then did she formally accept the ___.

map / ★ job / bet / toy

回饋：job 是工作職位。她確認薪資與有薪休假並簽訂受僱契約，才正式接受職位；不是直接用 paid position 作為詞義提示。

AI 審查：**不通過**。干擾選項 map、bet、toy 在句中說不通，學生不認識 job 也能用刪去法答對。

提案：選項改為 loan / ★ job / lease / award

提案回饋：job 指一份工作職位。談妥薪資和有薪假、簽下雇用契約後，她正式接受了這份工作。

備註：三個干擾選項都是無關的短名詞；回饋「不是直接用 paid position 作為詞義提示」是流程殘留。

- [ ] 採用提案　- [ ] 維持退回

**檢查題 check** `lx:question:04b5aa2f-f0f4-47e9-b32b-3f36dfe6cc36` r2

> The restaurant permanently closed, ending Rosa's paid position there. She lost her ___, not merely a day's earnings.

pension / ★ job / hobby / license

回饋：job 在此指一份受僱的工作。餐廳永久結束營業，使 Rosa 的職位消失；所失去的是整份工作，而不是單日收入。

AI 審查：通過

備註：題幹的「paid position」幾乎就是 job 的定義，降低難度。

- [ ] 核准　- [ ] 退回（原因：　　）

## 18. community（noun｜社區；居住在同一地區或具有共同連結的一群人｜語境選詞）

**教學** community 指社區或有共同連結的群體，是可數名詞，複數為 communities。community center 是社區活動中心；community spirit 是社區成員互相支持、共同參與的精神，不是單指一棟建築。

用法：a local community; community center; community spirit；例句：Residents meet at the community center to plan neighborhood activities.（居民在社區活動中心聚會，規劃鄰里活動。）

- [ ] 教學核准

**練習題 train** `lx:question:9915cf55-1418-4246-a2dc-939e779de499` r2

> After floodwater receded, residents from all over the village volunteered to clear mud from their neighbors' houses. The whole ___ joined the recovery effort.

orchestra / ★ community / audience / workforce

回饋：community 是社區。全村居民在災後共同幫助鄰居，呈現地域連結中的集體行動；不是說這些人形成一個定義上的群體。

AI 審查：通過

備註：回饋「不是說這些人形成一個定義上的群體」是流程殘留。

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:0a1c63dd-7b85-463e-8d04-e477ac8de58e` r2

> Deaf programmers in different countries exchange advice online for years. They describe this lasting, nonmilitary network of unrelated adults as a ___, even though its members never live together.

household / army / ★ community / species

回饋：community 也可指具有共同連結的人群。這些程式設計者因共同背景與長期交流形成社群，不必住在同一街區。

AI 審查：通過

備註：題幹硬加「nonmilitary」「never live together」來排除選項。

- [ ] 核准　- [ ] 退回（原因：　　）

## 19. money（noun｜錢；用於付款與交易的貨幣｜語境選詞）

**教學** money 在一般用法中不可數，說 some money 或 much money，不說 a money 或 many moneys。數金額或硬幣時可說 ten dollars 或 three coins。save money 是存錢或省錢，依情境判斷。

用法：save money; spend money; some money；例句：I saved enough money to pay for the train ticket.（我存了足夠的錢來支付火車票。）

- [ ] 教學核准

**練習題 train** `lx:question:9c77b333-de91-4847-82d1-432a6759c7dc` r3

> A traveler returned from a trip with foreign notes and coins. Before her next journey, she took the remaining ___ to an exchange counter.

luggage / medicine / tools / ★ money

回饋：money 是錢。外國紙鈔與硬幣是剩餘貨幣，旅客把它們帶到兌換櫃檯轉換幣別。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:96634db5-a510-4a10-b9f4-03f4afb1d9c9` r5

> The parking meter will not accept a library card. Arun returns to his car, finds several coins, and feeds this ___ into the meter to pay for another hour.

permit / notice / ★ money / key

回饋：money 是錢。Arun 投入硬幣來支付停車費；硬幣是金錢，而借書證不能在這台機器付款。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

## 20. health（noun｜健康；身體或心理的狀況｜語境選詞）

**教學** health 通常不可數，說 good health 或 improve your health，不說 a health 或 two healths 來數人的健康。physical health 與 mental health 分別指身體與心理健康。

用法：good health; improve your health; mental health；例句：Regular sleep has improved my health.（規律睡眠改善了我的健康。）

- [ ] 教學核准

**練習題 train** `lx:question:dcb82b2b-7299-431d-9169-bb1bc5bf2282` r2

> After weeks in hospital with an infection, Dev's fever was gone and he could eat and walk normally again. His family was relieved that he had regained his ___.

wealth / beauty / status / ★ health

回饋：health 指健康。感染後退燒並恢復正常進食與行走，顯示健康恢復；沒有沿用身體檢查項目或睡眠例句。

AI 審查：通過

備註：回饋「沒有沿用身體檢查項目或睡眠例句」是流程殘留。

- [ ] 核准　- [ ] 退回（原因：　　）

**檢查題 check** `lx:question:8110d6c0-5583-4b1e-a388-78bdf9369425` r4

> The factory installed air filters to protect employees' ___ from dust that could damage their lungs.

privacy / ★ health / income / reputation

回饋：health 指健康；減少可能傷害肺部的粉塵，是為了保護員工的身體健康。

AI 審查：通過

- [ ] 核准　- [ ] 退回（原因：　　）

## 審完之後

下一個 session 會：寫入你的決定、套用你採用的提案（封存新版本並保留舊版）、重跑稽核，然後建第一個私人內容包。
