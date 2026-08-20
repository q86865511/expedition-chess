# zh_TW 走查前證據

本目錄保存 Phase D 修改前、使用正式 zh_TW catalog 與 production route runners 取得的畫面。覆蓋 outgame 六 route、system/results、RUN_MAP 九組矩陣、RUN_COMBAT 九組矩陣與互動／播放序列；`core-routes/` 另保存主選單、PREPARE、REWARD 的 720p/UI150 壓力組與 1080p/UI100 對照。

走查確認的可修問題：

- RUN_MAP／RUN_COMBAT／RUN_REWARD 非 PREPARE route 的頂欄仍以四欄配置三個資源，造成「等級／經驗」不必要省略。
- PREPARE 的空羈絆說明在 720p/UI150 ItemList 內顯示為「部署單位後顯…」。
- catalog 內嵌 Noto Sans TC 能覆蓋目前截圖文字；全 catalog glyph gate 另以程式化測試補齊畫面未必出現的字符。

舊 B1 runner 的完整暫存輸出未保留：它成功產生截圖，但其 C-2 前商店卡標籤斷言與目前共用 shop-card 規格不相容，runner exit 2；必要的六張 PNG 已逐檔核對 SHA 後搬入本目錄，原未追蹤暫存目錄已刪除。
