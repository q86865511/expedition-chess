# PROGRESS — 遠征棋 (Expedition Chess)

> PVE 自走棋 Roguelite。本檔記錄專案進度;規格的單一事實來源是 `docs/game-architecture/`。

## 目前狀態

G2 `difficulty-curve`（`codex/g2-difficulty-curve`，本地 commits、未 push/PR）Phase 1
實作完成：六項機制（act 縮放、三幕 Boss、多敵編成、trait 階梯、池重標、challenge
回鏈）＋觀測性＋per-act gate 全數落地；3k screening fresh gate **PASS**（candidate
`balance.g2.041458b08bb5`、勝率 tempo 65.7%／economy 23.5%／synergy 84.1%、act1/act3
皆有淘汰）、fresh All 1,193/1,193、10k soak passed。T11 雙 fresh reviewer 進行中；
大樣本（10k/30k）依裁決屬 Phase 2。AC-032 維持 `PENDING_EXTERNAL`。

## 已完成

- [2026-08-07] 🩹 UI／美術／中文化整修 Phase A 可玩性止血 — 營地 compose
  預設指揮官 0／挑戰 0、`allow_reselect` 與 challenge 上限同步；RUN_PREPARE 18 個
  動作改為四組兩欄分頁，`prepare.start`／`run.menu` 固定可及；錯誤呈現改讀
  diagnostic `source_code`，設定成功清空雙狀態面，未知碼落在地化泛用訊息；地圖
  `map.select`／`map.confirm` 語意修正；全 production 畫面新增高對比焦點框；CSV/raw
  與 bootstrap SHA 同步。fresh `-Suite ExpeditionSoak` 10,000 seeds／0 failures，最終
  `-Suite All` exit 0（303 scripts、1200/1200 tests、24857/24857 assertions、
  failures/errors/orphans 皆 0）。隔離 APPDATA 實機以 OS 滑鼠走完主選單→營地→地圖→
  備戰→開始戰鬥，Tab 外框可見、讀回截圖無裸 key；既有 commit-before-present 在
  相鄰 10 ms 幀由備戰直接結算回地圖，無可見 RUN_COMBAT 幀，已如實保留前／後證據。
  詳見 `specs/ui-art-refresh/evidence/phase-a/README.md`。
- [2026-08-06] 🎯 G2 `difficulty-curve` Phase 1 實作完成（T01～T09） — 解除平衡迴圈
  結構性天花板六項機制：per-act 敵方成長縮放（DC-REQ-001）、三幕 Boss 決定性映射
  fail-closed（DC-REQ-002）、五個 encounter 多敵編成（DC-REQ-003）、12 trait 三階
  遞增 effect（DC-REQ-004）、tier-1 池 faction 覆蓋重標（DC-REQ-005）、challenge
  run-op 三桶 gate 回鏈（DC-REQ-006）；另補 driver 逐幕觀測性與 stable ID 計數
  （DC-REQ-007）、`BALANCE_ACT_ELIMINATION_FLAT` gate 雙實作 golden 一致性
  （DC-REQ-008）、曲線生效快篩三層（T09）。期間並修正 tempo/synergy XP 評分退化
  （commit `b2c7895`）與 `act_curve` 型別契約（`20db291`）。3k screening fresh gate
  **PASS**（candidate `balance.g2.041458b08bb5`、`gate_reasons=[]`、3,000/3,000
  terminal、150/150 replay 零 drift、`act_curve` 顯示 act1/act3 皆有淘汰即跨幕梯度已
  生效、勝率 tempo 65.7%／economy 23.5%／synergy 84.1%）；fresh `-Suite All`（Gut
  1,193/1,193、0 failures）與 10k ExpeditionSoak（10,000/10,000 passed）皆綠。
  BP-SI-001／004／005 與 BP-SI-006(i)(ii) 標 RESOLVED，BP-SI-002 續 OPEN。三輪 3k
  跑批教訓：session 需能撐過 8+ 小時單分片（16 分片並行分攤）、
  `run-sharded-cohort.ps1` per-shard timeout 預設 12h 需視工作量另傳更大值、XP 修正
  後單 case 時長翻倍（~159s／case）使大樣本成本估算需同步上修。詳細證據見
  `specs/difficulty-curve/evidence-index.md`；T11 兩份獨立 review 待執行。
- [2026-08-04] 🚢 G2 `balance-playtest` 合併 — PR #9 MERGED @ `master@24edea9`
  （16 commits、222 檔、+12,637/−489）。切片閉環；第 3.5 片 `difficulty-curve`
  自該基線開分支，計畫經使用者核可（三件套與實作概括授權）。
- [2026-08-04] ✅ G2 `balance-playtest` Phase 0 雙審閉環 — 兩位獨立 reviewer 首輪各
  10 條 findings（NOT APPROVED）→ 使用者裁決全修 → 四工作包並行修復＋主迴圈補丁 →
  閉環複核 **雙 APPROVED**。期間實證並修復新立案 BP-SI-007（`Array[StringName]`
  裸 `sort()` 依 interned 指標序＝隱形亂源；8 個 RNG 池點＋1 處 presentation 改
  `StableNameSort` 字典序，使用者授權 domain 修正；同 seed 戰局自此改變，3k #2
  凍結快照不作回歸對照）。F07 審查假說經實測否證（to_ascii_buffer 映非 ASCII 為
  0x20 本即拒收），仍施防禦性硬化。最終 fresh All 1,156 tests／0 failures、
  10k ExpeditionSoak 10,000/10,000 passed。四個分類 commit（43c206d/ebbcf50/
  f66a32b/a63a3a8），停在 push 硬停點。審查原文：
  `.pipeline/balance-playtest/reviews/phase0-final-review-{A,B}.md`。
- [2026-08-04] 🧪 G2 `balance-playtest` Phase 0 證據收尾 — tier2+ 入樣兩來源一致
  （277 selections／230 cases／13 units；tier5=0）、NUL 分隔符最小修正後 8 程序
  24/24 replay digest 與 frozen 3k #2 完全一致。Final source `6b072f8` 的 All 為
  9 steps、GUT 1,126 tests／22,224 assertions／0 failures/errors/orphans、NUL 0；
  ExpeditionSoak 10,000 seeds／10,000 cases／10,000 pool checks、64 replays、40,000
  build operations、0 failures。Windows RC 三程序 start/save/restart/load/natural terminal/
  abandon 全通過，兩份 report codec read-back、PCK 2,988 files／禁入 0、ZIP 四檔與 SHA
  read-back 通過。證據見 `artifacts/rc/phase0-final-evidence-summary.json`；狀態仍待雙審與
  使用者確認，不宣稱整片完成。

