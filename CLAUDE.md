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
- **單一 runner**：將 `All` 改成 `Toolchain`、`Import`、`Smoke`、`Gut`、`Content`、`Canonical`、`Combat`、`Soak`、`Expedition`、`ExpeditionSoak`、`BalancePlaytest`、`Spec` 或 `RunnerContract`。
- **BalancePlaytest targeted suite**（只跑 balance_playtest 測試目錄，不含大樣本 bot 跑批）：
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Gut -TestPath res://tests/unit/balance_playtest`
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
- UI 設計基準畫布為 1920×1080（支援 1280×720 與 2560×1440）；世界層解析度必須在所有支援輸出下皆為整數倍。呈現層尺寸一律經 `ExpeditionLayoutMetrics` 登記，不得直接寫 `custom_minimum_size`（spec §10.1、DEC-015）。
- 棋盤與其上的單位由世界層以 3/4 投影渲染，UI 層只疊血條、選取框與拖曳預覽；格位權威在 domain，反投影結果須經 domain 合法性檢查後才採用，且不得回寫 domain。
- 局內的返回主選單、設定與離開遊戲由 ESC 系統選單覆蓋層提供，不常駐於操作列；拖曳只映射既有 intent，不得新增或修改 domain command（spec §10.7、REQ-UX-006）。

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
- G2 `presentation-ui`：T00～T15、R12～R16 findings closure 與 final evidence 已完成；
  T13 視覺樣板獲使用者核可。PR #5 已合併為 9362e7d；merge 後 UI 審查修正由
  PR #6 合併為 5e78ccf，fresh All 為 Gut 1000/1000。原 review verdict 與
  closure table 均保留。
- G2 `content-production`:實作與 T25 三輪雙審已閉環(2026-08-01,分支
  `codex/g2-content-production` 10 個檢查點 commit);codec 3、save schema 4、
  codec 2→3 production migration、44 單位內容、node-choice 交易鏈、
  T24 acceptance(21+1 列)全數落地,fresh 全綠(Gut 1091、10k soak、All exit 0)。
  PR #8 已合併至 `master@bf818fb`。
- G2 `balance-playtest`:已完成（2026-08-04，PR #9 合併至 `master@24edea9`）;driver
  重寫走正式 RunController 鏈路、51 檔 content 修正、3k screening #2 gate PASS、
  Phase 0 雙審雙 APPROVED（含 BP-SI-007 StringName 排序決定性修正）。大樣本依裁決
  延後至 Phase 2。Phase 0~3 roadmap 見 `specs/g2-roadmap.md` §9。
- G2 `difficulty-curve`（`codex/g2-difficulty-curve`，進行中）:幕間難度縮放、三幕
  Boss 差異化、多敵遭遇、trait 門檻階梯、tier-1 池重標、challenge run-op 回鏈;
  規格位於 `specs/difficulty-curve/`。
- G2 `in-run-hud`（`codex/g2-ui-art-refresh-b`，**已完成** 2026-08-13：T31 收斂
  `7ff8db9`、T32 APPROVED，台帳 PASS 17／PARTIAL 0／BLOCKED 0；REWARD 依裁決
  接受 typed fixture）:局內四個
  route 全面重製、UI 基準改 1920×1080 並支援 2560×1440、棋盤移世界層 3/4 投影、
  ESC 系統選單、棋子與裝備拖曳（含合成）。規格位於 `specs/in-run-hud/`
  （三件套＋`layout-reference-1920.json`）;實作交 Codex，`T01` 備戰期屬性預覽 API 由
  Claude 執行。依使用者裁決，`ui-art-refresh` Phase B1R3 樣板不再作為基線。
