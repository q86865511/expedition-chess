# S5 meta-progression 技術設計

> 狀態：已核可（2026-07-24）
> 對應需求：[requirements.md](requirements.md)（REQ-META-001~004＋S5-AC-001~014）
> 架構基線：`docs/game-architecture/04-content-and-meta-progression.md` §7（REQ-META-001~004）、`08-testing-and-acceptance.md`（AC-021/022/023/042/043/044/061/073）、`10-traceability-matrix.md:39-41`；技術契約沿用 S1~S4 已落地：copy-validate-save-swap（`domain/run/controller/run_controller.gd:34-204`）、app 狀態機＋存檔提交能力（`app/state/app_state_machine.gd`、`services/save/save_repository.gd:230-280`）、RuntimeKey v1（`domain/common/runtime_key/runtime_key_schema_registry.gd`）、RngService 具名流（`domain/common/rng/rng_service.gd:8`）、內容 pinned digest＋catalog lease（`domain/run/controller/run_session_factory.gd:46-66`）。
> 設計取捨摘要：(1) 沿用既有 exactly-once 地基（receipt key codec／SettlementReceiptState 已存在，S5 補唯一 writer）；(2) 指揮官被動與挑戰詞綴複用遺物作用點＋敵方 affix 管線，挑戰另設負向 run 機制雙軌（使用者裁決）；(3) 局外成長全為「加選項」，禁項由驗證器擋，save schema 2→3 附 migration。

## 1. 設計目標

補上「局外層」與正式 composition root，使 S1~S4 的局內系統成為可從營地啟動、結算回營地的閉環，且不違反四條硬約束：局外成長只加選項不加基礎戰力（REQ-META-002）、進行中快照不變（REQ-META-003）、局外貨幣 exactly-once（REQ-META-004）、五類設施單一狀態源（REQ-META-001）。

關鍵事實——多數地基已存在，S5 是「補 writer 與接線」而非重造：

- `SettlementReceiptState`（`domain/run/settlement_receipt_state.gd`：key/outcome/currency_delta/payload_digest）與 `RuntimeKeySchemaRegistry.build_settlement_receipt(run_id)`（`domain/common/runtime_key/runtime_key_schema_registry.gd:142-155`，canonical tuple = `[k=settlement_receipt, s=run_id]`）已存在，但**無任何 writer**——S5 的 meta 結算是它的唯一 producer。
- `ProfileState`（`domain/run/profile_state.gd:4-11`）8 欄與其 codec（`services/save/save_json_codec.gd:62-73,663-701`）已完整往返；S5 只**新增**兩欄（最近選擇、按指揮官挑戰紀錄）＋一個 run 層 discovery 欄。
- app 狀態機已模型化 `BOOT/MENU/CAMP/RUN/RESULTS` 與 `START_RUN/FINISH_RUN/ABANDON_RUN/ACTIVE_RUN_LOADED` 的**存檔提交閘**（`app/state/app_state_machine.gd:31-119`，經 `transition_after_save`／`transition_after_active_run_load` 消費一次性能力 token），但 `AppRoot` 尚未建構 `RunController`（`app/app_root.gd:12,66` 恒 null）——正式接線＝S5。
- 遺物作用點（run 層 `domain/run/economy/income_service.gd:24-26`／`domain/run/economy/shop_service.gd:189-192`／`domain/run/map/map_service.gd:22-23`／`domain/run/economy/battle_settlement_service.gd:41-44`；戰鬥層 `domain/battle/setup/battle_setup_source_compiler.gd:220-246`）與敵方 affix 管線（`domain/battle/setup/encounter_compiler.gd:317-343`，`challenge_level` 已由 `domain/run/map/node_entry_service.gd:61` 接線）皆存在——S5 讓指揮官被動與挑戰詞綴**複用**它們。

S5 工作＝(a) camp 交易層（StartExpedition／PurchaseUnlock／CampViewModel）＋ AppRoot composition root；(b) meta 結算 exactly-once（receipt writer＋原子交易）；(c) 指揮官被動與挑戰詞綴注入既有作用點；(d) 挑戰詞綴正式內容＋驗證器擴充；(e) 圖鑑發現 in-run 原子標記；(f) MetaRewardTableDef 計算純函式。

## 2. 版本策略

