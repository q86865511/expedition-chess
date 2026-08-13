# in-run-hud 批次 3 Codex 獨立審核

日期：2026-08-13
baseline：`905e664cbde3cacbd8f4c83cf509487187d72e2c`（開工時 worktree clean）

## 結論

- 產品 finding：**0**。T14、T17、T19 符合批次 3 prompt。
- 文件 finding：**2，均已修正**。
  1. T16 的 current-source focused 實數是 2／2、36 assertions，不是自報的 38。
  2. T19 交付行漏列拖曳／按鈕 persisted canonical 等價測試 1／1、20 assertions。
- 需求台帳 IRH-REQ-011／013／014 的 PASS 已逐條重證；不是沿用
  `batch3-requirements-ledger.md` 的自報。

## T14 審核

- `PresentationErrorMapper._MESSAGE_KEYS` 的 16 個 `SHOP_*` 碼齊全：10 個具名玩家原因與
  6 個 internal failure 分流均符合 prompt。
- `ShopEconomySnapshot` 接線涵蓋金幣、level／XP、MAX、連勝／連敗與五階 basis-point odds。
- refresh／XP quote 以 authority 的費用、可負擔性與 `rejection_code` 控制按鈕；
  `SHOP_INPUT_INVALID` 使用中性文案，不推斷 run phase。
- focused：`test_prepare_economy_hud_t14.gd`，4／4、71 assertions、exit 0。

## T17 審核

- 二次確認條件精確為 `star >= 2 OR equipment_instance_ids 非空`；1★且無裝備直接出售。
- 售價來自 `shop_sell_quote(unit_instance_id)`；缺 inspection／拒絕或未知 quote 均 fail closed。
- modal 開啟後背景停用，payload 捕捉原單位 ID；cancel 0 dispatch，confirm exactly once。
- focused：`test_prepare_sell_confirmation_t17.gd`，6／6、47 assertions、exit 0；
  `test_prepare_unit_inspection_t17.gd`，12／12、127 assertions、exit 0。

## T19 審核

- 拖曳 hover 以 `try_board_draft_preview()` 取得人口、合法性與羈絆候選；
  `try_committed_board_preview()` 是 before 基準，畫面呈現 `before → after`。
- supply authority 的 `compile_trait_progress()` 以 pinned catalog 回傳 active 與 inactive 全列，
  因此羈絆下降至 0 仍會顯示；呈現層未重算門檻。
- 同 revision／target 使用 cache；drop 時 force-refresh authority。非法 drop 零 publication，
  合法 drop 收斂既有 `COMMIT_BOARD_LAYOUT` command。
- focused：typed preview／非法 drop 1／1、29 assertions；拖曳／按鈕 persisted canonical
  等價 1／1、20 assertions；單元 14／14、158 assertions，皆 exit 0。
- 視覺 read-back：九張 `prepare-board-draft-preview-*`；抽查 1080p@100 與 720p@150，
  人口與羈絆均有前→後文字，overlay 位於 world board 上方且有 overflow clipping。

## 台帳 PASS 重證

- IRH-REQ-011：T14 上述 economy／quote／16-code mapping 與 focused 71 assertions 支持 PASS。
- IRH-REQ-013：`trait_progress()` authority 5／5、45 assertions；popover 2／2、36 assertions；
  inactive／active、distinct count、門檻、effect、成員 portrait／持有非色彩 cue、36px safe-area
  水平／垂直 flip 均有程式與視覺證據，支持 PASS。
- IRH-REQ-014：prepare／combat typed inspector、clone-out、relocalize identity、空狀態清除、
  authoritative sell quote 與確認生命週期均有 focused 證據，支持 PASS。

## 批次尾

- Fresh `-Suite All`：exit 0；343 scripts、1421／1421 tests、38732 assertions、
  0 failures／errors；Spec 4092 cases、`passed=true`、`failures=[]`。
- Import／Smoke／Content／Canonical／Combat／Expedition／ActEliminationGate 均 exit 0。
- `git diff --check`：exit 0。
- 完成後背景檢查：Godot／舊 `run-tests` 程序 0。

完整統計摘錄：`batch3-all-suite-audit-output.txt`。
