# balance driver 整合測試 — 變異驗證證據

> 依 `specs/balance-playtest/rewrite-plan.md` §5.7（GUT 對 parse error 會靜默跳過整檔、
> suite 仍綠，變異驗證是唯一防呆）。對每一個新測試檔／每一條 §5 要求，
> 各弄壞一次被測行為 → 確認轉紅 → 還原 → 確認轉綠。
>
> - 產出日期：2026-08-04
> - 分支：`codex/g2-balance-playtest`（base commit `41f969d`，工作樹另有並行變更）
> - Godot：4.7.stable（`Godot_v4.7-stable_win64.exe`）／GUT 9.7.1
> - 指令樣板：
>   `<godot> --headless --path <repo> --script res://tests/runners/gut_runner.gd -- --test-path <目標>`
> - 被變異檔案在變異前後皆以 SHA-256 比對，確認逐 byte 還原：
>   - `application/balance/balance_production_case_driver.gd`
>     `e2db218d540ed516fac5aba240f9cd3caeba4cf36b2de68ad3735528c73fd065`
>   - `domain/run/economy/shop_service.gd`
>     `bc22aff8db72bcb3a0d76bb2eefda91d85fbf260cfdf88e277b39c96656426ce`
>   - `domain/run/economy/battle_settlement_service.gd`
>     `7811947ab285ac66dca51d50ce2a1dcd13980b0e3f789426dfe1c19cf6f00aed`

---

## MUT-1 — §5.1 full expedition smoke／cohort

- 測試檔：`tests/integration/balance_playtest/test_balance_driver_full_expedition.gd`
  （`test_three_strategies_share_one_cohort_world_and_reach_results`）
- 變異：`balance_production_case_driver.gd` 的 `run_case` 開局改成
  `_profile_for_seed(seed_index + BalanceBotStrategy.IDS.find(strategy_id), commander_id)`
  ——把 strategy 摻進 profile，等同重現 BP-IR-002（三策略各自一個世界）。

紅（exit 2）：

```
[Failed]: [STRING_NAME(run_4edf2369...c25e)] expected to equal
          [STRING_NAME(run_3938e7a0...4e07)]:  同 seed 三策略必須同一個 run_id（cohort）
[Failed]: [STRING_NAME(run_9eef77cb...1866)] expected to equal
          [STRING_NAME(run_3938e7a0...4e07)]:  同 seed 三策略必須同一個 run_id（cohort）
[Failed]: ["294d1d2a...cbe6"] expected to equal ["f67d8940...f4c7"]:  同 cohort 的地圖世界必須相同
[Failed]: ["aa05d72d...51d4"] expected to equal ["f67d8940...f4c7"]:  同 cohort 的地圖世界必須相同
Totals: Tests 2 / Passing 1 / Failing 1        EXIT=2  (294 s)
```

綠：還原後隨 MUT-2 的綠證據一併驗證（見下方「還原後全套綠」）。

---

## MUT-2 — §5.4 save-reload 等價

- 測試檔：同上（`test_save_reload_equivalence_matches_in_memory_continuation`）
- 變異：`balance_production_case_driver.gd` 存檔重載分支刪掉
  `controller = reloaded.controller`（session 換成重載後的、controller 仍是舊的）。

紅（exit 2；程序在大量失敗後以 255 收尾）：

```
[Failed]: [1] expected to equal [0]:  tempo 不得帶 failure code：[&"BALANCE_BATTLE_RESULT_MISSING"]
[Failed]: tempo 必須跑到 terminal
[Failed]: ["UNSET"] expected to equal ["RESULTS"]:  tempo 終局 phase
[Failed]: [7] expected to equal [21]:  tempo 必須走完整條 21 節點路線（關 BP-IR-001 的 3 戰版病徵）
[Failed]: [0] expected to equal [4]:  tempo 每場戰鬥必須恰有一筆結算 receipt
（economy／synergy 同樣三條全紅）                EXIT≠0  (52 s，重載點即炸)
```

