# Phase D `zh_TW` 視覺走查

## 走查範圍

實機證據涵蓋 1280×720、1920×1080、2560×1440 與 UI 100／125／150 的 production
route 組合，包括主選單、營地與設施、RUN_MAP、RUN_PREPARE、RUN_COMBAT、RUN_REWARD、
設定、結算及 fallback。Before 共 71 張，After 共 107 張；After 子集合計數為：

| 子集合 | PNG |
|---|---:|
| core routes | 6 |
| outgame | 54 |
| RUN_COMBAT | 23 |
| RUN_MAP | 12 |
| system/results | 12 |

最終文案裁決後另補 `final-copy/` 26 張（RUN_PREPARE／RUN_COMBAT 23、COLLECTION 3），
Phase D 全部 PNG 共 204 張：before 71、原 after 107、final copy 26。

## 發現與修正

| 問題 | Before | 修正 | After 結果 |
|---|---|---|---|
| RUN 頂欄中文數值在 720p／UI150 被裁切或省略 | 高縮放下 HP／金幣／人口等欄位預算不足 | `ExpeditionTopMetric` 由 Theme 統一字級，metric label 關閉 clipping／ellipsis；PREPARE 改四欄，其餘三欄 | 數值與標籤完整，未侵入中央或右欄 |
| PREPARE 空羈絆提示顯示「部署單位後顯…」 | `ItemList` 單列在窄欄省略完整文案 | 保留隱藏 `TraitList` 作完整 accessible copy；可見空狀態改成依 metrics 配額的自動換行 Label | 原文「部署單位後顯示羈絆摘要」於 720p／UI150 與 1080p／UI100 完整可讀 |
| RUN_COMBAT 檢視器的中文技能描述在窄畫布／高縮放溢出或消失 | 檢視欄直接使用不換行 label，且 route rebuild settle 太早 | 檢視 label 改任意字元換行、Theme 統一 14 px；證據 runner 等待 30 frames 取得穩定 route-local HUD | 720p／UI125、720p／UI150、1440p／UI150 均完整留在右欄，六項值可見 |
| accessibility metadata 曾暴露 loc key 而非在地化文字 | screen reader copy 取得 `*.title`／`*.prompt` 裸 key | camp／map／reward／combat metadata 改以 catalog resolve 後文字寫入 | 靜態 gate 與 accessibility focused suite 均通過，畫面文字與語意 copy 同源 |
| faction 正式四字名在共用商店卡徽章被裁切 | 最終補圖 runner 六組回報 `TraitName` clipped；原徽章固定 76 px | `SHOP_CARD_TRAIT_BADGE_WIDTH` 經 `ExpeditionLayoutMetrics` 調為 96 px，未縮字、未放寬 runner | PREPARE／COMBAT 六組 `clipped_labels=[]`，23 張 report `ok=true` |
| 單位詳情仍顯示 effect placeholder | canonical `loc.ability_*_description` 已定稿，但 RUN_COMBAT 實際讀 `loc.effect_*_primary` | 同一份核可 copy 機械同步到 44 個既有 display alias；不新增 key | 詳情顯示「對目前目標造成『自身攻擊力＋48』點物理傷害」，720p／UI150 完整換行 |

## 人工檢視結論

- 未見 fallback 方框、缺字 tofu 或錯誤英文字形；既有內嵌 Noto Sans TC 覆蓋有效。
- After 的主要決策文字無截斷；捲動區、卡片、地圖節點與戰鬥世界層無互相遮蓋。
- RUN_COMBAT 最窄／最高縮放案例的右欄檢視器、商店帶與 VFX 仍各自落在安全區。
- RUN_MAP 的 primary graph 保持可讀；右側文字清單仍是同步的無障礙次要通道。
- 四組結構化 evidence report（局外、RUN_COMBAT、RUN_MAP、system/results）均
  `ok=true`、`issues=[]`；core route 代表圖以人工 read-back 驗證。
- 最終補圖的 run 23／23 與 collection 3／3 均 `ok=true`、`issues=[]`；人工檢視
  720p／UI100、720p／UI150、1080p／UI100、1440p／UI100 代表圖無截斷或 fallback 字符。

代表修正圖：

- [PREPARE 720p／UI150](./walkthrough-after/core-routes/prepare-720p-ui150.png)
- [PREPARE 1080p／UI100](./walkthrough-after/core-routes/prepare-1080p-ui100.png)
- [RUN_COMBAT 720p／UI150](./walkthrough-after/run-combat/run-combat-720p-ui150.png)
- [RUN_MAP 720p／UI150](./walkthrough-after/run-map/run-map-720p-ui150.png)
- [最終 PREPARE 羈絆卡 1080p／UI100](./final-copy/run/shop-prepare-1080p-ui100.png)
- [最終 RUN_COMBAT 詳情 720p／UI150](./final-copy/run/run-combat-720p-ui150.png)
- [最終圖鑑 1080p／UI100](./final-copy/collection/collection-1080p-ui100.png)
