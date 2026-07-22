# S4 build-systems 任務清單

> 狀態：已核可（2026-07-22）
> 對應設計：[design.md](design.md)；需求：[requirements.md](requirements.md)
> 測試框架既有（GUT 9.7.1＋runner 契約），無需 T0 建框架。TDD 標記為 S4 新增慣例（S3 未逐條標）；TDD 任務走「測試先行→紅證據→鎖定→實作轉綠→Verify fresh 重跑」分代理流程。
> 勾選（`- [ ]`→`- [x]`）只由實作流程收尾階段回寫。

## Gate A — catalog 與編譯器

- [x] **T01 [HARD][TDD] Catalog 擴充：BattleRelicRule＋ForgeRecipeTable＋RunRelicTable**
  - Covers：REQ-ITEM-001（配方表）、REQ-RELIC-001（規則表）、S4-AC-004（封閉枚舉）
  - 驗收：battle catalog 新增 relic rule 並經 builder 填入；ForgeRecipeTable 無序配對（含自配）21 封閉、任一零件可反查；RunRelicTable 回 typed intent（非 Dictionary）；catalog 只依 pinned manifest 建構。
- [ ] **T02 [HARD][TDD] BattleSetupSourceCompiler（羈絆計數/快照/裝備/battle 遺物編譯）**
  - Covers：REQ-TRAIT-001/002、REQ-RELIC-001（battle 類）、S4-AC-001/002/003
  - 依賴：T01
  - 驗收：計數排除板凳/同 ID/召喚物；第三標籤三重計入；tier 依門檻遞增判定；快照凍結死亡不重算；preview 與 combat entry 用同一 compile 結果逐欄位相等；StartCombatEvent 的 roster 比對通過。

## Gate B — 構築操作 command

- [ ] **T03 [HARD][TDD] ForgeEquipmentCommand**
  - Covers：REQ-ITEM-001、S4-AC-004/005；依賴：T01
  - 驗收：兩零件（含相同）消耗→恰一裝備入庫（滿則 overflow）；查無配方拒；零件不可直接裝備；交易失敗物品庫不變；配 transaction receipt。
- [x] **T04 [NORMAL][TDD] EquipItemCommand＋DismantleEquipmentCommand＋validator 擴充**
  - Covers：REQ-ITEM-002、S4-AC-006/007
  - 驗收：3 件上限、unique_group 衝突、裝零件皆拒且回具名 error；拆卸消耗道具、失敗不消耗；裝備搬移全程恰一實例；validator 新增「綁定物必為 EquipmentDef」不變式。
- [ ] **T05 [HARD][TDD] ResolveOverflowCommand＋overflow 硬 gate＋crash/load 整合**
  - Covers：REQ-ITEM-002、S4-AC-008/009；依賴：T03、T04
  - 驗收：tray 逐件明確處置（裝備/鍛造/明確放棄）、無靜默丟棄；tray 非空拒絕開戰/離開 PREPARE；出售帶 3 裝棋子交易中斷→重載恢復為前或後、exactly-once。

## Gate C — 遺物作用點

- [ ] **T06 [HARD][TDD] 遺物 run-layer 作用點（經濟/路線/規則）＋槽序觸發**
  - Covers：REQ-RELIC-001、S4-AC-010/011；依賴：T01
  - 驗收：經濟型於 income/shop 決策點生效；路線型於 MapService 生效（沿用 map stream 無新 entropy）；規則型進 rules snapshot/settlement；同時觸發依 slot_index 升序；第六件替換後效果集合正確且重載不變（回歸 S3 替換流程）。

## Gate D — 內容與驗證器

- [x] **T07 [NORMAL][TDD] 內容驗證器擴充規則**
  - Covers：REQ-CONTENT-001（部分）、S4-AC-012
  - 驗收：unique_group 一致性、遺物四類各 ≥1 且 activation_limit 合法、battle 類 effect_refs 可解、拆卸道具 run_operations 語意、零件不得作為完整裝備發放——五類規則各有紅→綠測試。
- [ ] **T08 [NORMAL][免TDD：內容資料授權，由 T07 驗證器與 content suite 自動驗收] 構築內容 pack（.tres）**
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

## Dependency order

T01 → {T02, T03, T06}；T03+T04 → T05；T07 → T08 → T09；{T02~T06} → T10 → T11；全部 → T12。
可並行波次：wave1 = T01、T07（＋T04 無上游依賴可並行）；wave2 = T02、T03、T06、T08；wave3 = T05、T09、T10；wave4 = T11、T12。

## 雙向覆蓋檢查

- 每任務皆對應至少一 REQ/AC（見各 Covers）。
- 每 AC 至少一任務：AC-001/002/003→T02（內容樣本 T08）；AC-004→T01/T03；AC-005→T03；AC-006/007→T04；AC-008/009→T05；AC-010/011→T06；AC-012→T07/T08/T09；AC-013→T10/T11；全 AC 回歸→T12。
- 每 traced REQ 至少一任務：TRAIT-001/002→T02/T08；ITEM-001→T01/T03/T08；ITEM-002→T04/T05；RELIC-001→T01/T02/T06/T08；CONTENT-001→T07/T09；UX-002/TECH-004→T10/T11。

## Completion ledger

- [2026-07-23] wave1（T01／T04／T07）完成。TDD 紅綠證據：`.pipeline/tdd/w1-*`（紅證據產於實作前；三處測試檔 GDScript Parse Error／fixture 漂移經主迴圈測試爭議裁決修正並重算 manifest）。雙審：Sonnet `.pipeline/reviews/2026-07-22-sonnet-w1.md`＋Opus `.pipeline/reviews/2026-07-22-reviewer-w1.md`；裁決 F1~F5 全修（validator 不變式接入 RunController commit 路徑＋世代守衛、dismantle 以 ConsumableRuleTable 驗拆卸語意、equip 加 catalog digest 比對、forge builder 驗 1/2 元配方形狀、relic effect_refs 非空且必為 EffectDef）。修正後 Gut 275/275、`-Suite All` exit 0。備註：RunController 的 battle_catalog 為選填參數，正式 composition root 接線（T10/T11）必須傳入 pinned catalog。
