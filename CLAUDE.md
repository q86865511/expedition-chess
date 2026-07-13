# CLAUDE.md — 遠征棋 (Expedition Chess)

> 一款 PVE 自走棋 Roguelite（Godot 4.7 + GDScript）。本檔只放專案特有約定;全域規則見 `~/.claude/CLAUDE.md`,不重複。

## 專案簡介

每局是一次「遠征」:玩家透過自動戰鬥、局內棋子 / 羈絆 / 裝備 / 遺物組 build、局外營地水平成長推進。規格的單一事實來源是 `docs/game-architecture/`(入口 `docs/game-architecture-spec.md`)。

## 規格與實作的對照

- **單一事實來源**:`docs/game-architecture/` 的 12 分章(section 0~17)。實作前先對照對應需求;需求以 `REQ-*`、驗收以 `AC-*` 編號,§14 追溯矩陣是需求↔驗收的權威映射。
- 改動遊戲規則 / 數值 / 技術決策時,先改 spec、同步 §14 矩陣,再改程式。標 `TUNE` 的值可資料調整,固定規則不可。
- spec 的審查與完成標準見 §15(Claude 複檢契約)、§16(文件完成定義)。

## 常用指令

- **完整 S1 gate**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite All`
- **單一 runner**：將 `All` 改成 `Toolchain`、`Import`、`Smoke`、`Gut`、`Content`、`Canonical`、`Spec` 或 `RunnerContract`。
- **限定 GUT 目錄**：加上 `-TestPath res://tests/<path>`；canonical／content 可用 `-Case <case>`。
- Godot executable 由環境變數 `GODOT_BIN` 或 wrapper 的 `-GodotPath` 傳入；不得把本機絕對路徑寫進 repository。
- Runner artifacts 位於 `artifacts/test/`；退出碼固定為 `0／2／3／124`。

## 架構約定

<!-- 隨實作累積;初期骨架對應 spec §8 -->

- 狀態擁有權：canonical `RunState` 由 `RunController` 以 copy-validate-save-swap 交易更新；presentation 與 domain service 不得保留可變引用（spec §8.5、REQ-TECH-004）。
- `Main/AppRoot` 是 composition root；只允許 `ContentRegistry`、`SaveService`、`SettingsService`、`AudioService`、`SceneRouter` 五個 Autoload，instance name 不得與 `class_name` 相同。
- JSON `Dictionary` 僅能存在 `SaveJsonCodec` 邊界；公開 domain API 使用具名型別與 typed collection。
- 所有決定性亂數使用 `RngService` 的 `map/shop/reward/combat` stream；不得使用 Godot `rand*`、時間或 Object ID 產生 gameplay entropy。
- 內容以 immutable-style Resource authoring、canonical snapshot 與 pinned manifest digest 傳遞；舊 run 必須持有 catalog lease。
- `ShopService`、`BattleSimulation`、`EffectResolver` 屬後續切片；S1 禁止建立假成功 stub。

## 文件工作流

- 進度記於 `PROGRESS.md`(六區段);用 `/save-progress` 累積、`/sync-notion` 同步 Notion。
- 功能級開發用 `specs/<功能名>/` 三件套(requirements / design / tasks),餵 `/pipeline`。
- 架構規格 → 實作的切片規劃見 `docs/implementation-slices.md`(74 REQ 切成 5 個功能片 + 銜接流程);要實作某片時照它走三件套。

## 目前切片

- S1 `foundation-core`：已完成；規格位於 `specs/foundation-core/`。
- 下一片 S2 `combat-core`：尚未建立功能規格或實作。開始前先依架構需求建立三件套並通過獨立複檢。
