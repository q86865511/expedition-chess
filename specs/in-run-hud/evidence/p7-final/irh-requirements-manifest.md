# in-run-hud P7 最終需求證據清單

日期：2026-08-12
基準：`specs/in-run-hud/requirements.md` IRH-REQ-001～017、`design.md`、`tasks.md`
候選狀態：**T31 尚未完成；T32 已由 external Opus re-review `APPROVED` 關閉**

## 判定規則

- **PASS**：目前工作樹的實作與現有 focused test／runtime evidence 足以直接支持驗收條件。
- **PARTIAL**：已有實作或證據，但仍缺一項以上明列驗收條件；不得視為 requirement 完成。
- **BLOCKED**：缺必要 typed upstream contract，或最終 gate／review 尚未取得有效證據。

目前統計：**PASS 8／PARTIAL 7／BLOCKED 2**。

## Evidence candidate 摘要

- Fresh `evidence-report.json`：`ok=true`、`exit_code=0`、`locale=zh_TW`、137／137 cases、
  `issues=[]`；由 baseline 128 cases＋shop-tier 9 cases 組成。
- 產物包含 1280×720、1920×1080、2560×1440 × UI 100／125／150 的 9 組矩陣。
- `prepare-*`、`combat-*`、`map-*`、`reward-*` 各具完整 9 組截圖；另有 menu、camp、settings、
  action groups、node choice、modal、status、focus 與 scale rebuild 證據。
