# G2 difficulty-curve — Tasks

- [x] **T00 HARD**：鎖 requirements/design/tasks、DC-REQ↔Acceptance 對應、架構 spec
  先行改動（REQ-ENEMY-003、AC-079、§4.3／§4.4／§5.13／§14）與 spec-issues 狀態回寫。
- [ ] **T01 HARD/TDD**：`CombatConfigDef`／`BattleCombatConfigRule` 新增三個 per-act
  敵方成長 bps，`EncounterCompiler._build_unit_snapshot()` 疊乘、i32 守衛套縮放後值、
  battle golden 重算。（DC-REQ-001／Acceptance 1）
- [ ] **T02 NORMAL/TDD**：`node_entry_service.gd` 依 `node.act_index` 決定性映射
  `encounter.slice_boss_0/1/2`，pin 集合缺 `slice_boss_1/2` 時 fail-closed。
  （DC-REQ-002／Acceptance 2）
- [ ] **T03 NORMAL**：五個 encounter 的多敵編成 authoring（design 表逐列落地），
  含 Boss `logical_x` 置中與內容驗證通過。（DC-REQ-003／Acceptance 3）
- [ ] **T04 NORMAL**：24 個階梯 effect `.tres`＋48 loc key＋12 個 `TraitDef` 三階
  `effect_refs` 改指；compiler 零改動。（DC-REQ-004／Acceptance 4）
- [ ] **T05 NORMAL**：`slice_player_07` trait_refs verdant→shadow，全庫 faction 成員數
  與 tier-1 子集覆蓋掃描。（DC-REQ-005／Acceptance 5）
- [ ] **T06 NORMAL**：`slice_challenge_affix_01/03` 回 challenge unlock `modifier_refs`，
  `content_validator.gd` 回復三桶 gate；`_02` 停用、BP-SI-002 續 OPEN。
  （DC-REQ-006／Acceptance 6）
- [ ] **T07 NORMAL/TDD**：driver reward／購買選取記正式 content stable ID 與 opaque
  fail-visible；`BalanceBotActSnapshot` 補 per-act battle win/loss 與死亡節點 ID。
  （DC-REQ-007／Acceptance 7）
- [ ] **T08 HARD/TDD**：`BALANCE_ACT_ELIMINATION_FLAT` gate（seed_count ≥ 1000 才啟用）
  ＋`run-sharded-cohort.ps1` 鏡射，雙實作 golden 一致性測試。
  （DC-REQ-008／Acceptance 8）
- [ ] **T09 NORMAL/TDD**：曲線快篩三層（act1／act2／act3 各自的到達率與敗局分布）
  驗證 T01–T03 合起來確實產生跨幕梯度，非單點回歸。
- [ ] **T10 HARD**：3k screening、`-Suite All`、10k ExpeditionSoak、逐 Acceptance fresh
  evidence 與文件回寫（PROGRESS／HANDOFF／CLAUDE.md 目前切片／evidence-index）。
- [ ] **T11 HARD**：兩份獨立 implementation review、finding closure 與證據鎖定，
  停 Git gate 待使用者裁決。

依賴：T00→全部；T01／T02／T03→T09；T07→T08；T08／T09→T10→T11。
