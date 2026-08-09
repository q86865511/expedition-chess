# Codex plan mode prompt — `in-run-hud` 局內 HUD 重製

> 用法：在 repo 根目錄 `E:\ClaudeWorkingPlace\Game`、分支 `codex/g2-ui-art-refresh-b` 啟動 Codex，
> 進 plan mode 後把下列「--- PROMPT 開始 ---」到「--- PROMPT 結束 ---」之間的內容整段貼入。

--- PROMPT 開始 ---

你要為遠征棋（Godot 4.7 + GDScript，PVE 自走棋 Roguelite）重製**局內介面**。
規格已寫好並經使用者核可，你的工作是先產出實作計畫，不要直接動手改程式。

## 先讀這些（依序，全部都要讀）

1. `specs/in-run-hud/requirements.md` — 17 條需求與逐條驗收條件（IRH-REQ-001 ~ 017）
2. `specs/in-run-hud/design.md` — 技術設計：TFT 模組對照表、1920 空間骨架幾何、
   系統選單狀態機、世界層棋盤投影、拖曳資料流、測試策略
3. `specs/in-run-hud/tasks.md` — P0 ~ P7 共 33 項任務（T00 ~ T32）
4. `specs/in-run-hud/layout-reference-1920.json` — 版面資料（25 模組、5 剔除模組、1 待裁決項）
5. `docs/game-architecture/07-pixel-presentation-and-ui.md` — 第 10 章，含新增的 §10.7 系統選單與 REQ-UX-006
6. `HANDOFF.md` §0（本片接手點）與 §2（Presentation 消費契約七條＋本片追加約束）

## 硬邊界（違反即審查退回）

- **只有 `T01` 可以碰 `domain/`，而 `T01` 不是你的任務**——它由 Claude 執行。
  你的所有改動限於 `presentation/`、`scenes/`、`theme/`、`assets/`、`tools/`、`project.godot`、`tests/`。
- Autoload 維持既有五個（`ContentRegistry`、`SaveService`、`SettingsService`、`AudioService`、`SceneRouter`），不新增。
- 寫操作一律經既有 `RunController` command；**拖曳只是新的輸入路徑，不得新增或修改任何 domain command**。
- 只持 clone／snapshot，不保留 domain 可變引用；不逐幀輪詢 ViewModel（每次讀取都是 deep-clone）。
- 不得使用 Godot `rand*`／時間／Object ID 產生 gameplay entropy；純視覺抖動可用本地亂數但不得回寫 domain。
- 不得讀 latest catalog，一律用 pinned generation。
- 拒絕原因讀 `error.diagnostic_values["source_code"]`，不是頂層 `CommandError.code`（後者一律 `APPLY_FAILED`）。
- 呈現層不得複製任何 domain 公式——成本走 `ShopService.quote_*`，屬性走 ViewModel，
  羈絆走 `TraitPreviewViewModel`。
- 玩家可見文字一律用 localization key，不得硬編碼；`zh_TW` 與 `en` 必須同 key 集合。

## 這次要做什麼（摘要，細節以規格為準）

1. **基準遷移**：UI 設計畫布 1280×720 → **1920×1080**，支援 1280×720 與 2560×1440。
   既有尺寸字面值（14 處 `ExpeditionLayoutMetrics` 呼叫 ＋ `presentation/` 下 24 處殘留
   `custom_minimum_size` 直接賦值）全數換算，完成後 `presentation/` 不得殘留直接賦值。
2. **局內四個 route 全面重製**：`RUN_PREPARE`、`RUN_COMBAT`、`RUN_MAP`、`RUN_REWARD`
   共用同一版面骨架與同一套 HUD 元件。目前 `RUN_COMBAT` 是硬編絕對座標的開發灰盒，等同全新開發。
3. **ESC 系統選單**：繼續遊戲／設定／返回主選單／離開遊戲。設定必須**內嵌覆蓋層**不跳離 route；
   `RUN_COMBAT` 開啟時暫停播放並在關閉時**還原開啟前的暫停狀態**（不得代玩家恢復播放）；
   `run.menu` 自四個局內 route 的常駐動作列移除。**觸發鍵須註冊專屬 InputMap action，
   不得沿用 `ui_cancel`**（後者被控制項用於關閉 popup／取消編輯）。
