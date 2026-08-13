# in-run-hud 需求證據清單（批次 3 更新）

日期：2026-08-13
基準：`specs/in-run-hud/requirements.md` IRH-REQ-001～017、`design.md`、`tasks.md`
候選狀態：**T31 尚未完成；T32 已由 external Opus re-review `APPROVED` 關閉**

## 判定規則

- **PASS**：目前工作樹的實作與現有 focused test／runtime evidence 足以直接支持驗收條件。
- **PARTIAL**：已有實作或證據，但仍缺一項以上明列驗收條件；不得視為 requirement 完成。
- **BLOCKED**：缺必要 typed upstream contract，或最終 gate／review 尚未取得有效證據。

目前統計：**PASS 16／PARTIAL 1／BLOCKED 0**。

## Evidence candidate 摘要

- Fresh `p8-batch2/evidence-report.json`：`ok=true`、`exit_code=0`、`locale=zh_TW`、
  146／146 cases、`issues=[]`；由 baseline 128 cases＋shop-tier 9 cases＋
  board-draft-preview 9 cases 組成；SHA-256
  `6BB13FC1EAC9D8F429731C1A41C3CD508E4E3F7D52F00F00B7A36EDF1EBDC5D7`。
- 產物包含 1280×720、1920×1080、2560×1440 × UI 100／125／150 的 9 組矩陣。
- `prepare-*`、`combat-*`、`map-*`、`reward-*` 各具完整 9 組截圖；另有 menu、camp、settings、
  action groups、node choice、modal、status、focus 與 scale rebuild 證據。
- 146 cases 由既有 128 cases、`prepare-shop-tiers-*` 9 圖與
  `prepare-board-draft-preview-*` 9 圖組成；tier fixture 經 pinned
  `ProjectContentBootstrap`、`ShopUnitRule.cost` 與 `ShopOfferPreviewViewModel` 產生，並驗五種邊框、
  非色彩 tier 提示、portrait、權威 cost／tier／star、在地化 accessibility copy 與 raw identity 不外洩。
- `scale-rebuild-report.json`：150 → rebuild → 100 後，開始戰鬥按鈕 minimum 回復 `(120, 72)`。
- `world-board-state.json`：world surface 1、unit 1、renderer visible、snapshot valid。
- `real-appdata-integrity.json`：實際 `%APPDATA%/Godot/app_userdata/**` 前後 inventory SHA-256 相同。
  本輪 before／after 均為
  `b68bfb1afb4ab0ed9b90a1089ab3b1550ea318dcd4cde3c42b58a85866b22867`，完成後 Godot process 0。
- **限制**：`reward-evidence-source.json` 明列 REWARD 九圖使用
  `formal-screen-typed-snapshot-fixture` 與 typed `PendingRewardState.CHOOSING`；fresh profile 第一戰
  決定性落至 `RUN_MAP`，故這九圖是正式 screen typed-fixture evidence，不是自然流程 REWARD 證據。
