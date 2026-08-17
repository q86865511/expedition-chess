# UI／美術／中文化 重新審核報告與修改計畫（交付 Codex）

> 審核日期：2026-08-07。審核方式：主 repo 靜態盤點（presentation／assets／localization 全掃）＋
> **實機執行截圖導覽**（Godot 4.7 Windows，master 工作樹，全新 profile 走
> 主選單→營地→設定→圖鑑→遠征之門→開始遠征→地圖→備戰）。
> 本檔是單一交付文件：第 1〜4 節為審核發現（含證據），第 5 節為分階段修改計畫。
> 執行時遵循 `HANDOFF.md` §2 消費契約與 `docs/game-architecture/07-pixel-presentation-and-ui.md`。

---

## 1. P0 發現：主流程在正式 UI 上實際不可玩（實機驗證）

以下皆為實機重現、非推測。**在修 UI 美術之前必須先修**，否則後續視覺驗收無法進行。

### P0-1 新檔無法經滑鼠啟用「開始遠征」
- 現象：營地畫面選了「指揮官 1」、挑戰等級調到任何值，「開始遠征」永遠停用。
- 根因（已實機驗證）：`presentation/screens/camp_world_screen.gd:82-98` 建立的
  OptionButton 未設 `allow_reselect = true`。Godot 4 預設 current=0（畫面顯示
  「指揮官 1」），重選同一項**不會發出 `item_selected`**，因此
  `_selected_commander_id` 永遠是空字串（`camp_world_screen.gd:18,32`），
  `selected_expedition_request()` 永遠回 null（`:70-76`）。
  只有一位指揮官的新檔玩家無路可走。
- 驗證：審核中暫時加上 `_commander_selector.allow_reselect = true` 後按鈕即啟用、
  可正常開始遠征（該行已還原，未留在工作樹）。
- 建議修法：`allow_reselect = true` 是止血；正解是 compose 時把顯示與內部狀態對齊
  （預設即選 index 0＋challenge 0，讓「開始遠征」開箱即可按）。

### P0-2 挑戰等級 SpinBox 初始 -1、可選未解鎖等級、失敗無原因
- `camp_world_screen.gd:19,33` 初始 `_selected_challenge_level = -1`，但 SpinBox
  顯示 0——顯示與狀態不一致，使用者必須「實際改動一次數值」才算有選。
- max_value = highest+1（`:107-109`）允許選尚未解鎖的等級；實測選 1 按開始，
  只得到「操作未生效（尚未變更，可重試）：操作失敗」——具名錯誤未分流
  （違反 HANDOFF §2 第 6 條：應讀 `error.diagnostic_values["source_code"]`）。

### P0-3 備戰畫面「開始戰鬥」按不到（任何視窗尺寸）
- `RUN_PREPARE` 的動作欄有 18 顆按鈕垂直堆疊
  （`presentation/screens/production_screen.gd:1141-1163`），`prepare.start`
  排第 15。設計高度 720 只裝得下前 10 顆，無 ScrollContainer、滾輪無效、
  視窗最大化（canvas_items stretch）比例不變照樣裁切。
  `service.*`、`prepare.move_*`、**`prepare.start`（開始戰鬥）**、`run.menu`
  全數落在畫面外不可及。
- 這代表備戰畫面在正式 UI 上無法進入戰鬥；也是「動作欄一律單欄堆疊」
  這個佈局模式的極限證明——計畫 Phase B 必須重做。

### P0-4 鍵盤焦點不可見
- 備戰畫面按 Tab 後無任何可見焦點框（spec §10 要求「高亮度粗框帶角缺口」，
  `assets/pilot/palette.json` 亦有 `focus_high` token）。鍵盤救不了 P0-3。

## 2. P1 發現：錯誤呈現與文案縫隙（實機驗證）