說明：重載分支一旦接錯，run 會在第 7 個節點後立刻失去 committed combat snapshot，
本檔的完整局與等價兩條測試同時轉紅。

---

## MUT-3 — §5.2 action apply

- 測試檔：`tests/integration/balance_playtest/test_balance_driver_prepare_actions.gd`
  （`test_prepare_commands_change_canonical_snapshot`）
- 變異：`domain/run/economy/shop_service.gd` 的 refresh 交易刪掉 `economy.gold -= reroll_price`
  （command 仍成功、但不再改變 canonical 金幣）。

紅（exit 2）：

```
[Failed]: [9] expected to equal [7]:  refresh 必須扣掉 reroll 成本
Totals: Tests 2 / Passing 1 / Failing 1        EXIT=2
```

綠（還原後，同一指令）：

```
2/2 passed.   Totals: Tests 2 / Passing 2      EXIT=0  (5.2 s)
```

---

## MUT-4 — §5.3 Boss retry

- 測試檔：`tests/integration/balance_playtest/test_balance_driver_boss_retry_terminals.gd`
- 變異：`balance_production_case_driver.gd` 的 `_resolve_combat_node` 刪掉
  `result.boss_retry_count += 1`（重打仍發生、但不再被記錄與斷言看見）。

紅：

```
[Failed]: [0] expected to be > than [0]:  Boss 敗且 HP>0 必須回到 PREPARE 重打（附錄 C1-2 的政策）
[Failed]: [0] expected to equal [5]:  每一次重打都必須對應一次真的重新開打
[Failed]: 必須進到 Boss 重打狀態才驗得到 abandon
[Failed]: [0] expected to equal [1]:  abandon 結算 receipt 必須恰好一筆
Totals: Tests 2 / Passing none / Failing 2     EXIT≠0
```

---

## MUT-5 — §5.5 abandoned terminal exactly-once

- 測試檔：同 MUT-4（`test_abandon_boss_retry_settles_abandoned_terminal_exactly_once`）
- 變異：`domain/run/economy/battle_settlement_service.gd` 的 `abandon_boss_retry`
  跳過 `_append_settlement_receipt(draft, &"expedition_abandon", &"abandoned")`。

紅（exit 2）：

```
[Failed]: [0] expected to equal [1]:  abandon 結算 receipt 必須恰好一筆
Totals: Tests 2 / Passing 1 / Failing 1        EXIT=2
```

綠（還原後，同一指令）：

```
2/2 passed.   Totals: Tests 2 / Passing 2      EXIT=0  (35 s)
```

> MUT-4／MUT-5 的紅綠是對**改寫後**的 boss 測試（`force_empty_board_at_boss`
> 確定性構造）重跑的結果，不是對初版 seed 錨點測試的舊紀錄。

---

## 還原後全套綠

三個被變異檔案的 SHA-256 均回到本文件開頭記錄的值（逐 byte 相同），
`--test-path res://tests/integration/balance_playtest` 全綠：

```
res://tests/integration/balance_playtest/test_balance_driver_boss_retry_terminals.gd   2/2 passed
res://tests/integration/balance_playtest/test_balance_driver_full_expedition.gd        2/2 passed
res://tests/integration/balance_playtest/test_balance_driver_prepare_actions.gd        2/2 passed
res://tests/integration/balance_playtest/test_production_boss_battle_setup_validation.gd 1/1 passed

Totals: Scripts 4 / Tests 7 / Passing Tests 7 / Asserts 114 / Time 324.20s
---- All tests passed! ----                    EXIT=0
```

---

## 全套 GUT（不帶 `--test-path`）確認新測試已被 All 的 Gut 步驟收進去

`gut_runner.gd` 直接跑（.gutconfig.json 的 `dirs` 含 `res://tests/integration`、
`include_subdirs: true`），日誌可見四個新測試檔皆被蒐集並執行：

第一輪（初版 boss 測試，seed 錨點）：