- [2026-08-03] ⏸️ G2 `balance-playtest` Appendix C 修正中途暫停 — 首輪 3k
  為 3000/3000 terminal、150/150 replay 零 drift，但 economy 0 勝與 build selection
  dominance 使 Gate FAIL。已落地 economy 補人口／滿利息後買 XP、Boss HP>0 retry、
  faction≥2 build 歸因、動作計數／逐幕 stable-ID 快照、verdant 30→20、shop tier 階梯，
  並追加 BP-SI-004～006。第一次 24-case 重跑三策略皆於開局 fail-closed
  `SHOP_CONFIG_INVALID`；進一步定位 `.tres` scripted subresource runtime 欄位讀取與註解位置。
  暫停前已把無效 top-level 註解移至 `[resource]` 末端並加入 runtime assertions，**尚未重驗**；
  第二輪 3k 未啟動。精確接手點見
  `.pipeline/balance-playtest/PAUSE-2026-08-03-appendix-c.md`。

- [2026-08-02] 🟡 G2 `balance-playtest` 8-shard 校準與可重算 proof gate —
  `BalanceBotCaseResult`／report 已加入 authoritative final phase、route/completed-node、battle
  settlement receipt 與 reward receipt digest sequence；replay digest 同步涵蓋 terminal proof。
  修正通關判定為 21 節點且 HP>0（途中允許戰敗），新增全勝／全 fallback／ending-gold 恆定
  三條回歸 gate。`run-sharded-cohort.ps1` 以 `seed_index % shard_count == k` 決定性切割，
  合併時重算 cohort world、proof、replay sample 與 dominance，不信任 shard 局部統計 gate。
  2-seed／2-shard smoke 產出 6/6 cases、3/3 replay、0 drift，僅因 sample minimum 預期 FAIL。
  最終 24-case／8-shard 校準 primary 平均 64.402 秒、replay 71.149 秒，相對單程序
  56.429 秒 slowdown 14.13%，依裁決維持 8 分片；24/24 terminal／proof、0 failed seed，
  source freeze `716e9a324aae2f95c493ada5fde7ea4e390ad10507bc1bd7db9d4d1e4b3ec477`。
  3k screening 仍未宣稱完成。

- [2026-08-02] 🟡 G2 `balance-playtest` rewrite Part A～C／效能預量測 — 正式
  RunController composition 已走完整 21-node terminal；修復 51 檔／66 處 operation mode、
  global source lifecycle 與三個漏列 equipment effect，Content／Boss first-tick guards 綠。
  candidate ID 改由 tune digest 衍生並 append-only 留存；session report schema 2 降時戳精度、
  path-like fail-closed、三 terminal 分流。replay 依使用者裁決改 `seed_index % 20 == 0` 的 5%。
  六筆 primary 平均 56.429 秒，三筆 replay 平均 57.890 秒，5% 加權約 59.323 秒/case；
  3k 單程序理想估計 49.44 小時，等待分片裁決，未宣稱 screening 完成。

- [2026-08-01] ⚠️ G2 `balance-playtest` 舊 provisional evidence（rewrite 後撤銷）— 10,000 shared seeds ×
  3 strategies＝30,000 cases，三策略各 10,000 terminal／wins、0 failed seeds；fresh All
  1,103/1,103 tests（22,105 asserts）與 10k ExpeditionSoak PASS。Windows x86_64 ZIP
  fresh-profile boot 無 ERROR，SHA-256 `6b618627d749b2861afd88b3d2a0bb519abb221dffe072bc102b7ef28fb0b840`。
  但 balance driver 仍只跑每幕代表戰鬥，且 RC 尚缺互動式完整局 smoke，故本片不得 closure。
- [2026-08-01] ⛔ G2 `balance-playtest` 雙獨立 implementation review — 兩位唯讀
  reviewer 一致判定 NOT APPROVED：full-expedition/formal settlement 未落地、strategy run_id
  破壞 shared world cohort、bot action 未實際套用、RC 僅 boot smoke；另有 candidate/TUNE、
  report privacy/abandon、Gate proof 與 source-manifest findings。完整裁決見
  `specs/balance-playtest/implementation-review.md`；Git gate 保持封鎖。

- [2026-08-01] ⚠️ G2 `balance-playtest` 舊 3k screening（rewrite 後撤銷）— production bootstrap／pinned
  catalog／encounter compiler／battle rules／BattleSimulation 以 1,000 shared seeds ×
  tempo/economy/synergy 完成 3,000 strategy-seed cases；全數 terminal，無 replay drift
  或 failure seed，20pp selection／win-rate dominance Gate 通過。Candidate 與 TUNE digest、
  BalanceBotReport v1、PlaytestSessionReport v1 已產生；AC-032 保持 PENDING_EXTERNAL。

- [2026-08-01] ✅ G2 `content-production` 圖像／音訊最終閉環 — Claude reviewer
  一次審完 44 個候選並全數 ADOPT；ledger 回寫為 44 adopted＋14 rejected，
  inventory 與 Camp/shared production 全部綁定 adopted source。正式角色輸出為
  44 portraits、44 個 240-frame atlases、44 份 72-animation SpriteFrames；
  音訊依 R9 重生為 5 首 24 秒 loop＋21 SFX（48kHz/stereo/OGG q0.5），
  peak/seam/bus 由實際解碼驗證。fresh Wave 4、Wave 4B、Content、Canonical、
  Import、Smoke、RunnerContract、Gut 281/1093、10k soak 與 All 全綠；acceptance
  21＋1 全 PASS、`fully_closed=true`。工作樹保留未提交，未跑 TUNE／30k。

- [2026-08-01] ✅ G2 `content-production` Claude 接手完成實作與 T25 雙審閉環 —
  接手 codex 暫停點後依序完成:node runtime digest 修正驗證(`"<kind>_"+64hex`
  權威格式)、全 Gut 76 紅收綠(validator regex 同步、EffectDef v2 契約同步、
  choice 交易鏈適配等)、SFX 21 名對齊 R9(改名對映,使用者裁決)、Spec API
  契約 9+2 條修正、T24 acceptance 證據表(21+1 列,V/P/B 分類+fully_closed
  誠實語意)、NUL 噪音根因(u0000 字面量)修除。T25 三輪:R1(Claude)3H/6M/5L→
  H/M 全修(dismantle/exit/ack 命令補全、exact payload 11 拒絕碼、bootstrap
  fail-closed、nonce 改 RngService);R2(Claude+codex)4 Blocker+N1-N4→全修
  (validator receipt/transaction 逐欄綁定、production codec2→3 migration port
  接線+allowlist 硬化、canonical_set 比較器根因、ack 三路可達、catalog seal);
  R3 closure:Claude APPROVED、codex B1-B3 CLOSED、B4(mapping 套用語意)以
  886395b 關閉(ALIAS 改寫/TOMBSTONE 移除/ledger-bound fail-closed)。
  證據:`.pipeline/content-production/reviews/t25-round{1,2,3}-claude-reviewer.md`、
  `artifacts/test/content-production-acceptance.json`。