| 契約 | 版本 | 決策 |
|---|---:|---|
| save schema | **3（bump）** | S5 於 `ProfileState` 新增 `last_selection`、`commander_challenge_records`，於 `RunState` 新增 `discovered_content_ids`（in-run 發現載體，§8）——皆為新 wire 欄位，`SaveSchemaContract.CURRENT`（`services/save/save_schema_contract.gd:4`）2→3 |
| save migration | **v2→v3（新增）** | REQ-SAVE-003：新增 `SaveMigration` 將 schema-2 存檔升級——`last_selection`=null、`commander_challenge_records`=[]、`run.discovered_content_ids`=[]；保留一份 schema-2 fixture 供 migration 測試（沿用既有 `SaveMigrationRegistry` 機制，`services/save/save_repository.gd:371-393`） |
| content manifest generation | +1 | 新著作 challenge 詞綴 effects＋對齊後的 `meta_reward_tables/slice_default.tres` 產生新 pinned digest；進行中舊 run 憑 catalog lease 續持舊 digest（非 migration；REQ-META-003） |
| RuntimeKey codec | 1（不變） | `settlement_receipt` kind 已在 `_expected_tags`（`runtime_key_schema_registry.gd:227`）；`effect_claim` tuple 已含 `claim_scope`／`node_id`——claim_scope 真語意（§6.4）不需新 codec |
| RngService streams | map/shop/reward/combat（不變） | meta 結算、購買、發現標記皆為純決定性運算，**不新增 stream**；發現標記不得改變任何既有 stream 的 draw 序（§8） |
| RunRelicTable | 1（擴充） | `RunRelicRule` 新增 `source`（relic/commander/challenge）；`RunRelicTable` 新增 always-active 加總；不改既有 slot-gated 消費（§6.1） |

## 3. 模組

```text
Composition root (S5 接線):
  AppRoot(app/app_root.gd)
    ├─ Autoload: ContentRegistry / SaveService / SettingsService / AudioService / SceneRouter
    ├─ AppStateMachine (BOOT↔MENU↔CAMP↔RUN↔RESULTS; 既有)
    ├─ CampController         ── profile 範疇 copy-validate-save-swap ──┐
    │     ├─ StartExpeditionCommand → RunBootstrapService (建 RunState) │ 交易寫 SaveRoot
    │     ├─ PurchaseUnlockCommand  → UnlockPurchaseService             │ 經 SaveRepository.save
    │     └─ MetaSettlementCommand  → MetaSettlementService             │ →AppStateMachine
    │            └─ MetaRewardComputeService (純函式)                    │  .transition_after_save
    ├─ RunController (既有; run 範疇; §8 加 discovery union)            ─┘
    │     └─ RunCommandFactory  ── 顯式非 null relic_table 建構 4 命令 (S5-AC-014)
    └─ SceneRouter: CampScene(灰盒) ↔ Run presentation ↔ ResultsScene(灰盒)

run 層 modifier 注入 (§6):
  RunModifierTableBuilder(digest, relic_ids, commander_id, challenge_level)
    → RunRelicTable{ relic 規則(slot-gated) + commander/challenge 規則(always-active) }
  ChallengeAffixResolver(challenge_level) → 敵方 affix effect ids (→EncounterCompiler)
  BattleSetupSourceCompiler(+commander player 被動 effect ids)

ViewModel 契約 (Codex 接正式 UI; 全部只持 ProfileState/RunState clone):
  CampViewModel(五設施狀態) · ExpeditionGateViewModel(指揮官/挑戰/生效詞綴列表) · CollectionViewModel
```

新型別：`CampController`、`StartExpeditionCommand`、`RunBootstrapService`、`PurchaseUnlockCommand`、`UnlockPurchaseService`、`MetaSettlementCommand`、`MetaSettlementService`、`MetaRewardComputeService`、`RunModifierTableBuilder`、`ChallengeAffixResolver`、`ProfileLastSelectionState`、`CommanderChallengeRecordState`、`CampSaveRootFactory`、`CampViewModel`／`ExpeditionGateViewModel`／`CollectionViewModel`。命名沿用專案風格。

## 4. Camp 交易層與 composition root 接線

### 4.1 兩個交易範疇

專案既有唯一交易家是 `RunController`（範疇＝**active RunState**，profile 唯讀傳遞 `domain/run/controller/run_session.gd:24-25`）。S5 局外操作在**無 active run**（app=CAMP）或**跨 run 邊界**（建立/結算 run）發生，profile 是主體，故新增平行的 `CampController`：與 `RunController` 同紀律（clone→validate→save→swap、回具名 typed result、無部分變更 REQ-TECH-006），但主體是 `ProfileState`，寫 `SaveRoot` 經 `SaveRepository.save`（`services/save/save_repository.gd:68-173`，既有原子 tmp→readback→rotate→promote），成功後驅動 `AppStateMachine`。

