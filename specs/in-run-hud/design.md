# G2 in-run-hud — Design

對應需求：`specs/in-run-hud/requirements.md`（IRH-REQ-001 ~ 017）
上位規格：`docs/game-architecture/07-pixel-presentation-and-ui.md` §10、`HANDOFF.md` §2

## 設計取捨摘要

1. **1920×1080 是「換基準」而非「加縮放層」**：既有 `UiScaleRoot` 的 `fit_scale` 等比嵌入機制
   已能把設計畫布投到任意 16:9 視窗，2560×1440 支援不需新程式碼；本片只換 `REFERENCE_SIZE`
   與所有 reference 空間字面值。UI 縮放（100/125/150）的「回流」語意保持不動。
2. **不採用 TFT 的字級階梯**：TFT 在 2560 下 body 20／24，換算 1920 僅 15／18，對繁體中文與
   像素風格過小。沿用本專案既有 type scale ×1.5（title 48／heading 36／body 27／auxiliary 24），
   以滿足 §10.5 CJK 可讀性與 REQ-UX-003 的 150% 縮放不截斷。
3. **座標不照抄，比例才照抄**：TFT 是 7×8 六角格、9 格橫向 bench、PVP 對手名牌；本專案是
   8×8 方格、9 格 bench、單人 PVE 遠征 HP。`layout-reference-1920.json` 提供 TFT 座標的
   1920 換算值作為**比例參考**，實際模組尺寸以本節的區域幾何為準。

---

## 1. TFT 模組 → 本專案對照表

| # | TFT 模組 | 本專案對應 | 資料入口 | 狀態 |
|---|---|---|---|---|
| 1 | `round-tracker` 回合追蹤列 | 幕／層／節點進度列 | `RunViewState.act_index`、`MapNodeState.layer_index`、`MapState.completed_node_ids` | 語意改寫：本專案無 round |
| 2 | `perf-hud` 效能資訊 | — | — | 僅 debug 覆蓋層，不進正式介面 |
| 3 | `top-right-actions` 右上功能鍵 | 系統選單鍵 | 新增 | 新建（IRH-REQ-004） |
| 4 | `side-tools` 右側工具鍵 | 敵情／Boss 階段 | `RunCombatIntelModel.enemy_rows()` / `boss_phase_rows()` | 資料有，UI 新建 |
| 5 | `item-bench` 物品欄 | 裝備庫 | `InventoryViewModel.inventory_items()` / `overflow_items()` | 有 |
| 6 | `trait-list` 羈絆列 | 羈絆列 | `TraitPreviewViewModel.trait_snapshots()` → `TraitBattleSnapshot.tier` | **資料有、正式局內未接線** |
| 7 | `trait-tooltip` 羈絆詳情 | 羈絆詳情浮層 | 同上＋`member_instance_ids` | 新建 |
| 8 | `board-grid` 7×8 六角 | 棋盤 **8×8 方格**，玩家半場 `logical_y` 0–3 | `BoardValidationReport`、`BoardPreparationValidator` | 移至世界層（IRH-REQ-007） |
| 9 | `unit-bench` 備戰席 | 備戰席（容量 **9**） | `RosterState.bench_unit_instance_ids`、`BenchCompactor` | 有 |
| 10 | `unit-healthbar` 世界空間血條 | 單位血條／法力條 | 戰鬥期 `CombatUnitInspectionSnapshot.stats` | 新建（隨棋盤入世界層） |
| 11 | `player-nameplate` 玩家名牌 | **遠征 HP** | `RunViewState.expedition_hp` | 語意改：單人 PVE 無對手名牌 |
| 12 | `little-legend` 小小英雄 | — | — | 不做 |
| 13 | `round-banner` 大字提示 | 幕／節點轉場提示 | `RunViewState.act_index`、`MapNodeState.node_kind` | 新建 |
| 14 | `unit-inspector` 單位檢視 | 單位檢視面板 | 戰鬥：`RunPresentationSession.inspect_combat_unit()`；備戰：**IRH-REQ-016 新 API** | 備戰缺，需前置任務 |
| 15 | `level-panel` 等級經驗 | 等級與經驗 | `EconomyState.level/xp`＋`EconomyConfigRule.xp_thresholds` | 有 |
| 16 | `shop-odds` 商店機率 | 費用機率列 | `EconomyConfigRule.shop_odds_by_level` | 資料有、UI 缺 |
| 17 | `buy-xp-button` 購買 XP | 購買 XP | `BuyXpCommand`＋`ShopService.quote_buy_xp()` | 有 |
| 18 | `reroll-button` 刷新 | 刷新商店 | `RefreshShopCommand`＋`ShopService.quote_refresh()` | 有 |
| 19 | `gold-display` 金幣 | 金幣 | `EconomyState.gold` | 有 |
| 20 | `shop-cards` 商店卡 ×5 | 商店卡 | `EconomyState.shop_offers`、`ShopOffer` | 有 |
| 21 | `shop-lock` 商店鎖定 | — | — | **剔除**：與 `SHOP_LEAK` 不變式衝突 |
| 22 | `streak-indicator` 連勝指示 | 連勝／連敗 | `EconomyState.win_streak` / `loss_streak` | 有 |
| 23 | `fight-button` 戰鬥按鈕 | 開始戰鬥 | `prepare.start` | 有 |
| 24 | `augment-slots` 強化符文槽 | 遺物槽 | `RelicSlotViewModel.active_slots()` | 有（不新增選卡輪） |
| — | （TFT 無，本專案缺口） | **戰鬥期常駐資源列** | `RunPresentationSnapshot.economy` | 新建：戰鬥目前不顯示金幣／等級／遠征 HP |

