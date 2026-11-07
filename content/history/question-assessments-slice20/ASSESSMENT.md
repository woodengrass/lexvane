# Slice-20 independent semantic assessments

Evaluator: `claude-code:session_01EynPmDmZZcntYrnq6Y1gGn`, a separate Claude Code session; it did not author any of
these questions. Authors: the run receipts named in each row's provenance
(`content/jobs/.../receipts/*.json`, local only). Every row below is bound to
the sealed revision and `content_sha256` shown. Assessed 2026-11-07.

Scope: the three v3 semantic facets only (per-distractor plausibility, unique
answer, no leakage). This is not a full current review, family evidence or
owner approval. "Note" lines are non-blocking quality observations for the owner.

Plausibility rule used: a distractor passes when it fits the sentence
grammatically and is topically or collocationally credible, so that a learner
cannot discard it without understanding the target word. A distractor that is
meaningless in context, so the item is solvable by eliminating easy words,
fails.

Result: 37 of 40 pass all facets; 3 fail on distractor plausibility
(art train, history check, job train) and need new distractors.

## day (train)

`lx:question:5ca33009-0859-4c2e-a5cc-750d5675078c` revision 4, sha `ade4de21493bbb20d21d9cfd6b9a5cd86023004eef3c01eadf96a9a43618f2d2`, meaning_recognition. **PASS**

Stem: A wildlife camera ran continuously for three full days without a shutdown. Its service form asks for the total operating hours. Which total should the technician enter?

Options: option-a 12 operating hours, option-b 24 operating hours, option-c 72 operating hours, option-d 168 operating hours; key: **72 operating hours**

- option-a pass: 12 hours is the half-day confusion a learner who misreads day as daytime might pick.
- option-b pass: 24 hours is the one-day total a learner who ignores "three" would pick.
- option-d pass: 168 hours is a week total, a plausible unit confusion between day and week.
- unique answer: pass. Three full 24-hour days total 72 hours; no other option equals that.
- no leakage: pass. The stem uses "days" because the target is meaning recognition; the answer is a computed total, not a spelled form.
- note: Feedback ends with an unrelated sentence about rental deadlines (authoring residue).

## day (check)

`lx:question:7b2e4d2b-3d9b-4950-91c6-304d49637cd8` revision 6, sha `3787cfdeae203b9dc798415e7621db849df927dfb11dc1604f58e6978c6d279f`, meaning_recognition. **PASS**

Stem: A phone's photo album is grouped by day. Photos from both the morning and late evening of 8 May share one heading, while photos from 9 May begin another group. What unit does day name here?

Options: option-a A block of seven consecutive calendar dates., option-b Only the hours between sunrise and sunset., option-c One calendar date, from midnight to the next midnight., option-d A complete calendar month.; key: **One calendar date, from midnight to the next midnight.**

- option-a pass: A week-long block is a credible grouping unit for a photo album.
- option-b pass: Sunrise-to-sunset is the competing daytime sense of day and the most tempting wrong reading.
- option-d pass: Monthly grouping is a credible album unit and is excluded by the 8 May / 9 May split.
- unique answer: pass. Morning and late-evening photos of one date share a heading while the next date starts a new group, which fits only the calendar-date reading.
- no leakage: pass. The options paraphrase units; none restates the stem wording.

## year (train)

`lx:question:286a2493-4fa2-48f6-836e-c2ca7ffac2a1` revision 3, sha `6b2d682221bf4c743a22af27ae6f99e18bb7153f9b1d54475644bf0ccc32c664`, meaning_recognition. **PASS**

Stem: On May 6, 2026, Mina planted a tree and promised to photograph it again exactly one year later. Which date should she put in her reminder?

Options: option-a May 13, 2026, option-b June 6, 2026, option-c May 6, 2027, option-d May 7, 2026; key: **May 6, 2027**

- option-a pass: One week later is a credible interval slip.
- option-b pass: One month later is a credible interval slip.
- option-d pass: One day later tests confusing year with day.
- unique answer: pass. Exactly one year after May 6, 2026 is May 6, 2027; the other dates are earlier intervals.
- no leakage: pass. The answer is a date, not the word year.

## year (check)

`lx:question:7e3b09f3-64b5-426d-b2eb-3514cde3a480` revision 3, sha `f13c8ee6c86c32fe3ea4782ec9b980dfbff54c39658232f2e92976f002c527a2`, meaning_recognition. **PASS**

Stem: At midnight on December 31, the crowd watches the date change from 2026 to 2027. Which message fits the start of the new year?

