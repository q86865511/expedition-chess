# Codex 批次 2 prompt — in-run-hud 無上游相依的四項收尾

> 用法：在 repo 根目錄 `E:\ClaudeWorkingPlace\Game`、分支 `codex/g2-ui-art-refresh-b` 的
> 既有 Codex session 貼入「--- PROMPT 開始 ---」到「--- PROMPT 結束 ---」之間的內容。

--- PROMPT 開始 ---

繼續 in-run-hud。T32 已由 Opus re-review APPROVED 關閉；需求台帳
（`specs/in-run-hud/evidence/p7-final/irh-requirements-manifest.md`）目前
PASS 8／PARTIAL 7／BLOCKED 2。本批次只做**不依賴新上游 API** 的四項收尾，
依序：**T20 → T21 → T16（呈現半邊）→ T25（收尾）**。

## 並行邊界（本批次最重要的規則）

Claude 正在同一工作樹並行交付上游 API 批次。**你不得改動以下路徑**，
它們是 Claude 本輪的檔案範圍：

- `domain/**`、`services/**`、`app/**`
- `presentation/viewmodels/**`
- `tests/unit/in_run_hud/**`
- `specs/in-run-hud/codex-*.md`、`HANDOFF.md`

你的檔案範圍：`presentation/screens/**`、`presentation/run/**`（僅限呈現接線）、
`localization/**`、`tests/integration/**`、`specs/in-run-hud/tasks.md`（勾選）、
`specs/in-run-hud/evidence/p8-batch2/**`（本批證據落點）。
若發現必須動到 Claude 範圍內的檔案，**停下來回報，不要動手**。

開工前先把你目前工作樹的未提交變更 commit 起來（依既有訊息慣例），
避免與並行批次互相污染 baseline。

## T20 — 合成配方預覽（IRH-REQ-009 殘缺）

台帳明載：`ForgeViewModel.recipe_preview()` **已存在**
（`presentation/viewmodels/forge_view_model.gd:29`），只是 UI 從未呼叫。

1. 裝備拖曳懸停在「已持有裝備的棋子」上時，呼叫 `recipe_preview()` 顯示配方預覽
   （會合成什麼、消耗哪兩件）；預覽資料一律來自該 ViewModel，不得在 UI 端拼配方。
2. 落下後走既有 `prepare.forge` → `prepare.forge.confirm` 流程，一次確認不得省略。
3. 新增雙路徑等價整合測試：同一組合成經「拖曳」與「既有按鈕」兩條路徑，
   最終 `RunState`（含 inventory／overflow）完全一致。參考既有等價測試寫法：
   `tests/integration/presentation_ui_in_run_drag_canonical/test_projected_drag_matches_button_canonical_layout.gd`。

## T21 — 純鍵盤 E2E（IRH-REQ-010 殘缺）

新增整合測試：**只用鍵盤事件**完成「買棋 → 上場（W 快捷）→ 配裝 → 開始戰鬥」全程。
- 不得用滑鼠座標或直接呼叫 screen 方法模擬；用 InputEvent／focus 導航驅動。
- 驗證 `keyboard_focus_graph.gd` 涵蓋路徑上每個互動元素（該檔屬 Claude 範圍，
  只讀不改；若發現缺項，回報而非自行修改）。

## T16 呈現半邊 — 羈絆詳情浮層（IRH-REQ-013 的非 BLOCKED 部分）

上游的 inactive trait／distinct-def 計數／下一門檻 authority 由 Claude 並行交付，
**本批不做 inactive 列**。你做已有資料就能完成的部分：

1. 浮層成員縮圖列：用 `TraitBattleSnapshot.member_instance_ids` 對應 portrait，
   持有中的成員加非色彩標示（形狀框或符號，§10.5）。
2. 浮層高度自適應、貼近畫面邊緣時自動翻轉，且不超出安全區（36px）。
3. 資料來源收斂在單一掛點：浮層的資料組裝寫成一個獨立函式吃
   `Array[TraitBattleSnapshot]`，之後 Claude 的進度 API 落地時只換資料來源、
   不改浮層本體。

## T25 收尾 — 進度狀態 localization keys（IRH-REQ-015 殘缺）

台帳明載 screen-reader copy 只有符號與節點資訊。補上完成／當前／未達三種狀態的
zh_TW＋en localization key（進 `localization/catalog.v2.csv`，兩語系同 key 集合），
接進進度列的 accessibility copy。靜態 gate 的 loc parity 必須維持綠。

## 驗收與證據（每項任務完成即產出，不要囤到最後）

- 每項任務：focused 測試 exit 0＋輸出摘錄；涉及視覺的附實機截圖到
  `specs/in-run-hud/evidence/p8-batch2/`。
- 批次結束：`tools/run-tests.ps1 -Suite All` exit 0（附 GUT 統計行）；
  `git diff --check` 通過；勾選 `tasks.md` 對應項並附「交付：commit／證據」行。
- 一律遵守 `HANDOFF.md` §2 七條與 in-run-hud 追加約束（尺寸經
  `ExpeditionLayoutMetrics`、玩家可見文字一律 loc key、不逐幀輪詢 ViewModel）。

--- PROMPT 結束 ---