---

## 2. 版面骨架幾何（1920×1080 reference 空間）

沿用 `ProductionLayoutShell` 的七區模型，常數為既有值 ×1.5：

| 常數 | 1280 基準（現況） | 1920 基準（本片） |
|---|---|---|
| `REFERENCE_SIZE` | 1280 × 720 | **1920 × 1080** |
| `SAFE_MARGIN` | 24 | 36 |
| `GUTTER` | 16 | 24 |
| `TOP_HEIGHT` | 84 | 126 |
| `BOTTOM_HEIGHT` | 136 | 204 |
| `PREPARE_BOTTOM_HEIGHT` | 140 | 210 |
| `SIDE_WIDTH` | 280 | 420 |
| `STATUS_HEIGHT` | 44 | 66 |
| `STATUS_GUTTER` | 8 | 12 |
| `PANEL_CONTENT_MARGIN` | (16, 12) | (24, 18) |
| `TITLE_INSET` / `TITLE_WIDTH` | 8 / 300 | 12 / 450 |

Type scale（`ExpeditionThemeRuntime.TOKEN_SIZES`）與 spacing token 同步 ×1.5：
title 32→48、heading 24→36、body 18→27、auxiliary 16→24；
`min_button_height` 48→72、`safe_margin` 24→36、`gutter` 16→24。

### 區域內的模組編制

| 區域 | RUN_PREPARE | RUN_COMBAT |
|---|---|---|
| top | 幕／層／節點進度列（置中）、遠征 HP（左）、系統選單鍵（右） | 同左，另加戰鬥計時與播放速度 |
| left | 羈絆列（上）＋裝備庫（下） | 羈絆列（唯讀）＋遺物槽 |
| center | 棋盤（世界層）＋備戰席 | 棋盤（世界層），備戰席淡出為唯讀 |
| right | 單位檢視面板 | 單位檢視面板＋敵情摘要 |
| bottom | 等級經驗／機率／金幣／連勝＋商店卡列＋刷新／購買 XP＋開始戰鬥 | 常駐資源列（唯讀）＋暫停／倍速 |
| overlay | 系統選單、羈絆詳情浮層、拖曳預覽層、節點選擇 overlay | 同左 |
| status | 既有狀態列 | 既有狀態列 |

> 商店與備戰席在 `RUN_COMBAT` 轉為唯讀而非消失，使兩個 route 的版面骨架維持同構，
> 玩家視線不需重新定位（對應參考素材中規劃期與戰鬥期共用 HUD 的體驗）。

---

## 3. 世界層解析度取捨（**交 Codex 在 plan 階段裁決並回報**）

使用者已同意「必要時可重新生成素材」，故兩案皆可行。決策關鍵是整數縮放。

