# S4 build-systems 技術設計

> 狀態：已核可（2026-07-22）
> 對應需求：[requirements.md](requirements.md)
> 架構基線：`docs/game-architecture/` v0.2（Approved）；權威 §5.4 羈絆、§5.10 裝備鍛造、§5.11 遺物；追溯 `docs/game-architecture/10-traceability-matrix.md`。
> 設計取捨摘要：(1) S3 已落地 S4 全部持久欄位與驗證器不變式，S4 **不 bump save schema、無 migration**；(2) 新工作三塊——構築操作 command 群、`BattleSetupSourceCompiler`（羈絆計數/快照/裝備遺物效果編譯，S3 時只有 fixture 在建 bundle）、遺物經濟/路線/規則型的 run-layer 作用點；(3) 內容驗證器對整份 manifest 生效，S4 交付「build-systems 內容 pack＋TUNE 佔位伴生 catalog」使 manifest 可驗。

## 1. 設計目標

沿用 S1–S3 地基：RunController copy-validate-save-swap、PCG32 具名 stream、pinned manifest digest 與 catalog lease、save schema 2、EffectResolver 的 trait/equipment/relic 效果源支援（effect_resolver.gd:18-20,111,180,294-296）。

關鍵事實——S4 持久狀態已由 S3 全部落地並受驗證：
- `RosterState` 已含 `item_instances`／`inventory_item_instance_ids`（≤16）／`pending_item_overflow`／`active_relic_slots`（固定 5）（roster_state.gd:7-10）
- `UnitInstance.equipment_instance_ids`（≤3）（unit_instance.gd:7）；`ItemInstanceState.bound_unit_instance_id`；`RunState.next_item_serial`
- save codec 已完整編/解碼上述欄位（save_json_codec.gd:219-243, 1063-1146）
- run_state_validator.gd 已強制：5 遺物槽（:272）、每棋 ≤3 且唯一裝備（:281-283）、物品位置三選一互斥＋16 格（:311-349）、遺物槽 stable-id（:351-354）

S4 工作＝(a) 玩家構築操作 command 群；(b) 已提交 roster → 戰鬥效果源的 compiler；(c) 四類遺物 run-layer 作用點；(d) 首批正式 `.tres` 內容與驗證器擴充；(e) Build Lab＋唯讀 ViewModel。domain 操作只讀 clone/snapshot、回 typed transaction（REQ-TECH-004）。

## 2. 版本策略

| 契約 | 版本 | 決策 |
|---|---:|---|
| save schema | 2（不 bump） | S4 全部持久欄位已在 schema 2 wire 往返；復用 TransactionReceiptState／next_item_serial，無新 wire 欄位 |
| save migration | 無 | 不 bump 即無 migration |
| content manifest generation | +1 | 首批內容產生新 pinned digest；舊 run 憑 catalog lease 續持舊 digest（非 migration 問題） |
| battle rule catalog | 1（擴充） | 沿用 try_trait_rule/try_equipment_rule/try_effect_rule；**新增 `BattleRelicRule`**（battle 類遺物→effect_ids）由 catalog builder 填入 |
| run catalog | 1（擴充） | 新增 `ForgeRecipeTable`（component-pair→equipment，21 封閉）與 `RunRelicTable`（economy/route/rule 類效果 intent），依既有 pin 慣例 |

## 3. 模組

```text
ContentRegistryService (pinned manifest digest)
  -> BuildSystemsCatalogBuilder
        -> BattleRuleCatalog   (traits/equipment/effects/+relic-battle rules)
        -> ForgeRecipeTable    (component_pair -> equipment_id, 21 closed)
        -> RunRelicTable       (relic_id -> {category, run effect intents})

RunController (copy-validate-save-swap)
  ├─ ForgeEquipmentCommand      (2 零件 -> 1 裝備, inventory/overflow)
  ├─ EquipItemCommand           (inventory 裝備 -> 棋, <=3 / unique_group)
  ├─ DismantleEquipmentCommand  (消耗 ConsumableDef -> 解綁 -> inventory/overflow)
  ├─ ResolveOverflowCommand     (裝備/鍛造/明確放棄; gate PREPARE 離開)
  └─ (既有) SellUnitCommand / ResolveRelicRewardCommand / ResolveItemRewardCommand

Combat entry:
  RunState(committed roster) + BattleRuleCatalog
    -> BattleSetupSourceCompiler --> BattleSetupSourceBundle
    -> StartCombatEvent (既有, 逐棋驗證==已提交 roster) -> BattleSimulation

Run-layer relic application:
  RunRelicTable -> IncomeService/ShopService(經濟) · MapService(路線) · Settlement/Rules(規則)

Build Lab (dev greybox):
  BuildLabSession -> {TraitPreview/Forge/Inventory/RelicSlot}ViewModel (只持 clone/snapshot)
                  -> RunController commands
```

