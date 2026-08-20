# C-1 RUN_MAP 視覺化節點圖驗收證據

## 結果

C-1 已依使用者三項修訂裁決完成並核可；本批完成後直接進入 C-2，C-3 音訊尚未開始。

節點圖採 UI 層實作。RUN_MAP 是需要 UI scale、鍵盤焦點、雙語文字與精確點擊區的決策介面，節點座標只服務呈現，不參與 gameplay 模擬；RUN_MAP 的世界棋盤維持清除。

## Frontier 前置閘門

- 基線：`ebb9858`
- 權威讀取：`MapNodePresentation.is_reachable(snapshot.map, node)`
- 完成兩個真實 production 節點後：completed 2、frontier 3、historical frontier 0。
- `reachable_nodes()` 相容別名與 frontier 完全一致；新 C-1 程式碼未使用該別名。
- RUN_MAP 清單 enabled historical nodes 為 0，結論為 `continue C-1 implementation`。

完整讀回見 [frontier-preflight.json](./frontier-preflight.json)；[frontier-preflight.png](./frontier-preflight.png) 為通過後的 1080p／UI 100 RUN_MAP 狀態。

## 視覺與互動驗收

節點圖包含 3 幕、每幕 7 個水平 layer 欄、39 個節點與 78 條邊。非色彩訊號如下：

- 已完成：`✓` 與實線框。
- 可達：`‹ ›` 成對角括與雙框。
- 不可達：保留節點類型形狀、降低透明度且移除外框；`×` 僅存在 accessible copy，
  不再出現在中央節點文字。
- 目前位置：獨立 `▶` 指標，不混入三態。
- 選取預覽：既有缺角 focus 框。
- 七種節點類型沿用 `InRunHudShell.NODE_KIND_SIGNALS` 的 `●／▲／■／?／⌂／◇／★`。

文字 `NodeSelector` 保留相同名稱、metadata、`FOCUS_ALL` 與原焦點順序，降為右側無障礙通道。圖形節點與文字清單雙向同步；選取只更新本地預覽，確認仍透過既有 `map.confirm` 將 `ENTER_NODE` 交由 domain 最終裁決。

### 九組矩陣

| 解析度 | UI 100 | UI 125 | UI 150 |
|---|---|---|---|
| 1280×720 | [圖](./run-map-720p-ui100.png) | [圖](./run-map-720p-ui125.png) | [圖](./run-map-720p-ui150.png) |
| 1920×1080 | [圖](./run-map-1080p-ui100.png) | [圖](./run-map-1080p-ui125.png) | [圖](./run-map-1080p-ui150.png) |
| 2560×1440 | [圖](./run-map-1440p-ui100.png) | [圖](./run-map-1440p-ui125.png) | [圖](./run-map-1440p-ui150.png) |

每張均驗出 39 節點、78 邊、3 幕標、39 個無障礙列、1 個目前位置，以及 completed 2／reachable 3／unreachable 34。78 條邊再分為 background 74／traversed 1／frontier 3：背景邊低透明度、已走路徑中權重、當前節點出邊使用最粗青綠高亮。幕標為正式雙語 `第一幕／第二幕／第三幕` loc key。逐張檢視確認節點與連線無裁切或重疊、背景不搶資訊，且灰階下仍可藉形狀、透明度與框線辨識三態；結構化結果見 [evidence-report.json](./evidence-report.json) 與 [visual-qa.json](./visual-qa.json)。

### 互動序列（1920×1080／UI 100）

1. [初始](./interaction-01-initial.png)
2. [選取另一個可達節點](./interaction-02-selected.png)
3. [map.confirm 後進入 RUN_PREPARE](./interaction-03-confirmed-next-route.png)

## 背景資產

ImageGen 依 `camp.png` 與主選單 key art 產出兩個候選，採用第二稿 `environment.run_map`；未採用候選未複製進 repository 或 inventory。採用稿為 1672×941，SHA-256 `70476ec7524fd444a3ff4b47feb19def7af98681d8f240f19dc86fcde8064656`。完整 prompt、參考圖 SHA、輸出 SHA 與選用理由見 [run_map_environment.json](../../../../assets/production/provenance/run_map_environment.json)；摘要見 [asset-sha256.json](./asset-sha256.json)。

## 測試與靜態閘門

- C-1 focused Gut：6／6 tests、83 assertions，exit 0。
- `tools/run-tests.ps1 -Suite All`：exit 0；Gut 354 scripts、1487／1487 tests、39400 assertions。
- Import、Smoke、Gut、Content、Canonical、Combat、Expedition、ActEliminationGate、Spec 均 exit 0。
- `git diff --check`：exit 0。
- C-1 差異中的 `theme_override_*`：0。
- 未修改 `domain/`、`services/`、`presentation/viewmodels/` 或 `run_presentation_session.gd`。
  C-1 幕標題裁決授權的唯一 app 例外，是正式 localization source 與其 bootstrap SHA
  (`app/content/localization_catalog.gd`、`project_content_bootstrap.gd`)；CSV/raw parity 維持綠。
- 使用者既有 `project.godot` 編輯器改寫保留，C-1 未碰該檔。

完整 All runner 記錄見 [all-runner-execution.json](./all-runner-execution.json)，摘要見 [all-output-summary.json](./all-output-summary.json)，靜態檢查見 [static-gates.json](./static-gates.json)。
