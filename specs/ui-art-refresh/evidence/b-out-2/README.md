# B-out-2 視覺核可證據

本批涵蓋 `CAMP_WORLD` 的兩項順手收斂，以及五個營地設施 route：
`FACILITY_EXPEDITION_GATE`、`FACILITY_COMMANDER_HALL`、`COLLECTION`、
`FACILITY_UNLOCK_WORKSHOP`、`FACILITY_CHALLENGE_MONUMENT`。使用者於 2026-08-17
核可本批，並要求收斂圖鑑高縮放換行後再提交。

## 截圖矩陣

- 畫面：`CAMP_WORLD`＋五設施，共 6 個 route
- 視窗：1280×720、1920×1080、2560×1440
- UI scale：100%、125%、150%
- 合計：54 張 PNG，54 個 SHA-256 全部唯一
- 機器報告：`evidence-report.json`（`ok=true`、54/54、`issues=[]`）

54 張已按 route 排為六張 3×3 contact sheet 逐張人工檢視，並另以每 route 的
1920×1080／150% 原圖放大複核。所有畫面均無裁切、重疊、越界或空白截圖；固定底帶
控制項維持 `ExpeditionLayoutMetrics.set_fixed_min` 的 72 reference 高度契約，字級與
內距則隨 UI scale 套用。

## 圖鑑換行修訂

- `collection-revision/` 補存 1280×720、1920×1080、2560×1440 × UI 125%／150%
  共 6 張受影響組合，並保留原 54 張證據供前後對照。
- content 列實際包含一張無 portrait 的指揮官資料卡與三張單位卡；卡寬收為 190
  reference px，150% 下四欄仍留在同列，第三張 portrait 不再換行貼住左下緣。
- `collection-revision/evidence-report.json`：`ok=true`、6/6、`issues=[]`；6 張均已
  逐張人工複檢，無換行、裁切、重疊、越界或空白截圖。

## 畫面收斂

- 五設施均使用 `ProductionLayoutShell.build(route_kind)` 的 per-route 幾何；不改動
  RUN／其他 route 的共用常數。四個單區設施移除空左／右欄，`COLLECTION` 才保留右側
  比較區，五者共用緊湊頂欄與底部返回列。
- `COLLECTION` 保留 `CategorySelector`、`SearchInput`、`EntrySelector`、
  `CompareSelector`、`CompareResult` 的既有型別、名稱、搜尋／比較／focus 契約；內容
  清單改為上圖下文 portrait cards，右側比較列使用縮圖。
- portrait 經既有 `ProductionUnitVisualCatalog` 解析 production inventory；manifest
  現有 44 張單位 portrait。presentation 不建立虛構的 commander→unit 對映，無圖項目
  仍安全降級為文字資料卡。
- `CAMP_WORLD` shell 中央裝飾 surface 隱藏，由 `CampEnvironmentView` 獨佔單一可見
  框線；底帶左半正式用作目前 focus／hover 設施名稱的情境提示，文字沿用既有 loc。

## 自動驗證

- Godot 4.7 parser/import：exit 0
- `tests/unit/ui_art_refresh/test_b_out_2_facility_shell_and_portraits.gd`：
  5/5 tests、83 assertions、0 failures／errors／orphans（圖鑑修訂後重跑）
- `tests/runners/presentation_b_out_2_evidence_runner.gd`：exit 0，54/54，
  `issues=[]`；修訂子集另為 6/6、`issues=[]`
- `tools/run-tests.ps1 -Suite All`：exit 0（2026-08-17 17:24–17:42 Asia/Taipei）
  - GUT：1466/1466 tests、39116 assertions、0 failures／errors／orphans
  - Spec：4096 cases、0 failures
  - Import、Smoke、Content、Canonical、Combat、Expedition、ActEliminationGate 與
    RunnerContract 聚合結果皆通過

B-out-2 已通過使用者視覺核可與指定修訂，提交後始開始 B-out-3。