```
Scripts 293 / Tests 1152 / Passing 1150 / Failing 2 / Asserts 22414/22417 / Time 586.83s
失敗兩條皆為 seed 錨點的敗局假設（見下方「seed 錨點不穩定」），已據此改寫測試。
```

第二輪（改寫後重跑）：

```
Scripts 293 / Tests 1152 / Passing 1151 / Failing 1 / Asserts 22418/22419 / Time 561.09s
四個 balance driver 測試檔在全套脈絡下 2/2＋2/2＋2/2＋1/1 全綠。
唯一失敗為並行任務的檔案（tests/unit/presentation_ui_app_lifecycle/
test_supported_dev_cli_entries_consume_production_facade.gd：
dev CLI 白名單多出 --rc-smoke-confirm／--rc-smoke-phase），
與本批變更無關，依並行工作規則只記錄不診斷。
```

新增的 driver 整合測試在全套中約佔 325 秒。

因為單步 Gut 已達約 590 秒，`tools/run-tests.ps1` 的 Gut 步驟改為帶
`-TimeoutOverrideSeconds`（下限 `$GutTimeoutFloorSeconds = 1200`），
否則 All 用預設 `-TimeoutSeconds 180` 會被 124 砍掉（此為既有問題，
本次新增測試把它放大到必然發生）。

---

## seed 錨點不穩定（本輪實測到、已據此改寫測試的觀察）

初版的 Boss retry／failed terminal 測試用 3k screening #2 的
`(tempo, seed 48)` 當敗局錨點（該 case 的紀錄為 7 節點、HP 0、boss_retry 4）。

- 單獨跑該測試檔：重現敗局，綠。
- 同一份程式碼、同一台機器，改在**全套 GUT**（同 process 先跑過約 1,150 個測試）中跑：
  同一個 seed 變成走完 21 節點、`ending_hp = 72` 的勝局
  （`boss_retry_count > 0` 仍成立，即仍敗過 Boss，但後續重打贏了）。
- 期間 `application/balance/`、`domain/run/`、`content/` 皆未變動
  （driver SHA-256 與變異前備份逐 byte 相同）。

也就是說：**邊緣 case 的勝負會隨同 process 內先跑過哪些測試而改變**。
本輪未進一步診斷（超出本任務範圍，且工作樹有並行任務）。
處置：敗局／abandon 情境改用 `force_empty_board_at_boss` 確定性構造，
不再以任何 seed 的勝負當錨點；`seed 0 三策略全勝` 的斷言在兩種脈絡下皆成立，予以保留。

---

## 涵蓋不到、已回報的缺口

1. **`BALANCE_BOSS_RETRY_LIMIT` 耗盡分支**（`balance_production_case_driver.gd`
   `_resolve_combat_node` 迴圈走完 `BOSS_RETRY_LIMIT + 1` 次的回傳）：要觸發必須讓
   Boss 連敗 101 次且 HP 始終為正，正式規則下不可能（每敗必扣血）；`BOSS_RETRY_LIMIT`
   是 `const`，子類別無法遮蔽，driver 也沒有可注入的上限。同理
   `BALANCE_BOSS_RETRY_HP_INVALID`／`BALANCE_NON_BOSS_RETRY_PHASE` 兩個守衛亦無法自然觸發。
   目前只斷言 `boss_retry_count <= BOSS_RETRY_LIMIT`。若要覆蓋，最小改動是把上限
   由 `const` 改為可注入欄位（預設值不變）——屬 driver 改動，未自行執行。
2. **forge／equip 的 action apply**：driver 的 bot 動作集只有
   refresh／buy_unit／buy_xp／sell_unit，不含 forge／equip；且正式 content 的 reward table
   只發 gold／heal／relic（`content/packs/vertical_slice/reward_tables/`），
   實測整局 `roster.item_instances` 恆為 0，forge／equip 在 balance 鏈路上沒有可觸發狀態。
   已改為以 `test_production_reward_tables_still_yield_no_items` 當守門員，
   內容一旦開始發物品即轉紅。