| # | 現象 | 證據／根因 |
|---|---|---|
| P1-1 | 設定套用**成功**（語言確實切換）卻同時顯示「設定套用失敗」＋裸 key `error.settings.activation_diagnostic` | 該 key 不在 `localization/catalog.v2.csv`（已 grep 確認）；且成功路徑誤走失敗訊息分支 |
| P1-2 | 地圖「選擇節點」按鈕回報裸 key `error.presentation.run_map_node_selection_unavailable` | 同上，key 不在 catalog；靜態 gate 只驗 zh_TW/en parity，不驗「程式引用的 key 必存在」 |
| P1-3 | 「選擇節點」／「確認前進」語意顛倒：前者報錯，後者才打開節點清單 | 實機重現；按鈕文案與行為需對調或重命名 |
| P1-4 | 設定畫面：標題「設定」與第一列「語言」標籤重疊；每列標籤重複出現兩次（左欄＋控件內）；控件疊在 debug 色塊上 | 實機截圖；`scenes/production/settings.tscn`＋動態組裝的雙重標籤 |
| P1-5 | 先前測試殘留 `settings-v1.json` 的 `locale:"en"` 蓋掉 zh_TW 預設，首開畫面是英文 | 審核中已從遊戲內設定切回 zh_TW。產品面建議：首次啟動以 OS locale 初始化 |

## 3. 視覺現況總盤點（靜態＋實機一致）

**一句話：邏輯層完備，表現層是 0%——所有 production 畫面是灰底＋Godot 預設控件＋文字清單，已核可的 44 組美術資產零引用。**

- 場景空殼：`scenes/production/*.tscn`（17 檔）全部只有
  `Control + Composition + 空 Label`，無 ColorRect 背景、無 TextureRect、無 Panel
  樣式。唯二例外是 collection（裸控件）與 run_combat（無障礙探針，非戰鬥視覺）。
- 世界層：`app/main.tscn:32-47` 兩個純色 ColorRect 點擊靶（青／橘）直接曝光在
  正式畫面每一景；背景是 `presentation/viewport/production_world_surface.gd:24-28`
  `draw_rect` 畫的深藍網格。
- 實機所見：地圖無任何圖形化節點（純文字 ItemList 彈窗）；備戰的棋盤單位是
  純文字「遠征棋士 01」、商店是文字列「遠征棋士 10 · 1」；圖鑑是兩個預設
  ItemList。
- 資產閒置：`assets/production/` 有 44 組 sprite sheet＋SpriteFrames（各 240
  frames）、44 portraits、44×2 icons、camp.png 環境圖、shared atlas（ability／
  combat_vfx／core_ui／status_damage／trait）、音樂 5＋音效 21——
  **`presentation/`、`scenes/`、`app/` 沒有任何一行引用 `res://assets/`**。
  音訊同樣未接（實機全程無聲）。
- 無 Theme：全 repo 沒有 Theme `.tres`；樣式靠散落的 `theme_override_*`。
  已核可色盤 `assets/pilot/palette.json` 在 production 程式中無消費者；
  唯一色彩表是 `run_combat_screen.gd:28-53` 內嵌的 20 個 hex。
- 無內嵌字型：CJK 全靠 `SystemFont`（`presentation/accessibility/localized_typography_policy.gd:9-18`
  依序試 Microsoft JhengHei UI→…）；`assets/pilot/font-contract.json` 自陳
  `bundled_font_asset: null`、headless fallback 缺 zh_TW 必要字符。
- 視覺債樣本：magic size（`run_combat_screen.gd:350,383,433,457`）、
  無 spacing／type scale（dev 場景 separation 24/16/12 各行其是；字級 20/24 與
  18/20/22 兩處各自定義）。

## 4. 中文化現況：底盤已完成，剩四個缺口

**不要重做中文化**——本專案已是「預設繁中」的雙語專案：
`localization/catalog.v2.csv` 880 key×2 語系、`DEFAULT_LOCALE=zh_TW`
（`app/content/localization_catalog.gd:4-5`）、content 694 個 `loc.*` key 100%
覆蓋、production 層零硬編碼文字且有靜態 gate（`tools/presentation_ui_static_gate.gd:32-33`）強制。
實機驗證繁中全畫面渲染正常（系統字型）。

剩餘缺口（納入 Phase D）：
1. **內嵌 CJK 字型缺失**：跨機器／匯出版本有缺字風險，這是離「可發佈繁中版」
   最實質的一步。
2. **程式引用 key 未進 catalog**：至少 P1-1、P1-2 兩個 error key；gate 需加
   「code-referenced key 必存在」檢查。
3. **文案雙來源**：`presentation/accessibility/localization/production_accessibility_localization.gd:27-72`
   內嵌 21 key 雙語表未併入 CSV。
