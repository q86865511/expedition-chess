# B-out-3 視覺核可證據

本批是局外視覺最後一批，涵蓋 `SETTINGS`、`RESULTS`、
`RESULTS_FALLBACK`，以及 `CAMP_WORLD` 上開啟的 ESC 系統選單。原候選與
使用者指定修訂均已完成自動及人工驗收；本次提交後 Phase B 完成並停止，等待下一批指示。

## 截圖矩陣

- 畫面狀態：設定、正式結算、結算 fallback、營地 ESC 系統選單，共 4 組
- 視窗：1280×720、1920×1080、2560×1440
- UI scale：100%、125%、150%
- 合計：36 張 PNG，36 個 SHA-256 全部唯一
- 機器報告：`evidence-report.json`（`ok=true`、36/36、`issues=[]`）

36 張已逐張人工檢視，並對 125%／150% 的設定頂欄、結算左右欄、fallback
三按鈕底帶與最大 ESC 面板另以新檔名讀回複核。所有候選均無卡片重疊、內容越出
卡片、控制項出安全區或空白截圖。人工檢查曾發現結算右欄 label 在 125% 字級
minimum 臨界點向左生長；已把 metrics-owned label/card 固定為由左上向右下生長，
重產完整矩陣後收斂。

## 使用者核可修訂補圖

- `RESULTS` 的兩張大數字卡新增雙語欄位標籤：`results.metric.currency_delta`
  對應本次結算的貨幣增量，`results.metric.profile_currency` 對應結算後帳戶持有貨幣；
  數字維持主視線大字，receipt／digest 改為 14 px 輔助資訊。
- `SETTINGS` 的 `SettingsScroll` 延伸至 shell 內容區底，保留正常捲動裁切提示，移除
  裁切列下方的大面積空帶。
- 頂欄右上入口的實際行為只會呼叫 ESC 系統選單，故文字改綁雙語 loc key
  `system_menu.open`（「選單」／`Menu`），`MENU_MAIN` 排除規則不變。
- `RESULTS`「遠征完成」橫幅移除內層裝飾邊框，只保留 shell 外框。
- 補圖人工檢視時另發現 `CAMP_WORLD` 三個 metric 與「選單」入口重疊；已保留入口寬度
  並將 metrics 左移，重產後三組均無重疊。
- 受影響組合採 1280×720／UI 150%、1920×1080／UI 125%、
  2560×1440／UI 150%，四個狀態共 12 張；`revision/evidence-report.json` 為
  12/12、12 個唯一 SHA-256、`issues=[]`。12 張均已逐張人工檢視。

## 畫面收斂

- `SETTINGS` 經 `ProductionLayoutShell.build(route_kind)` 的局外 per-route 分支進入
  無左右側欄的主面板；保留既有 `Composition/SettingsScroll/SettingEditors/...`
  節點路徑、單一標籤欄與縮放版面權威，只新增 accessibility／audio 分區線與 row
  panel vocabulary。
- `RESULTS`／`RESULTS_FALLBACK` 移除 `.tscn` 的硬編 offset，幾何收進
  `ExpeditionLayoutMetrics`；結算結果、獎勵、帳戶總額、receipt 與 digest 成為五張
  metrics-owned 資訊卡，長識別字串可安全換行。正式結算維持兩個既有動作，fallback
  維持三個既有動作與節點契約。
- ESC 系統選單的 route allowlist 放寬至局外營地／五設施／圖鑑／設定／結算與既有
  RUN routes；`MENU_MAIN` 維持排除。內嵌設定、返回主選單雙確認與 route-specific
  action dispatch 契約不變。
- `app/main.tscn` 兩個世界點擊靶實查已是無繪製的 `Control`，不是 `ColorRect` 或
  `TextureRect`；因此沒有為了本批製造無效 app diff，也未碰 `app_root.gd`。
- B-out-3 presentation/theme 變更查無 `theme_override_*`；玩家可見文字未新增硬編碼。

## 自動驗證

- Godot 4.7 parser/import：exit 0
- `tests/unit/ui_art_refresh/test_b_out_3_outgame_shell_results_and_system_menu.gd`：
  5/5 tests、96 assertions、0 failures／errors／orphans
- presentation UI content／loc parity：13/13 tests、1936 assertions、
  0 failures／errors／orphans
- `tests/runners/presentation_b_out_3_evidence_runner.gd`：exit 0，36/36，
  36 unique SHA-256，`issues=[]`
- 同 runner 的 `--revision-only`：exit 0，12/12，12 unique SHA-256，`issues=[]`
- `tools/run-tests.ps1 -Suite All`：exit 0（2026-08-17 20:07–20:25 Asia/Taipei）
  - GUT：1471/1471 tests、39232 assertions、0 failures／errors／orphans
  - Spec：4096 cases、0 failures
  - Import、Smoke、Content、Canonical、Combat、Expedition、ActEliminationGate 與
    RunnerContract 聚合結果皆通過

B-out-3 修訂已獲使用者核可；本次提交後 Phase B 完成。未 push，也不開始 Phase C。
