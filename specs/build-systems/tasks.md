# S4 build-systems 任務清單

> 狀態：已核可（2026-07-22）
> 對應設計：[design.md](design.md)；需求：[requirements.md](requirements.md)
> 測試框架既有（GUT 9.7.1＋runner 契約），無需 T0 建框架。TDD 標記為 S4 新增慣例（S3 未逐條標）；TDD 任務走「測試先行→紅證據→鎖定→實作轉綠→Verify fresh 重跑」分代理流程。
> 勾選（`- [ ]`→`- [x]`）只由實作流程收尾階段回寫。

## Gate A — catalog 與編譯器

- [x] **T01 [HARD][TDD] Catalog 擴充：BattleRelicRule＋ForgeRecipeTable＋RunRelicTable**
  - Covers：REQ-ITEM-001（配方表）、REQ-RELIC-001（規則表）、S4-AC-004（封閉枚舉）
  - 驗收：battle catalog 新增 relic rule 並經 builder 填入；ForgeRecipeTable 無序配對（含自配）21 封閉、任一零件可反查；RunRelicTable 回 typed intent（非 Dictionary）；catalog 只依 pinned manifest 建構。
- [x] **T02 [HARD][TDD] BattleSetupSourceCompiler（羈絆計數/快照/裝備/battle 遺物編譯）**
  - Covers：REQ-TRAIT-001/002、REQ-RELIC-001（battle 類）、S4-AC-001/002/003
  - 依賴：T01
  - 驗收：計數排除板凳/同 ID/召喚物；第三標籤三重計入；tier 依門檻遞增判定；快照凍結死亡不重算；preview 與 combat entry 用同一 compile 結果逐欄位相等；StartCombatEvent 的 roster 比對通過。

## Gate B — 構築操作 command

- [x] **T03 [HARD][TDD] ForgeEquipmentCommand**
  - Covers：REQ-ITEM-001、S4-AC-004/005；依賴：T01
  - 驗收：兩零件（含相同）消耗→恰一裝備入庫（滿則 overflow）；查無配方拒；零件不可直接裝備；交易失敗物品庫不變；配 transaction receipt。
- [x] **T04 [NORMAL][TDD] EquipItemCommand＋DismantleEquipmentCommand＋validator 擴充**
  - Covers：REQ-ITEM-002、S4-AC-006/007
  - 驗收：3 件上限、unique_group 衝突、裝零件皆拒且回具名 error；拆卸消耗道具、失敗不消耗；裝備搬移全程恰一實例；validator 新增「綁定物必為 EquipmentDef」不變式。
- [ ] **T05 [HARD][TDD] ResolveOverflowCommand＋overflow 硬 gate＋crash/load 整合**
  - Covers：REQ-ITEM-002、S4-AC-008/009；依賴：T03、T04
  - 驗收：tray 逐件明確處置（裝備/鍛造/明確放棄）、無靜默丟棄；tray 非空拒絕開戰/離開 PREPARE；出售帶 3 裝棋子交易中斷→重載恢復為前或後、exactly-once。

## Gate C — 遺物作用點

- [x] **T06 [HARD][TDD] 遺物 run-layer 作用點（經濟/路線/規則）＋槽序觸發**
  - Covers：REQ-RELIC-001、S4-AC-010/011；依賴：T01
  - 驗收：經濟型於 income/shop 決策點生效；路線型於 MapService 生效（沿用 map stream 無新 entropy）；規則型進 rules snapshot/settlement；同時觸發依 slot_index 升序；第六件替換後效果集合正確且重載不變（回歸 S3 替換流程）。

## Gate D — 內容與驗證器

- [x] **T07 [NORMAL][TDD] 內容驗證器擴充規則**
  - Covers：REQ-CONTENT-001（部分）、S4-AC-012
  - 驗收：unique_group 一致性、遺物四類各 ≥1 且 activation_limit 合法、battle 類 effect_refs 可解、拆卸道具 run_operations 語意、零件不得作為完整裝備發放——五類規則各有紅→綠測試。
- [x] **T08 [NORMAL][免TDD：內容資料授權，由 T07 驗證器與 content suite 自動驗收] 構築內容 pack（.tres）**
  - Covers：REQ-TRAIT-001/002、REQ-ITEM-001、REQ-RELIC-001、S4-AC-002/012；依賴：T07
  - 驗收：12 TraitDef（6+6，含 4 隻三標籤棋對應）、遞增門檻；6 ItemComponentDef；21 EquipmentDef（含 unique_group 樣本）；≥15 RelicDef（四類皆有）；≥1 拆卸 ConsumableDef；引用 EffectDef 齊備；全數通過驗證器。
- [ ] **T09 [NORMAL][免TDD：內容資料授權，同 T08] 垂直切片伴生 catalog（TUNE 佔位）＋manifest pin**
  - Covers：S4-AC-012；依賴：T07、T08
  - 驗收：驗證器要求的完整 manifest（32 棋子/敵人/指揮官/節點/經濟/獎勵/戰鬥 config，數值標 TUNE）可 pin、digest 進 canonical snapshot；content/canonical suite 綠。

## Gate E — 介面層與收尾

- [ ] **T10 [NORMAL][TDD] ViewModel 四件套（TraitPreview/Forge/Inventory/RelicSlot）**
  - Covers：REQ-UX-002（downstream）、REQ-TECH-004、S4-AC-013；依賴：T02~T06
  - 驗收：讀端只持 clone/snapshot（契約測試：改 ViewModel 持有物不影響 domain）；寫端一律經 command；驗證失敗回具名 error。
- [ ] **T11 [NORMAL][免TDD：開發灰盒，驗收走 headless smoke 而非單元紅綠] Build Lab 灰盒場景**
  - Covers：S4-AC-013；依賴：T10
  - 驗收：比照 expedition_lab 慣例；可經 ViewModel 完成鍛造/換裝/遺物替換/羈絆預覽操作流；headless smoke 通過。
