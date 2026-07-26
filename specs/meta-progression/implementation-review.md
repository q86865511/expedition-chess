# S5 meta-progression 實作複檢（逐 AC 證據）

> 狀態：實作完成（2026-07-26）
> 驗證環境：Godot 4.7.stable.official；GUT 9.7.1；toolchain lock verified。
> 流程：6 waves、SDD 三件套、TDD 紅→鎖定→綠、逐波雙審；W5 R2/R3
> 回歸 manifest 合計 9/9 SHA-256 相符，W5 R4 兩份獨立複審皆零未決。

## 最終 gate（fresh，2026-07-26）

- `ExpeditionSoak -SeedCount 10000 -TimeoutSeconds 600`：exit 0；10,000 seeds、
  10,000 pool conservation checks、64 deterministic replays、40,000 build operations、
  0 failures。
- `-Suite All`：exit 0；Import／RunnerContract／Smoke／Gut／Content／Canonical／
  Combat／Expedition／Spec 全通過。
- Gut：737/737 tests、9332 assertions、0 failures/errors/orphans。
- Spec：3432 cases；Content：39 cases；Smoke：10 cases。
- 機器可讀證據：`artifacts/test/runner-execution.json`、
  `artifacts/test/expedition-soak.json`；摘要與 SHA-256：
  `.pipeline/tdd/w6-t12-green.txt`。

## 逐 S5-AC 證據對照

| AC | 判定 | 主要測試／artifact 證據 |
|---|---|---|
| S5-AC-001 營地五設施與單一狀態源 | PASS | `test_camp_view_model.gd`（五設施同一 Profile clone、隔離）；`test_app_root_boot_route.gd`（NOT_FOUND 建 profile→CAMP）；Smoke `minimal_boot`。 |
| S5-AC-002 指揮官建立遠征與鎖定 | PASS | `test_run_bootstrap_service.gd`（commander/challenge/snapshot/seed/roster/pool；starting_pack canonical 排序）；`test_camp_controller_start_expedition.gd`（原子提交與鎖定）。 |
| S5-AC-003 指揮官被動實際生效 | PASS | `test_run_relic_table_always_active.gd`；`test_income_service_commander_challenge_modifiers.gd`、`test_shop_service_commander_challenge_modifiers.gd`、`test_map_service_commander_challenge_modifiers.gd`、`test_battle_settlement_commander_challenge_modifiers.gd`；battle source compiler 回歸。 |
| S5-AC-004 局外成長禁提基礎戰力 | PASS | `test_meta_growth_forbids_base_power_and_validator_rejects.gd`、`test_commander_passive_mechanism_diversity*.gd`；Content 39/39。 |
| S5-AC-005 進行中快照隔離 | PASS | `test_in_progress_snapshot_isolated_from_later_unlock.gd`（既有 run pinned snapshot 不變、新 run 才讀新解鎖）；catalog generation/lease 回歸。 |
| S5-AC-006 MetaRewardTable 結算計算 | PASS | `test_meta_reward_compute_service.gd`（公式、floor、completion/failure/非戰鬥節點、純函式）；`test_meta_reward_table_reader.gd`（canonical payload 完整重建與 clone 隔離）。 |
| S5-AC-007 settlement receipt exactly-once | PASS | `test_meta_settlement_service.gd`（receipt key、冪等與挑戰紀錄）；`test_meta_settlement_command.gd`（原子清 run、各存檔故障點重試恰一次、非 RESULTS 位元組不變）。 |
| S5-AC-008 端到端原子結算與營地回返 | PASS | `test_camp_to_results_composition.gd`（成功/失敗 RUN→RESULTS→CAMP）；`test_camp_controller_discard_active_run.gd`（expected run-id compare-and-clear）；`test_app_root_boot_route.gd` 與 R3 `test_camp_writer_fail_closed_r3.gd`／`test_app_root_start_compose_failure_r3.gd`（retained run、所有 Camp writer fail-closed、INCOMPATIBLE boot failure、最新 profile 投影）。 |
| S5-AC-009 挑戰進度按指揮官記錄 | PASS | `test_start_expedition_command.gd`（逐階 prerequisite）；`test_meta_settlement_service.gd`（completed 才 max 更新、其他指揮官不變）；`test_challenge_affix_end_to_end.gd`。 |
| S5-AC-010 挑戰詞綴累積與預覽 | PASS | `test_challenge_affix_resolver.gd`、`test_challenge_affix_content_authoring.gd`、`test_challenge_affix_battle_catalog.gd`、`test_challenge_affix_end_to_end.gd`、`test_expedition_gate_view_model.gd`；正式 combined pack Content gate 綠。 |
| S5-AC-011 解鎖工坊購買 | PASS | `test_unlock_purchase_service.gd`、`test_camp_controller_purchase_unlock.gd`（成功扣款/排序、具名拒絕、validation/save failure 零變更）；R3 retained-run writer guard。 |
| S5-AC-012 圖鑑即時發現台帳 | PASS | `test_discovery_log_marking.gd`（買棋、商店、遭遇、上場、裝備、遺物、重載冪等與 save failure）；schema-3 codec/migration 與 profile/run deep-clone 回歸。 |
| S5-AC-013 claim_scope 真語意 | PASS | `test_claim_scope_semantics.gd`（once_per_node/on_first_clear/always、戰敗不消耗、payload mismatch、重複 tuple 拒絕）；validator/builder parity 測試。 |
| S5-AC-014 正式 composition 與 relic_table 接線 | PASS | `test_run_command_factory.gd`、`test_run_command_factory_challenge_world_consistency.gd`、`test_run_lab_session_factory_chain.gd`（五 factory 真呼叫、board 聯集、setup pending resume）；R3 `test_run_lab_result_pending_resume_r3.gd`（committed result resume 零重送/零 persistence mutation）。 |

## 波次與最終複審

| 波 | 任務 | 結果 |
|---|---|---|
| wave1 | T01／T03／T06 | 完成；雙審裁決修正後 Gut 綠；commit `64840ca`。 |
| wave2 | T02／T04／T09 | 完成；exactly-once、Camp 交易與 discovery ledger；commit `9c4d1a7`。 |
| wave3 | T05／T08 | 完成；starting run、claim_scope 真語意與 Spec silent-null 修正；commit `87cc2d0`。 |
| wave4 | T07 | 完成；challenge 雙軌與正式內容；commit `e6fbd25`。 |
| wave5 | T10／T11＋W5 R2/R3 | 完成但未 commit；W5 R4 behavior/architecture 雙審皆零未決。 |
| wave6 | T12 | 10k soak 與 All fresh 全綠；本逐 AC 證據完成。 |

## 已知邊界（非本輪未決缺陷）

- 正式產品 UI／美術／音效仍屬 Codex 橫切工作；Camp／Run／Results 為可操作灰盒。
- `INCOMPATIBLE_PRESERVED` 採資料保留硬停；需安裝相容內容或 migration 才能恢復，
  不提供缺乏可靠 decoded run-id 的危險刪除入口。
- SaveRepository 的交易模型為單程序同步 command；跨程序刻意共用同一 production save
  path 的 file lock／CAS 不在本切片 SDD。
- 正式內容數值仍標 TUNE；最終平衡與完整像素內容屬 G2。

## 判定

S5-AC-001～014：**14/14 PASS**。T01～T12 均有實作、測試／artifact 與複審證據；
無缺證據 AC；S5 可進入正式 UI／內容 TUNE 與發行準備。
