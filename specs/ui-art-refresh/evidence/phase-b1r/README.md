# Phase B1R 視覺樣板修訂證據

## 結論與核可閘門

本目錄是第一審退回後的 B1R 修訂證據。營地與備戰已在 zh_TW、720p／1080p、
100%／125%／150% 完成 12 張真實 Windows 視窗截圖；另含 F1 縮放重建、F3
node-choice、F4 狀態保留帶與 focus 缺角框。`evidence-report.json` 為 `ok=true`、
`issues=[]`。本次仍停在 B1 視覺核可閘門，未開始 B2。

## 隔離方式

所有會啟動 Godot 的步驟都經同一 wrapper，`APPDATA` 與 `LOCALAPPDATA` 分別指向：

- `artifacts/ui-art-refresh/phase-b1r/profile/AppData/Roaming`
- `artifacts/ui-art-refresh/phase-b1r/profile/AppData/Local`

使用方式：

```powershell
$env:GODOT_BIN = '<Godot 4.7 stable executable>'
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run-isolated-ui-evidence.ps1 -Mode Evidence
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run-isolated-ui-evidence.ps1 -Mode Activation `
  -FreshProfile -ExpectedDiagnostic Absent
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run-isolated-ui-evidence.ps1 -Mode AllTests -FreshProfile
```

wrapper 只接受 `-GodotPath` 或 `$env:GODOT_BIN`，不含本機硬編碼搜尋路徑。
`-FreshProfile` 在刪除前會解析絕對路徑，並拒絕任何不在
`artifacts/ui-art-refresh/phase-b1r` 下的目標。

## 畫面矩陣

營地：

- `camp-720p-ui100.png`、`camp-720p-ui125.png`、`camp-720p-ui150.png`
- `camp-1080p-ui100.png`、`camp-1080p-ui125.png`、`camp-1080p-ui150.png`

備戰：

- `prepare-720p-ui100.png`、`prepare-720p-ui125.png`、`prepare-720p-ui150.png`
- `prepare-1080p-ui100.png`、`prepare-1080p-ui125.png`、`prepare-1080p-ui150.png`

人工讀回結論：150% 下標題與資源列互斥；棋盤、bench、狀態帶、商店及右下固定
按鈕均未跨區或裁切。備戰以 8×4 可見格線棋盤為中央主體，bench 為正下方單排，
五張商店卡與金幣／等級／經驗、刷新／購買經驗值成組；左右欄分別為隊伍／羈絆與
可捲動遠征待辦。營地五個設施按鈕為主，遠征資訊降為次要面板。

## 四個必備情境

- F1：`prepare-scale-rebuild-150-rebuild-100.png` 與
  `scale-rebuild-report.json` 記錄 150% → 重建 → 100%，開始戰鬥按鈕回到 48px
  基準；單元測試另覆蓋在 150% Theme 下新建、沒有 authored size 的按鈕，證明
  base meta 不受污染。
- F3：`prepare-node-choice-720p-ui100.png` 與 `node-choice-layout-report.json`；
  三個選項位於右欄 ScrollContainer，右欄與開始戰鬥不相交且皆在畫布內。
- F4：`prepare-status-message-720p-ui100.png` 與 `status-band-report.json`；狀態列
  有獨立 44px 底色保留區，不覆蓋中央內容。
- focus：`focus-prepare-start.png` 顯示 `focus_high` 缺角焦點框。

## R4 真實偽回退根因

第一審後在 Windows display server、非 headless、zh_TW、fresh process、單一
`reduced_motion` 開關穩定重現。修正前
`activation-present-real-machine.json/png` 的常駐來源是
`PRODUCTION_VIEWPORT_TREE_INVALID`：以程式建立的 coordinator 沒有預設 NodePath，
五條 production viewport/UI 路徑皆為空，並非字型 glyph probe。

`ProductionViewportCoordinator` 現在提供相對 NodePath 預設值；若 640×360 viewport
尺寸需要校正，會先暫停 container stretch，避免 Godot 警告。最終
`activation-absent-real-machine.json/png` 記錄 `display_server=Windows`、
`headless=false`、`fresh_process=true`、`locale=zh_TW`、單一開關、五條路徑全可解析、
`diagnostic_visible=false`、`source_code=""`。這份 after 於最終程式碼上重新產生。

## 測試

Godot：`4.7.stable.official`。fresh 隔離 profile 執行
`tools/run-tests.ps1 -Suite All` exit 0：304 scripts、1213/1213 tests、25122
assertions、0 failures；Import、Smoke、Content、Canonical、Combat、Expedition、
ActEliminationGate、Spec 皆 exit 0。摘要見 `all-tests-summary.json`，原始報告位於
`artifacts/test/runner-execution.json`、`gut.xml` 與 `gut.godot.log`。

## 第一審逐項處置

- F1：修正；先在 100% 權威 Theme 下量測未 authored 軸，再掛縮放 Theme，並有
  150% 新建畫面回 100% 測試與實機證據。
- F2：修正；內文字型為 `FontVariation wght=400`，標題為 `wght=600`。
- F3：修正；右欄可捲動，node-choice 幾何報告通過。
- F4：修正；狀態列有底色與獨立保留區。
- F5：修正；wrapper 只讀 `$env:GODOT_BIN`／`-GodotPath`。
- F6：修正；Theme 使用 `duplicate(false)`。
- F7：修正；測試解析 `assets/pilot/palette.json` 並逐色精確比對十個 token。
- F8：修正；測試把 Label 掛入實際 Theme 樹，讀取生效 `FontVariation` 與 base font，
  並逐字驗 glyph。
- F9：修正；撤銷 evidence `.png.import` ignore，恢復與 master 一致的追蹤方式。
- F10：延後 B2；營地目前沒有 modal 路徑，全面 modal background registry 涉及其餘
  route 鋪開，不能在 B1R 擴張處理。
- F11：延後 B2；現行 zh_TW/en 可見字元皆由內嵌字型涵蓋；裝飾符號的 per-glyph
  fallback 需要和全畫面 typography policy 一起裁決，避免本段改變既有錯誤契約。
- F12：修正；生命、金幣、等級／經驗、人口等決策數值改用 parchment 等級的
  `ExpeditionMetric`，stone_500 僅留非決策空狀態／輔助字。
- F13：延後 B2；營地 action 語意分組應與 B2 的 `_required_action_ids()` 一致性 gate
  同步完成，避免先造第二份分組權威。
- F14：修正；安全區測試同時覆蓋 camp 與 prepare bottom-height 變體，實機 runner
  另逐 case 檢查棋盤／bench 不跨 status 或 footer。
- F15：修正；本 README 與 wrapper 現在明確記錄 `-FreshProfile` 清理行為及 guard。
- F16：修正；舊 runner 內模擬演算法與故障注入證據已移除，改由獨立非 headless
  Windows runner 留存實際修正前／後報告。

## 真實 APPDATA 完整性

主要真實設定 `Godot/app_userdata/遠征棋/settings-v1.json` 的開工與收尾長度、建立
時間、修改時間、SHA-256 完全相同；數值見 `real-appdata-integrity.json`。

另有一項無法歸因的旁支異常：開工盤點存在的
`Godot/app_userdata/遠征棋.bak/settings-v1.json` 在收尾讀回時不存在。本次唯一遞迴
刪除位於 wrapper 的 `-FreshProfile`，其 resolved-path guard 限定在 repo artifacts，
所有執行命令也都透過該 wrapper；因此沒有證據顯示 B1R 流程觸及該旁支，但也不把
「所有真實 APPDATA 項目完全未變」寫成已證實。主要使用者 settings 則可由相同
timestamp 與 hash 直接自證未被本次流程寫入。