`SaveRoot.run` 可為 null（`domain/run/save_root.gd:30`；load 已支援 `root.run==null`→`RunStatus.NONE`，`save_repository.gd:216-223`），故 camp 交易寫 `run=null` 的 profile-only 存檔是既有支援形狀。新增 `CampSaveRootFactory`：content_version 取自當前 pinned generation（`RunSaveRootFactory.build` 讀 `run.content_snapshot` 無法建 null-run，故需獨立 factory）。

### 4.2 StartExpeditionCommand（S5-AC-002）

輸入：`commander_id`、`challenge_level`。流程（`CampController.dispatch`）：
1. 驗證（否則具名 error，零變更）：commander 已在 `profile.unlocked_content_ids`；`challenge_level` 的 prerequisite 滿足——`commander_challenge_records` 中該指揮官最高通關 ≥ level−1（level 0 無前置；§7.4 逐階解鎖）。
2. `RunBootstrapService.build(profile, commander_def, challenge_level, pinned_receipt)`→初始 `RunState`：`commander_id` 鎖定（`domain/run/run_state.gd:13`，遠征中無 command 可改）、`challenge_level`、`content_snapshot`＝釘當前 generation（REQ-META-003）、`run_seed` 決定性衍生自 run key（profile_id＋next_run_serial）、`roster_state` 以 commander `starting_pack` 播種、`run_phase=MAP`、`expedition_hp`／`economy_state` 初值。指揮官**不入 board placements／不佔人口**；population cap 於此套用 `commander.population_bonus`。
3. 建 `SaveRoot(profile', run)`：`profile'`＝`next_run_serial+1`、`last_selection`=（commander_id, challenge_level）。save→`transition_after_save(START_RUN)`（CAMP→RUN）。

### 4.3 PurchaseUnlockCommand（S5-AC-011）

輸入：`unlock_id`。clone profile→驗證（`currency_cost ≤ meta_currency`；未重複持有；`prerequisite_refs` 全已解鎖）任一不滿足回具名 error（`UNLOCK_INSUFFICIENT_CURRENCY`／`UNLOCK_ALREADY_OWNED`／`UNLOCK_PREREQUISITE_UNMET`）且零變更→成功則 `meta_currency −= cost`、`unlocked_content_ids += unlocked_content_refs`（sorted, unique）→`SaveRoot(profile', null)` save→swap。購買紀錄＝`unlocked_content_ids`，由 CampViewModel 解鎖工坊讀出。

### 4.4 AppRoot composition root 與灰盒（S5-AC-001、S5-AC-014）

`_ready` 擴充：boot 後 `load()`；若 `RunStatus.LOADED`→建 `RunSession`（取 lease）＋`RunController`＋`RunCommandFactory`，`transition_after_active_run_load(ACTIVE_RUN_LOADED)`→RUN；否則 CAMP，掛 `CampController`＋`CampScene`。`SceneRouter` 依 app state 換 `CampScene`／run presentation／`ResultsScene`（灰盒 `scenes/dev/`，比照 combat_lab／expedition_lab 慣例；正式 UI 歸 Codex）。

**`RunCommandFactory`（防「忘傳靜默跳過」回歸，HANDOFF §4）**：唯一建構 `GenerateExpeditionMapCommand`／`RefreshShopCommand`／`SettleBattleResultCommand`／`EnterNodeEvent` 之處，一律注入本 run 的**非 null** `relic_table`（§6 含指揮官被動）。回歸測試斷言 factory 產物 `relic_table != null` 且效果可觀察（S5-AC-014）。

**CampViewModel（單一狀態源，S5-AC-001）**：五設施視圖欄位全部自**同一** `ProfileState` clone 導出——遠征門(`last_selection`＋各指揮官最高通關)、指揮官廳(`unlocked_content_ids` 濾 commander)、圖鑑館(`discovered_content_ids`／`unlocked_content_ids` 按類別)、解鎖工坊(`meta_currency`＋購買紀錄)、挑戰碑(`commander_challenge_records`＋`highest_challenge_level`)。無第二資料源。

## 5. 遠征結算 meta 段與 exactly-once

### 5.1 觸發與 app 協調

局內最終結算（三幕通關 boss 勝、遠征 HP 歸零、Boss 重戰放棄）由既有 `BattleSettlementService`（`battle_settlement_service.gd:45-152`）把 `run_phase` 設為 `RESULTS`、經 `RunController` 提交——**此時尚未發任何局外貨幣**，active run 仍持久於 `run_phase=RESULTS`。