| 項目 | A：維持 640×360 | B：提升 960×540 |
|---|---|---|
| 1920×1080 下縮放 | 3× **整數** | 2× **整數** |
| 2560×1440 下縮放 | 4× **整數** | **2.667× 非整數** |
| §10.1「相機不得使用造成半像素取樣的縮放」 | 兩解析度皆滿足 | **2K 下違反** |
| 既有資產 | 44 組 sprite sheet（各 240 frames）、44 portraits、88 icons **全數有效** | **全數需重生成**並重跑 content-production 驗收 |
| 棋盤每格可用像素（8×8 佔中央區） | 約 50×32 | 約 75×48 |
| 單位 sprite 尺寸 | 約 32×32 | 約 48×48 |

**本規格的建議是 A（維持 640×360）**：B 案在 2560×1440 下是 2.667 倍非整數縮放，
與需求要求支援的 2K 直接衝突，且需重跑全部 44 單位的產線。
若 Codex 認為 B 案的細節增益值得，必須在 plan 中提出 2K 下避免半像素取樣的具體作法
（例如世界層改以 1280×720 渲染再降採樣），並將資產重生成列為獨立前置批次。

---

## 4. 系統選單設計（IRH-REQ-004 ~ 006）

### 輸入註冊

`project.godot` 新增 `[input]` 段宣告自訂 action（建議 `system_menu`，綁 `KEY_ESCAPE`）。
**不沿用 `ui_cancel`**：Godot 控制項用它關閉 popup／取消 `LineEdit` 編輯，直接沿用會使
「關閉下拉選單」同時開啟系統選單。

優先序（`_unhandled_input` 處理，由高至低）：

1. 既有 modal（`_PRESENTATION_CONFIRMATIONS`）開啟中 → ESC 關閉該 modal，不開系統選單。
2. 系統選單已開啟 → ESC 關閉系統選單（等同「繼續遊戲」）。
3. 其他情況 → 開啟系統選單。

### 狀態機

```
CLOSED --ESC--> ROOT --ESC/繼續遊戲--> CLOSED
                 |
                 +--設定--> SETTINGS_EMBEDDED --返回--> ROOT
                 +--返回主選單--> CONFIRM_MENU --確認--> (既有 run.menu 流程)
                 +--離開遊戲--> CONFIRM_EXIT --確認--> (既有 menu.exit 流程)
```

- 掛載點：`ProductionLayoutShell.REGION_OVERLAY`（已是全 rect 控制區）。
- 焦點陷阱：開啟時記錄前一焦點節點，關閉後還原；期間底層控制項 `focus_mode` 暫時停用。
- 設定內嵌：複用 `settings_screen_composition.gd`，但需將其自 `SETTINGS` route 解耦
  （目前由 route 驅動 compose）。抽出可被 overlay 宿主呼叫的組裝入口，
  `SETTINGS` route 與 overlay 共用同一份實作，避免兩套設定 UI 分歧。

### 播放暫停還原（IRH-REQ-005）

```
開啟：previous_paused = session.is_paused(); session.set_playback_paused(true)
關閉：session.set_playback_paused(previous_paused)
```

不得無條件 `set_playback_paused(false)`——玩家原本手動暫停時，關閉選單不該替他恢復播放。

### 動作清單變更

`production_screen.gd:_required_action_ids()` 的四個局內 route 移除 `run.menu`：

| route | 變更後 |
|---|---|
| `RUN_PREPARE` | 移除 `run.menu`（其餘 19 項不變） |
| `RUN_COMBAT` | `combat.pause`、`combat.inspect`、`combat.speed` |
| `RUN_MAP` | `map.select`、`map.confirm`、`choice.ack` |
| `RUN_REWARD` | `reward.select`、`reward.confirm`、`choice.ack` |

`presentation/accessibility/keyboard_focus_graph.gd` 的 `_PRIMARY_ACTIONS` 必須同步，
否則 focus graph 靜態 gate 會紅。

---

## 5. 棋盤世界層投影（IRH-REQ-007）

- **權威分工**：格位（`logical_x`, `logical_y`）的合法性、佔用與人口由 domain 持有；
  presentation 只做「格位 ↔ 世界座標 ↔ 螢幕座標」轉換與命中測試。投影不得回寫 domain。
- **投影**：3/4 斜角投影，格位到世界座標為固定線性映射（無透視除法），
  確保 sprite 落在整數像素、相機不做非整數平移。
- **命中測試**：螢幕座標 → 世界座標（沿用 `WindowCoordinateMapper`）→ 反投影求格位。
  反投影必須是投影的精確逆運算，且結果需經 domain 合法性檢查後才採用。