Options: option-a Another month remains before the calendar changes., option-b A second day has begun within the same numbered year., option-c The next annual cycle has just begun., option-d One more hour remains before the new calendar date.; key: **The next annual cycle has just begun.**

- option-a pass: A month-remaining message is a credible misreading of the calendar change.
- option-b pass: A new day within the same year is the main competing reading of midnight.
- option-d pass: An hour-remaining message is a credible timing confusion.
- unique answer: pass. The year number changes from 2026 to 2027, so only a new annual cycle fits.
- no leakage: pass. The stem says "new year", which signals the context but does not paraphrase option-c; the item is easy rather than leaked.
- note: Very easy item; the stem phrase "the start of the new year" nearly states the answer.

## science (check)

`lx:question:4b5bedbf-92dc-4e2c-aa1c-62e1508ecd31` revision 6, sha `af3221b21bee493a9fcd9616fd66297b71d649c699a85a29245eb1a2d38987b8`, meaning_recognition. **PASS**

Stem: At an exhibition of old thermometers, an audio guide says, "These instruments helped science develop." What does science mean in this sentence?

Options: option-a The systematic study of the natural world using evidence., option-b The preservation of a community's inherited customs., option-c The creation of imagined characters and stories., option-d The organization of buying and selling goods.; key: **The systematic study of the natural world using evidence.**

- option-b pass: Cultural preservation is a credible museum-related field.
- option-c pass: Fiction writing is a credible alternative field definition.
- option-d pass: Commerce is a credible alternative field definition.
- unique answer: pass. Thermometers as instruments that helped a field develop fits only the evidence-based study of nature.
- no leakage: pass. Definitions are paraphrased; the word science appears because the item is meaning recognition.
- note: Feedback contains an unrelated phrase about choosing event sessions (authoring residue).

## science (train)

`lx:question:b3c8c6bd-0e1e-40f9-90b7-764421a2654a` revision 6, sha `6581d85e311ac98bc3d47896d24b516d1a21d22f5ae40d09f1554bd85140a4bc`, meaning_recognition. **PASS**

Stem: Mara wraps identical ice cubes in different materials and measures how long each takes to melt. She repeats the trials before drawing a conclusion about the materials. Which subject is she applying?

Options: option-a History, option-b Music, option-c Literature, option-d Science; key: **Science**

- option-a pass: History is a same-category school subject.
- option-b pass: Music is a same-category school subject.
- option-c pass: Literature is a same-category school subject.
- unique answer: pass. Controlled, repeated melting trials describe experimental science only.
- no leakage: pass. The stem describes an experiment without using the word science.

## question (train)

`lx:question:2324b8cf-27f9-451f-a8bf-f57da5ea4844` revision 2, sha `221f55ef468b4ca9ea3ebadcef1cdd433fa1eb86d212fdefc34c24224b5579f9`, contextual_choice. **PASS**

Stem: During the radio call, Jo said, 'Is anyone still inside the warehouse?' Nobody replied, so she repeated the ___ more loudly.

Options: option-a promise, option-b warning, option-c greeting, option-d question; key: **question**

- option-a pass: promise is a speech act that can be repeated louder.
- option-b pass: warning is a speech act shouted in emergencies and is the most tempting distractor.
- option-c pass: greeting is a speech act that can be repeated.
- unique answer: pass. The quoted sentence ends with a question mark and seeks a reply, so only question fits.
- no leakage: pass. The quoted utterance is a question but the stem never uses the word question.
- note: Feedback mentions a bus-route example and an interview form, which is the scenario of the check item for this target (authoring residue).

## question (check)

`lx:question:40953897-6bc3-4ff7-a0c5-b573f29f0634` revision 2, sha `994335274145aa255e91188d1894572c06841696d9f5272edbff7e7246afe1b0`, contextual_choice. **PASS**

Stem: The interview form has a separate box for the applicant's reply beside every ___. Instructions and final decisions are printed on another sheet.

Options: option-a verdict, option-b instruction, option-c question, option-d signature; key: **question**

- option-a pass: verdict is a form-related noun and is excluded only by the decisions-on-another-sheet clause.
- option-b pass: instruction is a form-related noun and is excluded only by the instructions-on-another-sheet clause.
- option-d pass: signature is a credible form field.
- unique answer: pass. A reply box beside every item fits only question.
- no leakage: pass. The stem does not contain question or a form of it.
- note: Stem adds an exclusion sentence to rule out distractors; reads unnaturally.