meta 結算＝`FINISH_RUN`（RUN→RESULTS，需存檔提交）這一**單一原子交易**（§7.3：貨幣/里程碑/挑戰紀錄/receipt/active run 清除同一交易）：`MetaSettlementCommand`→`MetaSettlementService.settle(profile, terminal_run, meta_reward_table)`：
1. 判 outcome：`defeated_boss_count == 3`→`COMPLETED`；否則→`FAILED`（含遠征 HP 歸零與 Boss 重戰放棄——S3 兩路徑終態同為 RESULTS＋hp0 不可區分，且 AC-043 本就同列兩者為失敗結算；`SettlementReceiptState.Outcome.ABANDONED` 枚舉值保留不使用。w2 裁決 2026-07-24）。
2. `currency_delta = MetaRewardComputeService.compute(...)`（§9，純函式）。
3. `key = build_settlement_receipt(run.run_id)`。**冪等守衛**：若 `profile.settlement_receipts` 已含此 key.digest→`currency_delta` 視為 0（不重發），仍授權清 run。
4. `profile'`＝`meta_currency += delta`、append `SettlementReceiptState(key, outcome, delta, payload_digest)`、`highest_challenge_level = max(舊, COMPLETED 時的 challenge_level)`、更新該指揮官 `commander_challenge_records`（COMPLETED 時取 max，§7.4）。
5. `SaveRoot(profile', run=null)`（清 active run）→save→`transition_after_save(FINISH_RUN)`→RESULTS。`ACKNOWLEDGE_RESULTS`（無提交）→CAMP。

`payload_digest` 涵蓋 run_id、outcome、cleared counts、challenge_level、delta（對齊 `battle_settlement_service.gd:246-250` 慣例），供載入竄改偵測。

### 5.2 三故障點×3 重載一致性（S5-AC-007／AC-061）

exactly-once 由四重保證疊加：(a) `compute` 純函式，同一 terminal run 恆得同值；(b) 單一原子存檔——`profile'(含貨幣+receipt)` 與 `run=null` 同一 `SaveRoot`，`SaveRepository` tmp→readback→promote→final-readback（`save_repository.gd:110-161`）全有或全無；(c) receipt key on run_id 冪等守衛；(d) app 層一次性提交能力 token（`save_repository.gd:230-242`）。故障於任一存檔子步：swap 未發生→重載仍是 active run＠RESULTS→重試 `FINISH_RUN`→決定性重算同值；成功後 run=null→無 active run 可再結算→零重發。receipt key 唯一性由 `RunStateValidator` 於 load/commit 對 `profile.settlement_receipts` 重編碼＋去重（重複 run_id tuple→拒載），對齊 REQ-DATA-007。

## 6. 指揮官被動與挑戰詞綴注入

三條注入路徑，皆釘 run 的 `content_snapshot.manifest_digest`（與既有世代守衛同一 digest），決定性、與遺物共存。

### 6.1 run 層（經濟/路線/規則）——擴充 RunRelicTable

`RunModifierTableBuilder.build(registry, digest, relic_ids, commander_id, challenge_level)` 產出擴充 `RunRelicTable`：
- **relic 規則**（source=`relic`，slot-gated）：沿用 `RunRelicTableBuilder`（`domain/run/build/run_relic_table_builder.gd`）現行解析。
- **commander 規則**（source=`commander`，always-active）：解 `commander.passive_effect_refs` 的 run_operations 成 `RunRelicRule`。
- **challenge 規則**（source=`challenge`，always-active）：解 challenge unlock 鏈 1..N 的 `modifier_refs` 中屬 run 層的 operation。

`RunRelicRule` 加 `source: StringName`（預設 `&"relic"`）。`RunRelicTable` 加 `sum_always_active(category, kind)`／`always_active_count(category)`：對 source∈{commander,challenge} 規則**無條件**加總（不看 slot）。各 run 層消費端（income/shop/map/settlement 作用點）在既有 slot-gated 加總後**再加** always-active 貢獻。決定性順序：slot 遺物（slot_index 升序）→ commander → challenge（effect_id 字典序）。`population_bonus` 於 §4.2 建 run 時套進 population cap。

### 6.2 戰鬥層（player 被動）——擴充 BattleSetupSourceCompiler

指揮官若含戰鬥 passive，`BattleSetupSourceCompiler.compile` 新增可選 `commander_passive_effect_ids` 參數，產 `source_category=&"commander"`、`source_side=&"player"` 的 `BattleEffectSnapshot`（比照 relic effects `battle_setup_source_compiler.gd:220-246`），隨 `BattleSetup` hash 凍結、進模擬。

### 6.3 挑戰詞綴——雙軌機制（使用者裁決：四類皆為獨立機制）

挑戰詞綴分兩軌，四類皆機械生效：

