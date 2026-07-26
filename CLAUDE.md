# CLAUDE.md — 遠征棋 (Expedition Chess)

> 一款 PVE 自走棋 Roguelite（Godot 4.7 + GDScript）。本檔只放專案特有約定;全域規則見 `~/.claude/CLAUDE.md`,不重複。

## 專案簡介

每局是一次「遠征」:玩家透過自動戰鬥、局內棋子 / 羈絆 / 裝備 / 遺物組 build、局外營地水平成長推進。規格的單一事實來源是 `docs/game-architecture/`(入口 `docs/game-architecture-spec.md`)。

## 規格與實作的對照

- **單一事實來源**:`docs/game-architecture/` 的 12 分章(section 0~17)。實作前先對照對應需求;需求以 `REQ-*`、驗收以 `AC-*` 編號,§14 追溯矩陣是需求↔驗收的權威映射。
- 改動遊戲規則 / 數值 / 技術決策時,先改 spec、同步 §14 矩陣,再改程式。標 `TUNE` 的值可資料調整,固定規則不可。
- spec 的審查與完成標準見 §15(Claude 複檢契約)、§16(文件完成定義)。

## 常用指令

- **完整快速 gate**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite All`
- **S2 正式 soak**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Soak -SeedCount 10000 -TimeoutSeconds 600`
- **S3 正式 soak**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite ExpeditionSoak -SeedCount 10000 -TimeoutSeconds 600`
- **單一 runner**：將 `All` 改成 `Toolchain`、`Import`、`Smoke`、`Gut`、`Content`、`Canonical`、`Combat`、`Soak`、`Expedition`、`ExpeditionSoak`、`Spec` 或 `RunnerContract`。
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
- `BattleSimulation`／`EffectResolver` 已由 S2 實作；兩者只讀 hashed `BattleSetup` 與 pinned rules，不得讀 latest catalog 或 presentation mutable state。
- `ShopService`、三幕地圖、節點收入與戰果／遠征 HP／獎勵 exactly-once 結算已由 S3 實作；S2 只產生 canonical result/proposal，只有 S3 settlement/reward transaction 可提交局內持久變更。
- S4 羈絆／裝備／遺物與 S5 局外成長已完成；AppRoot 是 CAMP↔RUN↔RESULTS 唯一 composition root，四個 run command 由 `RunCommandFactory` 顯式注入 pinned `relic_table`。
- 所有一般 Camp writer 必須 fresh load 且只在 `RunStatus.NONE` 時寫入；decoded retained run 只能 expected-run-id 明示棄置，`INCOMPATIBLE_PRESERVED` 必須保留並 boot failure。

## 文件工作流

- 進度記於 `PROGRESS.md`(六區段);用 `/save-progress` 累積、`/sync-notion` 同步 Notion。
- Claude／Codex 分工邊界與 presentation 消費契約見 `HANDOFF.md`;跨方交接（邏輯 vs 美術/UI）先讀該檔。
- 功能級開發用 `specs/<功能名>/` 三件套(requirements / design / tasks),餵 `/pipeline`。
- 架構規格 → 實作的切片規劃見 `docs/implementation-slices.md`(74 REQ 切成 5 個功能片 + 銜接流程);要實作某片時照它走三件套。

## 目前切片

- S1 `foundation-core`：已完成；規格位於 `specs/foundation-core/`。
- S2 `combat-core`：已完成；規格與複檢紀錄位於 `specs/combat-core/`，完成證據位於 `artifacts/test/`。
- S3 `economy-expedition`：階段 0～6、逐 AC 證據與獨立 T00R／T11B 已完成；複檢紀錄位於 `specs/economy-expedition/final-review.md`。
- S4 `build-systems`：已完成（2026-07-24）；規格與複檢紀錄位於 `specs/build-systems/`（三件套＋implementation-review.md）。
- S5 `meta-progression`：已完成實作（2026-07-26）；T01～T12、S5-AC 14/14、Gut 737/737、10k ExpeditionSoak、All 與 W5 R4 雙審通過；證據位於 `specs/meta-progression/implementation-review.md`。