- [2026-07-31] ⏸️ G2 `content-production` 實作中途暫停 — 工作樹停在
  `codex/g2-content-production`，全數變更未提交，未 stage／commit／push／PR。
  SDD 雙審已在第三輪達 Blocker/Major 0；codec 3、schema 4／allowlisted
  migration、三份歷史 fixture、44 組正式單位內容、14 組 node choice、
  production PNG/atlas/OGG/provenance，以及 RUN choice overlay／tooltip
  consumers 已進工作樹。最近有效綠燈包含 Content、presentation content
  bootstrap、Wave 5 choice confirmation、Wave 5B tooltip、build-items 與
  economy/reward targeted suites。最後新增的 treasure outcome regression
  揭露 runtime node ID 被誤當 Stable ID；已將 pending／receipt／service
  validator 改為 64 字元小寫 digest，但依使用者要求立即暫停，**修正尚未
  重跑驗證**。續接點與命令詳見
  `.pipeline/content-production/PAUSE-2026-07-31.md`。
- [2026-07-31] ✅ G2 `content-production` branch baseline —
  PR #5 `MERGED @ 9362e7d`、PR #6 `MERGED @ 5e78ccf`；由乾淨的
  `master@5e78ccf` 建立 `codex/g2-content-production`。實作前 fresh baseline：
  All exit 0、Gut 1000/1000、Content 39/39、presentation static gate
  `ok=true`／zero issues。
- [2026-07-30] ✅ G2 UI 審查 findings 全修正（branch `fix/g2-ui-review-findings`，4 commits）—
  使用者裁決全修。H1 正式路徑戰鬥驅動器（_process 播放時鐘＋自動 SETTLE→REWARD，
  含指揮官被動 pin/claim_scope 兩個前置缺陷）、H2 session↔coordinator 解綁、
  H3 常駐狀態列錯誤呈現（pre/post-commit 前綴）、H4 star 欄位；M1～M9 與 L3～L8
  全數處理（L1 判誤報仍做結構防護、L4 確認真 bug 已修）；L7 衍生的 Spec 公開 API
  Dictionary 違規以 SettingsStoragePort/Result 具名型別修正。新增測試 40+（含變異
  驗證）。fresh reviewer 全 diff 審查再抓 11 條（F1 狀態列被蓋住＝H3 未真封、
  F2 recovery modal 死結等），修復輪逐條處理（F4 新增 APP_ROUTE_FALLBACK route、
  F7 核實 router discard 洩漏並修）。最終全量 All suite fresh exit 0
  （Gut 1000/1000、Spec 全過）、PUI static gate 綠。證據：`.pipeline/reviews/`。
- [2026-07-30] ✅ G2 `presentation-ui` merge 後獨立 UI 審查（Claude 四維度）—
  PR #5 已 merge（9362e7d），主樹 fast-forward 後跑 All gate 全綠（Gut 945/945、
  10k ExpeditionSoak fresh 重驗）。審查產出：高 4（正式路徑無戰鬥驅動器致 COMBAT
  死結、session↔CombatCoordinator RefCounted 互持洩漏、UI 無錯誤呈現面、rarity
  非色彩線索真實資料下永不渲染）、中 9、低 8、非必改 6；R16 八群組 fresh 驗收
  4 CLOSED／3 PARTIAL／1 證據 PARTIAL；初勘 4 項嫌疑判誤報。完整報告：
  `.pipeline/reviews/g2-ui-review-final.md`（本機）。findings 已由使用者裁決全修，
  並透過 PR #6 merge 回 master（5e78ccf）。
- [2026-07-30] ✅ G2 `presentation-ui` R16 findings closure／T15 final —
  R16 architecture 2H/1M 與 behavior 4H/2M 全部採納；移除 split retry、補真
  world hit、雙方 inspection、COMBAT overlay、authoritative PREPARE report、
  formal PREPARE/COLLECTION/RESULTS loops、15-editor focus 與 typed non-color/
  damage semantics。R16 targeted 13 tests 全綠；final Gut 243 scripts、945/945
  （16295）、Spec 3696、All exit 0、10k ExpeditionSoak zero failures、static
  gate zero issues；42 manifests／155/155 references match。使用者明示不做
  R17／再次雙審；原 R16 `NOT APPROVED` 歷史報告與 closure table 均保留。
  T15 與 19 owning AC 已完成；2026-07-30 使用者已通過 Git 發布 gate。
