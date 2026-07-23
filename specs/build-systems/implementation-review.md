# S4 build-systems 實作複檢（逐 AC 證據）

> 狀態：完成（2026-07-24）
> 驗證環境：Godot 4.7.stable（SHA256 與 toolchain.lock 相符）；`tools/run-tests.ps1` 各 suite；證據 artifacts 位於本機 `artifacts/test/`（gitignored）。
> 流程：4 個實作波次（wave1~4）× TDD 分代理（紅證據→鎖定→轉綠→fresh 重驗）× 每波 Sonnet＋Opus 雙獨立審查（證據 `.pipeline/reviews/`，共 8 份）× 逐波使用者裁決修正。

## 最終 gate（fresh，2026-07-24）

- 全 GUT suite：**399 tests 全綠**（爭議修正後，見下）；Spec 契約 suite 3274+ cases 綠。
- `-Suite All` exit 0（Toolchain/Import/Smoke/Gut/Content/Canonical/Combat/Soak/Expedition/Spec/RunnerContract）。
- 10,000-seed ExpeditionSoak exit 0——每 seed 織入 4 步決定性構築操作（鍛造→換裝→拆卸→overflow 處置，共 **40,000 次構築操作**），含 item 守恆斷言與前 64 seed 逐位元 replay 比對。

## 逐 S4-AC 證據對照

| AC | 判定 | 主要證據（測試/檔案） |
|---|---|---|
| S4-AC-001 羈絆計數正確性 | PASS | `test_battle_setup_source_compiler.gd`（排板凳/同 ID/召喚物；10/10） |
| S4-AC-002 標籤結構與門檻 | PASS | 同上（第三標籤三重計入、tier 遞增判定）＋正式內容 12 TraitDef（`content/packs/build_systems/traits/`）與 32 棋子 trait 對應（4 隻三標籤，`test_vertical_slice_content_pack.gd`） |
| S4-AC-003 戰前快照/死亡不關閉/預覽同源 | PASS | compiler 兩次 compile 逐欄位相等＋StartCombatEvent roster 比對；死亡不重算整合案例 `test_trait_effect_persists_through_member_death.gd`（BattleSimulation 實跑，效果逐 tick 觸發到戰鬥結束） |
| S4-AC-004 21 配方封閉枚舉 | PASS | `test_forge_recipe_table.gd`（無序配對含自配 21 封閉、反查、1/2 元形狀防禦） |
| S4-AC-005 鍛造原子交易 | PASS | `test_forge_equipment_command.gd`＋`test_forge_equipment_command_transaction.gd`（消耗/產出/serial/overflow/世代守衛/失敗不變） |
| S4-AC-006 裝備上限與 unique_group | PASS | `test_equip_item_command.gd`（第 4 件拒、同組拒、裝零件拒、digest 拒） |
| S4-AC-007 綁定/取回/搬移不複製 | PASS | `test_dismantle_equipment_command.gd`（ConsumableRuleTable 驗拆卸語意、失敗不消耗）＋S3 SellUnitCommand 帶裝回收回歸 |
| S4-AC-008 16 格與 overflow tray | PASS | `test_resolve_overflow_command.gd`（12/12：三種處置、具名拒絕、tray 夥伴鍛造）＋`test_overflow_phase_gate.gd`（兩出口早退）＋`test_run_state_validator_overflow_phase_gate.gd`（validator 最終防線：COMBAT/MAP/RESULTS 期 tray 必空） |
| S4-AC-009 出售帶裝棋 crash/load | PASS | `test_sell_equipped_unit_crash_load.gd`（恢復為前或後、exactly-once；復用 S3 交易機制） |
| S4-AC-010 遺物 5 槽與第六件原子替換 | PASS | `test_relic_run_layer_regression.gd`（替換後效果集合＋save/reload 槽序不變）；S3 既有替換交易回歸 |
| S4-AC-011 遺物四類作用域 | PASS | battle→compiler 槽序進模擬；economy/route/rule→`test_income_service_relics.gd`／`test_shop_service_relics.gd`／`test_map_service_relics.gd`／`test_battle_settlement_relics.gd`；「不經 EffectResolver」由兩波雙審查呼叫路徑判通過（w2/w4 審查證據）；生產接線（command/event 層傳入 relic_table＋槽序 active ids）於 T12 補齊 |
| S4-AC-012 正式內容與驗證器 | PASS | 雙 pack（`content/packs/build_systems/` 90 資源＋`content/packs/vertical_slice/` 100+ 資源）`install_validated` 0 issue、digest pin＋registry 往返（`test_build_systems_content_pack.gd`、`test_vertical_slice_content_pack.gd`）；驗證器 S4 新規則十餘條各有紅→綠測試 |
| S4-AC-013 Build Lab 與 ViewModel 契約 | PASS | `presentation/viewmodels/` 四件套（deep-clone 隔離契約測試、具名 error 透傳、寫端經 dispatch）；`test_build_lab.gd`＋Smoke suite（真雙 pack、ContentRegistryReceiptAdapter、save/load 往返、五種操作流） |

## 波次與雙審軌跡

| 波 | 任務 | 雙審證據 | 裁決修正 |
|---|---|---|---|
| wave1 | T01/T04/T07 | `2026-07-22-sonnet-w1.md`＋`2026-07-22-reviewer-w1.md` | F1~F5 全修（validator 不變式接 RunController＋世代守衛、拆卸驗 ConsumableDef、equip digest、forge 形狀、effect_refs 非空） |
| wave2 | T02/T03/T06/T08 | `2026-07-23-sonnet-w2.md`＋`2026-07-23-reviewer-w2-r2.md` | W2-F1~F3/F6 修（裝備開戰路徑、拒不支援 intent＋死內容、收入/折扣拆 kind、NORMAL/ELITE 對等） |
| wave3 | T05/T09/T10 | `2026-07-23-sonnet-w3.md`＋`2026-07-23-reviewer-w3.md`＋`-w3-t10.md` | W3-F1~F6/F8 修（覆蓋測試、gate 集中 validator、HANDOFF 契約補充、SYNC 註解） |
| wave4 | T11/T12＋內容缺口 | `2026-07-24-sonnet-w4.md`＋`2026-07-24-reviewer-w4.md` | W4-F1~F6/F8/F9 修（claim_scope 雙層封洞＝run intent 一律 always、validator↔builder 對齊、經濟欄位測試、soak 守恆、死碼清理、文件同步）；F7 接受不修 |

## 已知邊界（如實記載，非缺陷）

- 遺物 `claim_scope` 的 S4 語意＝`always`（與消費端行為一致）；`once_per_node`/`on_first_clear` 的真語意（防重放）屬 S5，validator＋builder 雙層拒絕非 always 的 run intent。
- command 層 `relic_table` 為選填參數——正式 composition root（S5）接線必須顯式傳入，忘傳靜默跳過遺物效果（HANDOFF §4「S5 接手檢查項」）。
- 內容數值全 TUNE 佔位（雙 pack README 註明），最終平衡屬下游；32 棋子完整美術屬橫切 SCOPE-002（Codex）。
- `-Suite All` 的 expedition-soak 證據有新鮮度門檻：domain 程式碼變更後需重跑 `-Suite ExpeditionSoak -SeedCount 10000` 再跑 All。