**軌 A：敵方 battle affix（敵人編成/遭遇規則）**——複用既有 `EncounterCompiler._compile_affixes`（`encounter_compiler.gd:317-343`，`source_side=enemy`；菁英詞綴即此管線）。`challenge_level` 已由 `node_entry_service.gd:61` 送入 `EncounterCompileRequest`。S5：
- `ChallengeAffixResolver.resolve(challenge_level)`→challenge unlock 鏈 1..N 的詞綴 effect ids（sorted, dedup），分軌歸類。
- `EnterNodeEvent` 於 node entry 把軌 A 結果填入 `EncounterCompileRequest`（新欄位 `challenge_affix_effect_ids`），`_compile_affixes` 合併 encounter 自帶 affix 與 challenge affix（同一敵方管線、決定性 sort、去重）。

**軌 B：負向 run 機制（經濟壓力/遠征傷害）**——既有 run 層 operation 受 `content_validator.gd:688` amount≥0 約束；不放寬該不變量，改以**新 operation def 型別承載負向語意（amount≥0＝幅度、負向由型別表達）**：
- `ShopSurchargeOperationDef`（amount＝商店 reroll/購買成本**增量**）：shop 作用點消費端（`shop_service.gd:189-192` 既有 discount 加總處）改為 `cost + surcharge − discount`（下限 clamp 沿用既有規則）。**不對稱裁決**（W4-F4，2026-07-25）：此公式套用於單件 offer 的購買成本（`_generate_offers`）；`quote_refresh` 的 reroll 固定費用（`config.reroll_cost`）改為 `maxi(1, reroll_cost + surcharge)`，**只套 surcharge、不套 discount**——discount 維持 S4（economy-expedition）既有行為不套用到 reroll，避免動到已完成切片的平衡，非遺漏。
- `DrainExpeditionHpOperationDef`（amount＝戰敗時**額外**遠征 HP 損失）：settlement 作用點（`battle_settlement_service.gd:41-44` 既有 heal 加總處）於戰敗路徑加算額外損失（與 heal 同一決定性加總慣例、受 HP 下限 clamp）。
- 兩者作為 source=`challenge` 的 always-active 規則經 §6.1 `RunRelicTable` 消費（claim_scope=always，逐事件生效不設一次性 claim）；validator 對兩者維持 amount≥0、須擴充解碼分支（§7.2）。

challenge 0 無詞綴；菁英詞綴與 map node generator 不受重指影響（§7）。四類→機制映射：敵人編成/遭遇規則→軌 A；經濟壓力→ShopSurcharge；遠征傷害→DrainExpeditionHp。生效詞綴清單（含分類標籤）由 resolver 於開局前提供（S5-AC-010）。

### 6.4 claim_scope 真語意（S5-AC-013；S4 裁決/AC-073 settlement 子條款）

- **放寬**：`run_relic_table_builder.gd:83-84`（拒非 always→UNSUPPORTED_INTENT）與 `content_validator.gd:264-274`（`_validate_relic_effect_scope` 強制 always）同步改為接受 `{always, once_per_node, on_first_clear}`（`content_validator.gd:688` 的 scalar 路徑已允許三者）。
- **claim key**：沿用 `build_effect_claim(run_id, node_id, claim_scope, source, effect_id, op_index)`（`runtime_key_schema_registry.gd:110-140`）與 `claim_receipts` 去重（`battle_settlement_service.gd:169-200` 既有樣式）。`once_per_node`→node_id 用當前節點（同節點同 key→恰一次、跨節點重觸發）；`on_first_clear`→node_id 用 run 級 sentinel（全 run 同一 key→首次通過恰一次）。`always`→維持既有逐節點無條件加總（§6.1）。claim 消費對齊既有 S3 claim 紀律（AC-059 同款）：**戰敗不提交、不消耗 claim；首次合法勝利結算才提交恰一次**（w3 裁決 2026-07-25）。
- **支援集合收斂**（w3 裁決 2026-07-25）：非 always scope 只在「消費端具 claim-aware 去重」的 (category×kind) 開放——目前僅 (rule×heal_expedition_hp)（結算作用點）；economy/route 類 scalar intent 維持 always-only（消費端逐節點無條件加總、無法履行 claim 語意，開放即成死內容），直到對應消費端支援 claim 再擴。builder 與 validator 以同一判準拒絕。
- **唯一性**：`RunStateValidator` 對 `claim_receipts` 與 `settlement_receipts` 重編碼＋去重，重複 tuple 拒載（對齊 AC-073）。

## 7. 挑戰詞綴內容與驗證器擴充

### 7.1 內容授權

