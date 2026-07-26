# S5 meta-progression 任務清單

> 狀態：已核可（2026-07-24）
> 對應需求：[requirements.md](requirements.md) S5-AC-001~014；設計依據：[design.md](design.md)
> 本檔為 /pipeline 任務清單來源：pipeline 第 1 步直接採用本清單與 HARD/NORMAL 標記，不重新拆解。
> 勾選（`- [x]`）只由 pipeline 第 5 步收尾回寫，其他階段不動。
> TDD 慣例：標 [TDD] 者先派測試代理依 design.md §12 測試策略表產紅燈證據、測試鎖定後再派實作代理轉綠；免TDD 附一句理由。

## Gate A — 結算與存檔地基

- [x] **T01 [NORMAL][TDD] MetaRewardComputeService＋slice_default 對齊**
  - Covers：REQ-META-004、S5-AC-006；依賴：無
  - 驗收：compute 純函式對表計算（floor(base·bps/10000)、completion 僅 COMPLETED、failure 無加成、非戰鬥節點 0）；`meta_reward_tables/slice_default.tres` 對齊 §7.3（elite 2→3、merchant/event/treasure 1→0、failure 2→0；normal1/boss5/completion10/bps 10000..15000 不變）；同輸入同輸出。
- [x] **T02 [HARD][TDD] MetaSettlementCommand/Service（exactly-once receipt writer）**
  - Covers：REQ-META-004、REQ-DATA-007、REQ-TECH-004、S5-AC-007、S5-AC-009（紀錄更新段）；依賴：T01、T03
  - 驗收：FINISH_RUN 單一原子交易提交貨幣/receipt/highest_challenge_level/per-commander 紀錄/run=null；receipt key＝`build_settlement_receipt(run_id)`＋冪等守衛（已含 key→delta=0 仍清 run）；`RunStateValidator` 對 settlement_receipts 重編碼＋去重、重複 tuple 拒載；存檔各故障點終止×3 重載恰加值一次；ACKNOWLEDGE_RESULTS 無提交回 CAMP。
- [x] **T03 [NORMAL][TDD] ProfileState/RunState 擴欄＋save schema 3＋migration**
  - Covers：REQ-SAVE-001、REQ-SAVE-003、S5-AC-012（欄位載體段）；依賴：無
  - 驗收：`last_selection`（可 null）/`commander_challenge_records`/`RunState.discovered_content_ids` 編解碼往返；`SaveSchemaContract.CURRENT` 2→3；v2→v3 migration（預設 null/[]/[]）＋保留 schema-2 fixture 且 migration 測試綠；validator 驗新欄型別與 records 唯一性；既有 8 欄往返不變。

## Gate B — Camp 交易層

- [x] **T04 [HARD][TDD] CampController＋PurchaseUnlockCommand＋CampSaveRootFactory**
  - Covers：REQ-TECH-002、REQ-TECH-004、REQ-TECH-006、S5-AC-011；依賴：T03
  - 驗收：profile 範疇 copy-validate-save-swap（clone→validate→SaveRepository.save→swap）；`UNLOCK_INSUFFICIENT_CURRENCY`/`UNLOCK_ALREADY_OWNED`/`UNLOCK_PREREQUISITE_UNMET` 具名 error 且零變更；成功扣款＋unlocked_content_ids（sorted/unique）原子提交；run=null SaveRoot 寫讀通過。
- [x] **T05 [HARD][TDD] StartExpeditionCommand＋RunBootstrapService**
  - Covers：REQ-META-003、REQ-DATA-006、REQ-TECH-006、S5-AC-002、S5-AC-009（前置檢查段）；依賴：T03、T04
  - 驗收：commander 未解鎖/挑戰前置未滿足→具名 error 拒選；RunState 鎖 commander_id（無 command 可改）、challenge_level、snapshot 釘當前 generation、決定性 run_seed（profile_id＋next_run_serial）、starting_pack 播種 roster、population cap 套 population_bonus；指揮官不入 placements/不佔人口；profile' 寫 next_run_serial+1＋last_selection；START_RUN 轉 RUN。

## Gate C — 注入機制