- [2026-07-29] 🟡 G2 `presentation-ui` R15 修正／T15 fresh candidate — R15 的 retry root transaction、terminal no-fail seal、真 viewport/UI ownership、typed formal controls、production focus/modal、zero-size fail-closed、double-fault stale callback 與 evidence drift 八群已修正。有效 green：architecture 1/1（11）、terminal 3/3（62）、behavior 8/8（152）；完整 Gut 239 scripts、932/932（16123）。人工 runtime read-back 另以有效 red 修掉 4:3 long typed label overflow 與 125/150% CJK/action overlap，最終 10/10 PNG zero issues；static gate zero issues；ExpeditionSoak 10000 seeds／40000 operations zero failures；39 manifests、151/151 references match。下一步 fresh R16 雙審；最多到 R18，Git 與下一切片仍封鎖。
- [2026-07-29] 🟡 G2 `presentation-ui` T15 automation/supplemental green — 新增正式 CAMP 五設施、RUN_PREPARE/COMBAT/REWARD 非 terminal composition，補 pinned definition/catalog clone、authoritative population TUNE projection，以及 Windows OpenGL runtime screenshot matrix。supplemental 3/3（256）＋4/4（183），runtime 12/12 PNG 零 issue；final 九組 suites 全 exit 0，Gut 836/836（14072）、Spec 3667、10k soak 40000 build operations。static gate 零 issue，21 manifests 84/84 entries match。Godot access violation 已定位為不存在 log parent；dummy headless null texture/orphan與空白首幀均有撤銷／修正證據。R12/R13/雙 implementation review 未完成，T15 仍不勾。
- [2026-07-29] 🟡 G2 `presentation-ui` T15 fresh baseline＋AC audit — fresh Gut、Smoke、Content、Canonical、Combat、Expedition、Spec、All、10k ExpeditionSoak 九組皆 exit 0；Gut 829/829（13601 assertions）、Spec 3662、soak 10000 seeds／40000 build operations／零 failures。T13 validator 36 hashes／0 issues／user-approved，T14 production gate 零 issue，19 active manifests 74/74 entries 相符。19-row owning AC 初審未假造 PASS：發現正式非 terminal scenes、runtime screenshots 與 exact cross-layer evidence 缺口，已進 supplemental TDD；R12/R13/implementation reviews 仍未放行，因此 T15 checkbox 保持未勾。
- [2026-07-29] ✅ G2 `presentation-ui` wave5/T13 user-approved＋T14 green — T13 產出五角色 20 張 64×64 方向 sprite、5 portrait、3/4 營地、core UI、720p/1080p/1440p＋4:3/16:10 與四色覺 screenshots；deterministic asset validator 36 hashes／0 issues。使用者明示核可候選並接受 built-in ImageGen seed 不可取得的 provenance warning；完整 prompt/call id/處理參數/SHA 已留痕。T14 valid red 11/11，green 11/11（175）、6/6 manifest，正式專案 gate exit 0／零 issue。wave5 All exit 0，Gut 829/829（13601）、Spec 3662。wave6/T15 可開始；R12/R13/Git gate 未放行。
- [2026-07-29] ✅ G2 `presentation-ui` wave4/T10～T12 green — T10 viewport/input 4/4（225）、T11 playback/transcript 8/8（234）、T12 settings 4/4（295）、accessibility/error 8/8（362）、runtime integration 2/2（817）。補上四 concrete adapter、AppRoot SettingsService/AudioService typed port wiring、production load/fail-closed rebuild、locale/UI scale/四 bus apply 與 restart rebuild。runtime 首次 green 的 10 個 test-owned Node orphan 只以 `autofree` lifecycle cleanup 修正，舊 manifest 明確撤銷；最終五份 manifest 共 20 hash 全一致。首輪 All 唯一 Spec failure（public untyped helper）改為 private 後，最終 All exit 0：Gut 818/818（13426）、Spec 3662 cases，其餘 suites 全綠。rebuild adapter `void` 診斷傳播列 residual risk；R12/R13/Git gate 未放行。下一步 wave5 T13/T14。
- [2026-07-29] ✅ G2 `presentation-ui` wave3/T08、T09 component green — T08 完成 clone-only Collection browser、injected MENU exit、decoded/opaque recovery cancel 與 typed settings draft/port/error/focus，限定 4/4（59）；T09 完成 19-intent route allowlist、四項 irreversible exactly-once confirmation 與 clone-only read-only combat inspection，限定 3/3（121）。T09 首輪 green 的 captured integer counter 為無效測試，主迴圈改用 `Array[int]` 後把 production 暫移出 `res://` 重建 exact-hash red，再恢復 production 取得 final green；兩份 manifest 最終皆相符。wave3 All exit 0，Gut 792/792（11493 assertions），其餘 suites 全綠。broader scene composition 與 R12-A01/A02 terminal/results authority 未誤標完成；下一步 wave4 T10/T11 red。
- [2026-07-29] ✅ G2 `presentation-ui` wave3/T07 core green 與 hidden parse omission 修復 — 完成 15 條 production scene catalog/shell、staged read-only context、parent/generation subroute token、lease registry、stale live intent/navigation port、SceneRouter instantiate/bind-before-swap fault preservation，以及 AppRoot MENU/CAMP/RUN/RESULTS production route mapping；component 6/6（184）、integration 2/2（30）。主迴圈另拒收一輪「exit 0 但兩個舊 AppRoot scripts parse-failed」的假綠，將非 locked callers 同步至 typed StartExpeditionRequest、Boot→MENU 與 opaque recovery；最終 All exit 0，Gut 158 scripts、785/785 tests、11313 assertions，Smoke 10、Content 39、Canonical 5、Combat 2、Expedition 3、Spec 3630，零 parse/load/unexpected/orphan。R12-A01/A02 terminal/results integration 仍交 Claude，T07 不標整項完成。
- [2026-07-28] ✅ G2 `presentation-ui` wave2/T06 與整波收尾 — T06 鎖定 decoded/opaque repository identity/epoch/full-file-digest token、wrong/stale/replaced CAS、archive-before-clear 全 fault preservation 與 4×4 restart residue runtime matrix；無效首跑的 parser/orphan 不列紅證據，修正後有效紅 2 tests/155 assertions，production green 2/2（300 assertions）。RetainedRunRecoveryService、SaveRepository/StoragePort restart cleanup 與 AppRoot recovery wiring 落地；opaque 無 run digest，tmp 永不升格，R12-A02 仍標 review debt。wave2 最終 All exit 0；Gut 769/769（10987 assertions、0 failures/errors/orphans）、Smoke 10、Content 39、Canonical 5、Combat 2、Expedition 3、Spec 3628 cases 全綠。
- [2026-07-28] ✅ G2 `presentation-ui` wave2/T03、T05 — T03 完成 typed 四 bus atomic audio port/coordinator；原 test helper 與 fake public API 兩次不合格均明確撤銷舊 manifest 後重建，四項行為 assertions 不變，最終 4/4（93）。T05 完成固定 Boot→MENU、typed menu/continue/start/results/exit、repository identity/epoch、共享 Camp transaction、prepared capability 與 terminal handoff skeleton，限定 7/7（159）。修正 public Variant/Dictionary Spec failures、舊 Smoke/AppRoot boot 假設、opaque LoadResult invariant 與 discard 精確診斷後，All exit 0；Gut 767/767（10687 assertions）、Smoke 10、Content 39、Canonical 5、Combat 2、Expedition 3、Spec 3622 cases 全綠。R12 四項仍 unresolved。
- [2026-07-28] ✅ G2 `presentation-ui` wave1/T01、T02、T04 — 五份 behavioral tests 先紅後鎖定 SHA manifest，再完成 production content bootstrap＋210-key `zh_TW|en` catalog、schema-1 原子 SettingsRepository、24-intent RunPresentationSession/RunCommandFactory 與 Run/Combat Lab 薄包裝。主迴圈重驗 T01 7/7（464 assertions）、T02 4/4（403）、T04 12/12（55），五份 hash 全一致；wave-end All exit 0，Gut 764/764（10530 assertions、0 failures/errors/orphans）、Smoke 10、Content 39、Canonical 5、Combat 2、Expedition 3、Spec 3555 cases 全綠。R12 四項仍 unresolved，未執行 Git。
- [2026-07-28] ✅ G2 `presentation-ui` wave0/T00 — 有效 contract red 為 4 tests 中 3 個 assertion failures、parser/import 0；locked SHA `684bad…cadd13`。新增 AppActionResult、settings schema 1/port、run/session/playback、screen lease/capability 與 terminal handoff 等 35 個 compile-safe contracts；ResultInvariant Spec 契約修正後限定 GUT 4/4（276 assertions）、Spec 3481 cases、All 741 tests/9608 assertions 全綠。只完成 skeleton，無 runtime behavior。
- [2026-07-28] ⚠️ G2 `presentation-ui` review Gate override — 使用者明確指示 R12/R13 審查先跳過並繼續下一步；只放行本地 baseline/TDD/implementation，R12 四項仍 unresolved，Git/PR 與最終完成宣稱未放行。
- [2026-07-28] 📦 G2 `presentation-ui` R12 交接收斂 — 架構／行為雙審原文、4 項 Medium finding 與 proposed fixes 已同步 review-log、roadmap、PROGRESS、HANDOFF 及 `.pipeline`；使用者指定下一手由 Claude 修訂，fresh R13 雙審結果仍須先落檔。
- [2026-07-28] 📝 G2 `presentation-ui` R11 裁決回寫 — Exit root/UI-host tests 拆為兩個 wave manifest；T08 settings 改為 injected fake port component、T12 獨占 concrete coordinator 與 restart/四 bus production integration；T06/T08 分別鎖 recovery fault-preservation 與 cancel 零 dispatch evidence，等待 fresh R12。
- [2026-07-28] 📝 G2 `presentation-ui` R10 ownership 裁決回寫 — 使用者採納兩項整合建議：T05 成為 Exit root API／pending lifecycle 與 `--combat-lab` parse/route/bind/integrated smoke 的唯一 AppRoot owner；T01/T04/T08 收斂為 component／UI consumer，R1 追溯補 T04/T05，等待 fresh R11。
- [2026-07-28] 📝 G2 `presentation-ui` R9 裁決回寫 — 使用者採納三項 named-test coverage finding：Exit 改由可攔截 signal 且 runner-safe、`ABANDON_BOSS_RETRY` 納入 confirmation exactly-once 矩陣、`--combat-lab` exact dev allowlist 必須共用 production bootstrap/facade；已同步 requirements／design／tasks／review ledger，等待 fresh R10。
- [2026-07-28] 🧹 G2 worktree 整理與 R8 已知問題修正 — `codex/g2-presentation-ui` 從 ahead 1／behind 2 重放至最新 master，保留 checkpoint 並消除落後提交；`G2-R8-01` 已回寫 requirements／design／T07／T09／named lifecycle test，鎖定 guard 跨 repository unlock 的完整生命週期、六組重入 barrier、typed loser、零 save／route commit、state/route/lease 一致與 failure 後釋放。文件一致性稽查另修正 HANDOFF 的 S3 evidence 誤標；本項不等同 fresh R9 或 SDD 核可。
- [2026-07-28] ✅ S5 線合回 master — worktree 線 fd64ac2（三件套＋wave1~6）fast-forward 併入；合併後主樹 fresh gate 重驗：10,000-seed ExpeditionSoak exit 0、`-Suite All` exit 0（含 Gut/Combat/Expedition/Spec 全綠）。修復主樹 CRLF 假陽性（repo-local `core.autocrlf false`）。
- [2026-07-26] ✅ S5 `meta-progression` 完成（wave1～6／T01～T12） — schema 3 meta profile/run 欄位、指揮官與 challenge 雙軌、claim_scope 真語意、圖鑑 discovery union、Camp/Start/Meta exactly-once 原子交易、五設施 ViewModel、AppRoot 正式 composition 與 Camp/Run/Results 灰盒均落地；W5 R2/R3 修正 retained run fail-closed、expected-run-id 明示棄置、canonical readers／starting pack、兩種 combat pending resume 與 FakeSaveStorage 隔離。W5 R4 雙審零未決。最終 Gut 737/737（9332 asserts）、10k ExpeditionSoak 與 All exit 0；S5-AC-001～014 為 14/14 PASS。
- [2026-07-24] ✅ S4 `build-systems` 完成（wave4：T11 Build Lab／T12 整合驗收） — Build Lab 灰盒以真雙 pack＋ContentRegistryReceiptAdapter 完整接線（五種構築操作經 ViewModel、save/load 往返、Smoke 綠），並揭露修復兩個內容缺口（經濟 config 必填欄位、meta_reward_table 佔位）；T12 落地死亡不重算整合案例、claim_scope S4 語意（always，validator＋builder 雙層封洞）、四 service 世代守衛、生產層 relic 接線補洞、soak 織入四步決定性構築操作。雙審（Opus＋Sonnet）W4-F1~F9 裁決全數落地。最終 fresh gate：Gut 399/399（6226 asserts）、10,000-seed soak（40,000 構築操作）exit 0、`-Suite All` exit 0。逐 AC 證據落檔 `specs/build-systems/implementation-review.md`。
- [2026-07-23] ✅ S4 wave3（T05 overflow／T09 伴生內容／T10 ViewModel） — ResolveOverflowCommand（tray 逐件 equip/forge/abandon、具名 error）＋overflow 硬 gate 集中進 validator 最終防線（COMBAT/MAP/RESULTS 期 tray 必空，service 早退保留）＋出售帶裝棋 crash/load 回歸；`content/packs/vertical_slice/` 100 個 TUNE 佔位 .tres（32 棋子羈絆對應含 4 隻三標籤），完整雙 pack manifest 0 issue、digest 可 pin；`presentation/viewmodels/` 四件套（讀端 deep-clone、寫端經 dispatch、pinned catalog 接線）＋HANDOFF 消費契約更新。雙審三份（Opus×2＋Sonnet）W3-F1~F8 裁決全修（F7 除外）。Gut 376/376、Spec 3274 cases、`-Suite All` exit 0、10000-seed soak exit 0。
- [2026-07-23] ✅ S4 wave2（T02 戰鬥編譯器／T03 鍛造／T06 遺物作用點／T08 內容 pack） — BattleSetupSourceCompiler（羈絆計數/戰前快照/裝備/battle 遺物編譯，preview 與開戰同源）；ForgeEquipmentCommand（21 配方、自配、serial/overflow）；遺物 run-layer 作用點（income add_gold／shop 折扣拆新 kind shop_discount／map route 覆寫無新 entropy／settlement 治療與減傷，槽序升序、不經 EffectResolver）；首批正式內容 `content/packs/build_systems/` 90 個 .tres（12 羈絆/6 零件/21 裝備/16 遺物四類/拆卸道具/效果）。雙審（Opus＋Sonnet）W2-F1~F3/F6 裁決全修：帶裝備開戰路徑修通（validator 依 design §4 對齊）、builder 拒不支援 intent、4 件死內容遺物修正、NORMAL/ELITE 規則數不變式。Gut 333/333、`-Suite All` exit 0、10000-seed soak exit 0。
- [2026-07-23] ✅ S4 wave1（T01 catalog 擴充／T04 裝備 command／T07 驗證器五規則） — BattleRelicRule＋ForgeRecipeTable（21 封閉、1/2 元形狀）＋RunRelicTable（typed intent）；EquipItemCommand／DismantleEquipmentCommand（ConsumableRuleTable 驗拆卸語意）＋validator「綁定物必為 EquipmentDef」不變式接入 RunController commit 路徑（含 catalog 世代守衛）；內容驗證器新增 unique_group／遺物四類覆蓋／effect scope／拆卸語意／零件發放五類規則。TDD 分代理紅綠證據齊備；Sonnet＋Opus 雙審 F1~F5 全數修復。Gut 275 tests／3993 asserts 全綠；`-Suite All` exit 0。
- [2026-07-22] 📄 交接分工與 S4 規格 — 確立 Claude（程式邏輯／架構／ViewModel 介面層）與 Codex（美術／UI 視覺／UX）分工並落檔 `HANDOFF.md`；S4 `build-systems` 三件套（requirements／design／tasks，12 任務 5 Gate）經逐段核可後落檔 `specs/build-systems/`。修正本檔 S4 名稱（原誤植 `content-systems`）。實作雙審改採 Sonnet 5＋Opus 4.8 兩獨立 session（使用者裁決，取代 Codex review）。
- [2026-07-22] ✅ S3 `economy-expedition` 階段 4～6與獨立複檢 — 完成戰敗扣血／幕補助／Boss 無收入重戰、勝利 scalar claim、標準／遺物 reward stage、棋子／物品／遺物 overflow、不可逆 RESULTS、最終 shop release 與戰鬥／非戰鬥節點離場；新增 Expedition Lab、`Expedition`／`ExpeditionSoak` runners 與 11 條 S3-AC evidence 聚合。T00R／T11B 第五輪均為 Blocker 0／Major 0／Minor 0。最終 `-Suite All` exit 0（187.5 秒）；GUT 228 tests／3681 assertions／0 failures／0 errors／0 orphans；Spec 3170 cases／0 failures；10,000-seed soak exit 0（213 秒）、10,000 pool-conservation checks、64 deterministic replays／0 failures；S3-AC-001～011 為 11／11 pass 且 `evidence_verified=true`。
- [2026-07-18] ✅ S3 `economy-expedition` 階段 0～3 — 建立三件套與 typed economy contracts，完成三幕七層決定性 `MapService`、節點收入／首次商店、generate／refresh／buy／sell／buy XP、有限卡池與 reservation 守恆，並接入 `RunController` copy-validate-save-swap。`-Suite All` exit 0（68.9 秒）；GUT 198 tests／3373 assertions／0 failures；Spec 3095 cases／0 failures。此紀錄不代表完整 S3，階段 4～6 與獨立複檢仍待完成。
- [2026-07-16] ✅ S2 `combat-core` — 完成 setup schema 2／content codec 2／save schema 2、棋盤人口與升星守恆、pinned encounter preview、純 `BattleSimulation`、`EffectResolver` 9／10／9／4 矩陣、typed event/result codec、combat transactions/replay 與灰盒 Combat Lab。`-Suite All` exit 0（62.9 秒）；GUT 190 tests／3115 assertions／0 failures／0 errors／0 orphans；canonical 5 cases／151 assertions；32v32／64 entity stress 通過。正式 `-Suite Soak -SeedCount 10000 -TimeoutSeconds 600` exit 0（249 秒）：10,000 seeds、0 failures、最大 22 ticks、3 個 result hashes、64 次 deterministic replay；`combat-acceptance.json` 18／18 pass。最終獨立複檢 Blocker 0／Major 0。
- [2026-07-16] 📄 架構 v0.2 與 S2 規格 — 補足整數戰鬥、效果 stacking、事件／結果、版本 migration 與 DEC-014；三件套通過 Gate A 後核可。repository 僅保存 Codex 最終實作複檢紀錄，不冒充 Claude 外部報告。
- [2026-07-13] ✅ S1 `foundation-core` — 建立 Godot 4.7／GUT 9.7.1 鎖定工具鏈、`Main/AppRoot` 與五個 Autoload、u64／Stable ID／RuntimeKey／PCG32 決定性核心、canonical battle setup codec、typed DTO、內容 registry／generation pin／完整 synthetic 內容驗證、版本化原子存檔、App／Run FSM 與 copy-validate-save-swap。`-Suite All` exit 0；GUT 73 tests／667 assertions／0 failures／0 errors／0 orphans；canonical 4 cases／141 assertions；content 39 cases；spec contract 1826 cases。`foundation-acceptance.json` schema v2 逐 AC 讀回證據，F/X/D 為 15／7／11，downstream 項目未假稱通過。
- [2026-07-13] 📄 架構規格核可 — 使用者確認 Claude 外部複檢完成；repository 未虛構 review report。12 章狀態改為 `v0.1 / Approved`，Manifest 升級 schema v2 並改用只涵蓋 12 章的可重算 aggregate SHA-256。
- [2026-07-13] 📄 R2 實作切片規劃 — 建立 `docs/implementation-slices.md`,將 74 REQ 切成 5 個可獨立實作/驗收的功能片(`foundation-core` → `meta-progression`),定義每片走 specs 三件套 + `/pipeline` 的銜接流程;切片藍圖與 §14 追溯矩陣 74 REQ 一對一。
- [2026-07-13] 📄 R1 專案初始化 — 建立 PROGRESS.md、專案層 CLAUDE.md、README.md,git init;技術棧定為 Godot 4.7 + GDScript。既有 `docs/game-architecture/` 架構規格(74 REQ / 78 AC / 追溯矩陣 / Claude 複檢契約)保持不動。