- **繪製順序**：同格內 UI 疊層在 sprite 之上；多單位重疊時依 `logical_y` 深度排序
  （沿用 §10.1「特效不得遮蔽血條或選取狀態」）。
- **血條**：世界空間投影至螢幕後以**固定像素尺寸**繪製（不隨相機縮放），置於 UI 層。

---

## 6. 拖曳資料流（IRH-REQ-008 ~ 010）

Godot 拖放三函式（`_get_drag_data` / `_can_drop_data` / `_drop_data`）為全新實作，
但**不得新增 domain command**——拖曳只是既有意圖的另一條輸入路徑：

| 拖曳 | 來源 → 目標 | 映射到既有路徑 |
|---|---|---|
| 棋子上場 | 備戰席 → 棋盤格 | `move_selected_to_board()` → `commit_board_draft()` → `CommitBoardLayoutCommand` |
| 棋子收回 | 棋盤格 → 備戰席 | `move_selected_to_bench()` → 同上 |
| 棋子換位 | 棋盤格 → 已佔用格 | 交換後 `commit_board_draft()` |
| 裝備配戴 | 裝備庫 → 棋子（**限完整裝備**） | `prepare.equip` |
| 裝備合成 | 零件 → 零件（**裝備庫內**） | `ForgeViewModel.recipe_preview()` → `prepare.forge` → `prepare.forge.confirm`（二次確認不得省略） |

> **合成語意勘誤（2026-08-12）**：本專案的零件（component）**結構上不可裝備**——
> `forge_equipment_command.gd` 檔頭明載 components are never directly equippable、
> `EquipItemCommand` 拒收零件，合成的唯一路徑是 inventory 內兩個 component instance。
> 因此 TFT 式「拖零件到已持零件的棋子上合成」在本專案不存在；
> 合成拖曳＝裝備庫內零件對零件，拖到棋子上的只會是完整裝備（配戴）。
> 早前批次指示中「懸停在已持有裝備的棋子上顯示配方預覽」為誤述，以本節為準。

- 拖曳層使用 `REGION_OVERLAY`（L3 等價），棋子與裝備共用同一 drag layer。
- 拖曳中的預覽（合法格、交換箭頭、人口與羈絆變化）一律由既有 ViewModel 計算，
  不在拖曳層複製規則。
- **鍵盤等價**：既有「選取＋移動按鈕」保留；新增 `W` 快捷（懸停棋子時切換上場／收回），
  三條路徑最終都收斂到同一個 `commit_board_draft()`。

---

## 7. 前置 domain 任務介面草案（IRH-REQ-016，Claude 執行）

目的：讓備戰期的單位檢視面板能顯示「星級＋裝備加成後的有效屬性」，
且與戰鬥使用同一公式（§10.3 禁止在 tooltip 複製公式）。

- 現況：`CombatUnitInspectionSnapshot` 只在 `RUN_COMBAT` 由 transcript 提供；
  `BattleUnitStatsRule`（`domain/battle/catalog/battle_unit_stats_rule.gd`）是戰鬥期規則，
  無 presentation 可用的備戰期入口。
- 設計方向：於備戰資料流新增唯讀查詢，輸入為單位 instance id 與 pinned catalog generation，
  輸出為具名型別（非 `Dictionary`，遵守 CLAUDE.md 架構約定），內部走
  `BattleRuleCatalogBuilder` 既有的星級與裝備疊算路徑。
- 不變式：唯讀、不改 canonical 狀態、不新增 RNG draw、不改 save schema、不新增 Autoload。
- 驗收（AC 對應 IRH-REQ-016）：預覽逐欄位等於 `BattleSetupSourceCompiler.compile()` 產出的
  `UnitBattleSnapshot`，亦即 `BattleSimulation` 初始化寫進 `BattleEntityState` 的
  `base_*` 與 `max_health`。棋盤與板凳單位都必須可查。

**實作結果（T01 已完成）**：

- `BattleSetupSourceCompiler.try_compile_unit_stats(instance, catalog) -> UnitStatsPreviewSnapshot`
  ——與 `compile()` 共用 `_apply_stats` 與 `_find_scaling`，不需 `BoardPlacementState`，
  板凳單位同樣適用。