4. **棋盤移至世界層**：棋盤與單位改由世界層 `SubViewport` 以像素 sprite ＋ 3/4 投影渲染，
   UI 層只疊血條、選取框與拖曳預覽。棋盤邏輯維持 domain 既有的 **8×8 方格、玩家半場
   `logical_y` 0–3**，不得改為參考素材的 7×8 六角格。
5. **拖曳**：棋子（棋盤↔備戰席↔換位）與裝備（配戴、合成）皆可拖曳；
   合成沿用一次確認不得省略；所有拖曳都要有鍵盤等價路徑，並新增懸停＋`W` 快速上場／收回。
6. **接線既有但未用的資料**：羈絆列目前是空 Label（`TraitPreviewViewModel` 已存在）、
   商店費用機率 UI 缺（`EconomyConfigRule.shop_odds_by_level` 已有資料）、
   戰鬥畫面完全不顯示金幣／等級／遠征 HP（`RunPresentationSnapshot.economy` 已有）。

## 你必須在 plan 裡回答的三件事

1. **世界層解析度裁決**：維持 640×360 或提升 960×540。
   規格建議 640×360，理由是它在 1920×1080 為 3×、在 2560×1440 為 4×，兩者皆整數倍；
   而 960×540 在 2560×1440 是 2.667× 非整數縮放，與 §10.1「相機不得使用造成半像素取樣的縮放」
   衝突，且需重生成 44 組 sprite sheet（各 240 frames）、44 portraits 與 88 icons。
   若你選 960×540，必須同時提出 2K 下避免半像素取樣的具體作法，並把資產重生成列為獨立前置批次。
2. **棋盤投影參數**：格位到世界座標的映射、單位 sprite 尺寸、深度排序規則、
   以及螢幕座標反投影如何保證是投影的精確逆運算。
3. **拖曳與既有按鈕路徑如何並存**：兩條路徑必須收斂到同一個 `commit_board_draft()`，
   且既有鍵盤焦點圖（`presentation/accessibility/keyboard_focus_graph.gd` 的 `_PRIMARY_ACTIONS`）
   要如何同步——這個檔沒同步會讓 focus graph 靜態 gate 直接紅。

## 相依與阻擋

- **`T01` 備戰期單位屬性預覽 API 由 Claude 提供，尚未到位。** 在它到位前，
  `RUN_PREPARE` 的單位檢視面板屬性格顯示明確的「尚未可用」狀態，
  **不得以呈現層自行計算的數值填充**。面板其餘欄位（名稱、費用、星級、羈絆、裝備槽）照常實作。
- **`T22` 必須先於 `T23`**：目前 fresh profile 的短戰鬥 transcript 會在 `RUN_COMBAT`
  第一個可呈現影格即 exhausted，導致戰鬥畫面拿不到實機截圖（80 幀擷取仍全空）。
  這使戰鬥 HUD 沒有可信驗收手段，必須先建立「最短可見播放時間／首幀呈現契約」。

## 驗收與證據

- 每階段結束跑並貼出實際輸出：
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite All`，必須 exit 0。
- 視覺任務附實機截圖：`tools/run-isolated-ui-evidence.ps1`，
  尺寸 1280×720／1920×1080／**2560×1440**（`T07` 需先為此腳本加上 2560×1440 選項）
  × UI 縮放 100／125／150，共九組。
- 證據落 `specs/in-run-hud/evidence/<phase>/`；暫存檔不要落在專案根目錄。
- 靜態 gate 會擋：硬編碼玩家文字、loc parity、asset refs、focus graph、
  viewport／filter／theme token；這些不得因本片回歸。

## 產出格式

給我一份實作計畫，包含：

1. 三個待裁決事項的結論與理由（世界層解析度、投影參數、拖曳與按鈕並存）。
2. 任務排序與相依圖——`tasks.md` 的 T00~T32 你打算怎麼分批，哪些可並行。
3. 每批的驗收方式與證據產出點。
4. 你認為規格有問題、缺漏或自相矛盾的地方（有就直說，不要硬做；這比照單全收有價值）。

先不要改任何檔案。

--- PROMPT 結束 ---

## 給使用者的備註

- 若 Codex 回報「規格有問題」，優先看它是否踩到本專案 domain 不變式——
  參考素材是 PVP 遊戲，本專案是單人 PVE，概念不對應的地方規格已列在
  `layout-reference-1920.json` 的 `removedModules`。
- Codex 若要求改 `domain/`，除 `T01` 外一律先回主對話裁決，不要直接放行。