## market (check)

`lx:question:43e7fdc6-57e6-4088-883d-be532a1a2742` revision 5, sha `a777e720ad16fcbace1cebd45b30b0a5ab0037243ea526af0413e39e2c469cf2`, contextual_choice. **PASS**

Stem: Customers keep mistaking a waterproof notebook for an ordinary one. Rather than change the notebook, the shop decides to ___ it as equipment for divers, using demonstrations held underwater.

Options: option-a assemble, option-b market, option-c recycle, option-d license; key: **market**

- option-a pass: assemble is a product-handling verb that fits the syntax.
- option-c pass: recycle is a product-handling verb that fits the syntax.
- option-d pass: license is a business verb that fits the syntax.
- unique answer: pass. Repositioning an unchanged product for a new buyer group with demonstrations is marketing.
- no leakage: pass. The stem does not contain market.

## market (train)

`lx:question:b425e032-b16b-4a5a-8713-a0a94255d436` revision 4, sha `d5ad15539ad175602b2305c32b80713221566fee57a8ad157a1f8565a16c3c3a`, contextual_choice. **PASS**

Stem: A software company let people use its new app free for a week, hoping they would then buy a subscription. It used the trial to ___ the app.

Options: option-a repair, option-b encrypt, option-c archive, option-d market; key: **market**

- option-a pass: repair is a software-company verb that fits the syntax.
- option-b pass: encrypt is a software-company verb that fits the syntax.
- option-c pass: archive is a software-company verb that fits the syntax.
- unique answer: pass. A free trial meant to lead to paid subscriptions is a marketing action.
- no leakage: pass. The stem does not contain market.

## business (check)

`lx:question:7d4deea2-bbec-4f9c-a795-6bf368984735` revision 4, sha `0a97c46d43efe073250f5f444ff20226a69b5ddd6ef58c7fe195eb0d0ef1f4de`, contextual_choice. **PASS**

Stem: A furniture studio adds an online ordering page. After six months, online orders account for half its ___, while the other half still comes from sales in the showroom.

Options: option-a business, option-b training, option-c research, option-d exercise; key: **business**

- option-b pass: training is an activity a studio could measure in halves.
- option-c pass: research is an activity a studio could measure in halves.
- option-d pass: exercise is a same-form noun; weaker but grammatical.
- unique answer: pass. Online orders and showroom sales are sales channels, so only business fits.
- no leakage: pass. The stem does not contain business.

## business (train)

`lx:question:da532e6d-8034-4d73-a22f-5733409699e4` revision 3, sha `ea256bf5cef56659aeb7c4d9907c0ae99708dcdb2c665b04abf7146f4e162a80`, contextual_choice. **PASS**

Stem: Customs officers halted the shipment until an unpaid import duty was settled. The delay interrupted the company's international ___, leaving its contracted deliveries unfinished.

Options: option-a business, option-b research, option-c training, option-d mourning; key: **business**

- option-b pass: international research can be interrupted and fits the syntax.
- option-c pass: international training can be interrupted and fits the syntax.
- option-d pass: mourning is grammatical but weak; kept because the other two carry the item.
- unique answer: pass. Import duty and contracted deliveries point to trade, so only business fits.
- no leakage: pass. The stem does not contain business.
- note: Feedback mentions road traffic and a countable company name that are not in this item (authoring residue).

## life (train)

`lx:question:46a50a14-b7bd-43ea-befd-93c0b0486790` revision 5, sha `6f7f4da0e600d0118ade0e7f47a9c0d5c40acd6d2cba3751fdc7c8b4a710bc9b`, contextual_choice. **PASS**

Stem: A pension agreement promises Rosa a monthly payment until she dies, even if she lives for another forty years. It guarantees payments for the rest of her ___.

Options: option-a lease, option-b journey, option-c illness, option-d life; key: **life**

- option-a pass: "the rest of her lease" is a real collocation and the strongest distractor.
- option-b pass: "the rest of her journey" is a real collocation.
- option-c pass: "the rest of her illness" is grammatical and topically near.
- unique answer: pass. Payments continue until she dies, which fixes the period as her life.
- no leakage: pass. The stem does not contain life.
- note: Teaching focuses on biological life (forms of life) while this item uses lifetime; both are inside the sense definition.

## life (check)

`lx:question:6a8dff44-26b2-43aa-99d8-a4d297a1092e` revision 7, sha `d0c88020bbf2fe32070a5f16bf4a67a6cf36521694ca39e09886dfd469cb4010`, contextual_choice. **PASS**

