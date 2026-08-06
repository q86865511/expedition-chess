# G2 difficulty-curve — Fresh evidence index

> 本表記錄本分支（`codex/g2-difficulty-curve`）fresh 執行結果，HEAD 為 `493f1b2`
>（T11 修正：原表頭誤標 `20db291`，見已知訊號與缺口段落 T11 F10 說明）。
> 3k screening 為 gate_mode `screening`（非 30k full gate）；`AC-032` 沿用
> `balance-playtest` 定義，第三切片外部 Gate 維持 `PENDING_EXTERNAL`，不在本片重證範圍。

| DC-REQ | 重證內容 | Fresh evidence | 狀態 |
|---|---|---|---|
| DC-REQ-001 | per-act 敵方成長 bps 疊乘於既有星級 `_scaled` 之後；核心欄位（速度／射程／法力）三幕不變 | `tests/unit/difficulty_curve/test_act_scaling.gd`、`tests/unit/battle_encounter/test_encounter_compiler.gd`（act2 13000bps 重算）、`tests/integration/difficulty_curve/test_act_scaling_and_formation_structural.gd`（Acceptance 1 逐條斷言）；結構快篩見 `test_curve_pressure_and_report_trend.gd` | PASS |
| DC-REQ-002 | Boss 節點依 `act_index` 決定性映射 `encounter.slice_boss_0/1/2`，pin 缺項 fail-closed | `tests/unit/economy_expediton/test_node_entry_service_boss_mapping.gd`（`slice_boss_1` 自 pinned 集合移除→具名錯誤拒絕，非 fallback）、`test_act_scaling_and_formation_structural.gd`（三幕 Boss encounter id 互異） | PASS |
| DC-REQ-003 | 五個 encounter 多敵編成，spawn_key 唯一、格位不重疊、`logical_y`≥4 | `tests/integration/difficulty_curve/test_act_scaling_and_formation_structural.gd`（敵方單位數 2／3／3／4／5，spawn_key／格位驗證） | PASS |
| DC-REQ-004 | 12 個 trait 的 2／4／6 門檻各自指向強度遞增的獨立 effect，loc key 完整 | `tests/unit/content_validation/test_build_systems_content_pack.gd`（tier1/2/3 各自獨立且遞增，缺 loc key 非零退出） | PASS |
| DC-REQ-005 | tier-1 池重標後全庫每個 faction 成員數 ≥6，tier-1 子集覆蓋 ≥2 | `tests/unit/content_validation/test_vertical_slice_content_pack.gd`（全庫 faction 成員數與 tier-1 子集覆蓋掃描） | PASS |
| DC-REQ-006 | challenge unlock 回鏈三桶覆蓋（軌 A／ShopSurcharge／DrainExpeditionHp）；global source 仍不得攜帶 RunOperation 進 `BattleSetup` | `tests/unit/content_validation/test_challenge_affix_operation_validation.gd`（缺任一桶觸發 `CONTENT_CHALLENGE_AFFIX_COVERAGE`）、`test_global_effect_source_lifecycle_validation.gd`（負向案例維持紅）、`tests/integration/meta_progression/test_challenge_affix_content_authoring.gd`、`test_challenge_affix_end_to_end.gd` | PASS |
| DC-REQ-007 | 獎勵／購買選取在 `content_id` 存在時記正式 stable ID；`content_id` 結構上不存在（GOLD／EVENT 等 reward kind）時記 `reward.kind.N` 佔位並計入 opaque 統計、fail-visible；`BalanceBotActSnapshot` 補 per-act win/loss 與死亡節點 ID 並進 canonical token | `tests/unit/balance_playtest/test_balance_bot_act_snapshot_observability.gd`；3k screening 實測 `stable_id_observability.opaque_selected_id_count=24,469`／`selected_id_count=81,171`（30.1%），逐筆核對全數為 `reward.kind.N` 佔位（GOLD／EVENT 等結構上無 content ID 的獎勵種類），符合 fail-visible 設計；reservation_owner／offer 類（非 reward）選取 opaque 計數為 0（`artifacts/test/balance-playtest-screening.json` `stable_id_observability`）。原「3,000 筆 case proofs 的 selected_ids 皆為正式 stable ID」表述與此矛盾，已依 T11 F1/#1 修正並同步改寫 requirements.md Acceptance 7 | PASS |
| DC-REQ-008 | `BALANCE_ACT_ELIMINATION_FLAT` gate（seed_count≥1000 才啟用）雙實作（GDScript／PowerShell）golden 一致 | `tests/unit/balance_playtest/test_balance_act_elimination_gate.gd`＋`tools/balance/tests/test-act-elimination-gate.ps1` 對同一份 `tests/fixtures/balance_playtest/act_elimination_golden.json`（5 scenarios）逐字比對 `act_curve_token` 與 `BALANCE_ACT_` 前綴 gate reason 集合；3k screening 實跑 `act_curve.enforced=true`、`gate_reasons=[]`（見下方 3k 摘要） | PASS |

