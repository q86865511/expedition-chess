# PROGRESS — 遠征棋 (Expedition Chess)

> PVE 自走棋 Roguelite。本檔記錄專案進度;規格的單一事實來源是 `docs/game-architecture/`。

## 目前狀態

主體架構規格 v0.1 已完成外部複檢並標記 `Approved`。S1 `foundation-core` 已完成並通過完整 headless gate；目前只有 domain foundation 與最小 AppRoot，尚不可遊玩。下一步是建立並複檢 S2 `combat-core` 三件套。

## 已完成

- [2026-07-13] ✅ S1 `foundation-core` — 建立 Godot 4.7／GUT 9.7.1 鎖定工具鏈、`Main/AppRoot` 與五個 Autoload、u64／Stable ID／RuntimeKey／PCG32 決定性核心、canonical battle setup codec、typed DTO、內容 registry／generation pin／完整 synthetic 內容驗證、版本化原子存檔、App／Run FSM 與 copy-validate-save-swap。`-Suite All` exit 0；GUT 73 tests／667 assertions／0 failures／0 errors／0 orphans；canonical 4 cases／141 assertions；content 39 cases；spec contract 1826 cases。`foundation-acceptance.json` schema v2 逐 AC 讀回證據，F/X/D 為 15／7／11，downstream 項目未假稱通過。
- [2026-07-13] 📄 架構規格核可 — 使用者確認 Claude 外部複檢完成；repository 未虛構 review report。12 章狀態改為 `v0.1 / Approved`，Manifest 升級 schema v2 並改用只涵蓋 12 章的可重算 aggregate SHA-256。
- [2026-07-13] 📄 R2 實作切片規劃 — 建立 `docs/implementation-slices.md`,將 74 REQ 切成 5 個可獨立實作/驗收的功能片(`foundation-core` → `meta-progression`),定義每片走 specs 三件套 + `/pipeline` 的銜接流程;切片藍圖與 §14 追溯矩陣 74 REQ 一對一。
- [2026-07-13] 📄 R1 專案初始化 — 建立 PROGRESS.md、專案層 CLAUDE.md、README.md,git init;技術棧定為 Godot 4.7 + GDScript。既有 `docs/game-architecture/` 架構規格(74 REQ / 78 AC / 追溯矩陣 / Claude 複檢契約)保持不動。

## 進行中

（無；S1 已完成，等待使用者決定是否啟動 S2 規格。）

## 待辦

- 建立 S2 `combat-core` 的 `requirements.md`、`design.md`、`tasks.md`，對齊 BOARD／UNIT／COMBAT／ENEMY／EFFECT 共 16 條架構需求；三件套通過獨立複檢後再實作。
- S2 才實作 `BattleSimulation` 與 `EffectResolver`、canonical `BattleResult`／事件摘要及戰鬥壓測；S1 artifact 中相關 AC 維持 downstream。
- S3 才實作 `ShopService`、經濟與完整遠征結算；不在 S2 提前加入假成功介面。

## 已知問題

- S1 不包含可玩內容；戰鬥、商店、經濟、羈絆、正式 UI、正式內容與 soak 仍由 S2–S5／橫切工作負責。
- `artifacts/test/` 是本機驗證輸出，不是正式遊戲資料；清理或重建不影響 canonical source。

## 重要決策紀錄

- [2026-07-13] S1 完成 gate 採單一 `tools/run-tests.ps1 -Suite All`，並保留 `0／2／3／124` runner contract 與 F/X/D 分類 artifact；不能用 placeholder runner 或 downstream 假通過取代。
- [2026-07-13] 存檔成功與 App 狀態轉移以 repository-issued one-time capability 綁定；active run 持有 pinned content catalog lease，避免 caller 偽造 commit 或舊 generation 被移除。
- [2026-07-13] 技術棧採 Godot 4.7 + GDScript + GUT 9.7.1 —— 依 `docs/game-architecture/05-technical-architecture.md` §8 工具鏈與 §17 外部參考,沿用 spec 既定選型。
- [2026-07-13] 開發路徑採「架構規格先行 → REQ 切成功能切片 → 各切片走 specs 三件套 → /pipeline 實作雙審」—— 銜接既有藍圖級架構規格與功能級規格驅動開發。
- [2026-07-13] 專案代號定為「遠征棋 (Expedition Chess)」—— 取 spec §4「遠征」單局結構 + 自走棋核心兩大識別特徵。