新著作 5 條 challenge 詞綴 `EffectDef`（`content/packs/vertical_slice/effects/`，新 stable id `effect.slice_challenge_affix_00..04`），重指 `unlocks/slice_challenge_1..5.tres` 的 `modifier_refs`（現指向菁英詞綴佔位）。**不動**菁英詞綴與其被 treasure/rest/merchant generator 複用之處、不動 map nodes。五條為 `content_role=&"challenge_affix"`，四類全覆蓋（敵人編成/遭遇規則→軌 A 以既有 battle operation defs 表達；經濟壓力→`ShopSurchargeOperationDef`；遠征傷害→`DrainExpeditionHpOperationDef`；§6.3）。數值全標 TUNE。指揮官被動內容：`effect.slice_commander_passive`（現為空 op 佔位）補實際 run/battle operation；三名被動非同一效果的數值階級（§7.2 硬約束，內容驗證）。

### 7.2 驗證器擴充（REQ-CONTENT-001、REQ-META-002）

`ContentValidator` 新增：
- **`challenge_affix` 規則**：challenge unlock 鏈 1..5 的 `modifier_refs` 必指向 challenge_affix effects（非 elite_affix）；四類分類覆蓋；operation 落在可解碼集合。
- **新 operation 解碼分支**：`ShopSurchargeOperationDef`／`DrainExpeditionHpOperationDef` 進 `_scalar_run_amount`/`_scalar_run_claim_scope` 與相關白名單，維持 amount≥0 不變量（§6.3 軌 B）。
- **META 禁項（S5-AC-004／AC-022）**：unlock 的 `unlocked_content_refs`／`modifier_refs` 不得宣告永久基礎生命/攻防提升、商店免費刷新、固定起始人口——命中回非零退出碼（新 issue code `CONTENT_META_FORBIDDEN_GROWTH`）。
- **claim_scope 放寬**（§6.4）與 builder 對齊。
- **挑戰乘數表**：`MetaRewardTableDef.challenge_multiplier_bps` 覆蓋 level 0..5、basis_points ≥ 10000。
- 三指揮官被動非同一效果數值階級（§7.2 硬約束）。

## 8. 圖鑑發現局內即時標記

依裁決「局內即時、經 command 交易原子寫入」。難點：`RunController` 提交時 profile 唯讀（`run_controller.gd:196` 取 `_session.profile_snapshot()`）、command 只回 `RunState` draft。

設計：**run 側 discovery 台帳 ＋ 提交時 union 進 profile**：
- `RunState` 新增 `discovered_content_ids: Array[StringName]`（in-run 發現台帳，單調/去重）。
- 發現事件所屬 command 於 `apply_to(draft)` 內 append（union，冪等）：上場/購得棋子→買棋/部署 command；商店出現→`RefreshShopCommand`；遭遇敵人→`EnterNodeEvent` 的 encounter preview；取得裝備/遺物→reward/forge 解算 command。共用 helper `RunDiscoveryLog.mark(draft, content_id)`。
- `RunController._commit_draft` 擴充：`profile'` = profile_snapshot 的 `discovered_content_ids` 與 `draft.discovered_content_ids` **union**，存 `SaveRoot(profile', draft)`。此為 profile 於 run 期唯一可變面——**僅** discovery 的單調 append union。

保證：與觸發 command 同一 copy-validate-save-swap 原子提交；union 冪等（重載/重放不重複，S5-AC-012）；純 append 不消耗 RNG、不改 draw 序。圖鑑館經 `CollectionViewModel` 按類別讀取。

## 9. MetaRewardTableDef 計算服務與乘數收斂

`MetaRewardComputeService.compute(cleared_normal, cleared_elite, defeated_boss, challenge_level, outcome, table) -> int`，純函式：

```
base = cleared_normal·score(normal) + cleared_elite·score(elite) + defeated_boss·score(boss)
mult_bps = table.challenge_multiplier_bps[challenge_level]   # = 10000 + 1000·L
scaled = (base · mult_bps) / 10000            # 整數向下取整
delta  = scaled + (table.completion_reward if outcome==COMPLETED else 0)
```

- score 僅 normal/elite/boss 三鍵；非戰鬥節點不計。戰敗保留先前成功戰鬥計分（counts 本即只計已清戰鬥），`failure_reward` 無加成。
- **乘數權威收斂**：乘數單一權威＝表內 bps 欄；§7.3「100%+10%×level」為其 TUNE 初值推導，compute 讀表、不硬寫公式。
- **slice_default.tres 對齊 §7.3／S5-AC-006**（TUNE）：elite `2→3`、merchant/event/treasure `1→0`、`failure_reward 2→0`；completion `10`、boss `5`、normal `1`、bps 10000..15000 不變。