- [x] **T06 [HARD][TDD] 指揮官被動注入（RunModifierTableBuilder＋BattleSetupSourceCompiler）**
  - Covers：S5-AC-003；依賴：無
  - 驗收：`RunRelicRule.source`（預設 relic）＋`RunRelicTable.sum_always_active`/`always_active_count`；四個 run 層作用點消費端在 slot-gated 後加 always-active 貢獻；決定性順序（slot 升序→commander→challenge 字典序）；battle 層 `commander_passive_effect_ids` 產 `source_category="commander"`/`source_side="player"` snapshot 進 BattleSetup hash；既有 slot-gated 行為不變（S4 測試全綠）。
- [x] **T07 [HARD][TDD] 挑戰詞綴雙軌機制＋內容著作**
  - Covers：S5-AC-010、S5-AC-009（端到端段）、REQ-UX-005；依賴：T05、T06、T08
  - 驗收：`ChallengeAffixResolver` 1..N 累積（sorted/dedup/分軌）；軌 A 經 `EncounterCompileRequest.challenge_affix_effect_ids` 進 `_compile_affixes` 合併去重；軌 B 新 `ShopSurchargeOperationDef`/`DrainExpeditionHpOperationDef`（amount≥0）＋shop/settlement 作用點消費端實際生效（surcharge 提高成本、drain 加深戰敗損失、clamp 沿用）＋validator 解碼分支；五條 `effect.slice_challenge_affix_00..04`（content_role=challenge_affix、四類全覆蓋、loc key）＋重指 slice_challenge_1..5 modifier_refs；指揮官被動內容補實且三名非同一效果數值階級；菁英詞綴/map nodes 不動；Ch0 無詞綴；ExpeditionGate 開局前完整列出。
- [x] **T08 [HARD][TDD] claim_scope 真語意（once_per_node/on_first_clear 防重放）**
  - Covers：S5-AC-013；依賴：T02、T06
  - 驗收：`run_relic_table_builder.gd:83` 與 `content_validator.gd:264-274` 同步放寬接受三 scope；`build_effect_claim` key：once_per_node 用當前 node_id（同節點恰一次、跨節點重觸發）、on_first_clear 用 run 級 sentinel（全 run 恰一次）；重載重放不重複；claim keys 全 run 唯一、重複 tuple 拒載。

## Gate D — 發現標記與驗證器

- [x] **T09 [HARD][TDD] 圖鑑發現台帳＋提交 union**
  - Covers：S5-AC-012；依賴：T03
  - 驗收：`RunDiscoveryLog.mark` 於四類事件（上場/購得、商店出現、遭遇敵人、取得裝備/遺物）command apply 內 append；`RunController._commit_draft` union 進 profile'（僅 discovery 單調 append）；同 swap 原子；重載/重放冪等；不消耗 RNG、不改 draw 序（soak 對照）；CollectionViewModel 按類別讀出。
- [x] **T10 [NORMAL][TDD] 驗證器擴充（META 禁項＋challenge 規則）＋快照隔離驗證**
  - Covers：REQ-META-002、REQ-CONTENT-001、S5-AC-004、S5-AC-005；依賴：T07、T08
  - 驗收：`CONTENT_META_FORBIDDEN_GROWTH`（永久基礎生命/攻防、免費刷新、固定起始人口）非零退出＋具名 issue；challenge 鏈 modifier_refs 必指 challenge_affix＋四類覆蓋；`challenge_multiplier_bps` 覆蓋 0..5 且 ≥10000；三被動非同一效果數值階級；解鎖前後同 UnitDef compiled stats 逐欄相等測試；進行中 run（lease）購新解鎖後內容池不變、新 run 才套用。

## Gate E — 接線與收尾

