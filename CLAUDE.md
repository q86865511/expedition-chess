# CLAUDE.md — 遠征棋 (Expedition Chess)

> 一款 PVE 自走棋 Roguelite（Godot 4.7 + GDScript）。本檔只放專案特有約定;全域規則見 `~/.claude/CLAUDE.md`,不重複。

## 專案簡介

每局是一次「遠征」:玩家透過自動戰鬥、局內棋子 / 羈絆 / 裝備 / 遺物組 build、局外營地水平成長推進。規格的單一事實來源是 `docs/game-architecture/`(入口 `docs/game-architecture-spec.md`)。

## 規格與實作的對照

- **單一事實來源**:`docs/game-architecture/` 的 12 分章(section 0~17)。實作前先對照對應需求;需求以 `REQ-*`、驗收以 `AC-*` 編號,§14 追溯矩陣是需求↔驗收的權威映射。
- 改動遊戲規則 / 數值 / 技術決策時,先改 spec、同步 §14 矩陣,再改程式。標 `TUNE` 的值可資料調整,固定規則不可。
- spec 的審查與完成標準見 §15(Claude 複檢契約)、§16(文件完成定義)。

## 常用指令

<!-- Godot 專案尚未建立(無 project.godot);待建立後補實際指令 -->

- **執行**:TODO — 建立 Godot 專案後,以 Godot 4.7 開啟 `project.godot`,或 headless 跑遠征入口。
- **測試**:TODO — GUT 9.7.1;spec §11.4 要求固定 headless 測試入口,建立後補指令。
- **內容驗證**:TODO — spec §11.2 內容驗證器;匯出前以非零退出碼阻擋無效內容(REQ-QA-001)。

## 架構約定

<!-- 隨實作累積;初期骨架對應 spec §8 -->

- 狀態擁有權:canonical RunState 由 RunController 以 copy-validate-save-swap 交易更新;UI 與 domain service 不得保留可變引用(spec §8.5、REQ-TECH-004)。
- 模組分層與資料流見 spec §8.3;Autoload 清單見 §8.5。
- 內容以 Resource 定義、執行期以 DTO 傳遞(spec §8.8、§8.9)。

## 文件工作流

- 進度記於 `PROGRESS.md`(六區段);用 `/save-progress` 累積、`/sync-notion` 同步 Notion。
- 功能級開發用 `specs/<功能名>/` 三件套(requirements / design / tasks),餵 `/pipeline`。
- 架構規格 → 實作的切片規劃見 `docs/implementation-slices.md`(74 REQ 切成 5 個功能片 + 銜接流程);要實作某片時照它走三件套。
