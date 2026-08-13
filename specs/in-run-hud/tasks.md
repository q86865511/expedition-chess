# G2 in-run-hud — Tasks

執行者：**Codex**（T01 除外，T01 由 Claude 執行）。
每項任務完成時回填「交付：commit `<sha>`；證據：<測試檔或截圖路徑>」。

通則：

- 遵循 `HANDOFF.md` §2 七條消費契約。**不得修改 `domain/`、`services/`**（T01 除外）。
- 每個階段結束跑 `tools/run-tests.ps1 -Suite All` 並貼實際輸出（exit 0）。
- 視覺任務需附實機截圖：`tools/run-isolated-ui-evidence.ps1`，
  尺寸 1280×720／1920×1080／**2560×1440**、UI 縮放 100／125／150。
- 證據落 `specs/in-run-hud/evidence/<phase>/`；暫存檔不落專案根目錄。

---

## P0 前置

- [x] **T00 HARD**：鎖 requirements／design／tasks；架構規格先行改動已由 Claude 完成
  （`REQ-UX-006`、`AC-080`~`AC-082`、`DEC-015`、§10.1／10.2／10.3／10.4／10.6、§14 矩陣、manifest）。
  Codex 開工前確認 `-Suite Spec` exit 0。
- [x] **T01 HARD（Claude 執行）**：備戰期單位屬性預覽 API——唯讀查詢，與 `compile()` 共用
  `BattleSetupSourceCompiler` 的 `_apply_stats`／`_find_scaling` 星級縮放路徑，回傳具名型別。
  不改 canonical 狀態、不新增 RNG draw、不改 save schema、不新增 Autoload。（IRH-REQ-016）
  交付：`BattleSetupSourceCompiler.try_compile_unit_stats()`、`UnitStatsPreviewSnapshot`
  （`domain/battle/`）、`UnitStatsPreviewViewModel`（`presentation/viewmodels/`，
  `try_stats_for()`／`all_stats()`）。
  證據：`tests/unit/in_run_hud/test_unit_stats_preview_view_model.gd` 5 tests／36 asserts
  （含變異驗證：`preview.attack + 1` 使 4 個測試函式轉紅）；fresh All exit 0
  （307 scripts、1224/1224 tests、25773 asserts、Spec 0 failures）。
  範圍界線：裝備／羈絆／遺物的 effect 加成不併入數值，只回報來源 id（見 design.md §7）。
- [x] **T02 HARD**：世界層解析度裁決——依 `design.md` §3 的取捨表，在 plan 中提出結論與理由並回報。
  若選 B（960×540）必須同時提出 2560×1440 下避免半像素取樣的具體作法，
  並將 44 單位資產重生成列為獨立前置批次。（IRH-REQ-007）

## P1 基準遷移與骨架

- [x] **T03 HARD**：`REFERENCE_SIZE` 1280×720 → 1920×1080——
  `UiScaleRoot`、`ProductionLayoutShell`、`project.godot` 的 `viewport_width/height` 三處一致；
  骨架常數與 theme token 依 `design.md` §2 表格 ×1.5。（IRH-REQ-001）
- [x] **T04 NORMAL**：尺寸字面值全量換算——14 處 `ExpeditionLayoutMetrics.set_min` 系列呼叫
  ＋`presentation/` 下 24 處殘留 `custom_minimum_size` 直接賦值一律改經 metrics helper。
  完成後 `presentation/` 不得殘留任何直接賦值。（IRH-REQ-001）
- [x] **T05 NORMAL**：局外畫面機械遷移——`MENU_MAIN`、`CAMP_WORLD`、設施、`COLLECTION`、
  `SETTINGS`、`RESULTS` 在新基準下維持可用、不裁切、gate 不紅。**不做視覺重設計**。（範圍節）
- [x] **T06 NORMAL/TDD**：9 組幾何稽核（3 解析度 × 3 UI 縮放）——必要操作可見可點、
  無重疊、無裁切。（IRH-REQ-001、IRH-REQ-002／測試策略 #1、#2）
- [x] **T07 NORMAL**：`tools/run-isolated-ui-evidence.ps1` 新增 `2560x1440` 尺寸選項。

## P2 系統選單

- [x] **T08 HARD**：InputMap 自訂 action（`project.godot` 新增 `[input]` 段）與
  `_unhandled_input` 優先序（modal > 選單 > 開啟）。**不得沿用 `ui_cancel`**。（IRH-REQ-006／測試 #5）
- [x] **T09 HARD**：系統選單覆蓋層——掛 `REGION_OVERLAY`，四項（繼續遊戲／設定／
  返回主選單／離開遊戲），focus trap 與焦點還原。（IRH-REQ-004／測試 #3）
