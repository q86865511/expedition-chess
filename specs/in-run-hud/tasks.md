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

- [ ] **T00 HARD**：鎖 requirements／design／tasks；架構規格先行改動已由 Claude 完成
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
- [ ] **T02 HARD**：世界層解析度裁決——依 `design.md` §3 的取捨表，在 plan 中提出結論與理由並回報。
  若選 B（960×540）必須同時提出 2560×1440 下避免半像素取樣的具體作法，
  並將 44 單位資產重生成列為獨立前置批次。（IRH-REQ-007）

## P1 基準遷移與骨架

- [ ] **T03 HARD**：`REFERENCE_SIZE` 1280×720 → 1920×1080——
  `UiScaleRoot`、`ProductionLayoutShell`、`project.godot` 的 `viewport_width/height` 三處一致；
  骨架常數與 theme token 依 `design.md` §2 表格 ×1.5。（IRH-REQ-001）
- [ ] **T04 NORMAL**：尺寸字面值全量換算——14 處 `ExpeditionLayoutMetrics.set_min` 系列呼叫
  ＋`presentation/` 下 24 處殘留 `custom_minimum_size` 直接賦值一律改經 metrics helper。
  完成後 `presentation/` 不得殘留任何直接賦值。（IRH-REQ-001）
- [ ] **T05 NORMAL**：局外畫面機械遷移——`MENU_MAIN`、`CAMP_WORLD`、設施、`COLLECTION`、
  `SETTINGS`、`RESULTS` 在新基準下維持可用、不裁切、gate 不紅。**不做視覺重設計**。（範圍節）
- [ ] **T06 NORMAL/TDD**：9 組幾何稽核（3 解析度 × 3 UI 縮放）——必要操作可見可點、
  無重疊、無裁切。（IRH-REQ-001、IRH-REQ-002／測試策略 #1、#2）
- [ ] **T07 NORMAL**：`tools/run-isolated-ui-evidence.ps1` 新增 `2560x1440` 尺寸選項。

## P2 系統選單

- [ ] **T08 HARD**：InputMap 自訂 action（`project.godot` 新增 `[input]` 段）與
  `_unhandled_input` 優先序（modal > 選單 > 開啟）。**不得沿用 `ui_cancel`**。（IRH-REQ-006／測試 #5）
- [ ] **T09 HARD**：系統選單覆蓋層——掛 `REGION_OVERLAY`，四項（繼續遊戲／設定／
  返回主選單／離開遊戲），focus trap 與焦點還原。（IRH-REQ-004／測試 #3）
- [ ] **T10 HARD**：設定內嵌——將 `settings_screen_composition.gd` 自 `SETTINGS` route 解耦，
  抽出可被 overlay 宿主呼叫的組裝入口；`SETTINGS` route 與 overlay 共用同一份實作。（IRH-REQ-004）
- [ ] **T11 NORMAL/TDD**：播放暫停還原——開啟記錄 `previous_paused`、關閉還原；
  不得無條件恢復播放；canonical 摘要不變。（IRH-REQ-005／測試 #4）
- [ ] **T12 NORMAL**：動作清單變更——四個局內 route 移除 `run.menu`，
  `keyboard_focus_graph.gd` 的 `_PRIMARY_ACTIONS` 同步。（IRH-REQ-004）

## P3 備戰 HUD

- [ ] **T13 HARD**：`RUN_PREPARE` 版面重製——依 `design.md` §2 區域編制與
  `layout-reference-1920.json` 比例參考。（IRH-REQ-003）
- [ ] **T14 NORMAL**：經濟資訊列——金幣、等級與經驗、費用機率、連勝／連敗；
  成本一律 `ShopService.quote_*`，停用原因讀 `source_code`。（IRH-REQ-011／測試 #9）
- [ ] **T15 NORMAL**：商店卡片列——立繪、羈絆標籤、名稱、費用；費用等級同時以形狀或文字標示；
  已持有副本與升星預覽可見。（IRH-REQ-012）