## T09 曲線生效快篩

- (a) 結構層（跨幕梯度守門，責任所在）：
  `tests/integration/difficulty_curve/test_act_scaling_and_formation_structural.gd` 的
  `test_act2_and_act3_enemy_totals_strictly_exceed_previous_act_for_every_encounter`
  對五個 encounter 逐一斷言 act2 合計 HP／ATK 嚴格大於 act1、act3 嚴格大於 act2
  （共 10 條斷言）。W2-B 變異實測：把 `act2_enemy_stat_bps` 改回 10000 時，此測試轉紅
  ——這是本片唯一守住「跨幕梯度」本身的測試（T11 F5 閉環）。
- (b) 壓力層（戰鬥後果驗證，非梯度驗證）：
  `tests/integration/difficulty_curve/test_curve_pressure_and_report_trend.gd`：走正式
  `RunController`／`BalanceProductionCaseDriver` 鏈路的 tempo／synergy 兩個輕量 case，
  確認至少一個 Act2+ case 出現真實傷害訊號（`battle_losses>0` 或 HP 下降），非結構層
  空生效；此斷言只驗證「有損傷」，在 (a) 的同一組變異下仍可能維持綠（act3 仍有損傷），
  不承擔梯度守門責任。
- (c) 趨勢層：同時 read-back `BalanceBotReport.to_json()` 的 `act1_reached/act2_reached/
  act3_reached` 與逐案 `act_snapshots` 欄位完整，供人工判讀幕間曲線趨勢。

## 3k screening fresh 摘要

- 產物：`artifacts/test/balance-playtest-screening.json`；SHA-256（PowerShell
  `Get-FileHash`，2026-08-06 現場實算）
  `0ABB81FAF40614124F29CD80102190F47C964184E7E5F18F7006D8E6BAD106A6`。
- `gate_mode=screening`、`gate=PASS`、`gate_reasons=[]`；
  `candidate_id=balance.g2.041458b08bb5`、`tune_digest=041458b08bb5ea574b3d4b7448614cd6e76abb18bdd989e363534e23ec57258a`、
  `git_head=b2c7895a7106122bb96e598bfc56f58a355e8ec4`；
  `cohort_seed_count=1000`、`strategy_seed_case_count=3000`；16 分片。
- 3,000/3,000 terminal（三策略各 1,000/1,000）；`replay_validation`：150 抽驗
  （`sample_rate_bps=500`、`seed_index % 20 == 0`）、`drift_case_ids=[]`（零 drift）；
  `failed_seeds` 為空、`case_proofs` 3,000 筆。
- 勝率：tempo 657/1,000（65.7%）、economy 235/1,000（23.5%）、synergy 841/1,000
  （84.1%）。
- `act_curve`（`enforced=true`、`min_seed_count=1000`）：
  - act1：entered 3,000、eliminated 400、battle_wins 8,738、battle_losses 4,691
  - act2：entered 2,600、eliminated 0、battle_wins 10,400、battle_losses 0
  - act3：entered 2,600、eliminated 867、battle_wins 9,533、battle_losses 3,506
  - `elimination_total=1,267`、`elimination_acts=[1,3]`
  - `BALANCE_ACT_ELIMINATION_FLAT` 未觸發（淘汰分布跨兩幕，非單幕集中），
    `gate_reasons=[]` 與此一致。