Stem: A baker mixes yeast into dough. As the yeast cells multiply and consume sugar, they release gas that makes the dough rise. Complete the baker's description of those living cells: 'This recipe puts microscopic ___ to work.'

Options: option-a friction, option-b gravity, option-c electricity, option-d life; key: **life**

- option-a pass: friction is a physical cause a learner might attach to dough rising.
- option-b pass: gravity is a physical cause a learner might attach to dough rising.
- option-c pass: electricity is a physical cause a learner might attach to a process.
- unique answer: pass. Only life names multiplying, sugar-consuming cells.
- no leakage: pass. The stem says "living cells", which supports but does not spell the answer.
- note: "puts microscopic life to work" is slightly unusual phrasing.

## answer (train)

`lx:question:32331447-9db8-4d16-a491-6558eea443c2` revision 4, sha `92f6488f775d3d4f959f0f23328582897c531b93a08deafb3286af2167722137`, contextual_choice. **PASS**

Stem: At the quiz table, the host asked, 'Which planet is closest to the Sun?' Lila pressed her buzzer to ___ the question and said, 'Mercury.'

Options: option-a repeat, option-b answer, option-c translate, option-d withdraw; key: **answer**

- option-a pass: "repeat the question" is a real collocation.
- option-c pass: "translate the question" is a real collocation.
- option-d pass: "withdraw the question" is a real collocation.
- unique answer: pass. Saying "Mercury" after buzzing in is answering.
- no leakage: pass. The stem does not contain answer.

## answer (check)

`lx:question:ca7391b0-e011-409e-856a-86d7fc33d465` revision 2, sha `660cc5057abd37da0c60bc89a50058719cedd2462bd772d956c9a6cc1e06c78b`, contextual_choice. **PASS**

Stem: The online form asks, 'Which entrance did you use?' To complete it, you must ___ by selecting the entrance you actually used; leaving the item blank does not count.

Options: option-a answer, option-b erase, option-c refuse, option-d sleep; key: **answer**

- option-b pass: erase is a form-related verb.
- option-c pass: refuse is a form-related verb that fits intransitively.
- option-d pass: sleep is grammatical but weak; kept because the other two carry the item.
- unique answer: pass. Selecting the entrance used is responding to the form's question.
- no leakage: pass. The stem does not contain answer.
- note: Stem adds "leaving the item blank does not count" to exclude distractors.

## art (check)

`lx:question:0cc4903f-f0f0-44f7-8100-0959c63cb7e7` revision 2, sha `652a744078156004dfa1475031b3bac0eac006f50054cf411b7d9ec53c71f25e`, contextual_choice. **PASS**

Stem: On an unused wall, residents arrange colored tiles into an image of their memories. The work is meant to express their feelings, not to sell anything, give directions or cover damage. They call it public ___.

Options: option-a transport, option-b advertising, option-c insurance, option-d art; key: **art**

- option-a pass: "public transport" is a strong collocation that tempts by form.
- option-b pass: "public advertising" is a real collocation.
- option-c pass: "public insurance" is a real collocation.
- unique answer: pass. A tile image made to express feelings is art; the stem excludes selling, directions and repair.
- no leakage: pass. The stem does not contain art.
- note: Stem lists exclusions explicitly ("not to sell anything, give directions or cover damage"), which makes elimination easy.

## art (train)

`lx:question:8e73bbfc-4af2-4b3b-b9eb-78bf4308c49b` revision 2, sha `3ce3a8540b9d21ca4b9dee45b31e616b7652730107598d0a6013e065e9d31cf7`, contextual_choice. **FAIL (distractor plausibility)**

Stem: After a fire threatened the artist's studio, conservators rushed in to protect the original ___, moving the finished portraits out before smoke damaged them.

Options: option-a law, option-b art, option-c war, option-d aid; key: **art**

- option-a FAIL: "protect the original law" makes no sense in a studio fire; a learner can discard it without knowing art.
- option-c FAIL: "protect the original war" makes no sense in a studio fire; trivially eliminated.
- option-d FAIL: "protect the original aid" makes no sense here; trivially eliminated.
- unique answer: pass. Finished portraits in an artist's studio are art; the answer is unique.
- no leakage: pass. The stem does not contain art.
- note: All three distractors are unrelated three-letter nouns. Needs new distractors such as design, furniture or equipment.

## history (check)