- [x] **T11 [HARD][TDD] AppRoot composition root＋RunCommandFactory＋Camp/Results 灰盒＋ViewModels**
  - Covers：REQ-META-001、REQ-TECH-002、REQ-UX-005、S5-AC-001、S5-AC-008、S5-AC-014；依賴：T02、T04、T05、T06、T07
  - 驗收：boot→load 分流（LOADED→RunSession/RunController/factory→RUN；NOT_FOUND→建 profile→CAMP；INVALID/I/O/INCOMPATIBLE_PRESERVED→boot_failed）；factory 唯一建構四命令且 relic_table 非 null（含被動＋詞綴）、防回歸測試；Camp 灰盒五設施進出、CampViewModel 單一 ProfileState 源；端到端：新 profile→選指揮官→三幕通關與失敗/放棄→RESULTS→CAMP、重載 RESULTS 不重發；SceneRouter 依 app state 換場。W5 R2/R3 增補：第二節點備戰不得遺失既有 board 棋；COMBAT setup/result pending 皆可續跑且不重送 StartCombatEvent；非 RESULTS meta 結算具名拒絕；bind_services 僅入樹前；Smoke/Gut 使用 FakeSaveStorage；MetaRewardTable 從 canonical payload 重建；starting_pack canonical 排序；compose 失敗保留 run 並提供 expected_run_id 明示棄置交易；所有一般 Camp writer 只在 fresh load 明確 `RunStatus.NONE` 時寫入，load 故障／LOADED／INCOMPATIBLE_PRESERVED 均 fail-closed；同程序 compose-fail 立即以已提交 profile' 刷新 CampViewModel。世代一致性：factory 建構的四命令（含 challenge 詞綴管線 resolver→RunModifierTableBuilder→BattleSettlementService/ShopService）須共用同一 content_snapshot.manifest_digest，補一條端到端測試證明——`test_challenge_affix_end_to_end.gd` 因橋接兩個獨立 fixture factory（ContentRegistryService／ResolutionFixtureFactory，見該檔 :67 註解）未覆蓋此面向（W4-Sonnet#3 遺留，2026-07-25），本任務不得只靠該檔既有斷言頂替。
- [x] **T12 [NORMAL][免TDD：整合驗收與 soak 實跑證據彙整，無新測試標的] 全 AC 回歸＋soak 新鮮度＋證據彙整**
  - Covers：全 S5-AC 回歸、S4 已知邊界（soak 新鮮度）；依賴：T10、T11
  - 驗收：domain 改動後先 `ExpeditionSoak -SeedCount 10000` 綠再 `-Suite All` 綠（帶 -GodotPath）；逐 S5-AC 證據對照落 `specs/meta-progression/implementation-review.md`；PROGRESS.md/HANDOFF.md/implementation-slices.md 狀態更新。

## Dependency order

- wave1＝T01、T03、T06；wave2＝T02、T04、T09；wave3＝T05、T08；wave4＝T07；wave5＝T10、T11；wave6＝T12。
- 同波內無共用檔（validator 系列 T02→T08→T07→T10 跨波序列化；CampController T04→T05 序列化；builder T06→T08 序列化）。

## 雙向覆蓋檢查

- S5-AC→任務：001→T11；002→T05；003→T06；004→T10；005→T10；006→T01；007→T02；008→T11；009→T02/T05/T07；010→T07；011→T04；012→T03/T09；013→T08；014→T11。全 14 條覆蓋。
- 任務→S5-AC/REQ：T01~T12 每條 Covers 欄非空（上列）。無孤兒任務。

## Completion ledger

| 任務 | 狀態 | 主要證據 |
|---|---|---|
| T01 | PASS | `test_meta_reward_compute_service.gd`＋slice_default；wave1 reviews |
| T02 | PASS | `test_meta_settlement_{service,command}.gd`；wave2 reviews |
| T03 | PASS | schema-3 codec/migration/profile-state tests；wave1 reviews |
| T04 | PASS | Camp purchase transaction tests；wave2 reviews |
| T05 | PASS | start expedition／bootstrap tests；wave3 reviews |
| T06 | PASS | commander always-active/battle source tests；wave1 reviews |
| T07 | PASS | challenge affix resolver/content/e2e tests；wave4 reviews |
| T08 | PASS | `test_claim_scope_semantics.gd`；wave3 reviews |
| T09 | PASS | `test_discovery_log_marking.gd`；wave2 reviews |
| T10 | PASS | meta/content validator＋snapshot isolation tests；wave5 reviews |
| T11 | PASS | AppRoot/Camp/Run factory/R2/R3 regression tests；W5 R4 雙審零未決 |
| T12 | PASS | `.pipeline/tdd/w6-t12-green.txt`；`implementation-review.md` 14/14 PASS |
