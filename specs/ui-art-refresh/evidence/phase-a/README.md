# Phase A 實機與測試證據

日期：2026-08-07
分支：`codex/g2-ui-art-refresh-a`

## 自動測試

修復前先以 UI 信號路徑建立有效紅燈：

- R15 營地：7/8 tests、137/139 assertions；預設選擇未同步、
  `allow_reselect` 未開啟。
- R14 地圖：11/12 tests、171/174 assertions；`map.select` 未產生地圖，
  `map.confirm` 仍承擔錯誤語意。
- G2 findings：22/25 tests、278/281 assertions；備戰分組與焦點指示層不存在。
- Run facade：12/13 tests、56/57 assertions；錯誤碼仍是
  `RUN_COMMAND_APPLY_FAILED/EQUIP_ITEM_SLOTS_FULL`。

最終執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite All
```

- exit code：0
- 時間：810.4 秒（2026-08-07T06:39:59Z～06:53:29Z）
- GUT：303 scripts、1200/1200 tests、24857/24857 assertions
- failures / errors / orphans：0 / 0 / 0
- Import、Smoke、Content、Canonical、Combat、Expedition、
  ActEliminationGate、Spec：全部 exit 0
- runner 要求的 fresh `ExpeditionSoak` 已先執行：10,000 seeds、0 failures，
  `-Suite ExpeditionSoak` exit 0。

## 實機路徑

使用 repo 內隔離且先清空的 APPDATA，Godot 4.7 正式視窗為 1280×720、
UI scale 100%。所有導航均以 Win32 OS 滑鼠事件操作；Tab 證據以 Win32 鍵盤事件輸入。

1. [主選單](00-main-menu.png)
2. [營地：指揮官 0／挑戰 0 已同步，開始遠征可按](01-camp.png)
3. [新遠征空地圖：選擇節點／確認前進語意已分離](02-map-empty.png)
4. [選擇節點後：地圖已產生且有可見選取](03-map-selected.png)
5. [備戰：預設商店組，開始戰鬥與返回主選單固定可及](04-prepare-shop.png)
6. [備戰分組：商店／鍛造裝備／隊伍調整／推進](05-prepare-groups.png)
7. [Tab：高對比粗框清楚包住目前焦點控制項](06-tab-focus.png)

逐張讀回未發現 `error.*`、`prepare.*` 等裸 localization key。自動測試另在
100%／125%／150% UI scale 驗證四個分組內全部動作可見、可聚焦且位於 720p 安全區。

## 戰鬥畫面截圖阻塞

OS 滑鼠確實按下「開始戰鬥」，而且流程隨即回到下一個可達地圖節點；但本次 fresh
profile 的 committed transcript 在第一個可呈現影格即 exhausted，`RUN_COMBAT` 同幀請求
`SETTLE_BATTLE`。以 10 ms 間隔連續擷取 80 幀仍沒有任何可見戰鬥幀：

- [frame 020：仍為備戰](07-combat-transition-before.png)
- [frame 021：已回地圖](08-combat-transition-after.png)

因此「滑鼠走到開始戰鬥」已驗收，但無法提供不造假的戰鬥畫面截圖。未修改播放速度、
未直接呼叫 presentation 方法，也未為了截圖擴大 Phase A 範圍。