固定規則（乘數公式形態、exactly-once、floor、禁項）不可資料化放寬；score/reward/bps 數值為 TUNE。

## 10. ProfileState 擴欄位與 save schema

`ProfileState` 新增兩欄：
- `last_selection: ProfileLastSelectionState`（可 null；`{commander_id, challenge_level}`）——遠征門「最近選擇」，`StartExpeditionCommand` 寫。
- `commander_challenge_records: Array[CommanderChallengeRecordState]`（`{commander_id, highest_cleared_level}`）——挑戰碑「各指揮官最高通關」，meta 結算 COMPLETED 時更新。

save 影響：`save_json_codec.gd` `_encode_profile`／`_decode_profile`（:62-73,663-701）加兩欄；`SaveSchemaContract.CURRENT` 2→3；新增 v2→v3 migration（新欄預設 null/[]）＋保留 schema-2 fixture（REQ-SAVE-003）。`RunStateValidator` 擴充驗新欄型別與 receipts/records 唯一性。既有 8 欄與 codec 往返不變。

## 11. 需求追溯

| Requirement / AC | Design | Tasks |
|---|---|---|
| REQ-META-001（五設施單一狀態源） | §4.4 | T03、T11 |
| REQ-META-002（禁提基礎戰力） | §7.2 | T10 |
| REQ-META-003（進行中快照不變） | §4.2、§2 | T05、T10 |
| REQ-META-004（結算＋receipt exactly once） | §5、§9 | T01、T02 |
| REQ-DATA-007（局外結算冪等識別） | §5.2 | T02 |
| REQ-DATA-006（ContentSnapshot 不可變；沿用） | §4.2 | T05 |
| REQ-SAVE-001/003（版本化原子寫入；migration＋fixture） | §2、§10 | T03 |
| REQ-TECH-002（轉移經 RunController/AppStateMachine） | §4、§5.1 | T04、T05、T11 |
| REQ-TECH-004（copy-validate-save-swap） | §4.1、§8 | T02、T04、T05、T09 |
| REQ-TECH-006（具名 result 無部分變更） | §4.2、§4.3 | T04、T05 |
| REQ-CONTENT-001（驗證器數量/分布/禁項） | §7.2 | T07、T10 |
| REQ-UX-005（可見文字 localization key） | §3、§7.1 | T07、T11 |
| S5-AC-001 | §4.4 | T11 |
| S5-AC-002 | §4.2 | T05 |
| S5-AC-003 | §6.1、§6.2 | T06 |
| S5-AC-004 | §7.2 | T10 |
| S5-AC-005 | §4.2、§2 | T10 |
| S5-AC-006 | §9 | T01 |
| S5-AC-007 | §5.1、§5.2 | T02 |
| S5-AC-008 | §5.1、§4.4 | T11 |
| S5-AC-009 | §5.1、§4.2 | T02、T05、T07 |
| S5-AC-010 | §6.3、§7.1 | T07 |
| S5-AC-011 | §4.3 | T04 |
| S5-AC-012 | §8 | T03、T09 |
| S5-AC-013 | §6.4 | T08 |
| S5-AC-014 | §4.4 | T11 |
| 全 AC 回歸＋expedition-soak 新鮮度 | §1~§10 | T12 |

## 12. 測試策略

層級：單元＝GUT 純函式/單服務；整合＝多元件/命令→存檔往返（可含故障注入 storage）；實跑＝Godot runner soak/gate。本表為 pipeline TDD 代理翻譯測試的直接依據。

