# G2 in-run-hud — Requirements

狀態：APPROVED FOR IMPLEMENTATION（依使用者 2026-08-09 裁決）

實作交付對象：**Codex**。前置 domain 任務（IRH-REQ-016）由 Claude 執行。

## 背景

參考素材為聯盟戰旗（TFT）對局主介面的逆向拆解規格（2560×1440 座標系）。本片以其
**版面比例與模組編制**為依據，重製遠征棋的局內介面；不照抄其遊戲概念，凡本專案 domain
沒有對應語意的模組一律剔除（見「明列不做」）。

## 範圍

- 本片擁有新增的 `REQ-UX-006`，並重證 `AC-028`、`AC-029`；新增 `AC-080`、`AC-081`、`AC-082`。
- 涵蓋局內四個 route 的完整版面重製：`RUN_PREPARE`、`RUN_COMBAT`、`RUN_MAP`、`RUN_REWARD`。
- 涵蓋全域基準解析度自 1280×720 遷移至 1920×1080，並支援 2560×1440。
- 依使用者 2026-08-09 裁決：**`ui-art-refresh` Phase B1R3 的視覺樣板不再作為基線**，
  局內畫面直接以新基準重新設計，B1R3 的視覺核可閘門對本片不生效。
- 局外畫面（`MENU_MAIN`、`CAMP_WORLD`、設施、`COLLECTION`、`SETTINGS`、`RESULTS`）
  在本片**只做基準遷移的機械調整**（維持可用、不裁切、gate 不紅），正式視覺重設計不在本片。

### 明列不做

- **商店鎖定（TFT `shop-lock`）**：本專案 `domain/run/economy/node_entry_service.gd:44-45`
  將「進入節點時 `shop_offers` 非空」判為 `SHOP_LEAK` 錯誤，商店由
  `try_release_shop_offers()` 在結算與離節點時強制清空。跨回合鎖定商店在本專案沒有對應語意，
  且實作將破壞既有不變式與 `reserved_copies` 帳務。剔除，不做前置 domain 任務。
- **小小英雄（`little-legend`）、對手名牌、偵察其他玩家、連勝計數以外的 PVP 模組**：
  本專案是單人 PVE，無對應概念。
- **效能 HUD（`perf-hud`）**：僅允許以 debug build 覆蓋層存在，不進正式介面。
- **強化符文選擇輪（`augment` 選卡輪）**：本專案以遺物（relic）與獎勵節點承擔該角色，
  沿用既有 `RUN_REWARD` 流程，不新增選卡輪。
- 任何 domain 規則、數值、codec、save schema、RNG stream 集合的變更（IRH-REQ-016 除外，
  且該項為唯讀查詢，不改 canonical 狀態）。
- 美術資產的重新生成（若 IRH-REQ-004 的世界層解析度裁決為提升，則另立 content-production 批次）。

---

## IRH-REQ

### 基準與骨架

- **IRH-REQ-001 基準解析度遷移**：UI 設計畫布必須自 1280×720 改為 **1920×1080**。
  `UiScaleRoot.REFERENCE_SIZE`、`ProductionLayoutShell.REFERENCE_SIZE` 與
  `project.godot` 的 `window/size/viewport_*` 必須一致為 1920×1080。
  既有以 reference 空間登記的尺寸字面值（`ExpeditionLayoutMetrics.set_min` 系列 14 處
  ＋ `presentation/` 下 24 處殘留 `custom_minimum_size`）必須全數換算，不得留下混用兩套基準的值。
  - 驗收：1280×720、1920×1080、2560×1440 三種視窗尺寸下，畫面等比嵌入無裁切、無黑條偏移；
    2560×1440 為 1920×1080 的 1.3333 倍等比，不得出現獨立分支邏輯。
  - 驗收：`presentation/` 下不存在任何直接寫 `custom_minimum_size = Vector2(...)` 的呼叫；
    尺寸一律經 `ExpeditionLayoutMetrics`。

- **IRH-REQ-002 UI 縮放語意不變**：UI 縮放 100/125/150 必須維持既有「回流 token」語意——
  放大控制項高度、字級與內距，而非縮放整棵樹。骨架寬度維持 reference 值。
  - 驗收：三種縮放 × 三種解析度共 9 組組合，必要操作（開始戰鬥、系統選單、刷新、購買 XP）
    全部可見且可點擊，文字不重疊。

- **IRH-REQ-003 局內共用版面骨架**：四個局內 route 必須共用同一版面骨架與同一套 HUD 元件，
  區塊編制依 `design.md` 的 1920 空間座標表：頂部進度列、左側羈絆／裝備欄、中央棋盤區、
  右側單位檢視面板、底部經濟與商店帶。
  - 驗收：同一模組（例：金幣顯示、羈絆列）在四個 route 只有一份實作，不得各 route 各寫一套。
  - 驗收：`RUN_COMBAT` 不再使用硬編絕對座標建構控制項。