- [ ] **T12 [HARD][TDD] S4 整合驗收＋soak**
  - Covers：全部 S4-AC 回歸、S4-AC-009/010 持久性；依賴：T01~T11
  - 驗收：逐 S4-AC 整合測試綠；`run-tests.ps1 -Suite All` 綠；含構築操作的 soak（比照 S3 ExpeditionSoak，種子數正式跑 10000）通過；追溯表回填。
  - 補充（2026-07-23 untestable 裁決，使用者核可）：整合測試必須含「羈絆成員戰鬥中死亡→已啟動羈絆效果持續到戰鬥結束」明確案例（S4-AC-003 子句，T02 單元層無法表達）；「run-layer 遺物不經 EffectResolver」（S4-AC-011 子句）由雙審 code review 驗證呼叫路徑。
  - 補充（2026-07-23 T02 實作觀察）：整合測試必須含「帶裝備棋子實際開戰通過 v2 驗證」案例——`BattleSetupInputsValidator._validate_source_list` 對 `player_equipment_effects` 的 owner_mode 為 `player_unit`（要求 source_instance_id 解為棋 instance），與 design §4／T02 鎖定測試的「source_instance_id=物品 instance id」存在契約張力，T02 fixture 無裝備未觸發，T12 需對齊（調整 validator owner_mode 或改綁 wearer）。→ 已於 wave2 修正（W2-F1，使用者裁決 2026-07-23）：依 design §4 保留 compiler（source_instance_id=物品 instance id、target_ids=[穿戴棋]），改 `battle_setup_inputs_validator.gd` 的 equipment owner 驗證 `player_unit`→`equipment`（物品 id 非空＋target 恰一且為上場 player 棋），並同步修正 v2 source-graph 排序改依穿戴棋(target)格序；回歸測試 `test_compiled_bundle_with_equipment_passes_start_combat_event`（1~3 件裝備開戰）已綠。T12 仍保留此回歸案例。
  - 補充（2026-07-23 wave2 雙審延後項，使用者裁決）：(a) W2-F5——`RunRelicOperationRule.claim_scope` 已解碼但無消費點（on_first_clear 等 scope 語意未被遵守），T12/正式接線時定 scope 語意並補防重放；(b) W2-F7——economy/map/settlement 服務收 relic_table 時未比對 manifest digest 世代，T12 接線時統一加世代守衛（比照 forge/equip 慣例）。

## Dependency order

T01 → {T02, T03, T06}；T03+T04 → T05；T07 → T08 → T09；{T02~T06} → T10 → T11；全部 → T12。
可並行波次：wave1 = T01、T07（＋T04 無上游依賴可並行）；wave2 = T02、T03、T06、T08；wave3 = T05、T09、T10；wave4 = T11、T12。

## 雙向覆蓋檢查

- 每任務皆對應至少一 REQ/AC（見各 Covers）。
- 每 AC 至少一任務：AC-001/002/003→T02（內容樣本 T08）；AC-004→T01/T03；AC-005→T03；AC-006/007→T04；AC-008/009→T05；AC-010/011→T06；AC-012→T07/T08/T09；AC-013→T10/T11；全 AC 回歸→T12。
- 每 traced REQ 至少一任務：TRAIT-001/002→T02/T08；ITEM-001→T01/T03/T08；ITEM-002→T04/T05；RELIC-001→T01/T02/T06/T08；CONTENT-001→T07/T09；UX-002/TECH-004→T10/T11。

## Completion ledger

- [2026-07-23] wave2（T02／T03／T06／T08）完成。TDD 紅綠證據：`.pipeline/tdd/w2-*`（T02/T06 各有 untestable 裁決：digest 拒絕依 design 原文由 StartCombatEvent 把關、死亡不重算移 T12 整合、不經 EffectResolver 由雙審查呼叫路徑——兩審皆判通過；T06 三處測試爭議裁決修正）。內容 pack：`content/packs/build_systems/` 90 資源。雙審：Opus `.pipeline/reviews/2026-07-23-reviewer-w2-r2.md`＋Sonnet `2026-07-23-sonnet-w2.md`；裁決修 W2-F1（裝備開戰路徑：validator equipment owner 依 design §4 對齊＋v2 排序修正）、W2-F2（builder 拒不支援 intent＋4 件死內容遺物改支援組合）、W2-F3（收入/折扣拆 kind：add_gold=income、新 shop_discount=商店）、W2-F6（NORMAL/ELITE 規則數對等不變式）；F4 保留防禦不修；F5/F7 記入 T12。修正後 Gut 333/333、`-Suite All` exit 0、10000-seed ExpeditionSoak exit 0。
- [2026-07-23] wave1（T01／T04／T07）完成。TDD 紅綠證據：`.pipeline/tdd/w1-*`（紅證據產於實作前；三處測試檔 GDScript Parse Error／fixture 漂移經主迴圈測試爭議裁決修正並重算 manifest）。雙審：Sonnet `.pipeline/reviews/2026-07-22-sonnet-w1.md`＋Opus `.pipeline/reviews/2026-07-22-reviewer-w1.md`；裁決 F1~F5 全修（validator 不變式接入 RunController commit 路徑＋世代守衛、dismantle 以 ConsumableRuleTable 驗拆卸語意、equip 加 catalog digest 比對、forge builder 驗 1/2 元配方形狀、relic effect_refs 非空且必為 EffectDef）。修正後 Gut 275/275、`-Suite All` exit 0。備註：RunController 的 battle_catalog 為選填參數，正式 composition root 接線（T10/T11）必須傳入 pinned catalog。