`lx:question:afecd769-4823-49d5-a519-1ba202128b9c` revision 9, sha `4c958b6f53e0adc9166c23b38aa9cdfc3cef830c03f4d54c0ba2c78943158135`, contextual_choice. **FAIL (distractor plausibility)**

Stem: The museum traces the ___ of diving equipment, from early metal helmets to the breathing systems used today.

Options: option-a weather, option-b balance, option-c history, option-d flavour; key: **history**

- option-a FAIL: "the weather of diving equipment" is meaningless; trivially eliminated.
- option-b pass: "the balance of diving equipment" is a credible equipment property.
- option-d FAIL: "the flavour of diving equipment" is meaningless; trivially eliminated.
- unique answer: pass. Tracing equipment from early helmets to today is its history.
- no leakage: pass. The stem does not contain history.
- note: Two of three distractors are unrelated; candidates: design, technology, safety record.

## history (train)

`lx:question:b128b18a-c7a1-48a8-99fa-ac88884dc0e5` revision 2, sha `3fc1f5b38bf156dfdae68db38b6d349a52a247ed8bf5950c400fea20a0a1f176`, contextual_choice. **PASS**

Stem: Restorers found arrowheads inside the castle's old walls. The discovery revealed a forgotten siege in the castle's ___.

Options: option-a climate, option-b cuisine, option-c history, option-d scenery; key: **history**

- option-a pass: climate is an aspect of a place.
- option-b pass: cuisine is an aspect of a place.
- option-d pass: scenery is an aspect of a place.
- unique answer: pass. A forgotten siege is a past event, so only history fits.
- no leakage: pass. The stem does not contain history.

## environment (check)

`lx:question:8f433bea-17e3-4852-b5dd-0fda0ccee31f` revision 5, sha `e54f352acf884742a24e2609ce6fe2de174310d42f9d8a0511fe714b30d75083`, contextual_choice. **PASS**

Stem: The greenhouse provides a warm, humid ___ in which tropical orchids can survive the winter.

Options: option-a environment, option-b experiment, option-c measurement, option-d observation; key: **environment**

- option-b pass: experiment fits a greenhouse context.
- option-c pass: measurement fits a greenhouse context.
- option-d pass: observation fits a greenhouse context.
- unique answer: pass. "a warm, humid ___ in which orchids can survive" needs surrounding conditions.
- no leakage: pass. The stem does not contain environment.

## environment (train)

`lx:question:cc009b68-552b-4550-992a-af994b1c7d97` revision 2, sha `841f64a84de303e30f861626f71613174185db512f56076889c59c126dd29042`, contextual_choice. **PASS**

Stem: After the eruption, ash coated the island's lake and shoreline, and fish disappeared from the shallows. Researchers returned to assess the damage to the island's ___.

Options: option-a government, option-b employment, option-c environment, option-d invitation; key: **environment**

- option-a pass: damage to an island's government is grammatical after a disaster.
- option-b pass: damage to an island's employment is grammatical after a disaster.
- option-d pass: invitation is grammatical but weak; kept because the other two carry the item.
- unique answer: pass. Ash on lake and shoreline and lost fish describe the natural environment.
- no leakage: pass. The stem does not contain environment.
- note: Feedback mentions a slogan and a cactus-habitat definition that are not in this item (authoring residue).

## experience (train)

`lx:question:13f1b7f1-792a-4cc1-9fc5-30bbc73899d3` revision 6, sha `61da7b54645c507cff53e8edef397018971ca8741455cf0c5a4366512758d0fd`, contextual_choice. **PASS**

Stem: An insurance company requires applicants for a claims examiner position to have at least five years of ___ in reviewing claims. Mara lists the eight years she spent doing that work at another firm.

Options: option-a funding, option-b insurance, option-c publicity, option-d experience; key: **experience**

- option-a pass: "years of funding" is a real collocation.
- option-b pass: "years of insurance" is a real collocation in an insurance context.
- option-c pass: "years of publicity" is grammatical.
- unique answer: pass. Eight years doing the work answers a requirement for experience.
- no leakage: pass. The stem does not contain experience.
- note: Feedback mentions comparing theory and practice, which is not in this item (authoring residue).

## experience (check)

`lx:question:481aa81a-2490-446a-b4ab-00d4628d2ccf` revision 10, sha `987e26f6482b33fe24049ea93352426a6cbc2604403bc098db576491b03a96eb`, contextual_choice. **PASS**

Stem: The young sailor understood every rule in the handbook, but lacked the ___ that comes from steering a boat through real storms.

Options: option-a permission, option-b equipment, option-c experience, option-d qualification; key: **experience**