`ForgeRecipeTable` 與 `RunRelicTable` 只保存 manifest digest＋解碼後的 typed rule；不保存 Resource、不做 latest-catalog lookup。`BattleSetupSourceCompiler` 為純函式式（讀 clone、回傳新 bundle），供 PREPARE 期預覽與 combat entry 共用同一份編譯結果（§4）。

## 4. 羈絆計數與戰前快照編譯（BattleSetupSourceCompiler）

- 新增 `domain/run/controller/combat/battle_setup_source_compiler.gd`；是羈絆計數/快照編譯的唯一家（S3 時只有 fixture 建 bundle，production 缺 producer）。
- `compile(committed_roster, catalog) -> BattleSetupSourceBundle`：純函式式、只讀 clone 與 pinned catalog，marks 全部 `*_sources_resolved=true`（battle_setup_source_bundle.gd:51）。
- 計數（S4-AC-001/002）：上場 placements 的**不同 def_id** set；板凳/同 ID 重複/召喚物不計；逐棋累加 trait_ids（含四隻指定棋子第三標籤，同一棋計入三個羈絆）；依 BattleTraitRule.thresholds（battle_trait_rule.gd:7）遞增比對決定啟動 tier；未達第一門檻不產出 snapshot。
- 快照凍結（S4-AC-003）：combat entry 前一次編譯，寫入 `BattleSetupInputs.player_active_traits`（battle_setup_inputs.gd:9）隨 BattleSetup hash 凍結；模擬期間 member_instance_ids 只讀、成員死亡不重算 tier（模擬不回呼編譯器）。**預覽同源**：PREPARE 期 ViewModel 對 roster clone 呼叫同一 `BattleSetupSourceCompiler.compile()`；StartCombatEvent 開戰重編譯＋既有 `_player_sources_match_committed_roster`（start_combat_event.gd:136-159）比對，不符即拒開戰（PLAYER_SOURCE_MISMATCH）。
- 裝備效果：逐上場棋 equipment_instance_ids → ItemInstanceState.def_id → try_equipment_rule（battle_equipment_rule.gd：stat_modifiers＋effect_ids＋unique_group）→ BattleEffectSnapshot(equipment) 綁定該棋 instance，寫入 player_equipment_effects（battle_setup_inputs.gd:10）。has_equipment 條件由 EffectResolver 既有支援（effect_resolver.gd:180,294-296）。
- 遺物（battle 類）：依 active_relic_slots 槽序 → BattleRelicRule.battle_effect_ids → try_effect_rule → BattleEffectSnapshot(relic)，寫入 player_relic_effects（battle_setup_inputs.gd:11）。非 battle 類遺物在此不產出（於 run 層作用，§6）。

## 5. 裝備鍛造與物品庫（狀態模型與交易切分）

狀態模型全部復用 S3 欄位（§1）：零件與完整裝備都是 `ItemInstanceState`（def_id 指向 ItemComponentDef 或 EquipmentDef）；位置三態互斥由 validator 保證（run_state_validator.gd:311-349）——綁定於棋、或在 inventory（≤16）、或在 overflow。validator 需擴充：綁定物必為 EquipmentDef（零件不可綁定）。

交易切分（每個都是獨立 copy-validate-save-swap command，回 CommandApplyResult，沿用 resolve_relic_reward_command.gd 的 command→service→result 慣例）：

