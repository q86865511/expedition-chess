# G2 difficulty-curve — Tasks

- [x] **T00 HARD**：鎖 requirements/design/tasks、DC-REQ↔Acceptance 對應、架構 spec
  先行改動（REQ-ENEMY-003、AC-079、§4.3／§4.4／§5.13／§14）與 spec-issues 狀態回寫。
- [x] **T01 HARD/TDD**：`CombatConfigDef`／`BattleCombatConfigRule` 新增三個 per-act
  敵方成長 bps，`EncounterCompiler._build_unit_snapshot()` 疊乘、i32 守衛套縮放後值、
  battle golden 重算。（DC-REQ-001／Acceptance 1）
  交付：commit `7210653`；證據：`tests/unit/difficulty_curve/test_act_scaling.gd`、
  `tests/unit/battle_encounter/test_encounter_compiler.gd`（act2 13000bps 重算）、
  `tests/integration/difficulty_curve/test_act_scaling_and_formation_structural.gd`
  （Acceptance 1 逐條斷言）。
- [x] **T02 NORMAL/TDD**：`node_entry_service.gd` 依 `node.act_index` 決定性映射
  `encounter.slice_boss_0/1/2`，pin 集合缺 `slice_boss_1/2` 時 fail-closed。
  （DC-REQ-002／Acceptance 2）
  交付：commit `7210653`；證據：
  `tests/unit/economy_expediton/test_node_entry_service_boss_mapping.gd`
  （slice_boss_1 自 pinned 集合移除→act2 Boss 節點具名錯誤拒絕）、
  `test_act_scaling_and_formation_structural.gd`（三幕 Boss encounter id 互異）。
- [x] **T03 NORMAL**：五個 encounter 的多敵編成 authoring（design 表逐列落地），
  含 Boss `logical_x` 置中與內容驗證通過。（DC-REQ-003／Acceptance 3）
  交付：commit `39d79d3`；證據：
  `tests/integration/difficulty_curve/test_act_scaling_and_formation_structural.gd`
  （五個 encounter 敵方單位數 2／3／3／4／5、spawn_key 無重複、logical_y≥4）。
- [x] **T04 NORMAL**：24 個階梯 effect `.tres`＋48 loc key＋12 個 `TraitDef` 三階
  `effect_refs` 改指；compiler 零改動。（DC-REQ-004／Acceptance 4）
  交付：commit `39d79d3`；證據：
  `tests/unit/content_validation/test_build_systems_content_pack.gd`（12 個 TraitDef
  tier1/2/3 門檻各自指向獨立且遞增的 effect，loc key 缺項非零退出）。
- [x] **T05 NORMAL**：`slice_player_07` trait_refs verdant→shadow，全庫 faction 成員數
  與 tier-1 子集覆蓋掃描。（DC-REQ-005／Acceptance 5）
  交付：commit `39d79d3`；證據：
  `tests/unit/content_validation/test_vertical_slice_content_pack.gd`（全庫每個 faction
  trait 成員數 ≥6、tier-1 子集內每個 faction 至少 2 名成員）。
- [x] **T06 NORMAL**：`slice_challenge_affix_01/03` 回 challenge unlock `modifier_refs`，
  `content_validator.gd` 回復三桶 gate；`_02` 停用、BP-SI-002 續 OPEN。
  （DC-REQ-006／Acceptance 6）
  交付：commit `9c50910`；證據：
  `tests/unit/content_validation/test_challenge_affix_operation_validation.gd`
  （缺任一桶觸發 `CONTENT_CHALLENGE_AFFIX_COVERAGE`）、
  `test_global_effect_source_lifecycle_validation.gd`（純 run_operations 不進
  `BattleSetup` 負向案例維持紅）、
  `tests/integration/meta_progression/test_challenge_affix_content_authoring.gd`、
  `test_challenge_affix_end_to_end.gd`。