## 進行中

- G2 `difficulty-curve` T11：兩份獨立 implementation review、finding closure 與證據
  鎖定，停 Git gate 待使用者裁決。

## 待辦

- UI／美術／中文化整修（交 Codex）：Phase A 止血已完成實作與自動驗收，實機
  RUN_COMBAT 截圖受 commit-before-present 同幀結算阻塞；審核報告與四階段計畫位於
  `specs/ui-art-refresh/review-and-plan.md`（2026-08-07 實機截圖審核；含 4 個 P0
  可玩性 bug、視覺 0% 現況盤點、中文化剩餘四缺口）。後續為 Phase B Theme／
  字型、Phase C 資產接線、Phase D 中文化收尾。
- Phase 2：平衡迭代迴圈（TUNE 迭代＋每輪 3k screening）至收斂判準達標，之後跑
  大樣本（10k/30k × 24 分片，規模屆時裁決）作正式平衡基線。
- Phase 3：`performance-release`（效能／migration bridge／90 場真人 release gate）。
- 詳見 `specs/g2-roadmap.md` §9。

## 已知問題

- Fresh profile 的短戰鬥 transcript 會在 RUN_COMBAT 第一個可呈現影格即 exhausted，
  `SETTLE_BATTLE` 使畫面由備戰直接回地圖；Phase A 以 10 ms 間隔擷取 80 幀仍無可見
  RUN_COMBAT 畫面。這不阻擋「開始戰鬥」寫操作，但阻擋戰鬥畫面實機截圖，後續 UI
  phase 應檢查最短可見播放時間或首幀呈現契約。