- [x] **T10 HARD（Claude 完成，2026-08-12）**：settings port 注入——查證縫已存在
  （`production_screen.bind_system_menu_settings(snapshot, port)`），缺的是 AppRoot 從未呼叫；
  `_commit_route` 對 RUN routes 每次重讀當前 `settings_application_port()` 與
  `repository.current_snapshot()` 再綁定（查證：settings 套用不重建 coordinator，
  會過期的是 committed snapshot 而非 port）。
  交付：commit `06acfcc`；證據：`test_system_menu_settings_port_injection.gd` 2 tests
  （含重載後非 stale 案例）＋變異驗證（移除綁定呼叫 → 3 條連鎖紅）。
  原描述保留於下供追溯：設定內嵌——將 `settings_screen_composition.gd` 自 `SETTINGS` route 解耦，
  抽出可被 overlay 宿主呼叫的組裝入口；`SETTINGS` route 與 overlay 共用同一份實作。（IRH-REQ-004）
- [x] **T11 NORMAL/TDD**：播放暫停還原——開啟記錄 `previous_paused`、關閉還原；
  不得無條件恢復播放；canonical 摘要不變。（IRH-REQ-005／測試 #4）
- [x] **T12 NORMAL**：動作清單變更——四個局內 route 移除 `run.menu`，
  `keyboard_focus_graph.gd` 的 `_PRIMARY_ACTIONS` 同步。（IRH-REQ-004）

## P3 備戰 HUD

- [x] **T13 HARD**：`RUN_PREPARE` 版面重製——依 `design.md` §2 區域編制與
  `layout-reference-1920.json` 比例參考。（IRH-REQ-003）
- [x] **T14 NORMAL**：經濟資訊列——金幣、等級與經驗、費用機率、連勝／連敗；
  成本一律 `ShopService.quote_*`，停用原因讀 `source_code`。（IRH-REQ-011／測試 #9）
  交付：上游 localization commit `7f6ce69`；`ShopEconomySnapshot`／quote clone-out 接線、16 個
  `SHOP_*` 錯誤映射、MAX／連勝敗／五階費率與可存取停用原因；focused
  `test_prepare_economy_hud_t14.gd` 4／4、71 assertions。
- [x] **T15 NORMAL**：商店卡片列——立繪、羈絆標籤、名稱、費用；費用等級同時以形狀或文字標示；
  已持有副本與升星預覽可見。（IRH-REQ-012）
- [x] **T16 HARD**：羈絆列接線＋詳情浮層——接 `TraitPreviewViewModel.trait_snapshots()`，
  取代現有空 Label；階級非色彩訊號；浮層邊緣翻轉。（IRH-REQ-013／測試 #10）
  交付：commit `9d9be78`；inactive／active、distinct progress、門檻、成員縮圖、非色彩階級、
  safe-area 翻轉；current-source focused 2／2、36 assertions，authority 5／5、45 assertions；
  證據 `p8-batch2/t16-trait-detail-popover.*`。
- [x] **T17 HARD**：單位檢視面板（備戰）——依 T01 的 API；T01 未到位前屬性格顯示
  「尚未可用」，**不得以呈現層自行計算的數值填充**。（IRH-REQ-014／測試 #11）
  交付：備戰／戰鬥 inspector clone、權威 sell quote、2★／帶裝確認、captured identity、
  cancel 零 dispatch／confirm exactly once；focused inspector 12／12（127 assertions）、
  sell confirmation 6／6（47 assertions）。
- [x] **T18 NORMAL**：裝備庫與遺物槽——`InventoryViewModel` 與 `RelicSlotViewModel` 接線，
  overflow 可見。（IRH-REQ-003）

## P4 拖曳互動

- [x] **T19 HARD**：棋子拖曳——備戰席↔棋盤、換位；合法格提示、交換預覽、人口與羈絆變化預覽。
  只映射既有 intent，不新增 domain command。（IRH-REQ-008／測試 #7）
  交付：typed draft preview、revision cache、route／resize resolver lifecycle、commit 後刷新與
  canonical full-chain；preview focused 1／1（29 assertions），拖曳／按鈕 persisted canonical
  等價 1／1（20 assertions），九組 `p8-batch2/prepare-board-draft-preview-*` 證據。
- [x] **T20 HARD**：裝備拖曳與合成——配戴走 `prepare.equip`；合成走
  `recipe_preview()` → `prepare.forge` → `prepare.forge.confirm`，二次確認不得省略。（IRH-REQ-009）
  交付：commit `bf2f3f5`；focused unit 2／2（15 assertions）、canonical integration
  1／1（36 assertions），證據 `p8-batch2/t20-forge-recipe-preview.*`。
- [x] **T21 NORMAL/TDD**：鍵盤等價——保留按鈕路徑，新增 `W` 快捷（懸停切換上場／收回）；
  純鍵盤可完成「買棋→上場→配裝→開始戰鬥」。（IRH-REQ-010／測試 #8）
  交付：commits `993e511`、`e15b783`；正式純鍵盤 E2E 1／1（本批 current-source
  39 assertions），證據 `p8-batch2/t21-keyboard-only-e2e.txt`。

## P5 戰鬥、地圖、獎勵

- [x] **T22 HARD（阻擋項，先於 T23）**：修「最短可見播放時間／首幀呈現契約」——
  現況 fresh profile 短戰鬥 transcript 在 `RUN_COMBAT` 首個可呈現影格即 exhausted，
  導致戰鬥畫面無法實機截圖（`PROGRESS.md` §已知問題）。未解則 P5 無可信驗收手段。
