# PROGRESS — 遠征棋 (Expedition Chess)

> PVE 自走棋 Roguelite。本檔記錄專案進度;規格的單一事實來源是 `docs/game-architecture/`。

## 目前狀態

主體架構規格 v0.2 已標記 `Approved`。S1 `foundation-core`、S2 `combat-core` 均完成；S3 `economy-expedition` 階段 0～6 與獨立 T00R／T11B 已完成，包含 pinned 經濟／reward catalog、決定性三幕地圖、戰鬥與非戰鬥節點、商店、戰果 exactly-once 結算、持久獎勵、Expedition Lab 與正式 runners。最新 10,000-seed 完整拓樸／reservation-ledger soak 已通過。

## 已完成

- [2026-07-23] ✅ S4 wave2（T02 戰鬥編譯器／T03 鍛造／T06 遺物作用點／T08 內容 pack） — BattleSetupSourceCompiler（羈絆計數/戰前快照/裝備/battle 遺物編譯，preview 與開戰同源）；ForgeEquipmentCommand（21 配方、自配、serial/overflow）；遺物 run-layer 作用點（income add_gold／shop 折扣拆新 kind shop_discount／map route 覆寫無新 entropy／settlement 治療與減傷，槽序升序、不經 EffectResolver）；首批正式內容 `content/packs/build_systems/` 90 個 .tres（12 羈絆/6 零件/21 裝備/16 遺物四類/拆卸道具/效果）。雙審（Opus＋Sonnet）W2-F1~F3/F6 裁決全修：帶裝備開戰路徑修通（validator 依 design §4 對齊）、builder 拒不支援 intent、4 件死內容遺物修正、NORMAL/ELITE 規則數不變式。Gut 333/333、`-Suite All` exit 0、10000-seed soak exit 0。
- [2026-07-23] ✅ S4 wave1（T01 catalog 擴充／T04 裝備 command／T07 驗證器五規則） — BattleRelicRule＋ForgeRecipeTable（21 封閉、1/2 元形狀）＋RunRelicTable（typed intent）；EquipItemCommand／DismantleEquipmentCommand（ConsumableRuleTable 驗拆卸語意）＋validator「綁定物必為 EquipmentDef」不變式接入 RunController commit 路徑（含 catalog 世代守衛）；內容驗證器新增 unique_group／遺物四類覆蓋／effect scope／拆卸語意／零件發放五類規則。TDD 分代理紅綠證據齊備；Sonnet＋Opus 雙審 F1~F5 全數修復。Gut 275 tests／3993 asserts 全綠；`-Suite All` exit 0。
- [2026-07-22] 📄 交接分工與 S4 規格 — 確立 Claude（程式邏輯／架構／ViewModel 介面層）與 Codex（美術／UI 視覺／UX）分工並落檔 `HANDOFF.md`；S4 `build-systems` 三件套（requirements／design／tasks，12 任務 5 Gate）經逐段核可後落檔 `specs/build-systems/`。修正本檔 S4 名稱（原誤植 `content-systems`）。實作雙審改採 Sonnet 5＋Opus 4.8 兩獨立 session（使用者裁決，取代 Codex review）。
- [2026-07-22] ✅ S3 `economy-expedition` 階段 4～6與獨立複檢 — 完成戰敗扣血／幕補助／Boss 無收入重戰、勝利 scalar claim、標準／遺物 reward stage、棋子／物品／遺物 overflow、不可逆 RESULTS、最終 shop release 與戰鬥／非戰鬥節點離場；新增 Expedition Lab、`Expedition`／`ExpeditionSoak` runners 與 11 條 S3-AC evidence 聚合。T00R／T11B 第五輪均為 Blocker 0／Major 0／Minor 0。最終 `-Suite All` exit 0（187.5 秒）；GUT 228 tests／3681 assertions／0 failures／0 errors／0 orphans；Spec 3170 cases／0 failures；10,000-seed soak exit 0（213 秒）、10,000 pool-conservation checks、64 deterministic replays／0 failures；S3-AC-001～011 為 11／11 pass 且 `evidence_verified=true`。
- [2026-07-18] ✅ S3 `economy-expedition` 階段 0～3 — 建立三件套與 typed economy contracts，完成三幕七層決定性 `MapService`、節點收入／首次商店、generate／refresh／buy／sell／buy XP、有限卡池與 reservation 守恆，並接入 `RunController` copy-validate-save-swap。`-Suite All` exit 0（68.9 秒）；GUT 198 tests／3373 assertions／0 failures；Spec 3095 cases／0 failures。此紀錄不代表完整 S3，階段 4～6 與獨立複檢仍待完成。
- [2026-07-16] ✅ S2 `combat-core` — 完成 setup schema 2／content codec 2／save schema 2、棋盤人口與升星守恆、pinned encounter preview、純 `BattleSimulation`、`EffectResolver` 9／10／9／4 矩陣、typed event/result codec、combat transactions/replay 與灰盒 Combat Lab。`-Suite All` exit 0（62.9 秒）；GUT 190 tests／3115 assertions／0 failures／0 errors／0 orphans；canonical 5 cases／151 assertions；32v32／64 entity stress 通過。正式 `-Suite Soak -SeedCount 10000 -TimeoutSeconds 600` exit 0（249 秒）：10,000 seeds、0 failures、最大 22 ticks、3 個 result hashes、64 次 deterministic replay；`combat-acceptance.json` 18／18 pass。最終獨立複檢 Blocker 0／Major 0。
- [2026-07-16] 📄 架構 v0.2 與 S2 規格 — 補足整數戰鬥、效果 stacking、事件／結果、版本 migration 與 DEC-014；三件套通過 Gate A 後核可。repository 僅保存 Codex 最終實作複檢紀錄，不冒充 Claude 外部報告。
- [2026-07-13] ✅ S1 `foundation-core` — 建立 Godot 4.7／GUT 9.7.1 鎖定工具鏈、`Main/AppRoot` 與五個 Autoload、u64／Stable ID／RuntimeKey／PCG32 決定性核心、canonical battle setup codec、typed DTO、內容 registry／generation pin／完整 synthetic 內容驗證、版本化原子存檔、App／Run FSM 與 copy-validate-save-swap。`-Suite All` exit 0；GUT 73 tests／667 assertions／0 failures／0 errors／0 orphans；canonical 4 cases／141 assertions；content 39 cases；spec contract 1826 cases。`foundation-acceptance.json` schema v2 逐 AC 讀回證據，F/X/D 為 15／7／11，downstream 項目未假稱通過。
- [2026-07-13] 📄 架構規格核可 — 使用者確認 Claude 外部複檢完成；repository 未虛構 review report。12 章狀態改為 `v0.1 / Approved`，Manifest 升級 schema v2 並改用只涵蓋 12 章的可重算 aggregate SHA-256。
- [2026-07-13] 📄 R2 實作切片規劃 — 建立 `docs/implementation-slices.md`,將 74 REQ 切成 5 個可獨立實作/驗收的功能片(`foundation-core` → `meta-progression`),定義每片走 specs 三件套 + `/pipeline` 的銜接流程;切片藍圖與 §14 追溯矩陣 74 REQ 一對一。
- [2026-07-13] 📄 R1 專案初始化 — 建立 PROGRESS.md、專案層 CLAUDE.md、README.md,git init;技術棧定為 Godot 4.7 + GDScript。既有 `docs/game-architecture/` 架構規格(74 REQ / 78 AC / 追溯矩陣 / Claude 複檢契約)保持不動。