| S5-AC | 測試案例名 | 輸入/前置 | 預期結果 | 層級 |
|---|---|---|---|---|
| 001 | `test_camp_view_model_derives_all_facilities_from_single_profile` | 一個 ProfileState 建 CampViewModel | 五設施視圖欄位全等於該 profile 對應欄；換 profile 值→視圖全變 | 整合 |
| 002 | `test_start_expedition_locks_commander_and_excludes_from_board` | 基礎 profile＋三已解鎖指揮官各建 run | commander_id 各異且鎖定；不在 board.placements、population 不因其增；三起始包/被動 refs 不同；無 command 可改 | 整合 |
| 003 | `test_commander_passive_and_population_applied_via_action_point` | 含被動＋population_bonus 的指揮官建 run 經作用點 | 被動與 population_bonus 實際改變輸出（source=commander）；三被動非同一效果數值階級 | 整合 |
| 004 | `test_meta_growth_forbids_base_power_and_validator_rejects` | 同 manifest 解鎖前後比 UnitDef；含禁項 unlock 內容 | 基礎 stats 逐欄相等；驗證器禁項回非零＋具名 issue | 單元 |
| 005 | `test_in_progress_snapshot_isolated_from_later_unlock` | 進行中 run 持 snapshot＋lease；後購新棋子 | 該 run 內容池不變；新 run 才含新解鎖 | 整合 |
| 006 | `test_meta_reward_compute_matches_table_formula` | 對齊表；多組 (n,e,b,L,outcome) | delta==floor(base·bps/10000)+completion(僅 COMPLETED)；failure 無加成；非戰鬥 0；純函式 | 單元 |
| 007 | `test_settlement_receipt_exactly_once_under_fault_injection` | 無 receipt terminal run；存檔各故障點終止重載 ×3 | 增量恰一次；profile/receipt/run==null 原子一致；key=build_settlement_receipt(run_id) 且去重唯一 | 整合＋實跑 |
| 008 | `test_end_to_end_settlement_atomic_and_returns_to_camp` | 新 profile；(a)三幕通關 (b)HP 歸零/放棄 | 六項同一提交；結算後 app=CAMP；重載 RESULTS 不重發 | 整合 |
| 009 | `test_challenge_progress_recorded_per_commander` | 指揮官 X 於 Challenge N 通關 | X 紀錄==N、profile 最高階同步；N+1 前置=通過 N（未滿足拒選）；他人紀錄不變 | 整合 |
| 010 | `test_challenge_affixes_accumulate_and_listed_before_run` | Challenge N run＋新 challenge affixes（含軌 B） | 詞綴 1..N 累積生效（決定性）：軌 A 敵方 affix 進 encounter、ShopSurcharge 實際提高 reroll/購買成本、DrainExpeditionHp 實際加深戰敗損失；開局前完整列出；Ch0 無詞綴；菁英詞綴/map generator 不受影響 | 整合 |
| 011 | `test_purchase_unlock_success_and_named_failures` | profile 餘額＋可購清單 | 成功扣款原子提交；不足/重複/前置未滿足各回具名 error 零變更；購買紀錄可讀 | 單元＋整合 |
| 012 | `test_discovery_marked_in_run_atomically_and_idempotent` | run 中首次事件（上場/購得/商店/遭遇/取得） | 同一 swap 原子 union；重載/重放不重複；按類別讀出；不改 RNG draw 序 | 整合 |
| 013 | `test_claim_scope_semantics_once_per_node_and_first_clear` | scope∈三值；同節點重入/重載重放/跨節點 | once_per_node 同節點恰一次、on_first_clear 全 run 恰一次、always 逐節點；validator/builder 同步；keys 唯一重複拒載 | 整合 |
| 014 | `test_run_command_factory_injects_non_null_relic_table` | RunCommandFactory 建四命令 | 四命令 relic_table 非 null（含被動）；factory 路徑效果可觀察；EnterNodeEvent 注入 challenge 詞綴 | 整合 |
| 全 AC | `run-tests -Suite All`＋`ExpeditionSoak -SeedCount 10000` | domain 改動後 | gate 綠；expedition-soak 新鮮度證據重跑通過 | 實跑 |

## 13. Failure policy

- 所有 camp/run 交易走 copy-validate-save-swap：validation／save／read-back 任一失敗→丟棄整份 draft、回具名 typed error，不 assert crash、不 silent null、不部分 mutation（REQ-TECH-006）。
- 具名 error（新增）：`UNLOCK_INSUFFICIENT_CURRENCY`／`UNLOCK_ALREADY_OWNED`／`UNLOCK_PREREQUISITE_UNMET`；`EXPEDITION_COMMANDER_LOCKED`／`EXPEDITION_CHALLENGE_PREREQUISITE_UNMET`；`META_SETTLEMENT_*`；沿用 `GENERATION_MISMATCH`。
- exactly-once（§5.2）：單一原子 SaveRoot 提交＋run_id receipt 冪等守衛＋一次性能力 token；任一故障點重載決定性重算、零重發。
- 局外禁項（§7.2）：unlock 宣告禁項→manifest 不可 pin（非零退出碼）。
- claim/settlement key 唯一性（§6.4）：載入/提交重編碼＋去重，重複 tuple 拒載。
- 決定性邊界：meta 結算/購買/發現標記不消耗 RNG、不新增 stream；發現標記純 append union 不改 draw 序。
- 範圍邊界（明列）：正式營地自由移動場景與 UI 視覺歸 Codex（灰盒僅功能載體）；詞綴/獎勵數值平衡為 TUNE；多存檔槽、meta.currency 世界觀命名、32 棋子完整美術不在本片。進行中舊 run 憑 catalog lease 續持舊 digest（非 save migration）。