- 137 cases 由既有 128 cases 加上 `prepare-shop-tiers-*` 9 圖組成；tier fixture 經 pinned
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
- 2026-08-11（UTC）修正後 fresh full All：
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run-tests.ps1 -Suite All`
  `-GodotPath 'E:\OneDrive\桌面\Godot_v4.7-stable_win64.exe' -TimeoutSeconds 3600`，
  18:27:27Z～18:49:46Z，exit 0，1339 秒；`artifacts/test/runner-execution.json` 的 suite `All` exit 0。
- GUT：326 scripts／1354 tests／1354 passing／37956 assertions／0 failures／0 errors；
  `gut.godot.log` 與 `import.godot.log` 無 `Parse Error`／`Failed to load`。Spec：4076 cases、
  `failures=[]`、`passed=true`；Content／Canonical／Combat／Expedition／ActEliminationGate 皆 exit 0。
- Opus closure 代表性 focused：projected DnD／button persisted canonical 等價
  1 test／20 assertions；active `COMBAT_PENDING` empty inspection fail-closed
  10 tests／87 assertions，皆 exit 0。
- 上述 final current-source All 已包含修正後 evidence runner contract；Import／Smoke／Gut／
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
| IRH-REQ-004 ESC 系統選單 | PARTIAL | `presentation/screens/production_screen.gd`；`system_menu_overlay.gd`；`settings_screen_composition.gd`；system-menu 單元與四 route 整合測試 | 選單、雙確認與 composition 已實作；focus trap 能抑制 unlisted、late-added、late-enabled controls 並精確還原。**正式 settings application port 尚未由 production boundary 注入**，因此實機 route 不能宣稱內嵌設定完成。 |
| IRH-REQ-005 選單暫停／還原 | PASS | `production_screen.gd` 的 previous-paused capture/restore；`run_combat_screen.gd` 共用 settlement guard；system-menu／combat settle 整合測試 | paused=true／false、canonical digest、initial settle 與 retry 在 menu/modal/paused 下不 transition 均有案例。 |
| IRH-REQ-006 專屬輸入 action | PASS | `project.godot` 的 `system_menu`／`prepare_quick_toggle_unit`；`production_screen.gd` input priority；B1 input contract 與 system-menu 整合測試 | modal／文字輸入優先序已有測試，未沿用 `ui_cancel`。 |
| IRH-REQ-007 棋盤世界層 | PARTIAL | `board_projection.gd`；world-board renderer/mount/overlay；`combat_world_event_projection.gd`；T27/T28/T29／factory/event 單元測試；`world-board-state.json` | 8×8、玩家半場、逆投影、整數像素、640×360、world-space head anchor、renderer-equivalent depth、duplicate-cell／empty-active-combat fail-closed 與 late-event lifecycle 已有契約；但 dynamic summon/spawn 缺 visual/max-stat authority，只能追蹤為 unrenderable。 |
| IRH-REQ-008 拖曳擺位 | PARTIAL | `board_draft_move_adapter.gd`；`run_prepare_screen.gd`；world-board drag target/overlay；`tests/integration/presentation_ui_in_run_drag_canonical/test_projected_drag_matches_button_canonical_layout.gd` | 拖放、換位、來源→目標／swap 非色彩提示與同一 command path 已接；button 與 projected DnD 的 persisted layout digest 已等價，`saved_at_utc` 是唯一 publication metadata allowlist、其餘 document fields 全 denylist。仍缺人口／羈絆變化 typed preview；不宣稱 native pointer gesture QA。 |
| IRH-REQ-009 裝備拖曳與合成 | PARTIAL | `prepare_equipment_drag_list.gd`；`prepare_unit_drag_button.gd`；`run_prepare_screen.gd` | 配戴拖放與 forge confirmation 已接；`ForgeViewModel.recipe_preview()` 尚未由 UI 呼叫，缺配方預覽與雙路徑等價測試。 |
| IRH-REQ-010 鍵盤等價路徑 | PARTIAL | W action；`run_prepare_screen.gd` quick toggle；`keyboard_focus_graph.gd`；evidence runner quick-toggle probe | 缺純鍵盤「買棋→上場→配裝→開始戰鬥」完整 E2E。 |
| IRH-REQ-011 經濟資訊列 | BLOCKED | `in_run_hud_shell.gd` 現有 gold、level/xp；cloned `RunPresentationSnapshot.economy` | Streak 已存在 cloned `EconomyState` 但尚未呈現；authored odds 可由 pinned catalog 讀取但尚未投影；**quote/disabled reason 仍缺正式 typed upstream writer input**，presentation 不得複製公式。MAX、費用機率、連勝／連敗與具名停用原因尚未完成。 |
| IRH-REQ-012 商店帶 | PASS | `shop_offer_preview_view_model.gd`；`shop_offer_preview_snapshot.gd`；`production_screen.gd` shop cards；`prepare-shop-tiers-*` 九圖與 functional gate | Canonical offer＋rich preview 嚴格匹配；cost 單一權威值、tier 以非文字 pips、star true/false 以 rise/flat shapes，另有 portrait、traits、持有數與固定空槽；缺／不符 preview fail closed。Fresh tier visual gate 9／9、全 report 0 issues。 |
| IRH-REQ-013 羈絆列與詳情浮層 | BLOCKED | `TraitPreviewViewModel.trait_snapshots()`；`RunPresentationSnapshot.active_trait_progress`；pinned authored threshold projection；`in_run_hud_shell.gd` ItemList | Active trait authority＋完整 authored threshold ladder 已投影且 manifest mismatch fail-closed；**inactive trait、distinct-def count／next progress 仍缺 upstream authority**，另缺成員縮圖／持有標示、自適應浮層與安全區 flip。 |
| IRH-REQ-014 單位檢視面板 | PARTIAL | `InRunHudShell.mount_unit_inspector()`；prepare typed inspector DTO；combat inspector；T01/T17 tests | 正式 prepare composition 只有一個玩家可見 panel，真實 selector 與完整 hover-exit relay 可 empty→selected→empty；內容欄位已接。仍缺 ShopService sell quote 與高星／帶裝出售確認的 production parity。 |
| IRH-REQ-015 進度列與轉場 | PARTIAL | `in_run_hud_shell.gd` deterministic node sequence／non-color node-kind state／non-blocking banner；四 route 截圖；T25 focused tests | 節點序列、完成／當前／未達非色彩狀態與 750 ms 大字已接；screen-reader copy 仍只有符號與節點資訊，缺完成／當前／未達的在地化文字 key。 |
| IRH-REQ-016 備戰屬性預覽 API | PASS | `BattleSetupSourceCompiler.try_compile_unit_stats()`；`UnitStatsPreviewSnapshot`；`UnitStatsPreviewViewModel`；`tests/unit/in_run_hud/test_unit_stats_preview_view_model.gd` | 已有棋盤／板凳、逐欄位同源、clone-only 與裝備來源 5 tests／36 asserts，且納入本次 fresh All。 |
| IRH-REQ-017 既有 gate 不回歸 | PASS | 本目錄 `all-suite-output.txt`／`evidence-report.json`；`artifacts/test/runner-execution.json`；`gut.xml`／logs；`spec-contract.json` | 18:27:27Z～18:49:46Z final current-source All exit 0：326 scripts／1354 passing／37956 assertions／0 failures／0 errors；Spec 4076 與其他 gates 取得預期 exit 0。Fresh evidence 137／137、0 issues、Godot 0；All 已涵蓋修正後 runner contract。 |

## T31／T32 closure 狀態

- T31：**PARTIAL（整體 closure 仍 BLOCKED）**。Fresh visual evidence 為 137／137、0 issues，
  final current-source All 亦為 exit 0；上述 PARTIAL／BLOCKED requirements 尚未 closure。
- T32：**CLOSED／APPROVED**。Codex 第二審、原始 external Opus `CHANGES_REQUESTED` review
  與 external Opus closure re-review 均已取得；re-review 對前次 13 項 findings 判定
  10 項 `CLOSED`、3 項 `ACCEPTED`、0 項 `OPEN`。使用者轉交的 `APPROVED` 原文保存於
  `in-run-hud-opus-re-review-approved.md`；此核可不改變 requirement 統計，也不關閉 T31。

## 主線必須補填

1. 正式 settings application port 注入完成後的 production-boundary 程式／測試／實機證據。
2. inactive／distinct trait progress authority 與 shop odds／quote typed upstream API 的裁決、
   交付路徑與 focused tests；active authored threshold ladder 已交付。
3. forge recipe preview、拖曳人口／羈絆預覽，以及純鍵盤完整 E2E 的測試與 evidence；
   button／projected-drag persisted canonical 等價已交付。
4. 動態 summon/spawn 的 typed visual/max-stat authority、出售 quote／確認 parity，與進度狀態
   accessibility localization keys。
5. 自然流程若可到達 REWARD，補自然路徑九組或明確核可 typed fixture 的驗收範圍。