## 進行中

- S4 `build-systems`（羈絆／裝備鍛造／遺物）實作——三件套規格已核可落檔（`specs/build-systems/`），依 tasks T01～T12 波次執行中。

## 待辦

- S4 接入正式羈絆、裝備、遺物與人口來源；S2 synthetic／proxy 內容不假稱正式內容完成。
- S5 與橫切工作再完成營地、局外成長、正式像素內容、最低規格效能與完整單局驗收。

## 已知問題

- Combat Lab 與 Expedition Lab 都是開發用灰盒，不是正式遊戲 UI；羈絆、正式裝備／遺物內容、RESULTS 後的 Profile settlement 與完整產品流程仍由 S4–S5／橫切工作負責。
- `AC-030` 完整單局 soak 仍是 downstream；S2 `soak.json` 的 scope 明確為 `combat-core`。
- `artifacts/test/` 是本機驗證輸出，不是正式遊戲資料；清理或重建不影響 canonical source。

## 重要決策紀錄

- [2026-07-22] S3 reward generation 的 standard stage 固定三選一且必要時保留最後一格給合法非棋子候選；event grant 使用同一 table 但只建立單一 pending offer。菁英 standard→relic 期間保留 shop，最後 stage 與 overflow 全解決後才釋放。
- [2026-07-22] RewardTable conditions 以 roster／inventory／HP／pool 決定性過濾並由 content gate 要求 stage fallback；unit-only event 在卡池耗盡時提交零效果 EVENT choice，不虛構副本。非戰鬥節點透過正式 command 離開 PREPARE，避免路線軟鎖。
- [2026-07-18] S3 階段 0～3 沿用 save schema 2；空 shop slot 以缺少該 `slot_index` 的 0～5 筆排序 offer 表示，不引入 sentinel Unit ID。地圖與商店分別只消費具名 `map`／`shop` PCG32 stream，所有提交仍走 `RunController` 原子交易。
- [2026-07-16] S2 採 20 Hz 整數累加、固定排序、PCG32 具名 combat stream、wave-start 傷害代數與版本化 event/result codec；presentation 只能消費 setup/event/result clone。
- [2026-07-16] `UnitBattleSnapshot.basic_attack_profile` 納入 setup v2 hash 與 save JSON，避免由射程猜測近戰／遠程並保留 `magic_projectile` authoring；v1 codec/golden 不變。
- [2026-07-13] S1 完成 gate 採單一 `tools/run-tests.ps1 -Suite All`，並保留 `0／2／3／124` runner contract 與 F/X/D 分類 artifact；不能用 placeholder runner 或 downstream 假通過取代。
- [2026-07-13] 存檔成功與 App 狀態轉移以 repository-issued one-time capability 綁定；active run 持有 pinned content catalog lease，避免 caller 偽造 commit 或舊 generation 被移除。
- [2026-07-13] 技術棧採 Godot 4.7 + GDScript + GUT 9.7.1 —— 依 `docs/game-architecture/05-technical-architecture.md` §8 工具鏈與 §17 外部參考,沿用 spec 既定選型。
- [2026-07-13] 開發路徑採「架構規格先行 → REQ 切成功能切片 → 各切片走 specs 三件套 → /pipeline 實作雙審」—— 銜接既有藍圖級架構規格與功能級規格驅動開發。
- [2026-07-13] 專案代號定為「遠征棋 (Expedition Chess)」—— 取 spec §4「遠征」單局結構 + 自走棋核心兩大識別特徵。