### 系統選單

- **IRH-REQ-004 ESC 系統選單**：局內四 route 必須提供 ESC 開啟的系統選單覆蓋層，
  內容為**繼續遊戲／設定／返回主選單／離開遊戲**四項。
  - 選單必須掛在 `ProductionLayoutShell.REGION_OVERLAY`，層級在既有 modal 之上。
  - ESC 開啟、再按 ESC 或「繼續遊戲」關閉。
  - **設定必須為選單內嵌覆蓋層**，不得跳離當前 route（不走 `SETTINGS` 場景路由）；
    關閉後回到原畫面且局內狀態不變。
  - 「返回主選單」沿用既有 `run.menu` 的二次確認；「離開遊戲」必須二次確認。
  - `run.menu` 必須自局內四 route 的常駐動作列移除，改由本選單提供。
  - 驗收：`_required_action_ids()` 的四個局內 route 不再含 `run.menu`，且
    `keyboard_focus_graph.gd` 的 `_PRIMARY_ACTIONS` 同步更新。
  - 驗收：選單開啟時焦點被限制在選單內（focus trap），Tab 不會跑到底下畫面的控制項。

- **IRH-REQ-005 選單開啟時暫停戰鬥播放**：在 `RUN_COMBAT` 開啟系統選單時必須暫停播放；
  關閉時**還原開啟前的暫停狀態**（若玩家原本已暫停，關閉選單不得自動恢復播放）。
  - 驗收：暫停與恢復不得改變 canonical 戰鬥摘要（沿用 REQ-UX-002／AC-007）。

- **IRH-REQ-006 輸入動作註冊**：ESC 必須以**自訂 InputMap action** 觸發，不得直接沿用
  `ui_cancel`（後者被 Godot 控制項用於關閉 popup／取消編輯，直接沿用會與控制項行為衝突）。
  - 驗收：`project.godot` 新增 `[input]` 段並宣告該 action；在文字輸入或既有 modal 開啟時
    按 ESC 的行為有明確定義且不誤觸系統選單。

### 棋盤與互動

- **IRH-REQ-007 棋盤移至世界層**：棋盤與其上的單位必須改由世界層 `SubViewport` 以像素 sprite
  搭配 3/4 視覺投影渲染；UI 層只疊血條、選取框與拖曳預覽。
  - 棋盤邏輯維持 domain 既有的 **8×8 方格、玩家半場 `logical_y` 0–3**，不得改為 TFT 的 7×8 六角格。
  - 投影只負責「格位 ↔ 畫面座標」轉換，不得進入 domain 模擬（沿用 §10.1）。
  - 驗收：世界空間點擊能正確命中格位，且命中結果與 domain 的格位權威一致；
    相機不得產生半像素取樣，sprite 停在整數像素。

- **IRH-REQ-008 拖曳擺位**：必須支援以拖曳在棋盤與備戰席之間移動棋子。
  - 拖曳中必須顯示合法格提示、佔用格的交換預覽、人口使用與羈絆變化預覽（沿用 §10.3）。
  - 拖曳只得映射到既有意圖（`move_selected_to_board()` / `move_selected_to_bench()` →
    `commit_board_draft()` → `CommitBoardLayoutCommand`），**不得新增或修改 domain command**。
  - 驗收：拖曳完成後的 canonical 結果與既有按鈕路徑完全一致（同一佈局經兩種操作路徑
    產生相同 `RunState`）。

- **IRH-REQ-009 裝備拖曳與合成**：必須支援自裝備庫拖曳**完整裝備**至棋子身上配戴，
  以及在裝備庫內拖曳**零件至零件**觸發合成時的配方預覽與確認。
  （零件結構上不可裝備——`EquipItemCommand` 拒收零件，合成唯一路徑是 inventory 內
  兩個 component instance，見 `forge_equipment_command.gd`；拖零件到棋子上不是合法操作，
  UI 須以非色彩訊號拒絕並說明。）
  - 合成沿用既有 `prepare.forge` / `prepare.forge.confirm` 與 `ForgeViewModel.recipe_preview()`；
    §10.3 要求的「不可逆操作一次確認」必須保留。
  - 驗收：拖曳配戴／合成的結果與既有按鈕路徑一致；overflow 與拆卸行為不變。

- **IRH-REQ-010 鍵盤等價路徑**：所有拖曳操作必須有鍵盤等價路徑，不得只能用滑鼠。
  - 保留既有「選取＋移至棋盤／備戰席」按鈕路徑作為無障礙通道。
  - 新增快捷鍵：游標懸停於棋子時按 **`W`** 在上場與收回之間切換（對應 TFT 慣例）。
  - 驗收：僅用鍵盤可完成「買棋 → 上場 → 配裝 → 開始戰鬥」全程；
    `keyboard_focus_graph.gd` 涵蓋所有新增互動元素（沿用 REQ-UX-003／AC-029）。

### 資訊模組

