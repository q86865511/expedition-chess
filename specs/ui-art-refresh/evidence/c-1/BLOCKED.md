# C-1 BP-SI-003 前置硬閘阻擋報告

- 日期：2026-08-17
- 基線：`9d98e4d`
- 結果：**BLOCKED — 不開始 C-1 呈現實作**
- 前置議題：`BP-SI-003`

## 實測方式

使用 production content bootstrap、`BalanceProductionCaseDriver` 與真實
`RunPresentationSession`，固定 `tempo`／seed `0`，完整走過節點進入、戰鬥、結算、
獎勵與存檔，直到完成兩個節點。之後由該存檔重新組成 session，在 RUN_MAP 階段同時
讀取 `snapshot.map`、`reachable_nodes()`，並以現行 `RunMapScreen` 組出
`NodeSelector`。預檢以刻意的非零 exit code `2` 表示硬閘觸發。

## 阻擋證據

完成節點為 Act 1 layer 0 的單一入口，以及 Act 1 layer 1 的 slot 1。此時
`reachable_nodes()` 回傳四個節點：三個位於下一層 Act 1 layer 2，另有一個位於
已走過的 Act 1 layer 1 slot 0：

`node_ec2e3a3694eecb5c982753d17af448ca80bec7dacd0573a3c8ea48715474feba`

現行 RUN_MAP 對該歷史分支的 `NodeSelector.disabled` 為 `false`；實際選取後，
`RunMapScreen.selected_node_id()` 也等於該 node id。這證明 topology reachability
會讓本層不可選的歷史分支進入 UI 可達／高亮語意，符合 `BP-SI-003` 的已知病徵。

完整 clone-only 讀取面、39 個節點座標、四個 query 結果、所有 ItemList disabled
狀態與截圖 SHA 見 [frontier-preflight.json](./frontier-preflight.json)。視覺證據見
[frontier-preflight.png](./frontier-preflight.png)：Act 1 layer 1 的未選分支被高亮，
同層已完成的 slot 1 則為 disabled；真正下一步的三個 layer 2 節點也同時 enabled。

## 裁決與續作條件

依 C-1 計畫的硬閘，presentation 不得自行建立、複製或推測 frontier 演算法，因此本次
沒有修改 `domain/services/app`、`presentation/viewmodels`、
`run_presentation_session.gd` 或任何 presentation UI；也沒有啟動 ImageGen、建立地圖
資產、執行九組矩陣或開始 C-2／C-3。

續作前需要 Claude 交付具名 current-frontier 查詢及其契約，並讓
`RunPresentationSession` 提供可直接消費的合法下一步集合。該前置合併後，應重新執行
本硬閘；只有歷史分支不再出現在可選集合時，才開始 C-1 節點圖實作。
