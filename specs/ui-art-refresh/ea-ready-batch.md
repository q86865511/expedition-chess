# 體驗版整備批次（EA-ready，Phase E）

> 依 2026-08-20 美術上板審核（Claude 逐畫面檢視 Phase D／B-out／C 證據）與使用者裁決制定：
> 設施頁採「補內容框架」、P0＋P1 全收同一批。執行時機：44 單位命名裁決之後，
> 與命名 reseal 併為同一批（單次 catalog reseal、單輪視覺閘門）。

## 目標

體驗版上板前的最後一輪 UI 整備：清除「玩家會判定壞掉」的 P0 與觀感層 P1，
含 44 單位正式名落地。完成後 UI 線進入凍結，只留 bug 修。

## P0（上板阻擋）

| # | 項目 | 內容 | 依據 |
|---|---|---|---|
| P0-1 | 設施頁內容框架 | 共用 `presentation/screens/camp_facility_screen.gd` 裝修一次、四頁受益：每頁＝頂部統計卡＋清單＋空狀態文案。挑戰紀念碑＝最高挑戰等級卡＋逐指揮官紀錄表（`profile.commander_challenge_records`）；解鎖工坊＝工坊貨幣卡＋解鎖項目清單（`unlocked_content_ids`，含鎖定態顯示）；指揮官大廳＝指揮官立繪卡片；遠征之門＝上次出征摘要（`last_selection`）＋指揮官卡片。資料源限 `ProfileState` 既有欄位（clone-only，經 `CampFacilityBundle` 擴充讀取面），不新增 domain API | phase-d after：四頁僅懸浮「0」／「指揮官 1」 |
| P0-2 | 結算頁去除開發資訊 | `settlement_receipt_<64hex>` 不得直接顯示於主畫面；移除或收進 tooltip／詳情摺疊 | results-1080p |
| P0-3 | 戰鬥單位詳情格式化 | 右側詳情由逗號串 dev dump 改分欄標籤排版；「千分比」內部單位轉玩家可讀（攻速／移速）；空值欄位隱藏或給標籤，不再裸「無」 | run-combat 全組 |
| P0-4 | 44 單位正式名落地 | 依使用者裁決結果走既有 exporter＋bootstrap SHA reseal 配方；與本批其他 loc 變更（P1-6）併同一次 reseal | copy-debt 後續批 |

## P1（同批打磨）

| # | 項目 | 內容 |
|---|---|---|
| P1-1 | 備戰商店面板 | 底部按鈕截斷修正（購買經驗值等；720p×150% 為最壞案例）；移除棋盤中央與頂欄重複的「遠征資訊」資訊行 |
| P1-2 | 地圖右欄與底欄 | 節點清單去重語（節點種類只顯示一次）＋加節點圖示；底部三顆通欄大按鈕高度縮減至合理操作列 |
| P1-3 | 獎勵列視覺化 | 獎勵選項加內容圖示（單位立繪縮圖／物品圖示）與類型徽章，不再純文字列 |
| P1-4 | bench 空槽 | 戰鬥下方與備戰 bench 空槽改框線＋淡化槽位圖示語言，不再顯示文字「無」 |
| P1-5 | 圖鑑 | 搜尋框 placeholder 文案；格線密度與留白調整；「選擇兩個項目進行比較」提示整合進版面 |
| P1-6 | 主選單標題 | 「遠征主選單」改遊戲名「遠征棋」（loc 值變更，併入 P0-4 同次 reseal） |
| P1-7 | 營地設施標籤 | 大塊實心色板縮小／半透明化（描邊小標籤方向），讓場景美術呼吸 |
| P1-8 | ESC 營地 overlay 頂欄 | camp-menu-entry 所示：overlay 開啟時頂欄按鈕與貨幣列重疊修正 |

## 邊界與守衛（沿用 UI 線既有紀律）

- presentation-only；domain 零改動；HANDOFF §2 消費契約（clone-only、五 Autoload、
  `ExpeditionLayoutMetrics` 登記、禁 gameplay RNG）。
- loc／catalog 變更僅 P0-4＋P1-6，單次 reseal（catalog → exporter 重導 CSV/raw → bootstrap SHA），
  其餘 app/ 不動。
- 驗收：focused 套件綠、loc parity＋引用 gate 綠、`-Suite Smoke` exit 0、fresh `-Suite All` exit 0；
  逐畫面 before/after 截圖（1080p ui100 全套＋720p ui150 抽驗）落
  `specs/ui-art-refresh/evidence/ea-ready/`，停使用者視覺核可閘門。
- P0-1 若需擴充 `CampFacilityBundle` 讀取面，維持 clone-only 投影，附對應單元測試。

## 上板檢查表（批次完成後）

- [ ] P0-1～P0-4 視覺核可
- [ ] P1-1～P1-8 視覺核可（個別項可依裁決降級為「接受現狀」）
- [ ] fresh All＋10k soak（若涉 save/catalog）綠
- [ ] PROGRESS／roadmap 收斂，UI 線凍結