4. **死檔**：`catalog.v2.en.translation`／`catalog.v2.zh_TW.translation` 無人引用
   （runtime 讀 `.csv.raw`），時間戳已落後，應清理或納管。

## 5. 修改計畫（分四階段，建議依序）

> 通則（每階段皆適用）：
> - 遵循 `HANDOFF.md` §2 七條消費契約；正式場景放 `scenes/`、經 SceneRouter。
> - 視覺方向沿用 **T13 已核可樣板**：`assets/pilot/provenance.md` 的三段 prompt、
>   `assets/pilot/palette.json` 十色 token、core-ui 樣板佈局（上資源列／左 roster+商店／
>   右遭遇+羈絆／下行動列、9-slice 面板、nearest-neighbor）。不要重新發明視覺語言。
> - 靜態 gate 會擋：dev reference、硬編碼玩家文字（含英文 text/tooltip/add_item）、
>   loc parity、asset refs、focus graph、viewport/filter/theme tokens
>   （`specs/presentation-ui/tasks.md` T14 清單）。
> - 每階段完成判準一律含：`tools/run-tests.ps1 -Suite All` exit 0＋實機截圖對照
>   本報告對應發現（修一項截一張）。
> - 注意 `specs/presentation-ui/design.md` M9 稽核表已知漂移（45 條 named test 有
>   12 條查無對應），不要把它當可靠清單。

### Phase A｜可玩性止血（P0，小 diff，先行合併）
1. 營地選擇流程重做：compose 即同步顯示與內部狀態（預設選指揮官 0＋挑戰 0，
   「開始遠征」開箱可按）；`allow_reselect = true`；SpinBox 上限限制在已解鎖等級，
   或選了未解鎖等級時給出具名原因。
2. 備戰動作欄重佈局（過渡版）：分組（商店／鍛造裝備／隊伍調整／推進）收進
   子選單或分頁，確保 `prepare.start` 與 `run.menu` 永遠可及；這是 Phase B 正式
   佈局前的最小修正，可與 B 合併做。
3. 錯誤呈現分流：成功路徑不再誤報失敗；失敗訊息顯示 `source_code` 對應文案。
4. 焦點可見：全域 focus StyleBox（可先用簡單粗框，Phase B 換 palette token 版）。
5. 補 P1-1／P1-2 缺 key 進 catalog；「選擇節點／確認前進」語意修正。
- 驗收：新檔可 滑鼠全程 主選單→營地→開始遠征→選節點→備戰→開始戰鬥→結算；
  Tab 焦點肉眼可見；無裸 key。

### Phase B｜Theme 與版面系統（介面樣板落地）

> **狀態更新（2026-08-09，使用者裁決）**：Theme 與內嵌字型（本階段第 1、2 項）保留有效，
> 已於 `codex/g2-ui-art-refresh-b` 落地至 B1R3。**第 3 項「依 core-ui 樣板重排各畫面」的
> B1R3 視覺樣板不再作為基線**——使用者裁決捨棄舊畫面，局內介面改以新基準重新設計，
> B1R3 的視覺核可閘門對局內畫面不再生效。
>
> 局內四個 route（`RUN_PREPARE`／`RUN_COMBAT`／`RUN_MAP`／`RUN_REWARD`）的版面工作
> **改由 `specs/in-run-hud/` 三件套承接**，該片同時把 UI 設計基準自 1280×720 改為
> 1920×1080（支援 2560×1440）、把棋盤移至世界層 3/4 投影、新增 ESC 系統選單與拖曳互動。
> 局外畫面（主選單／營地／設施／圖鑑／設定／結算）在該片只做基準遷移的機械調整，
> 正式視覺重設計仍留在本階段，待局內完成後再排。
>
> 本階段的驗收解析度矩陣同步更新為 1280×720／1920×1080／2560×1440。
> Phase C（美術資產接線）與 Phase D（中文化收尾）不受影響，維持原計畫。
1. 依 `palette.json` 建立單一 Godot Theme `.tres`（named color／StyleBox／
   font size tokens；type scale 與 spacing scale 一次定案），`project.godot`
   掛 `gui/theme/custom`，清除散落的 `theme_override_*` 與內嵌 hex
   （`run_combat_screen.gd:28-53` 色盲模式表改讀 token）。
2. 內嵌 CJK 字型：加入 OFL 授權中文字型（建議 Noto Sans TC；短標題可另配
   像素風 Latin 字型，遵守 spec §10.5「像素字型只用於短標題」），更新
   `font-contract.json` 與 typography policy fallback 鏈。
