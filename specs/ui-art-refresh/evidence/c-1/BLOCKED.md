# C-1 BP-SI-003 前置硬閘解除紀錄

- 原始阻擋日期：2026-08-17
- 解除基線：`ebb9858`
- 最終狀態：**RESOLVED — C-1 已繼續並完成**

## 原始缺陷

舊版 `reachable_nodes()` 使用拓撲可達語意，會把未選的歷史同層分支列為可選；domain
同樣允許玩家回頭重刷節點收入。原 C-1 前置探針因此依約停止呈現實作。

## 權威修復與重驗

`ebb9858` 交付與 `NodeEntryService` 同源的 frontier 權威。C-1 screens 直接使用
`MapNodePresentation.is_reachable(snapshot.map, node)`，沒有在 presentation 建立或推測
frontier 演算法。

production content、`BalanceProductionCaseDriver` 與真實 `RunPresentationSession` 走過兩個
節點後的重驗結果：completed 2、frontier 3、historical frontier 0，RUN_MAP enabled
historical nodes 亦為 0。完整資料見 [frontier-preflight.json](./frontier-preflight.json)，
通過後畫面見 [frontier-preflight.png](./frontier-preflight.png)。

本檔保留原 hard-gate 路徑，供 source-freeze 與歷史稽核讀取；它不再表示目前工作受阻。