- [ ] **T16 HARD**：羈絆列接線＋詳情浮層——接 `TraitPreviewViewModel.trait_snapshots()`，
  取代現有空 Label；階級非色彩訊號；浮層邊緣翻轉。（IRH-REQ-013／測試 #10）
- [ ] **T17 HARD**：單位檢視面板（備戰）——依 T01 的 API；T01 未到位前屬性格顯示
  「尚未可用」，**不得以呈現層自行計算的數值填充**。（IRH-REQ-014／測試 #11）
- [ ] **T18 NORMAL**：裝備庫與遺物槽——`InventoryViewModel` 與 `RelicSlotViewModel` 接線，
  overflow 可見。（IRH-REQ-003）

## P4 拖曳互動

- [ ] **T19 HARD**：棋子拖曳——備戰席↔棋盤、換位；合法格提示、交換預覽、人口與羈絆變化預覽。
  只映射既有 intent，不新增 domain command。（IRH-REQ-008／測試 #7）
- [ ] **T20 HARD**：裝備拖曳與合成——配戴走 `prepare.equip`；合成走
  `recipe_preview()` → `prepare.forge` → `prepare.forge.confirm`，二次確認不得省略。（IRH-REQ-009）
- [ ] **T21 NORMAL/TDD**：鍵盤等價——保留按鈕路徑，新增 `W` 快捷（懸停切換上場／收回）；
  純鍵盤可完成「買棋→上場→配裝→開始戰鬥」。（IRH-REQ-010／測試 #8）

## P5 戰鬥、地圖、獎勵

- [ ] **T22 HARD（阻擋項，先於 T23）**：修「最短可見播放時間／首幀呈現契約」——
  現況 fresh profile 短戰鬥 transcript 在 `RUN_COMBAT` 首個可呈現影格即 exhausted，
  導致戰鬥畫面無法實機截圖（`PROGRESS.md` §已知問題）。未解則 P5 無可信驗收手段。
- [ ] **T23 HARD**：`RUN_COMBAT` 版面重製——與備戰同構骨架；移除硬編絕對座標；
  新增戰鬥期常駐資源列（金幣／等級／遠征 HP，唯讀）；商店與備戰席轉唯讀而非消失。（IRH-REQ-003／對照表末列）
- [ ] **T24 NORMAL**：單位檢視面板（戰鬥）——`inspect_combat_unit()` 接線，
  空狀態不殘留前一單位。（IRH-REQ-014）
- [ ] **T25 NORMAL**：頂部進度列與轉場大字——幕／層／節點、遠征 HP、節點類型非色彩訊號；
  大字提示不阻擋輸入。（IRH-REQ-015／測試 #12）
- [ ] **T26 NORMAL**：`RUN_MAP` 與 `RUN_REWARD` 版面納入同一骨架。（IRH-REQ-003）

## P6 棋盤世界層

- [ ] **T27 HARD**：3/4 投影與反投影——格位↔世界↔螢幕；反投影為投影的精確逆運算；
  結果經 domain 合法性檢查後才採用。（IRH-REQ-007／測試 #6）
- [ ] **T28 HARD**：棋盤與單位 sprite 移入世界層——8×8 方格、玩家半場 `logical_y` 0–3；
  sprite 停在整數像素、相機無非整數平移。（IRH-REQ-007）
- [ ] **T29 NORMAL**：世界空間血條與法力條——投影至螢幕後以固定像素尺寸繪製，
  依 `logical_y` 深度排序，不被特效遮蔽。（IRH-REQ-007／§10.1）
- [ ] **T30 NORMAL**：拖曳層與世界層棋盤整合——拖曳預覽在世界層棋盤上正確對位。（IRH-REQ-008）

## P7 收尾

- [ ] **T31 HARD**：全 gate 與證據收斂——`-Suite All` exit 0、9 組解析度×縮放截圖、
  IRH-REQ-001 至 IRH-REQ-017 逐條對應證據表（含 IRH-REQ-017 既有 gate 不回歸）；
  `PROGRESS.md` 回填。
- [ ] **T32 HARD**：雙審——`reviewer`（opus）＋ codex MCP 第二審；findings closure 落
  `.pipeline/reviews/`。