- [x] **T07 NORMAL/TDD**：driver reward／購買選取記正式 content stable ID 與 opaque
  fail-visible；`BalanceBotActSnapshot` 補 per-act battle win/loss 與死亡節點 ID。
  （DC-REQ-007／Acceptance 7）
  交付：commit `e72044f`；證據：
  `tests/unit/balance_playtest/test_balance_bot_act_snapshot_observability.gd`
  （per-act battle_wins/battle_losses/死亡節點 ID 改變反映於 canonical token）。
- [x] **T08 HARD/TDD**：`BALANCE_ACT_ELIMINATION_FLAT` gate（seed_count ≥ 1000 才啟用）
  ＋`act-elimination-gate.ps1` 鏡射模組（`run-sharded-cohort.ps1` dot-source 接線），
  雙實作 golden 一致性測試。
  （DC-REQ-008／Acceptance 8）
  交付：commit `8e97d5f`；證據：
  `tests/unit/balance_playtest/test_balance_act_elimination_gate.gd`＋
  `tools/balance/tests/test-act-elimination-gate.ps1` 對同一份
  `tests/fixtures/balance_playtest/act_elimination_golden.json`（5 scenarios）逐字比對
  `act_curve_token` 與 `BALANCE_ACT_` 前綴 gate reason 集合。
- [x] **T09 NORMAL/TDD**：曲線快篩三層——(a) 結構層驗證 T01–T03 合起來對每個 encounter
  產生跨幕嚴格遞增的敵方 HP/ATK 梯度（act2>act1、act3>act2），(b) 壓力層走正式
  RunController 鏈路驗證 Act2+ 確實出現真實損傷訊號（非結構層空生效），(c) 趨勢層
  read-back report 逐案 act_snapshots 欄位供人工判讀。「跨幕梯度」由 (a) 結構層斷言
  保證；(b) 只驗證「Act2+ 存在真實損傷」，不驗證「隨幕遞增」——W2-B 變異實測：把
  `act2_enemy_stat_bps` 改回 10000（曲線失效）時，
  `test_act_scaling_and_formation_structural.gd:66-89`
  （`test_act2_and_act3_enemy_totals_strictly_exceed_previous_act_for_every_encounter`
  的 act2>act1 嚴格遞增斷言，5 encounter × HP/ATK 共 10 條）轉紅，而
  `test_curve_pressure_and_report_trend.gd` 的 `damaged_snapshot_count>0` 斷言在該變異下
  仍可能維持綠（act3 仍有損傷）——(b) 不承擔梯度守門責任，這是本任務描述「驗證跨幕梯度」
  時容易誤讀之處（T11 F5 閉環：原措辭未區分兩層各自的守門範圍）。
  交付：commit `8e97d5f`；證據：
  `tests/integration/difficulty_curve/test_act_scaling_and_formation_structural.gd`
  （(a) 結構層梯度斷言）、
  `tests/integration/difficulty_curve/test_curve_pressure_and_report_trend.gd`
  （(b)(c) 壓力層損傷訊號＋趨勢層 read-back）。
- [x] **T10 HARD**：3k screening、`-Suite All`、10k ExpeditionSoak、逐 Acceptance fresh
  evidence 與文件回寫（PROGRESS／HANDOFF／CLAUDE.md 目前切片／evidence-index）。
  交付：本次文件回寫；證據：`artifacts/test/balance-playtest-screening.json`（gate
  PASS、candidate `balance.g2.041458b08bb5`、git_head `b2c7895`、3,000/3,000
  terminal、150/150 replay 零 drift）、`artifacts/test/gut.xml`（1,193 tests／0
  failures）、`artifacts/test/expedition-soak.json`（10,000/10,000 seeds passed）。
- [x] **T11 HARD**：兩份獨立 implementation review、finding closure 與證據鎖定，
  停 Git gate 待使用者裁決。

依賴：T00→全部；T01／T02／T03→T09；T07→T08；T08／T09→T10→T11。
