# Codex 批次 3 prompt — gate 已補齊，自 supply port 起續作

> 用法：在 repo 根目錄 `E:\ClaudeWorkingPlace\Game`、分支 `codex/g2-ui-art-refresh-b` 的
> 既有 Codex session 貼入「--- PROMPT 開始 ---」到「--- PROMPT 結束 ---」之間的內容。

--- PROMPT 開始 ---

繼續 in-run-hud。你上一輪停工等待的四個 gate 已由 Claude 交付
（commits `06acfcc`＋`c6bc770`，baseline 乾淨，fresh All exit 0：
333 scripts／1388/1388／38268 asserts／Spec 0 failures）。本批依序做：
**S0 supply port → T20 → T21 → T16（完整）→ T25 → T14 → T17 殘缺 → T19 殘缺**。

## gate 交付摘要（你現在可用的東西）

`RunPresentationSession` 新增唯讀讀取面（全部 clone-out，畫面拿不到 controller）：

```gdscript
forge_inventory_components() -> Array[ItemInstanceState]
forge_recipes_containing(component_def_id: StringName) -> Array[ForgeRecipeRule]
try_forge_pair_recipe(instance_a: String, instance_b: String) -> ForgeRecipeRule  # 配不出回 null
shop_economy_status() -> ShopEconomySnapshot        # 金幣/gold_cap/等級經驗/MAX/連勝敗/費用機率
shop_refresh_quote() -> ShopQuoteSnapshot            # 實際扣款/可負擔/具名 rejection_code
shop_buy_xp_quote() -> ShopXpQuoteSnapshot           # +at_max_level/xp_gain/折算後等級經驗
shop_sell_quote(unit_instance_id: String) -> ShopQuoteSnapshot
try_board_draft_preview(placements, bench_ids) -> BoardDraftPreviewSnapshot  # 人口/合法性/羈絆變化
try_committed_board_preview() -> BoardDraftPreviewSnapshot                   # 拖曳前基準
trait_progress() -> Array[TraitProgressSnapshot]     # 含 inactive 列/distinct_count/門檻階梯
```

另已完成：T10 settings port 注入（AppRoot 每次 route commit 綁當前 snapshot＋port）；
focus graph RUN_PREPARE 補滿 11 個 action（`test_prepare_focus_graph_covers_actions.gd`
直接向 ProductionScreen 比對，日後新增動作忘登記會直接紅）；三個進度狀態 key 已入
catalog（`map.node_state.completed`／`map.node_state.current`／`map.node_state.unreached`，
zh_TW/en parity 綠）。

## ⚠ T20 語意勘誤（以本節為準，早前批次 2 prompt 的描述是錯的）

本專案的零件（component）**結構上不可裝備**：`EquipItemCommand` 拒收零件，
合成唯一路徑是 inventory 內兩個 component instance（`forge_equipment_command.gd`）。
因此**不存在**「拖零件到已持裝棋子上合成」：

- 合成拖曳 ＝ **裝備庫內零件拖到零件上**：懸停時 `try_forge_pair_recipe(a, b)` 顯示
  成品預覽（回 null 就顯示不可合成），落下走 `prepare.forge` → `prepare.forge.confirm`。
- 拖到棋子上的只會是**完整裝備**（配戴，`prepare.equip`）。
- 拖零件到棋子上：以非色彩訊號拒絕並說明（不是合法操作）。
- 詳見 `specs/in-run-hud/design.md` §6 勘誤區塊與修訂後的 IRH-REQ-009。

## 檔案邊界

Claude 已停工，無並行寫入者。你**仍不得改**：`domain/**`、`services/**`、`app/**`、
`presentation/viewmodels/**`、`presentation/run/run_presentation_session.gd`（只准消費）、
`tests/unit/in_run_hud/test_run_presentation_session_supply_api.gd`／
`test_unit_stats_preview_view_model.gd`／`test_trait_progress_authority.gd`／
`test_board_draft_preview_view_model.gd`／`test_shop_economy_view_model.gd`／
`test_prepare_focus_graph_covers_actions.gd`（Claude 的契約測試）。
其餘（screens／viewport／localization 接線／integration 測試／新 unit 測試）都是你的。
需要新的上游能力時停下來回報，不要自己動 Claude 範圍。

## 任務

**S0（新增，最先做）**：`LiveScreenSupplyPort`——lease 保護的唯讀 port，
比照既有 `LiveScreenIntentPort` 的 lease 驗證寫法，轉發上列十個 session 方法；
接進 `ProductionLiveScreenContext`。沒有它，畫面拿不到任何報價與配方。

**T20 合成配方預覽**（修訂語意）：裝備庫內零件對零件拖曳＋`try_forge_pair_recipe`
懸停預覽＋一次確認；雙路徑等價整合測試（拖曳 vs 按鈕，最終 `RunState` 含
inventory／overflow 完全一致）。

**T21 純鍵盤 E2E**：只用鍵盤事件完成「買棋 → 上場（W）→ 配裝 → 開始戰鬥」。
focus graph 已補滿，不需再改它。

**T16 羈絆列與詳情浮層（完整版）**：資料來源改為 supply port 的 `trait_progress()`
（含 inactive 列——這是上次做不了的部分）；成員縮圖＋持有非色彩標示、
浮層自適應與安全區翻轉、階級非色彩訊號。單一掛點原則不變。

**T25 收尾**：把 `map.node_state.*` 三個 key 接進進度列的 accessibility copy
（`in_run_hud_shell.gd` 的 accessible_tokens 目前只有符號＋節點類別＋內容名）。

**T14 經濟資訊列**：`shop_economy_status()`＋`shop_refresh_quote()`＋
`shop_buy_xp_quote()` 接線——金幣、等級經驗（MAX 停用）、費用機率、連勝敗；
停用原因顯示具名 `rejection_code` 對應文案，缺 key 就補（雙語 parity）。

**T17 殘缺**：出售價改 `shop_sell_quote()`；2★ 以上或帶裝出售的二次確認。

**T19 殘缺**：拖曳中以 `try_board_draft_preview()` 顯示人口與羈絆變化
（`try_committed_board_preview()` 當基準做「變化前→後」）。

## 驗收與證據

- 每項任務完成即產出 focused 測試 exit 0＋輸出摘錄；視覺項附實機截圖到
  `specs/in-run-hud/evidence/p8-batch2/`（沿用同一目錄）。
- 批次結束：`tools/run-tests.ps1 -Suite All` exit 0（附 GUT 統計行）、
  `git diff --check` 通過、勾選 `tasks.md` 並附交付行、更新台帳
  `irh-requirements-manifest.md` 受影響列（011/013/014 的 BLOCKED/PARTIAL 應可轉 PASS，
  008/009/010/015 依實況）。
- 遵守 `HANDOFF.md` §2 七條＋in-run-hud 追加約束；玩家可見文字一律 loc key。

--- PROMPT 結束 ---