- option-a pass: permission is something a young sailor might lack.
- option-b pass: equipment is something a young sailor might lack.
- option-d pass: qualification is the strongest near-synonym distractor.
- unique answer: pass. "comes from steering a boat through real storms" defines experience.
- no leakage: pass. The stem does not contain experience.

## problem (train)

`lx:question:17f16e2b-36bc-42ae-b04d-bc292d86346b` revision 2, sha `18b2f4cbe2869aead50e5c4f2b037c294efd3a164f1d51c8b16176525a19454c`, contextual_choice. **PASS**

Stem: The cake looked golden outside, but wet batter poured out when Tara cut it. She returned it to the oven to deal with the ___.

Options: option-a problem, option-b reward, option-c promise, option-d journey; key: **problem**

- option-b pass: reward is grammatical after "deal with".
- option-c pass: promise is grammatical after "deal with".
- option-d pass: journey is grammatical but weak.
- unique answer: pass. Unbaked batter is a difficulty to fix, so only problem fits.
- no leakage: pass. The stem does not contain problem.
- note: Feedback mentions equipment faults and scheduling that are not in this item (authoring residue).

## problem (check)

`lx:question:c8da43d4-e5a9-463e-a98f-c4afd36db7c6` revision 5, sha `36cccb81a88a80b710c8be51469bc2c6733f0c704103369fd9baad99dda3609f`, contextual_choice. **PASS**

Stem: A cracked irrigation pipe has become a serious ___ for the greenhouse: the seedlings are drying out before the repair crew can arrive.

Options: option-a success, option-b problem, option-c routine, option-d solution; key: **problem**

- option-a pass: success is the antonym distractor.
- option-c pass: routine is grammatical in the greenhouse context.
- option-d pass: solution is the strongest associative distractor.
- unique answer: pass. Seedlings drying before repair shows a difficulty, so only problem fits.
- no leakage: pass. The stem does not contain problem.

## language (train)

`lx:question:39927719-6821-4b14-a3ee-0afc98f81be9` revision 2, sha `691cacb5b78d64b51a9b5c3959dcb4af0cdd7984f4edd4037e3223b54c2b4884`, contextual_choice. **PASS**

Stem: When Olek changed the application's ___ setting from English to Polish, all the menu labels changed, but the buttons stayed in the same places.

Options: option-a currency, option-b province, option-c language, option-d festival; key: **language**

- option-a pass: currency is a real app setting.
- option-b pass: province is a real region setting.
- option-d pass: festival is grammatical but weak.
- unique answer: pass. Switching labels from English to Polish is the language setting.
- no leakage: pass. The stem names English and Polish but not the word language.

## language (check)

`lx:question:a63621bb-7594-42d7-b594-704fcc6ca1e2` revision 2, sha `daa76cb5245e23bc2ebebee60548b90108f8f6bc50032f5271c4ef3ced813c2b`, contextual_choice. **PASS**

Stem: The twins use signs instead of speech. Their signs form complete sentences with their own grammar; researchers recognize the system as a ___, not merely random gestures.

Options: option-a gesture, option-b noise, option-c language, option-d costume; key: **language**

- option-a pass: gesture is the strongest distractor because the stem mentions gestures.
- option-b pass: noise is grammatical.
- option-d pass: costume is grammatical but weak.
- unique answer: pass. A sign system with grammar and complete sentences is a language.
- no leakage: pass. The stem does not contain language.
- note: Stem adds "not merely random gestures" to exclude a distractor.

## music (train)

`lx:question:23003285-3da0-47fb-b84f-4a6ac70849fe` revision 2, sha `91b92aba0b9420a1bb0aeed21ffac6e72dab5659d68c954d262a171ceafdebc6`, contextual_choice. **PASS**

Stem: The film's chase scene felt strangely empty after its orchestral soundtrack was removed. The director restored the ___, and the rapid notes made the scene tense again.

Options: option-a static, option-b speech, option-c music, option-d silence; key: **music**

- option-a pass: static is a sound-related noun.
- option-b pass: speech is a soundtrack component.
- option-d pass: silence is the contrast distractor.
- unique answer: pass. An orchestral soundtrack with rapid notes is music.
- no leakage: pass. The stem says "orchestral soundtrack" but not music.
- note: Feedback mentions sorting piano and drum sounds, which is not in this item (authoring residue).

## music (check)