- [x] **T23 HARD**：`RUN_COMBAT` 版面重製——與備戰同構骨架；移除硬編絕對座標；
  新增戰鬥期常駐資源列（金幣／等級／遠征 HP，唯讀）；商店與備戰席轉唯讀而非消失。（IRH-REQ-003／對照表末列）
- [x] **T24 NORMAL**：單位檢視面板（戰鬥）——`inspect_combat_unit()` 接線，
  空狀態不殘留前一單位。（IRH-REQ-014）
- [x] **T25 NORMAL**：頂部進度列與轉場大字——幕／層／節點、遠征 HP、節點類型非色彩訊號；
  大字提示不阻擋輸入。（IRH-REQ-015／測試 #12）
  交付：commit `29ffb11`；progress 6／6（40 assertions）、accessibility localization
  1／1（7 assertions），證據 `p8-batch2/t25-progress-accessibility-localization.txt`。
- [x] **T26 NORMAL**：`RUN_MAP` 與 `RUN_REWARD` 版面納入同一骨架。（IRH-REQ-003）

## P6 棋盤世界層

- [x] **T27 HARD**：3/4 投影與反投影——格位↔世界↔螢幕；反投影為投影的精確逆運算；
  結果經 domain 合法性檢查後才採用。（IRH-REQ-007／測試 #6）
- [x] **T28 HARD**：棋盤與單位 sprite 移入世界層——8×8 方格、玩家半場 `logical_y` 0–3；
  sprite 停在整數像素、相機無非整數平移。（IRH-REQ-007）
- [x] **T29 NORMAL**：世界空間血條與法力條——投影至螢幕後以固定像素尺寸繪製，
  依 `logical_y` 深度排序，不被特效遮蔽。（IRH-REQ-007／§10.1）
- [x] **T30 NORMAL**：拖曳層與世界層棋盤整合——拖曳預覽在世界層棋盤上正確對位。（IRH-REQ-008）

## P7 收尾

- [x] **T31 HARD**：全 gate 與證據收斂——`-Suite All` exit 0、9 組解析度×縮放截圖、
  IRH-REQ-001 至 IRH-REQ-017 逐條對應證據表（含 IRH-REQ-017 既有 gate 不回歸）；
  `PROGRESS.md` 回填。
  交付：commit `0d120ea`；證據：`evidence/p8-batch2/t31-closure-audit.md`、
  `evidence/p8-batch2/t31-all-suite-output.txt`、
  `evidence/p8-batch2/t31-summon-renderer-focused.txt`、
  `evidence/p7-final/irh-requirements-manifest.md`。
- [x] **T32 HARD**：雙審——`reviewer`（opus）＋ codex MCP 第二審；findings closure 落
  `.pipeline/reviews/`。External Opus closure re-review 原文與 `APPROVED` verdict 保存於
  `.pipeline/reviews/in-run-hud-opus-re-review-approved.md`，並鏡像至
  `specs/in-run-hud/evidence/p7-final/in-run-hud-opus-re-review-approved.md`。

### 2026-08-13 T31 final closure checkpoint

- Task boxes：已完成 `T00～T32`（33／33）。
- Fresh formal evidence：146／146 cases（baseline 128＋shop-tier 9＋board-draft-preview 9）、
  `issues=[]`、exit 0；
  三尺寸 × 三 UI scale 產物已重建，real APPDATA before／after SHA-256 相同，Godot process 0。
- Codex 以 `905e664` 為 baseline 獨立審核 T14／T17／T19；產品 finding 0，文件 finding 2
  （T16 assertion 計數、T19 漏列 canonical 等價測試）已更正，詳見
  `evidence/p8-batch2/batch3-codex-audit.md`。
- 2026-08-13T09:02:43Z～09:18:57Z current-source `-Suite All` 為 exit 0：345 scripts、
  1428／1428 tests、38825 assertions、0 failures／errors／orphans，Spec 4092 cases；
  Import／GUT 無 `Parse Error`／`Failed to load`。
- IRH-REQ-007 dynamic summon 已由 pinned template→supply port→screen→projection→renderer
  單一路徑閉合；Claude 契約 5／5（78）與 screen renderer seam 2／2（15）皆 exit 0。
  正式內容無 summon effect，依交付約束以 typed fixture 驅動正式 renderer 並明示限制。
- 需求台帳：PASS 17／PARTIAL 0／BLOCKED 0；T31 關閉。
- 原外部 Opus review 為 `CHANGES_REQUESTED`；13 項 decision table 與使用者轉交的 external
  Opus closure re-review `APPROVED` 原文均已落
  `evidence/p7-final/in-run-hud-opus-re-review-approved.md`，無 OPEN finding，故 T32 關閉。
- T14／T16／T17／T19／T20／T21／T25 已依 production、focused、Fresh All 與 p8 證據關閉；
  不回退或重做既有 T16／T21／T25 實作。
