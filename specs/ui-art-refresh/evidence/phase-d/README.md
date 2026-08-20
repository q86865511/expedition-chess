# Phase D 中文化收尾驗收證據

## 結果

Phase D 已依 2026-08-20 最終裁決完成並收斂。六個 faction 採候選 A、六個 role 保留
直譯、全部英文羈絆名不變；44 個技能描述採提案原文。44 個編號單位名本批保持現值，
下一批才依 faction／role／cost／戰鬥定位／視覺稿提出每單位兩個候選。

- 全畫面 `zh_TW` 走查覆蓋局外、RUN_MAP、RUN_PREPARE、RUN_COMBAT、RUN_REWARD 與
  RESULTS／fallback 狀態。修正頂欄數值、備戰空羈絆文案及戰鬥檢視器在窄畫布／高縮放下
  的截斷與溢出。
- 新增 `PUI_LOCALIZATION_REFERENCE_MISSING` 靜態 gate：程式中的具名 loc 引用與
  accessibility dictionary `text_key` 都必須存在於 catalog；一般 stable ID 不會誤判。
- 經使用者核准，19 個 accessibility 內嵌 key 與 6 個既有 `text_key` 以機械遷移方式併入
  catalog。`ProductionAccessibilityLocalization` 降為保留既有 API 的薄轉接，雙語值只由
  catalog／sealed emergency catalog 提供。
- 首開無設定檔時由 OS locale 初始化：`zh_TW`／`zh-Hant` 圈採 `zh_TW`，其餘採 `en`；
  已有設定、損壞檔與未來 schema 的既有策略不變。
- `.translation` 定位為 Godot importer 可重建的本機產物，維持 ignore；runtime 權威仍是
  sealed `catalog.v2.csv.raw`。
- RUN_COMBAT 單位詳情實際消費 `loc.effect_*_primary` display key；本批將同一份核可描述
  機械同步到 44 個既有 display alias，確保產品不再顯示「Slice Player 00 的主要技能效果」
  類佔位。沒有新增 key 或創作第二份文案。

## 25-key reseal 與邊界

完整對映與來源見 [accessibility-localization-migration.md](./accessibility-localization-migration.md)。
catalog／raw 最終共有 966 筆資料列，CSV 與 raw byte-identical，SHA-256 均為
`c3cad96d04179ea278c9138b47c69cc70f5581d2fc3c3e53bc3f870729e3ac73`；bootstrap seal 已同步。

本次 app 差異只有：

- `app/content/localization_catalog.gd`：原 25-key accessibility 遷移，加上本次核可的
  6 個 faction 中文值、44 組技能描述與 44 個現行單位詳情 display alias；row count 不變。
- `app/content/project_content_bootstrap.gd`：同步 catalog SHA。

`tools/content-production/export-localization-catalog.gd` 只被執行、未修改；CSV／raw 由 exporter
重導，沒有手改。既有使用者 `project.godot` 編輯器差異保留且未納入本批。

## 視覺走查

- Before：71 張 PNG。
- After：107 張 PNG，其中 core routes 6、局外 54、RUN_COMBAT 23、RUN_MAP 12、
  system/results 12。
- 四個結構化 after runner report 皆 `ok=true`、`issues=[]`；core routes 六張另逐張人工檢視。
- 最終裁決後另補 [final-copy](./final-copy/) 26 張：RUN_PREPARE／RUN_COMBAT 23 張、
  COLLECTION 3 張；兩份 runner report 均 `ok=true`、`issues=[]`。首次補圖發現四字 faction
  在 76 px 膠囊截斷，將 metrics 調為 96 px 後原 clipping gate 轉綠並重拍。
- 前後問題、修正與代表圖見 [visual-qa.md](./visual-qa.md)。完整圖檔分別位於
  [walkthrough-before](./walkthrough-before/) 與 [walkthrough-after](./walkthrough-after/)。

## 驗證

- `tools/run-tests.ps1 -Suite All`：exit 0；1510／1510 tests、41532 assertions、
  0 failures／errors／orphans。All 內的 Smoke、Content、Canonical、Combat、Expedition、
  ActEliminationGate、Spec 均 exit 0。
- 獨立 Smoke：10 cases、failures 0、exit 0；實際走過 minimal boot 與 catalog digest 驗證。
- final copy contract：3／3 tests、576 assertions；loc parity／reseal：16／16 tests、
  2574 assertions，皆 exit 0。
- localization static gate：20／20 tests、312 assertions，exit 0。
- accessibility：14／14 tests、1458 assertions；settings locale：7／7、451 assertions；
  in-run HUD：157／157、5870 assertions；combat inspection：2／2、74 assertions；
  theme：10／10、147 assertions，全部 exit 0。
- `git diff --check`：exit 0；本批 diff 新增 `theme_override_*` 0；tracked `.translation` 0。

原始 XML、runner JSON 與 log 在 [test-results](./test-results/)，機器可讀總表在
[evidence-report.json](./evidence-report.json)。

## 最終裁決

[copy-debt-proposals.md](./copy-debt-proposals.md) 保存提案、裁決與落地狀態：

1. faction 六項採 A；role 六項保留直譯；羈絆英文全數維持現值。
2. 44 個依 `base + source.attack` 實際公式撰寫的中英文描述整批核可並已落地。
3. 44 個編號單位名確定進入正式命名，但本批未改；下一批另提每單位兩候選並停裁決。