`lx:question:257df3e6-8aba-4ebe-af7a-3aab642e1b2b` revision 2, sha `f2196af1eca8c5feafed55567ee53ee3f080cc5abac199456f4a3fdce8cedf10`, contextual_choice. **PASS**

Stem: The choir performs without instruments. Its members sing in harmony from a score; the program describes their organized sounds as vocal ___.

Options: option-a noise, option-b music, option-c speech, option-d static; key: **music**

- option-a pass: "vocal noise" is grammatical.
- option-c pass: "vocal speech" is grammatical.
- option-d pass: "vocal static" is grammatical but weak.
- unique answer: pass. Singing in harmony from a score is music.
- no leakage: pass. The stem does not contain music.

## opportunity (train)

`lx:question:4f9b7f34-17d4-4024-a874-1e0e17e3e24a` revision 2, sha `d274b1d4f623bacc45b0053adca68da6f4609e6af326ba2c06a08085c89959a5`, contextual_choice. **PASS**

Stem: When the scheduled soloist withdrew, the conductor invited Amir to perform at the national concert instead. Amir accepted the ___ and began rehearsing that evening.

Options: option-a opportunity, option-b disappointment, option-c restriction, option-d disagreement; key: **opportunity**

- option-b pass: "accepted the disappointment" is grammatical.
- option-c pass: "accepted the restriction" is a real collocation.
- option-d pass: "accepted the disagreement" is grammatical.
- unique answer: pass. An invitation to perform that he accepts and rehearses for is an opportunity.
- no leakage: pass. The stem does not contain opportunity.

## opportunity (check)

`lx:question:ca5dba38-5a71-4965-8a90-fa90c1ee1ae9` revision 2, sha `dcdf9c5607e653bae40ca5ba7d7bf1d50f7a93abe60d29aa4070757fcfd0e434`, contextual_choice. **PASS**

Stem: Clouds finally part during the eclipse, letting the astronomers photograph it before it ends. The clear patch gives them a brief ___ to capture the event; it permits action rather than preventing it.

Options: option-a prohibition, option-b delay, option-c failure, option-d opportunity; key: **opportunity**

- option-a pass: prohibition is grammatical and is the contrast distractor.
- option-b pass: "a brief delay" is a real collocation and the strongest distractor.
- option-c pass: failure is grammatical.
- unique answer: pass. A clear patch that lets them photograph the eclipse is an opportunity.
- no leakage: pass. The stem does not contain opportunity.
- note: Stem adds "it permits action rather than preventing it" to exclude distractors.

## job (check)

`lx:question:04b5aa2f-f0f4-47e9-b32b-3f36dfe6cc36` revision 2, sha `ada3d4aa92e5c193b73f2cc14f437d25097f30357b6660a8f01ef111ab297f60`, contextual_choice. **PASS**

Stem: The restaurant permanently closed, ending Rosa's paid position there. She lost her ___, not merely a day's earnings.

Options: option-a pension, option-b job, option-c hobby, option-d license; key: **job**

- option-a pass: pension is a work-related loss.
- option-c pass: hobby is grammatical.
- option-d pass: license is a work-related loss.
- unique answer: pass. Losing a paid position when the restaurant closes is losing a job.
- no leakage: pass. The stem says "paid position", which defines job; acceptable for contextual choice but lowers difficulty.
- note: "paid position" in the stem nearly glosses the answer.

## job (train)

`lx:question:d2e48691-5eb9-4d04-9f10-f8ee05862b2b` revision 2, sha `ffe852cb0de170c4574fbe2f8d9cf4fde5981ce56830e1fa0c7021dcbc9f1d8c`, contextual_choice. **FAIL (distractor plausibility)**

Stem: Imani negotiated the salary and paid leave before signing the employment contract. Only then did she formally accept the ___.

Options: option-a map, option-b job, option-c bet, option-d toy; key: **job**

- option-a FAIL: "formally accept the map" after a salary negotiation makes no sense; trivially eliminated.
- option-c FAIL: "formally accept the bet" does not fit an employment contract; trivially eliminated.
- option-d FAIL: "formally accept the toy" makes no sense; trivially eliminated.
- unique answer: pass. Negotiating salary and leave and signing an employment contract leads to accepting a job.
- no leakage: pass. The stem does not contain job.
- note: All three distractors are unrelated short nouns. Needs work-related distractors (offer is too close to job); candidates: loan, lease, award.

## community (check)

`lx:question:0a1c63dd-7b85-463e-8d04-e477ac8de58e` revision 2, sha `552a1d8f4ed6b62af13290bb1f6271575dea36894350d5d90710ca1db4efd46b`, contextual_choice. **PASS**

