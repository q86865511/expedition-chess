# PROGRESS — 遠征棋 (Expedition Chess)

> PVE 自走棋 Roguelite。本檔記錄專案進度;規格的單一事實來源是 `docs/game-architecture/`。

## 目前狀態

專案剛初始化基礎文件;主體架構規格 v0.1 已完成、標記 Ready for external review,尚未開始程式實作。

## 已完成

- [2026-07-13] 📄 R2 實作切片規劃 — 建立 `docs/implementation-slices.md`,將 74 REQ 切成 5 個可獨立實作/驗收的功能片(`foundation-core` → `meta-progression`),定義每片走 specs 三件套 + `/pipeline` 的銜接流程;切片藍圖與 §14 追溯矩陣 74 REQ 一對一。
- [2026-07-13] 📄 R1 專案初始化 — 建立 PROGRESS.md、專案層 CLAUDE.md、README.md,git init;技術棧定為 Godot 4.7 + GDScript。既有 `docs/game-architecture/` 架構規格(74 REQ / 78 AC / 追溯矩陣 / Claude 複檢契約)保持不動。

## 進行中

（無）

## 待辦

- 補文件驗證器腳本(讀 spec manifest,一鍵驗 12 檔的計數 / section 錨點 / ID 唯一性 / 跨檔連結 / 追溯覆蓋)—— 對應 spec 檢驗建議 1,把 §16 完成定義變成可執行。
- 為選定切片走 specs 三件套 + `/pipeline` 實作(切片藍圖見 `docs/implementation-slices.md`,建議首片 `foundation-core`)—— 對應 spec 檢驗建議 4;切片規劃已完成,實作依當前選擇暫緩。
- 完成架構規格 v0.1 的外部複檢(依 §15 Claude 複檢契約)。

## 已知問題

- SHA-256 內容守恆基線是「拆分前」快照,拆分成 12 檔後不可持續驗證,正文一經修訂即失效(spec 檢驗建議 2)。
- 數條核心 invariant（Boss 重戰無收入、連敗補助、最大人口、EncounterPreviewSnapshot 共用）跨 4+ 檔重複詳述,改動時有 desync 風險(spec 檢驗建議 3)。

## 重要決策紀錄

- [2026-07-13] 技術棧採 Godot 4.7 + GDScript + GUT 9.7.1 —— 依 `docs/game-architecture/05-technical-architecture.md` §8 工具鏈與 §17 外部參考,沿用 spec 既定選型。
- [2026-07-13] 開發路徑採「架構規格先行 → REQ 切成功能切片 → 各切片走 specs 三件套 → /pipeline 實作雙審」—— 銜接既有藍圖級架構規格與功能級規格驅動開發。
- [2026-07-13] 專案代號定為「遠征棋 (Expedition Chess)」—— 取 spec §4「遠征」單局結構 + 自走棋核心兩大識別特徵。