1. **ForgeEquipmentCommand**（S4-AC-004/005）：兩個 inventory 零件 instance id →`ForgeRecipeTable` 以無序 component-pair（含相同零件自配）查恰一 equipment_id（21 封閉，查無即拒）→ 消耗兩零件、以 next_item_serial 產一件完整裝備入 inventory（滿則入 overflow）。單一 draft 原子；validation/read-back 失敗整份丟棄、物品庫不變。零件不可裝備（只有此 command 能合成）。
2. **EquipItemCommand**（S4-AC-006）：inventory 完整裝備 → 綁定至指定棋。前置驗證：equipment_instance_ids.size() < 3、無同 unique_group 衝突、目標為完整裝備非零件。違反則拒且狀態不變、回具名 error。
3. **DismantleEquipmentCommand**（S4-AC-007）：消耗一個拆卸 ConsumableDef（consumable_def.gd：run_operations/stack_limit）→ 同一交易解綁目標裝備、送回 inventory 或 overflow。任何驗證失敗不消耗道具。這是除出售（S3 SellUnitCommand 已實作帶裝回收）外唯一取回途徑。
4. **ResolveOverflowCommand**（S4-AC-008）：tray 一次性、非靜默丟棄；逐件明確選擇：裝備（走 Equip 邏輯）、鍛造（若為零件）、或明確放棄（移除該 instance）。**pending_item_overflow 非空為硬 gate**：拒絕開戰/離開 PREPARE（沿用 phase gate 慣例 run_state_validator.gd:546-565），保證無軟鎖。overflow 來源：升星（S3 merge 溢出）、出售、獎勵、鍛造入庫溢出。
- crash/load（S4-AC-009）：復用 S3 TransactionKeyState＋SHA-256 payload digest＋save 成功才 swap；crash 後重載恢復為交易前或後之一，exactly-once。S4 不新增機制，只確保 forge/equip/dismantle 各配 transaction receipt。

## 6. 遺物五槽與四類作用點

- 槽模型（S4-AC-010）：active_relic_slots 固定 5 槽（validator :272），slot_index 決定同時觸發序；啟用序＝依序填最小空槽。
- 第六件原子替換/放棄：S3 已實作（reward_service.gd:365-394，slot_index ∈ [-1,4]：-1=放棄、0–4=放入/替換；_first_empty_relic_slot :701-704）。被替換者該局永久移除、不轉貨幣（無局內遺物倉庫）；選擇走 reward 交易＋read-back，重載後槽序與結果不變。S4 不重做此流程，補「遺物效果實際作用」（S3 只存 relic_id 未套效果）。
- 四類作用點（S4-AC-011）——遺物不佔裝備格，依 RelicDef.category：

| 類別 | 作用點 | 機制 |
|---|---|---|
| 戰鬥 | BattleSetup.player_relic_effects | §4 compiler 產 BattleEffectSnapshot(relic)，依槽序進模擬 |
| 經濟 | IncomeService / ShopService 決策點 | RunRelicTable 於 income 計算（基礎/利息/連勝）與 shop odds/價格前，依槽序套用 intent；只讀 pinned rule、決定性 |
| 路線 | MapService / node reachability | 生成或可達性決策點依槽序套用（用既有 map stream，不新增 entropy） |
| 規則 | 戰鬥規則 / settlement | 進 BattleRulesSnapshotBuilder 輸入或 BattleSettlementService（如遠征 HP/獎勵修正），依槽序 |

作用點統一由 RunRelicTable 提供 typed intent（非 Dictionary），觸發序＝slot_index 升序，保證決定性。經濟/路線/規則效果**不**經 EffectResolver（戰鬥專用），而是各 run-layer service 讀 RunRelicTable 的具名 rule。

## 7. 內容授權（.tres）與驗證器擴充

- **隱含依賴**：ContentValidator.validate() 對整份 manifest 生效——硬性要求 32 棋子、6+6 羈絆、4 個三標籤、21 配方、6 零件、≥15 遺物、3 指揮官、≥12 monster、3 Boss、≥6 elite affix、≥12 event generator、完整 node 類型、challenge 鏈、economy/reward 表、單一 combat config（content_validator.gd:117-123,154-178,207-212）。故「通過驗證」必然要求完整可驗 catalog。
- **交付決策**（使用者裁決 2026-07-22）：
  1. **Build-systems 內容 pack**（本片權威）：12 TraitDef（6 陣營＋6 職能）＋TraitThresholdDef 遞增門檻、6 ItemComponentDef、21 EquipmentDef（含 component_pair/stat_modifiers/effect_refs/unique_group）、≥15 RelicDef（category 覆蓋 battle/economy/route/rule 四類）、≥1 拆卸 ConsumableDef，及其引用的 EffectDef。
  2. **垂直切片伴生 catalog**（TUNE 佔位、非最終平衡）：驗證器所需最小 units/encounters/commanders/nodes/economy/reward/combat-config 集合，讓 manifest 可 pin 可驗、Build Lab 可實跑。伴生內容標 TUNE；最終棋子/敵人授權屬下游 content-completion 橫切（SCOPE-002）。