Stem: Deaf programmers in different countries exchange advice online for years. They describe this lasting, nonmilitary network of unrelated adults as a ___, even though its members never live together.

Options: option-a household, option-b army, option-c community, option-d species; key: **community**

- option-a pass: household is a group noun and the main contrast.
- option-b pass: army is a group noun.
- option-d pass: species is a group noun.
- unique answer: pass. A lasting network with shared bonds and no shared residence is a community.
- no leakage: pass. The stem does not contain community.
- note: Stem adds "nonmilitary" and "never live together" only to exclude distractors.

## community (train)

`lx:question:9915cf55-1418-4246-a2dc-939e779de499` revision 2, sha `4c1352a7210cb80e0ad51ff0c05b892efadd171465824c13b704fb0d500c6d8d`, contextual_choice. **PASS**

Stem: After floodwater receded, residents from all over the village volunteered to clear mud from their neighbors' houses. The whole ___ joined the recovery effort.

Options: option-a orchestra, option-b community, option-c audience, option-d workforce; key: **community**

- option-a pass: orchestra is a collective noun.
- option-c pass: audience is a collective noun.
- option-d pass: workforce is a collective noun and the strongest distractor.
- unique answer: pass. Residents from all over the village acting together is the community.
- no leakage: pass. The stem says "village" and "neighbors" but not community.
- note: Feedback says this is "not a group by definition", which is authoring residue.

## money (check)

`lx:question:96634db5-a510-4a10-b9f4-03f4afb1d9c9` revision 5, sha `a85f6334afec587345332b70218d34f66e298847d6af0656fd3686a687f58da1`, contextual_choice. **PASS**

Stem: The parking meter will not accept a library card. Arun returns to his car, finds several coins, and feeds this ___ into the meter to pay for another hour.

Options: option-a permit, option-b notice, option-c money, option-d key; key: **money**

- option-a pass: permit is a parking-related item.
- option-b pass: notice is a parking-related item.
- option-d pass: key is a car-related item.
- unique answer: pass. Coins fed into a meter to pay are money.
- no leakage: pass. The stem says "coins" but not money.

## money (train)

`lx:question:9c77b333-de91-4847-82d1-432a6759c7dc` revision 3, sha `76a1af90b682a028f8ca631de927092d9eb3bc81c4231340f751d182eb623842`, contextual_choice. **PASS**

Stem: A traveler returned from a trip with foreign notes and coins. Before her next journey, she took the remaining ___ to an exchange counter.

Options: option-a luggage, option-b medicine, option-c tools, option-d money; key: **money**

- option-a pass: luggage is something a traveler takes somewhere.
- option-b pass: medicine is something a traveler carries.
- option-c pass: tools is grammatical.
- unique answer: pass. Foreign notes and coins taken to an exchange counter are money.
- no leakage: pass. The stem says "notes and coins" but not money.

## health (check)

`lx:question:8110d6c0-5583-4b1e-a388-78bdf9369425` revision 4, sha `bbe3ba8c87958a2a2d8bc180f090cd668c06b0f74bbbc903a0bd81896bb2aba8`, contextual_choice. **PASS**

Stem: The factory installed air filters to protect employees' ___ from dust that could damage their lungs.

Options: option-a privacy, option-b health, option-c income, option-d reputation; key: **health**

- option-a pass: "protect employees' privacy" is a real collocation.
- option-c pass: "protect employees' income" is a real collocation.
- option-d pass: "protect employees' reputation" is a real collocation.
- unique answer: pass. Dust that damages lungs threatens health.
- no leakage: pass. The stem does not contain health.

## health (train)

`lx:question:dcb82b2b-7299-431d-9169-bb1bc5bf2282` revision 2, sha `e6f351a669936f70f16586588fbe7be721beb0ad07547011f6a0ff7484c9c53b`, contextual_choice. **PASS**

Stem: After weeks in hospital with an infection, Dev's fever was gone and he could eat and walk normally again. His family was relieved that he had regained his ___.

Options: option-a wealth, option-b beauty, option-c status, option-d health; key: **health**

- option-a pass: "regained his wealth" is a real collocation.
- option-b pass: "regained his beauty" is grammatical.
- option-c pass: "regained his status" is a real collocation.
- unique answer: pass. Recovery from infection is regaining health.
- no leakage: pass. The stem does not contain health.
- note: Feedback mentions body-check items and sleep examples that are not in this item (authoring residue).