## 證據 HEAD 與時序說明（T11 F10／B#8 閉環）

- 分支 HEAD 為 `493f1b2`（純文件 commit）。3k screening／10k soak 產物的 `git_head` 記載
  為 `b2c7895`（T01～T10 最後一個程式碼 commit）；`b2c7895` 之後到 `493f1b2` 之間只有
  `20db291`（`act_curve()`→`_act_curve()` 純改名，`to_json()` 輸出與行為不變，已逐 diff
  查證）與本輪 T11 文件回寫，兩者皆不影響 3k／soak 產物的代表性。
- `artifacts/test/gut.xml` 在 T11 雙審過程中曾被兩位 reviewer 的 targeted 重跑覆寫（分別
  覆成 9-test／targeted 內容）；下方「Fresh All／ExpeditionSoak」的 `tests=1193`／
  `assertions=24765` 是 reviewer A 於 HEAD `493f1b2` 的 fresh `-Suite Gut` 重跑實測（見
  `.pipeline/difficulty-curve/reviews/phase1-final-review-A.md` 開頭驗證紀錄），非
  `gut.xml` 當下內容。**fresh `-Suite All` 尚未在本輪文件修正後的最終 HEAD 重新執行**
  ——T11 finding closure（本次文件修正）完成、Git gate 前，必須在最終 HEAD 重跑一次
  `-Suite All` 並以該次輸出覆蓋此檔的 `gut.xml` 引用，不得沿用本表已記的舊數字當作
  最終 HEAD 的證據。

## Battle golden 重算揭露（T11 F9 閉環）

- design.md「決定性與失敗政策」要求 battle golden 重算需在 commit 訊息中揭露；
  commit `7210653`（功能: T01 act 縮放與 T02 三幕 Boss 決定性映射）訊息本身未列出
  重算清單，揭露僅存在於程式碼註解，屬程序疏漏，補記於此作為權威來源：
  - `tests/unit/battle_encounter/test_encounter_compiler.gd`：
    `test_compile_is_deterministic_and_persists_boss_source_id` 的 act2（13000bps）
    ★1 敵方 health 180→234、attack 18→23；第二個決定性斷言的 health 100→130
    （act_index=2 疊乘 star_bps 後再套 act2 乘數）。
  - `tests/fixtures/canonical/canonical_verification_suite.gd:332-334`：
    `BattleResultV1` 的 `summary_hash`
    `6248075f...` → `52d67c1d...`、`result_hash` `03d9decb...` → `34db310e...`
    （`BattleRulesSnapshot` 新增三個 per-act 欄位改變 setup canonical bytes；
    event stream golden 不含 setup hash，未變）。
  - 其餘受影響 golden：`test_encounter_compiler_affix_error_priority.gd`、
    `test_encounter_compiler_challenge_affixes.gd`、`test_content_v2_and_battle_catalog.gd`
    （同批次、同根因，皆為新增 `act1/2/3_enemy_stat_bps` 欄位進 canonical bytes 的連鎖
    重算，非獨立 drift）。

## REQ-ENEMY-003／AC-050／AC-079 對應（T11 F10／B#8 閉環）

- `docs/game-architecture/10-traceability-matrix.md` 將 `REQ-ENEMY-003` 對應
  `AC-050`／`AC-079`；本表原無對應 AC 列，補列如下：
  - **AC-079**（三幕 Boss 互異、act1 敵方數值等於星級縮放值本身、act2/3 疊乘幕乘數、
    節奏／可達性欄位三幕不變、重複編譯 byte-identical、pin 缺項具名失敗）：對應
    DC-REQ-001／DC-REQ-002 兩列，證據同上表 `test_act_scaling.gd`、
    `test_act_scaling_and_formation_structural.gd`、
    `test_node_entry_service_boss_mapping.gd`。
  - **AC-050**（固定 seed/act/node/難度/解鎖池、只換玩家 roster/羈絆/裝備、
    EncounterDef／敵隊／詞綴完全不變）：`EncounterCompileRequest` 本片未新增
    roster／traits／items 相關欄位（design.md「資料與介面」段），既有決定性測試
    `test_encounter_compiler.gd` 的 `test_compile_is_deterministic_and_persists_
    boss_source_id`（同輸入重複編譯 byte-identical）在新增 act 乘數後仍持續通過，
    佐證該不變量不因本片改變。