- **IRH-REQ-011 經濟資訊列**：必須呈現金幣、等級與經驗進度、商店費用機率、連勝／連敗。
  資料一律取自 `EconomyState` 與 `EconomyConfigRule.shop_odds_by_level`，
  成本一律取自 `ShopService.quote_*`，**不得在呈現層複製任何公式**（§10.3 硬規則）。
  - 驗收：等級 9 時經驗條顯示 MAX 且購買 XP 停用；金幣不足時刷新與購買以具名原因停用，
    原因讀自 `error.diagnostic_values["source_code"]`（HANDOFF §2 第 6 條）。

- **IRH-REQ-012 商店帶**：商店必須以卡片列呈現 `EconomyState.shop_offers`，
  每張卡含立繪、羈絆標籤、名稱與費用，邊框依費用著色且**同時以形狀或文字**標示費用等級
  （不得只靠顏色，§10.5）。
  - 驗收：已持有副本數與購買後是否升星必須可見（§10.3）；買空的槽位維持佔位不重排。

- **IRH-REQ-013 羈絆列與詳情浮層**：必須接上 `TraitPreviewViewModel.trait_snapshots()`，
  呈現各羈絆的已啟用數／門檻與階級；hover 顯示詳情浮層（效果條列、當前生效階級高亮、
  成員棋子縮圖與持有標示）。
  - 現況為未接線的空 Label，本片必須實作。
  - 驗收：階級不得只靠顏色區分，需同時有圖示或文字（§10.5）；浮層高度自適應、
    貼近畫面邊緣時自動翻轉且不超出安全區。

- **IRH-REQ-014 單位檢視面板**：右側面板在**備戰與戰鬥兩個 route 都必須可用**。
  - 戰鬥期資料取自 `RunPresentationSession.inspect_combat_unit()`。
  - 備戰期資料取自 IRH-REQ-016 提供的屬性預覽 API。
  - 內容：立繪與星級、羈絆標籤、名稱與費用、生命與法力、技能與定位、裝備槽、屬性格、出售價值。
  - 驗收：出售在 2★ 以上或已配戴裝備時需二次確認；面板未選取單位時為明確空狀態，不得殘留前一單位資料。

- **IRH-REQ-015 進度列與轉場提示**：頂部必須呈現遠征進度。本專案**沒有 TFT 的 round 概念**，
  進度單位為幕（`RunViewState.act_index`）／層（`MapNodeState.layer_index`）／節點；
  必須以節點類型圖示標示已完成、當前與未達節點，並顯示遠征 HP。
  - 節點類型必須以圖示或形狀區分，不得只靠顏色（§10.5）。
  - 進入節點與幕轉換時顯示全螢幕大字提示，該提示不得阻擋輸入。

- **IRH-REQ-016 備戰期單位屬性預覽 API（前置 domain 任務，Claude 執行）**：
  必須提供 presentation 可用的查詢，回傳備戰期單位「套用星級與已配戴裝備後的有效屬性」。
  - 必須複用戰鬥所用的同一公式來源（`domain/battle/catalog/battle_unit_stats_rule.gd` 一系），
    **不得在 presentation 或 tooltip 複製公式**（§10.3 硬規則）。
  - 必須是唯讀查詢，回傳具名型別（非 `Dictionary`），不改變任何 canonical 狀態、
    不新增 RNG draw、不改 save schema。
  - 驗收：同一單位在備戰顯示的屬性，逐欄位等於 `BattleSetupSourceCompiler.compile()`
    產出的 `UnitBattleSnapshot`——亦即 `BattleSimulation` 初始化時寫進 `BattleEntityState`
    的 `base_*` 與 `max_health`（`battle_simulation.gd:182-196` 為逐欄位直接賦值）。
    棋盤與板凳單位都必須可查（`compile()` 只收棋盤單位，板凳單位是本 API 的存在理由）。
  - **不納入**：裝備、羈絆與遺物在實戰是經 effect 解算成 `BattleTimedState` 後由
    `BattleCombatMath` 疊加的，其是否生效取決於 effect 的條件與觸發時機。預覽不得重現
    effect 解算（§10.3 禁止在呈現層複製公式），改以「配戴中的來源清單」呈現。
    因此「備戰屬性＝戰鬥首 tick 屬性」不是本片的驗收判準——`battle_start` 觸發的效果
    會在首個 tick 前生效，該判準對帶此類效果的單位必然不成立。

### 不回歸

- **IRH-REQ-017 既有 gate 不回歸**：本片不得使既有靜態 gate 與測試回歸——
  硬編碼玩家文字禁令、localization parity、asset refs、focus graph、
  viewport／filter／theme token 檢查、決定性測試與 soak 全部維持通過。
  - 驗收：`tools/run-tests.ps1 -Suite All` exit 0。
  - 驗收：呈現層不得觸碰 `RngService` 的 gameplay stream；純視覺抖動使用本地亂數。