- 2026-08-13（UTC）Codex 以 `905e664` 為 baseline 獨立重跑 current-source fresh full All：
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run-tests.ps1 -Suite All`
  `-GodotPath 'E:\OneDrive\桌面\Godot_v4.7-stable_win64.exe' -TimeoutSeconds 3600`，
  06:17:42Z～06:35:04Z，exit 0；摘要與獨立逐條判定見
  `p8-batch2/batch3-all-suite-audit-output.txt`／`batch3-codex-audit.md`。
- GUT：343 scripts／1421 tests／1421 passing／38732 assertions／0 failures／0 errors；
  `all-gut.godot.log` 與 `import.godot.log` 無 `Parse Error`／`Failed to load`。Spec：4092 cases、
  `failures=[]`、`passed=true`；Content／Canonical／Combat／Expedition／ActEliminationGate 皆 exit 0。
- Opus closure 代表性 focused：projected DnD／button persisted canonical 等價
  1 test／20 assertions；active `COMBAT_PENDING` empty inspection fail-closed
  10 tests／87 assertions，皆 exit 0。
- 上述 current-source All 已包含批次 3 修正與 evidence runner contract；Import／Smoke／Gut／
  Content／Canonical／Combat／Expedition／ActEliminationGate／Spec 均取得預期 exit 0，runner
  contract negative fixtures 亦維持預期非 0。
- 封版文件落地後另於 18:56:05Z～18:56:09Z 補跑 `-Suite Spec`：4076 cases，
  `passed=true`、`failures=[]`、exit 0；目前 `runner-execution.json` 因此記錄該最後 Spec-only run，
  All 實數保留於 `all-suite-output.txt` 與 `gut.xml`。

## IRH-REQ-001～017

| Requirement | 狀態 | 程式／測試／證據 | 尚缺或限制 |
|---|---|---|---|
| IRH-REQ-001 基準解析度遷移 | PASS | `project.godot`；`presentation/viewport/ui_scale_root.gd`；`presentation/screens/production_layout_shell.gd`；`presentation/viewport/world_viewport_policy.gd`；`tests/unit/presentation_ui_viewport/test_b1_reference_and_input_contract.gd`；三尺寸產物 | `custom_minimum_size` lexical gate 會拒絕真 assignment、忽略註解／字串／讀取；`presentation/` 唯一 production setter 為 `expedition_layout_metrics.gd`；fresh visual report 0 issues。 |
| IRH-REQ-002 UI 縮放語意 | PASS | `presentation/theme/expedition_theme_runtime.gd`；`presentation/theme/expedition_layout_metrics.gd`；九組矩陣；`scale-rebuild-report.json` | 現有 geometry runner 為零 issue。 |
| IRH-REQ-003 四 route 共用骨架 | PASS | `presentation/screens/in_run_hud_shell.gd`；四 route 分別建立同一 `InRunHudShell`；prepare/combat/map/reward 各 9 圖；combat 5-slot shop＋9-slot bench scroll/focus gate | 共用 class、route 區域編制與容器式 combat layout 已成立；runtime 不再依硬編絕對座標排 combat HUD。 |
| IRH-REQ-004 ESC 系統選單 | PASS | `presentation/screens/production_screen.gd`；`system_menu_overlay.gd`；`settings_screen_composition.gd`；commit `06acfcc`；system-menu 單元、四 route contract 與 `test_system_menu_settings_port_injection.gd` | 四 route 無常駐 `run.menu`；內嵌設定不換 route，AppRoot 每次 route commit 重讀 committed snapshot／port 注入，reload 不保留 stale snapshot；modal／選單 focus trap 與雙確認均有 runtime 測試。 |
| IRH-REQ-005 選單暫停／還原 | PASS | `production_screen.gd` 的 previous-paused capture/restore；`run_combat_screen.gd` 共用 settlement guard；system-menu／combat settle 整合測試 | paused=true／false、canonical digest、initial settle 與 retry 在 menu/modal/paused 下不 transition 均有案例。 |
| IRH-REQ-006 專屬輸入 action | PASS | `project.godot` 的 `system_menu`／`prepare_quick_toggle_unit`；`production_screen.gd` input priority；B1 input contract 與 system-menu 整合測試 | modal／文字輸入優先序已有測試，未沿用 `ui_cancel`。 |
| IRH-REQ-007 棋盤世界層 | PARTIAL | `board_projection.gd`；world-board renderer/mount/overlay；`combat_world_event_projection.gd`；T27/T28/T29／factory/event 單元測試；`world-board-state.json` | 8×8、玩家半場、逆投影、整數像素、640×360、world-space head anchor、renderer-equivalent depth、duplicate-cell／empty-active-combat fail-closed 與 late-event lifecycle 已有契約；但 dynamic summon/spawn 缺 visual/max-stat authority，只能追蹤為 unrenderable。 |
| IRH-REQ-008 拖曳擺位 | PASS | `board_draft_move_adapter.gd`；`run_prepare_screen.gd`；world-board drag target/overlay；`test_t19_production_drag_preview_commit.gd`；`test_projected_drag_matches_button_canonical_layout.gd`；九張 `p8-batch2/prepare-board-draft-preview-*` | 備戰席↔棋盤、換位、合法／交換 cue、人口與羈絆 typed preview、revision cache、route／resize resolver lifecycle 與 command-boundary refresh 均成立；非法 drop 零 publication，合法 drop 走既有 canonical command，拖曳／按鈕 persisted RunState 等價。 |
| IRH-REQ-009 裝備拖曳與合成 | PASS | `prepare_equipment_drag_list.gd`；`prepare_unit_drag_button.gd`；`run_prepare_screen.gd`；commit `bf2f3f5`；T20 unit／canonical integration／PNG | 配戴走既有 equip；零件組合先取 pinned `recipe_preview()`，再走 forge→confirm；drag／button 在 exactly-once confirm 後完整 canonical state 等價。 |
| IRH-REQ-010 鍵盤等價路徑 | PASS | W action；`run_prepare_screen.gd` quick toggle；正式 focus graph；commit `993e511`／`e15b783`；`test_prepare_keyboard_only_purchase_deploy_equip_start.gd` | 正式 production route 已以 InputEvent 完成純鍵盤買棋→上場→配裝→開始戰鬥；本批 current-source focused 1／1、39 assertions。 |
| IRH-REQ-011 經濟資訊列 | PASS | `ShopEconomySnapshot`／quote clone-out；`in_run_hud_shell.gd`；`production_screen.gd`；`presentation_error_mapper.gd`；`test_prepare_economy_hud_t14.gd` | 金幣、level／XP threshold 或 MAX、五階 authored odds、連勝／連敗、refresh／XP 權威 quote 費用與可存取停用原因均接線；16 個 `SHOP_*` code 依裁決分流，`SHOP_INPUT_INVALID` 不推斷 phase。 |
| IRH-REQ-012 商店帶 | PASS | `shop_offer_preview_view_model.gd`；`shop_offer_preview_snapshot.gd`；`production_screen.gd` shop cards；`prepare-shop-tiers-*` 九圖與 functional gate | Canonical offer＋rich preview 嚴格匹配；cost 單一權威值、tier 以非文字 pips、star true/false 以 rise/flat shapes，另有 portrait、traits、持有數與固定空槽；缺／不符 preview fail closed。Fresh tier visual gate 9／9、全 report 0 issues。 |
| IRH-REQ-013 羈絆列與詳情浮層 | PASS | `LiveScreenSupplyPort.trait_progress()`；`TraitProgressSnapshot`；`in_run_hud_shell.gd`；commit `9d9be78`；T16 focused／PNG | inactive／active、distinct progress／next threshold、authored ladder／effects、成員縮圖與持有 cue、自適應 scroll、水平／垂直 safe-area flip 均由 typed clone 接線。 |
| IRH-REQ-014 單位檢視面板 | PASS | `InRunHudShell.mount_unit_inspector()`；prepare／combat typed DTO；權威 sell quote；captured-id confirmation；T17 inspector／sell focused | 備戰與戰鬥 inspector 模式／identity 可跨 relocalize；未選取清空；1★無裝直接售出，2★或帶裝須確認，cancel 零 dispatch、confirm captured unit exactly once；缺 inspection fail closed。 |
| IRH-REQ-015 進度列與轉場 | PASS | `in_run_hud_shell.gd` deterministic sequence／non-color node-kind state／non-blocking banner；commit `29ffb11`；T25 focused／TXT | 節點序列、完成／當前／未達非色彩狀態與本地化 screen-reader copy、遠征 HP、750 ms 大字及不攔輸入契約均有測試。 |
| IRH-REQ-016 備戰屬性預覽 API | PASS | `BattleSetupSourceCompiler.try_compile_unit_stats()`；`UnitStatsPreviewSnapshot`；`UnitStatsPreviewViewModel`；`tests/unit/in_run_hud/test_unit_stats_preview_view_model.gd` | 已有棋盤／板凳、逐欄位同源、clone-only 與裝備來源 5 tests／36 asserts，且納入本次 fresh All。 |
| IRH-REQ-017 既有 gate 不回歸 | PASS | `p8-batch2/batch3-all-suite-audit-output.txt`／`batch3-codex-audit.md`；既有 `all-gut.godot.log`／`spec-contract.json`／`evidence-report.json` | 2026-08-13T06:17:42Z～06:35:04Z current-source All exit 0：343 scripts／1421 passing／38732 assertions／0 failures／0 errors；Spec 4092 與其他 gates 取得預期 exit 0。Fresh visual evidence 146／146、0 issues，收尾背景 Godot 0。 |

## T31／T32 closure 狀態

- T31：**PARTIAL**。Fresh visual evidence 為 146／146、0 issues，current-source All 亦為
  exit 0；IRH-REQ-007 dynamic summon typed visual／max-stat authority 尚未 closure。
- T32：**CLOSED／APPROVED**。Codex 第二審、原始 external Opus `CHANGES_REQUESTED` review
  與 external Opus closure re-review 均已取得；re-review 對前次 13 項 findings 判定
  10 項 `CLOSED`、3 項 `ACCEPTED`、0 項 `OPEN`。使用者轉交的 `APPROVED` 原文保存於
  `in-run-hud-opus-re-review-approved.md`；此核可不改變 requirement 統計，也不關閉 T31。

## 主線必須補填

1. 動態 summon／spawn 的 typed visual／max-stat authority；目前 presentation 只可追蹤為
   unrenderable，不能虛構 sprite 或最大值。
2. 自然流程若可到達 REWARD，補自然路徑九組或明確核可 typed fixture 的驗收範圍；
   現有九圖仍明示為正式 typed snapshot fixture。