- **驗證器新增規則**：(a) EquipmentDef.unique_group 一致性——has_unique_group=true 時 unique_group 為有效 stable-id、同組語意一致；(b) 遺物 category 覆蓋四類且各 ≥1、activation_limit 合法；(c) battle 類遺物 effect_refs 解為戰鬥可用 EffectDef、非 battle 類的 run effect intent 落在 RunRelicTable 支援 kind；(d) 拆卸 ConsumableDef 的 use_timing/run_operations 符合 dismantle 語意；(e) 零件不得被任何 equipment effect_refs/reward 當成完整裝備發放（零件僅 forge 消耗）。
- digest：通過後進 canonical snapshot 的 pinned manifest digest（既有 ContentRegistryService generation pin）。

## 8. Build Lab 灰盒與 ViewModel 契約

- Lab 場景：新增 `scenes/dev/build_lab/build_lab.tscn`＋`scripts/`，比照 expedition_lab／combat_lab 慣例（灰盒、僅開發用、非 domain correctness 證據）。`BuildLabSession` 持一個 RunController 實例，經 command 驅動 build 操作。
- ViewModel 介面切分（Codex 接正式 UI 的消費契約；全部只持 clone/snapshot、不保留 domain 可變引用、寫操作一律經 RunController command）：

| ViewModel | 讀（snapshot） | 寫（一律經 command） |
|---|---|---|
| `TraitPreviewViewModel` | BattleSetupSourceCompiler.compile() 的 TraitBattleSnapshot（當前數量/下一門檻/精確效果，與實戰同源） | 無（純預覽） |
| `ForgeViewModel` | inventory 零件清單＋ForgeRecipeTable 成品/效果/限制預覽 | ForgeEquipmentCommand |
| `InventoryViewModel` | RosterState 的 items/棋裝備/16 格/overflow tray 快照 | EquipItemCommand／DismantleEquipmentCommand／ResolveOverflowCommand |
| `RelicSlotViewModel` | active_relic_slots（槽序/內容）＋第六件替換候選 | ResolveRelicRewardCommand（既有） |

ViewModel 讀 RunController 提供的 read-only run snapshot（clone），任何操作回傳新 snapshot；驗證失敗回具名 error 供 UI 呈現。ViewModel 不得直接改 draft、不得跨操作快取可變 domain 物件。

## 9. 需求追溯

| Requirement | Design | Tasks |
|---|---|---|
| REQ-TRAIT-001 | §4 | T02、T08 |
| REQ-TRAIT-002 | §4 | T02、T08、T10 |
| REQ-ITEM-001 | §3/§5.1/§7 | T01、T03、T08 |
| REQ-ITEM-002 | §5.2–5.4 | T04、T05 |
| REQ-RELIC-001 | §4/§6 | T01、T02、T06、T08 |
| REQ-CONTENT-001（部分） | §7 | T07、T09 |
| REQ-UX-002（downstream） | §8 | T10、T11 |
| REQ-TECH-004 | §1/§5/§8 | T01–T05、T10 |
| S4-AC-001/002/003 | §4 | T02（內容樣本 T08） |
| S4-AC-004 | §5.1/§7 | T01、T03 |
| S4-AC-005 | §5.1 | T03 |
| S4-AC-006/007 | §5.2/§5.3 | T04 |
| S4-AC-008/009 | §5.4 | T05 |
| S4-AC-010/011 | §6 | T06 |
| S4-AC-012 | §7 | T07、T08、T09 |
| S4-AC-013 | §8 | T10、T11 |
| 全 AC 回歸＋soak | §10 | T12 |

## 10. Failure policy

- 所有 command 走 copy-validate-save-swap：validation／save／read-back 任一失敗 → 丟棄整份 draft、回具名 error，不 assert crash、不 silent null、不部分 mutation。
- 具名 error 情境：查無配方（forge）、零件當裝備、裝備逾 3 件、unique_group 衝突、拆卸道具不足、overflow tray 未清空即離開 PREPARE、遺物槽越界、非 battle 類遺物 intent 不受支援、內容 digest 不符（generation mismatch）。
- overflow tray 非空為硬 gate：拒絕開戰/離開 PREPARE，杜絕軟鎖（S4-AC-008）。
- 內容驗證：任一 issue 即 manifest 不可 pin；不虛構副本、不放行未知效果/形狀（沿用 ContentValidator 既有 issue 機制）。
- 範圍邊界（明列）：伴生 catalog（§7 第 2 點）為 TUNE 佔位以滿足驗證器與 Build Lab，非最終平衡；32 棋子完整美術與最終敵人/指揮官授權屬下游 content-completion 橫切（SCOPE-002），不在 S4 邏輯片。若後續授權改變 manifest，舊 run 憑既有 catalog lease 續持舊 digest（非 save migration）。