## Fresh All／ExpeditionSoak

- `artifacts/test/gut.xml`：`tests=1193`、`failures=0`、`errors=0`、`orphans=0`、
  `assertions=24765`。
- `artifacts/test/expedition-soak.json`：`case_count=10000`、`seed_count=10000`、
  `failures=[]`、`passed=true`、`pool_conservation_checks=10000`、
  `build_operation_count=40000`、`deterministic_replay_count=64`。

## 已知訊號與缺口（Phase 2 輸入，不在本片修復範圍）

1. **Act2 淘汰 0／戰敗 0**：3k `act_curve` 顯示 act2 entered 2,600、eliminated 0、
   `battle_losses=0`——中盤敵方成長曲線目前壓不過玩家 build 力量，是 Phase 2 調參
   （§6.3b 收斂判準）的首要訊號，本片依範圍只做結構性解除，不做數值收斂。
2. **三策略勝率未收斂**：tempo 65.7%／economy 23.5%／synergy 84.1%，策略間勝率差距
   （synergy 與 economy 相差 60.6pp）尚未收斂至 `g2-roadmap.md` §6.3b 的目標帶；
   留待 Phase 2 TUNE 迭代處理。
3. **`run-final-cohort.ps1` 尚無 per-act gate**：T08 的鏡射模組
   `tools/balance/act-elimination-gate.ps1` 已由 `run-sharded-cohort.ps1` dot-source
   接線（本輪 3k gate PASS 即含此判準），但大樣本聚合腳本 `run-final-cohort.ps1`
   只彙總 shard 摘要、不讀 case_proofs，尚未接同一模組；Phase 2 大樣本工具化時
   需補上，否則正式 10k/30k final gate 跑不到 per-act 淘汰檢查。
4. **XP 修正後單 case 時長顯著增加**：commit `b2c7895`（tempo/synergy XP 評分退化修正）
   後單 case 平均耗時實測約 159 秒（3k screening
   `execution_metrics.primary_mean_elapsed_ms`≈158,874ms、`effective_mean_elapsed_ms`
   ≈166,761ms，含 150 抽驗 replay），單一分片（189 case）耗時 8.3 小時量級；Phase 2
   大樣本（10k/30k）成本估算需同步反映此漲幅，不可沿用修正前的舊估值。
5. **runner per-shard timeout 預設不足**：`tools/balance/run-sharded-cohort.ps1` 的
   `$TimeoutSeconds` 預設 43200（12 小時）在本輪新工作量（單 case ~190s×每分片近
   190 case）下逼近上限；本輪以 16 分片＋更大的 `-TimeoutSeconds`（64800 秒／18 小時）
   迴避，Phase 2 工具化大樣本 runner 時應把預設值調高或於文件中明示需自訂 timeout。
6. **`BALANCE_ACT_ELIMINATION_FLAT` 的中盤幕盲點**（T11 F11 閉環）：現行判準只在「敗局
   全部集中同一幕」時觸發；本輪 act2（`entered=2,600`、`eliminated=0`、
   `battle_losses=0`，即現象 #1 描述的白給幕）因 act1／act3 都有淘汰
   （`elimination_acts=[1,3]`，跨兩幕）而不落入單幕集中判準，gate 依
   `design.md` §「觀測性與 per-act gate」的文字定義判 PASS，屬預期行為、非實作偏離。
   建議 Phase 2 對 `BalanceBotReport` 補一條獨立判準：「任一幕 `entered>0` 且
   `battle_losses==0` 即 flag」，用以捕捉本輪這種「中盤幕完全無壓力」但不觸發現行
   FLAT gate 的形態。