- Combat／Expedition／Build／Camp／Run／Results Lab 仍是開發用灰盒，不是正式產品 UI；正式 production 美術與音訊已由 content-production 閉環，後續產品化 UX 依 roadmap 的剩餘切片處理。
- Godot 4.7 以 `--script` 執行 production runtime runner 時，程序 exit 0、report 10/10，但 stderr 固定回報 5385 ObjectDB／92 resources；verbose 顯示為 5277 domain `RefCounted`、92 GDScript、15 RegEx、1 GDScriptNativeClass，沒有 leaked Node／Control／Viewport。原始與 verbose logs 保留於 `.pipeline/visual/r15-production-runtime/`，列 runner shutdown 診斷而非隱藏。
- SaveRepository 依 SDD 採單程序同步交易；跨程序刻意共用同一 production save path 的 file lock／CAS 未納入本切片。
- `artifacts/test/` 是本機驗證輸出，不是正式遊戲資料；清理或重建不影響 canonical source。

## 重要決策紀錄

- [2026-08-04] G2 `balance-playtest` 使用者裁決：大樣本統計（10k/30k）自本切片移至
  Phase 2 平衡收斂後執行，本切片以 3k screening #2 gate PASS 作 screening 證據收尾；
  採用 Phase 0~3 執行計畫並新增 `difficulty-curve` 機制切片（`specs/g2-roadmap.md` §9）。
  理由：Act 2/3 難度曲線為機制缺失（BP-SI-004），修復前的大樣本數字必然作廢，
  先修機制再進平衡輪迴，收斂後的大樣本才是有效基線。
