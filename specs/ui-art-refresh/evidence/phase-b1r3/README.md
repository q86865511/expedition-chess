# Phase B1R3 證據（Claude 親自實作）

日期：2026-08-08。分支：`codex/g2-ui-art-refresh-b`
commits：`78e24e0`（稽核紅燈基線）→ `f5484b8`（viewport）→ `70dc17a`（runner 隔離）
→ `f61c0ff`（縮放契約）→ `d49aff1`（版面主批）。

## 自動測試

- **幾何稽核（新，A4）**：`tests/integration/presentation_ui_b1r3/test_layout_geometry_audit.gd`
  ——4 route × 3 縮放，規則：同容器同類控制項同高、按鈕文字不截
  （autowrap 與明示 cell 豁免）、互動控制項在安全區（follow_focus 捲動豁免）、
  分組頁初始高度>0（P1）、設定動作列底緣≤696（P3）、商店卡在鍵盤焦點環（P2）、
  modal 置中（P10）、150% 左欄收斂（autowrap 夾制回歸鎖）。
  先紅（48 項失敗基線，見 78e24e0）後綠：**3/3 tests、544 asserts、exit 0**。
  縮放一律走真實設定套用管線（draft→settings.apply→consumer）。
- **世界解析度（§10.1）**：`test_world_viewport_resolution.gd`——SubViewport
  恆 640×360、stretch_shrink=2。
- **fresh `-Suite All`：exit 0**——306 scripts、**1219/1219 tests**、
  **25737 asserts**、0 failures／errors（Import／Smoke／Content／Canonical／
  Combat／Expedition／ActEliminationGate／Spec 全綠）。
- **evidence runner（隔離 APPDATA）**：`issues=[]`（0 項），
  真實 APPDATA 前後 inventory SHA-256 相同
  （`real-appdata-integrity.json` `ok=true`），涵蓋巢狀 `遠征棋.bak`。

## 根因修復紀錄

- U1 黑條：`window/stretch/aspect="expand"`＋`default_clear_color=navy_950`；
  coordinator 既有置中邏輯由死碼轉活；`stretch_shrink` 修正世界解析度
  （舊寫法 stretch 開關會被 recalc 覆寫）。
- U2 對齊/縮放：theme runtime 泛化（BASE_THEME 全 type 的字級/constant/
  content margin ×factor）；`ExpeditionLayoutMetrics` 為尺寸唯一入口
  （寬=版面預算 reference 固定、高×factor；cell 兩軸固定＋ellipsis＋稽核豁免）；
  shell 頂/底/狀態帶高度 scale-aware，中央由 follow_focus 捲動吸收。
- autowrap min 夾制（新發現）：`Control.set_size` 在子節點 reflow 前被
  combined min 向上夾制且不回縮（autowrap Label 寬 1px 時 min 暴漲）——
  `run_prepare_screen.refresh_layout_rects` 以 set_deferred 二次指派收斂。
- 測試污染真實 APPDATA 的三輪懸案根因：**test harness 經 SettingsService
  autoload 寫真實 user://**，非流程紀律問題。`tools/run-tests.ps1` 現對
  子程序注入隔離 APPDATA（`Invoke-GodotChild`），實測 settings SHA 前後不變。

## 實機驗證（真實 Windows、副螢幕、最大化 1920×1080）

1. 最大化無黑條、UI 滿版置中（主選單按鈕真置中）。✔（對話紀錄截圖）
2. 備戰：棋盤主體＋部署單位顯示、底部帶欄位同高對齊、裝備庫可見、
   商店卡與動作鈕同基線。✔
3. modal 真置中＋不透明底板。✔
4. 設定：新版單欄版面、150% 套用→全域等比放大、動作列在安全區、
   無偽回退訊息；100%↔150% 往返正常。✔
5. 已知取捨（提請核可裁決）：備戰分組頁 7 顆動作在 140px 帶內以同尺寸
   按鈕＋follow_focus 細捲軸呈現（原「縮小號按鈕」已修為同尺寸；
   完全去捲軸需帶區加高或動作重分組，屬 B2 佈局議題）。

## 審查與處置

reviewer 一審原文：`.pipeline/reviews/ui-art-refresh-phase-b1r3-review.md`
（P1~P11 全數「已修」；U1 已修、U2 部分修；新提 N1~N9）。逐項處置：

| 編號 | 處置 |
|---|---|
| N1 token 零消費者 | **已修**：刪除 11 個平行 token 與 `px()`，寬度值單一事實來源留在呼叫端（不留會分歧的死常數）。 |
| N2 `safe_margin` 被縮放 | 隨 N1 一併消滅（畫布常數不再對外發布）。 |
| N3 中央守門與捲動設計矛盾 | **已修**：evidence runner 改驗「捲動視窗本身在中央區內＋follow_focus」，內容溢出由捲動吸收；issues 由 38 → **0**。 |
| N4 證據未落檔／All 佔位 | **已修**：本檔回填實測數字，phase-b1r3 納入版控。 |
| N5 隔離目錄不清理 | **已修**：`run-tests.ps1` 清理 6 小時前的殘留隔離目錄。 |
| N6 跨欄位同高未稽核 | **已修**：新增 `_audit_band_uniform_heights`（底部帶跨欄位同高），正是使用者主訴的症狀。 |
| N7 `set_deferred` 夾制脆弱 | **部分修**：回歸鎖改為對照 shell 實際區域高度（不再硬編 280），文案變動不再間歇紅；根治屬 B2 版面重構。 |
| N8 建構期寫死 100% 閃幀 | 留待 B2（一幀閃爍，實機不可見；已記於本檔）。 |
| N9 縮放測試只驗字級 | 留待 B2（幾何稽核已覆蓋控制項尺寸，此為重複保險）。 |

另審查確認無問題（勿重工）：StyleBox 無共享污染、constant 縮放未誤傷旗標常數、
`stretch_shrink` 數學成立、`aspect=expand` 對四個 `get_visible_rect` 讀點語意一致、
P1/P2/P3/P10 新斷言逐條可失敗、未觸 `domain/`／`services/` 業務邏輯。

## 審查後修復的額外回歸（主對話自驗）

- 底部帶錨定重構：`_place_panel` 讓 REGION_BOTTOM 錨定畫面底、向上生長，
  內容 min 晚到（主題切換延遲重算、分組切換、node-choice）也不會把底緣
  推出安全區——evidence runner 的 6 項 `prepare_bottom_outside_safe_area` 因此歸零。
- `Actions` 節點路徑：置中一度改用 `ActionsHost` 包裝，破壞
  `screen.get_node(^"Actions")` 契約（兩個 modal 測試紅）。改回直屬子節點
  ＋grow BOTH 置中，29/29 綠。
- deferred 回呼守衛：`is_instance_valid` 於 theme runtime 與 settings consumer
  （freed 物件不等於 null，跨 teardown 邊界會在引擎層炸 find_children）。
