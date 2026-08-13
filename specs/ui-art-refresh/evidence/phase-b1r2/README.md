# Phase B1R2 視覺樣板修訂證據

## 結論與核可閘門

B1R2 僅修第二審 N1～N16 指出的新回歸、重疊與裁切問題；已確認的 B1R 版面骨架與
R4 症狀修正沒有重做，也未開始 B2。非 headless Windows runner 的
`evidence-report.json` 為 `ok=true`、`exit_code=0`、`issues=[]`，共 41 張截圖。
本分支仍停在 B1 視覺核可閘門，等待使用者裁決。

## 隔離與真實 APPDATA 守門

所有 Godot 啟動都經 `tools/run-isolated-ui-evidence.ps1`，profile 固定在：

- `artifacts/ui-art-refresh/phase-b1r2/profile/AppData/Roaming`
- `artifacts/ui-art-refresh/phase-b1r2/profile/AppData/Local`

使用方式：

```powershell
$env:GODOT_BIN = '<Godot 4.7 stable executable>'
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run-isolated-ui-evidence.ps1 -Mode Evidence -FreshProfile
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run-isolated-ui-evidence.ps1 -Mode AllTests -FreshProfile
```

wrapper 只接受 `-GodotPath` 或 `$env:GODOT_BIN`，`-FreshProfile` 只可清除 repo 內
`artifacts/ui-art-refresh/phase-b1r2`。非 headless Evidence／Activation 改用
`Start-Process -Wait`，確保遊戲程序真正退出後才做 after 快照。

`real-appdata-before.json` 與 `real-appdata-after.json` 對
`%APPDATA%/Godot/app_userdata/**` 全目錄遞迴記錄相對路徑、大小、建立／修改時間與
SHA-256；其中明確包含實際位於 `遠征棋/遠征棋.bak/settings-v1.json` 的巢狀備份。
兩端皆為 241 個目錄、73 個檔案、2,338,766 bytes，inventory SHA-256 同為
`7d1c0553ea2142425d4b4a48ba56b1d43b571b29e8ef0c3c2e44cb3a1d5b280a`。
`real-appdata-integrity.json` 為 `ok=true`。

## 截圖矩陣

營地與備戰基礎矩陣共 12 張：

- `camp-{720p,1080p}-ui{100,125,150}.png`
- `prepare-{720p,1080p}-ui{100,125,150}.png`

T3 與指定情境：

- 主選單：`menu-main-720p-ui{100,125,150}.png`
- 設定套用後：`settings-after-apply-720p-ui{100,125,150}.png`
- 三個備戰分組：`prepare-group-{forge-equipment,party,advance}-720p-ui{100,125,150}.png`
- node-choice：`prepare-node-choice-720p-ui{100,125,150}.png`
- node-choice modal：`prepare-node-choice-modal-720p-ui{100,125,150}.png`
- 返回主選單 modal：`prepare-return-modal-720p-ui{100,125,150}.png`
- 狀態訊息：`prepare-status-message-720p-ui{100,125,150}.png`
- F1 縮放重建：`prepare-scale-rebuild-150-rebuild-100.png`
- 焦點缺角框：`focus-prepare-start.png`

人工逐張讀回：主選單與設定 action 文字完整；設定標題不再壓住語言列，內容由原列結構
外包一層 scroll viewport，沒有半顆控制項露在動作列上方，hover 也不再重複可見標籤。
備戰 8×4 棋盤與 9 格 bench 的四邊完整，中央裝備庫可見，右欄與 bottom band 不相交；
100%／125%／150% 的 bottom panel 都停在 y=696 安全底線內，刷新、購買經驗值、分組
與固定動作沒有截字。頂欄只留單一道金線，面板縫隙由不透明 navy 背景承接。空狀態時
44px 色帶隱藏；有狀態時獨立保留且不疊內容。返回 modal 為不透明 navy 面板、3px amber
邊框，文字不會與棋盤格線混在一起。

## N1～N11 與 O1～O6 處置

- N1：移除 action factory 的 `clip_text=true`；文字寬重新參與 minimum size。只有明確
  96×72 的商店卡保留裁切／換行契約。
- N2：`InventorySelector` 移入中央「裝備庫」，保持多選、滑鼠操作與鍵盤焦點環。
- N3：prepare bottom 改用固定 14px 動作變體與 8px 專屬間距，商店／分組／固定動作
  重新配寬；不再由 150% 字級把 140px panel 撐破安全區。
- N4／N5：焦點測試直接斷言按鈕自身 global rect 與文字寬；F1 以獨立 100% 控件及
  runner 先錄基準，再驗 150%→重建→100%，不讀被測 meta 作期望。
- N6：`StatusRegion` 無訊息時隱藏；訊息出現時才縮回內容區並顯示獨立底板。
- N7：營地中央加入選定指揮官、挑戰等級與發現摘要，不再保留 640×372 空框。
- N8：R4 真機制更正為 `main.tscn` 的 `node_paths` 相對 NodePath 賦值被 Godot 4.7
  靜默丟棄；已刪五條死賦值，腳本預設值為唯一生效來源。R4 症狀既已核可，本輪未重跑。
- N9：隔離流程新增全真實 APPDATA 前後 inventory hash，並修正 `.bak` 的巢狀路徑。
- N10：商店卡不再帶通用 `action_id`；卡片自己的 pressed handler 每次只 dispatch 一次。
- N11：node-choice 期間逐張停用五張 shop card，報告為 5/5 disabled。
- O1：共用 confirmation root 改為 `ExpeditionModalPanel` 不透明實板與邊框。
- O2：棋盤固定 8px／4px格距、bench 固定 8px 格距；中央 scroll viewport 與 608px
  內容寬對齊，右格與底格完整。
- O3：top bar 改用不透明單底線 StyleBox；全螢幕 menu／settings 補不透明背景。
- O4：設定只做重疊修補：標題／內容／底部 action 分區、既有 rows 外包 scroll，並移除
  重複 tooltip 與 CheckButton 可見重複文字；未做 B2 的整頁視覺重構。
- O5：見 N6。
- O6：見 N7。

## 低項裁決

- N12 延後：board／bench 交叉清選屬選取語意與空格回饋，不是本輪重疊／裁切回歸；
  B2 統一操作提示時一併處理。
- N13 已修：雖原列低項，但 O2 明確要求所有縮放格子完整，因此 bench 改固定 8px 間距。
- N14 延後：`ShopOffer` 沒有星級權威欄位，本輪不得擴張 domain/service；卡片暫維持
  現行一星投影，待資料契約另案處理。
- N15 延後：空 overflow／issue 目前已有玩家可見占位文案；固定保留空 selector 節點只影響
  測試契約，留待 B2 全畫面版面契約一起收斂。
- N16 本輪不動：difficulty tier 後綴是 B1R 既有內容層修正，超出 B1R2 聚焦範圍。

## 測試

Godot `4.7.stable.official`。fresh 隔離 profile 執行
`tools/run-tests.ps1 -Suite All` exit 0：304 scripts、1216/1216 tests、25185 assertions、
0 failures、0 errors；Import、Smoke、Content、Canonical、Combat、Expedition、
ActEliminationGate、Spec 皆通過。RunnerContract 中刻意驗證錯誤／timeout 的非零子程序
是 runner 自測預期值，最外層 All 為 0。摘要見 `all-tests-summary.json`，原始報告位於
`artifacts/test/runner-execution.json`、`gut.xml` 與 `gut.godot.log`。