- [2026-08-01] G2 `content-production` T25 議決記錄項(可接受並記錄,非必修):
  M6 缺 choice set 的 event/rest/treasure 節點硬拒=刻意 fail-closed;
  L3 StableIdValidator 多段 id 放寬=刻意內容設計;L5 digest 大小寫/HashingContext
  容錯現況可接受;N5 ability trigger 閘涵蓋全部 effect_ids(日後加被動需調整);
  N6 exit 的 shop release 硬前置(現無可達失敗路徑);R3-3 跨 category ALIAS
  的 single-hop 檢查限制(現不可達);emergency catalog 為全量 keys 而非
  design 要求的 boot/recovery 子集(seal 已擋 production 誤用);map node
  generated_payload_digest 於 ALIAS 改寫後不重算(validator 僅驗格式,無反推路徑)。
- [2026-08-01] G2 `content-production` 音訊最終裁決：維持 R9 規格，不修改規格
  遷就舊輸出；5 music／21 SFX 已重生成為 48kHz、stereo、OGG Vorbis q0.5，
  music 固定 24 秒且通過 true-peak／loop-seam／bus gate。較早「只改名、不重生」
  條目為 closure 前歷史狀態。
- [2026-07-28] G2 `presentation-ui` 使用者 override：R12/R13 規格複審先延後，允許繼續本地 baseline/TDD/implementation；R12 findings 不視為 resolved，R13 與 Git/PR gate 未豁免。
- [2026-07-28] G2 `presentation-ui` R12 後續 ownership：使用者指定四項 finding 保留待修，交由 Claude 完成；R13 雙審原文與彙整狀態必須先同步 review-log／PROGRESS／HANDOFF／roadmap，未達雙 zero findings 不進 TDD。
- [2026-07-28] G2 `presentation-ui` R12 雙審未通過：terminal handoff DAG/ownership 循環、Results snapshot commit boundary 矛盾、invalid playback multiplier 與完整 accessibility runtime/static evidence 缺口；4 項均待使用者裁決，TDD 硬停。
- [2026-07-28] G2 `presentation-ui` R11 三項 findings 全採納：Exit evidence 拆成 T05/T08 兩份 immutable tests；T08 settings 只做 injected-port component、T12 做 concrete integration；T06/T08 分別覆蓋 recovery fault preservation/cancel。狀態為 `R11_FIXES_APPLIED_PENDING_R12`。
- [2026-07-28] G2 `presentation-ui` R11 雙審未通過：Exit named test 跨 wave 與 SHA lock 衝突、T08 settings UI 依賴後置 T12 concrete coordinator、AC-070 recovery cancel/fault preservation 缺 fresh named matrix；3 項均待使用者裁決，TDD 硬停。
- [2026-07-28] G2 `presentation-ui` R10 ownership findings 全採納：T05 單獨擁有 Exit root lifecycle 與 CLI composition/integrated smoke；T01 僅 bootstrap component、T04 僅 facade/dev wrapper component、T08 僅 UI button/host smoke。R1→Tasks 補 T04/T05，狀態為 `OWNERSHIP_FIXES_APPLIED_PENDING_R11`。
- [2026-07-28] G2 `presentation-ui` R9 三項 finding 全採納：Exit 只在 MENU_MAIN 發一次可攔截 request、重複／錯 lifecycle 具名拒絕且不終止 runner；`ABANDON_BOSS_RETRY` 逐項納入 begin/cancel/confirm/repeat/stale/lease confirmation test；dev CLI allowlist 精確為 `--combat-lab` 並共用 production bootstrap/facade。狀態為 `FIXES_APPLIED_PENDING_R10`。
- [2026-07-28] G2 `presentation-ui` R8 修正：採納 `G2-R8-01`，results-action guard 改為在首次 fallback lease 驗證前取得，跨 repository ownership release 持有到 route commit/failure cleanup，全段無 `await`；named test 固定在 repository ownership 前、CAS/repository release 後、candidate bind 中各注入 Camp/Menu 重入，並驗 typed loser、零 save/route、state/route/lease 一致與 guard 可恢復。狀態僅為 `RESOLVED_IN_SDD_PENDING_R9`。
- [2026-07-26] G2 `presentation-ui` R8 checkpoint：使用者指示先記錄 `G2-R8-01` 並更新交接後 commit；此指示不視為採納修正。finding 要求補 retry-vs-Camp／Menu 三個 barrier 的 single-flight 競爭紅燈，下一位接手者須先取得裁決、修訂並通過 R9 雙審，才可進 TDD。
- [2026-07-26] G2 `presentation-ui` R7 唯一一項裁決採用：RESULTS fallback retry token 增加獨立 retry-attempt generation；consume 必須在 repository read ownership 內 fresh-read authoritative bytes 並重新核對 receipt／完整 file digest。任何 attempt 都消耗 token、推進 generation 並撤銷同代 sibling token；競爭寫入、receipt replacement、read fault 與 sibling token 納入 TDD。
- [2026-07-26] G2 `presentation-ui` R6 兩項裁決全採用：terminal settlement 的 save commit、internal capability consume、RUN writer lease 撤銷、session invalidation 與 RESULTS transition 必須位於同一 AppRoot single-flight＋SaveRepository writer ownership，禁止中途釋放或 await；postcommit presentation failure 進 typed `RESULTS_FALLBACK`，只提供 repository／receipt／完整檔案 digest／fallback generation 綁定的單次 retry 與零新 save 的 Camp／Menu 離開路徑。
- [2026-07-26] G2 `presentation-ui` R5 三項裁決全採用：terminal settlement commit 後先撤銷 RUN writer/session 並進 RESULTS，route failure 僅留唯讀 fallback；正式 screen 只持 lease-bound LiveScreenIntentPort，raw RunPresentationSession 不外流；Collection 強制涵蓋 discovered/unlocked content、recipes、rule glossary 並以 typed comparability 限制比較。
- [2026-07-26] G2 `presentation-ui` R4 四項裁決全採用：same-state route 使用 parent-bound subroute token；每個 screen 以可撤銷 LiveScreenLease 隔離，RUN 子畫面共用 session；RESULTS→CAMP／MENU 分成零新 save 的 typed event；SettingsRepository clone-in/out，coordinator 以 digest-bound plan/token＋single-flight 防 alias 與交錯 apply。
- [2026-07-26] G2 `presentation-ui` R3 七項裁決全採用：所有 Camp writer 共用 repository-owned 原子交易；transcript 採 precommit accumulator→postcommit 唯一 buffer ownership transfer；復原測試擴為四 base states×四 tmp residue；不可逆操作 typed confirm/cancel exactly-once；戰鬥單位唯讀 inspection；locale 僅 `zh_TW|en`；圖鑑以 cloned ViewModel 提供 filter/search/compare。
- [2026-07-26] G2 `presentation-ui` R2 七項裁決全採用：recovery 明列既有 save rotation 的可恢復 main-missing 中間態；opaque token 統一完整 committed-file digest；repository operation epoch＋consume 鎖內 fresh-read；staging read-only＋commit 後 activation；SettingsApplicationCoordinator 跨 adapter two-phase；BattleTranscriptBuffer 私有 owner／4096 window／byte budget；正式 typed Camp start-expedition 路徑。
- [2026-07-26] G2 `presentation-ui` R1 雙審 14 項裁決全採用：完整 facade intent、pre/post commit failure 分流、19 AC fresh evidence、四 bus volume/mute 原子套用、opaque digest recovery、敵我非色彩提示、pointer mapping、settings stable wire/future-version、PreparedRunCapability、atomic scene swap、commit-before-present playback、typed clone accessor、AppRoot 單一 integration owner、T00 compile-safe contract TDD。
- [2026-07-26] S5 retained run 採 fail-closed：所有一般 Camp writer 只在 fresh load 明確 `RunStatus.NONE` 時寫入；decoded unresumable run 只能以 expected run-id 明示棄置，opaque incompatible run 保留並 boot failure。MetaReward/Commander 皆由 pinned canonical payload reader 重建 clone。
- [2026-07-22] S3 reward generation 的 standard stage 固定三選一且必要時保留最後一格給合法非棋子候選；event grant 使用同一 table 但只建立單一 pending offer。菁英 standard→relic 期間保留 shop，最後 stage 與 overflow 全解決後才釋放。
- [2026-07-22] RewardTable conditions 以 roster／inventory／HP／pool 決定性過濾並由 content gate 要求 stage fallback；unit-only event 在卡池耗盡時提交零效果 EVENT choice，不虛構副本。非戰鬥節點透過正式 command 離開 PREPARE，避免路線軟鎖。
- [2026-07-18] S3 階段 0～3 沿用 save schema 2；空 shop slot 以缺少該 `slot_index` 的 0～5 筆排序 offer 表示，不引入 sentinel Unit ID。地圖與商店分別只消費具名 `map`／`shop` PCG32 stream，所有提交仍走 `RunController` 原子交易。
- [2026-07-16] S2 採 20 Hz 整數累加、固定排序、PCG32 具名 combat stream、wave-start 傷害代數與版本化 event/result codec；presentation 只能消費 setup/event/result clone。
- [2026-07-16] `UnitBattleSnapshot.basic_attack_profile` 納入 setup v2 hash 與 save JSON，避免由射程猜測近戰／遠程並保留 `magic_projectile` authoring；v1 codec/golden 不變。
- [2026-07-13] S1 完成 gate 採單一 `tools/run-tests.ps1 -Suite All`，並保留 `0／2／3／124` runner contract 與 F/X/D 分類 artifact；不能用 placeholder runner 或 downstream 假通過取代。
- [2026-07-13] 存檔成功與 App 狀態轉移以 repository-issued one-time capability 綁定；active run 持有 pinned content catalog lease，避免 caller 偽造 commit 或舊 generation 被移除。
- [2026-07-13] 技術棧採 Godot 4.7 + GDScript + GUT 9.7.1 —— 依 `docs/game-architecture/05-technical-architecture.md` §8 工具鏈與 §17 外部參考,沿用 spec 既定選型。
- [2026-07-13] 開發路徑採「架構規格先行 → REQ 切成功能切片 → 各切片走 specs 三件套 → /pipeline 實作雙審」—— 銜接既有藍圖級架構規格與功能級規格驅動開發。
- [2026-07-13] 專案代號定為「遠征棋 (Expedition Chess)」—— 取 spec §4「遠征」單局結構 + 自走棋核心兩大識別特徵。