- `UnitStatsPreviewSnapshot`（`domain/battle/`）——具名型別，欄位與 `UnitBattleSnapshot`
  的屬性段一對一，另帶 `equipment_instance_ids` 供面板列出來源。
- `UnitStatsPreviewViewModel`（`presentation/viewmodels/`）——與 `TraitPreviewViewModel`
  同構：`stats_for(instance_id)` 與 `all_stats()`，catalog 持 deep clone，每次讀取重新
  向 `RunController.roster_snapshot()` 取值。
- **範圍界線**：裝備、羈絆與遺物在實戰是經 effect 解算成 `BattleTimedState` 後由
  `BattleCombatMath` 疊加的；預覽不重現 effect 解算，只回報配戴中的來源 id。
  「備戰屬性＝戰鬥首 tick 屬性」不是判準——`battle_start` 效果會在首 tick 前生效。
- 附帶查證：`BattleEquipmentRule.stat_modifiers` 目前**沒有任何模擬消費者**
  （只有 catalog builder 填值與測試 fixture 使用）；裝備在實戰的屬性貢獻只走 `effect_ids`。

**Codex 相依處理**：此 API 到位前，`RUN_PREPARE` 的單位檢視面板以降級呈現
（名稱、費用、星級、羈絆、裝備槽可正常顯示；屬性格顯示明確的「尚未可用」狀態），
不得以呈現層自行計算的數值填充。

---

## 8. 測試策略

| # | 對應需求 | 測試 | 層級 |
|---|---|---|---|
| 1 | IRH-REQ-001 | reference size 為 1920×1080；`presentation/` 無直接 `custom_minimum_size` 賦值 | 靜態 gate |
| 2 | IRH-REQ-001、IRH-REQ-002、IRH-REQ-003 | 3 解析度 × 3 UI 縮放共 9 組幾何稽核：必要操作可見可點、無重疊、無裁切；四個局內 route 共用同一骨架與元件 | 整合（幾何稽核） |
| 3 | IRH-REQ-004 | ESC 開關、focus trap、`_required_action_ids()` 四 route 無 `run.menu`、focus graph 同步 | 整合 |
| 4 | IRH-REQ-005 | 原本未暫停→開關選單後恢復播放；原本已暫停→開關後維持暫停；canonical 摘要不變 | 整合＋決定性 |
| 5 | IRH-REQ-006 | modal 開啟時 ESC 只關 modal；文字輸入時不誤觸 | 整合 |
| 6 | IRH-REQ-007 | 格位↔螢幕反投影為精確逆運算；命中結果與 domain 格位一致 | 單元 |
| 7 | IRH-REQ-008、IRH-REQ-009 | 拖曳路徑與按鈕路徑產生相同 `RunState`（同佈局雙路徑等價） | 整合 |
| 8 | IRH-REQ-010 | 純鍵盤完成「買棋→上場→配裝→開始戰鬥」；`W` 快捷切換正確 | 整合 |
| 9 | IRH-REQ-011、IRH-REQ-012 | 成本一律來自 `ShopService.quote_*`；9 級 XP 停用；停用原因為具名 `source_code`；商店卡費用等級有非色彩訊號 | 整合 |
| 10 | IRH-REQ-013 | 羈絆階級接線正確；非色彩訊號存在；浮層邊緣翻轉不出安全區 | 整合 |
| 11 | IRH-REQ-014、IRH-REQ-016 | 備戰預覽逐欄位＝`compile()` 的 `UnitBattleSnapshot`；板凳單位可查；空狀態不殘留前一單位 | 單元＋整合 |
| 12 | IRH-REQ-015 | 幕／層／節點進度與 domain 一致；轉場提示不阻擋輸入 | 整合 |
| 13 | IRH-REQ-017 | `-Suite All` exit 0；呈現層不觸碰 gameplay RNG stream | 全 gate |

### 已知阻擋（P3 開工前必須先解）

`PROGRESS.md` §已知問題記載：**fresh profile 的短戰鬥 transcript 會在 `RUN_COMBAT`
第一個可呈現影格即 exhausted**，Phase A 以 10 ms 間隔擷取 80 幀仍拿不到可見戰鬥畫面。
這使戰鬥 HUD 無法以實機截圖驗收。P3（戰鬥 HUD）開工前必須先建立
「最短可見播放時間／首幀呈現契約」，否則該階段沒有可信驗收手段。