3. 依 core-ui 樣板重排各畫面：camp／map／prepare／combat／reward／results／
   collection／settings。settings 修 P1-4（單一標籤欄、分區、與探針層分離）。
   移除 `app/main.tscn` debug 色塊靶在正式畫面的可見性（改為不可見命中區或
   正式美術）。
- 驗收：All＋static gate 過；100%/125%/150% 縮放與 720p/1080p/1440p 截圖無裁切
  無重疊；零 `theme_override_*` 散落（探針類除外，列外清單）。

#### 局外畫面批次

- **B-out-1（2026-08-14 使用者核可）**：`MENU_MAIN` key art 直疊操作按鈕與
  `CAMP_WORLD` 主環境／場景設施標記；18 張解析度×UI scale 證據與 All exit 0。
- **B-out-2（2026-08-17 使用者核可，含圖鑑換行修訂）**：五設施已進
  `ProductionLayoutShell` 的 per-route 分支；production portraits 已接圖鑑 content
  cards，並保留搜尋／比較／focus／節點契約。54 張解析度×UI scale 證據逐張檢視、
  `issues=[]`，fresh All exit 0。核可後另補 6 張 UI 125%／150% 圖鑑證據；190
  reference px 卡寬讓一張指揮官資料卡與三張 portrait 卡在高縮放仍維持同列，6/6、
  `issues=[]`，定向契約 5/5、83 assertions。
  - `CAMP_WORLD` 中央裝飾 surface 已收斂，由環境圖框獨佔單一可見框線。
  - 底部帶左半用途定案為目前 focus／hover 設施名稱的情境提示，沿用既有 loc。
  - 指定修訂完成並提交後，依使用者裁決開始 B-out-3。

### Phase C｜美術資產接線（讓 44 組資產上場）
1. 單位視覺：棋盤與備戰用 SpriteFrames（idle/walk/attack 動畫）、商店卡與圖鑑
   用 portrait＋icon；星級／費用以形狀符號輔助（palette 三硬規則）。
2. 場景背景：營地用 `assets/production/environment/camp.png`；地圖／戰鬥背景
   需新產（依 T13 anchors 走 content-production 的 ImageGen 流程，未採用變體
   不進 inventory）；主選單至少一張 key art。
3. 地圖圖形化：節點清單改為視覺化節點圖（node graph＋連線＋目前位置），
   文字清單降為輔助／無障礙通道。
4. 戰鬥呈現：BattlePlayback 接 combat_vfx／status_damage atlas，傷害數字密度
   設定已存在（settings）直接對接。
5. 音訊接線：music 5 軌與 sfx 21 個接入 AudioService（畫面路由與動作觸發）。
- 驗收：每畫面前後對照截圖；soak／Combat determinism suite 不退化
  （視覺層不得碰 RngService gameplay stream，純視覺抖動用本地亂數）。

### Phase D｜中文化收尾（發佈品質）
1. 字型內嵌後全畫面 zh_TW 截圖走查（含長字串截斷、fallback 字符）。
2. gate 增補：「程式引用之 loc key 必存在於 catalog」檢查。
3. `production_accessibility_localization.gd` 內嵌表併入 catalog 單一來源。
4. 清理 `.translation` 死檔（或改為由 CSV 建置產物並納管）。
5. 首次啟動 locale 策略：無設定檔時以 OS locale 初始化（zh_TW 圈外預設 en）。
- 驗收：全新環境（刪 user://）首開即繁中、無缺字、無裸 key；en 切換完整。

## 6. 風險與備註
- P0-1／P0-2 有現成單元測試綠著（它們直接呼叫 `select_expedition()`，繞過了
  UI 信號路徑）——修復時應補「經 UI 信號」的整合測試，避免同類 E2E 盲區。
- 本報告實機驗證用的暫時修改已全數還原；工作樹僅剩 `project.godot` 的編輯器
  自動改寫（feature tag 4.7 等，無行為差異，可隨 Phase A 一併提交或還原）。
- 審核者環境 settings 已由 en 切為 zh_TW（遊戲內正常操作，非改檔）。
- 大樣本 balance 相關工作依既有裁決在 Phase 2 roadmap，另行處理，與本計畫無關。
