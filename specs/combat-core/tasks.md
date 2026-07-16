# S2 `combat-core` 實作任務

> 狀態：`Completed / verified 2026-07-16`
> HARD/NORMAL 標記不可在實作中靜默降級；每項完成後附實際命令與 artifact。

## Gate A — 規格與架構（HARD）

- [x] **T00 [HARD] 建立三件套與雙向追溯**
  - Covers：16 條 traced REQ、S2-AC-001–018
  - 驗收：需求→設計→任務與反向掃描零孤兒；12 full／4 partial 與 downstream owner 明列。
- [x] **T01 [HARD] 架構 v0.2 相容性增補**
  - Covers：REQ-COMBAT-002/003/005、REQ-EFFECT-001/002
  - 交付：攻速/移速/回魔/減傷/stacking/event/result 語意、DEC-014、版本矩陣、Manifest/hash。
- [x] **T02 [HARD] 獨立規格複檢**
  - 驗收：依 review contract 產生 decision table；Blocker=0、Major=0 才允許 T03。

## Gate B — 版本、內容與 setup（HARD）

- [x] **T03 [HARD] content codec v2 與 CombatConfigDef**
  - Covers：S2-AC-002、006、007
  - 驗收：v1 golden 不變；v2 category/config/Boss source round-trip、negative、catalog A/B pinning。
- [x] **T04 [HARD] save schema 2 migration**
  - Covers：S2-AC-014、016
  - 驗收：0→1→2、1→2、2→2冪等；僅idle MAP/no-node/no-preview可用old generation＋allowlisted Config/Boss mapping原子升版；BSM1/CGM1/CGR1 golden與逐欄negative；PREPARE/preview/pending/缺pack一律incompatible-preserved；ProposalSource/RMP2 exact schema。
- [x] **T05 [HARD] BattleSetup v2 codec/hash**
  - Covers：S2-AC-007
  - 驗收：11頂層欄、exact六版本tuple、hashed七類effect source owner/slot mapping＋reload golden、expanded rules＋summon transitive closure、enemy preview authority、hash-before-seed、envelope digest、從run seed重派生逐位比對、wrong generation/tuple negative。
- [x] **T06 [NORMAL] BattleRuleCatalog typed decoder**
  - Covers：S2-AC-006、010、013
  - 驗收：Unit/Trait/Ability/Effect/Encounter/Equipment/Config clone isolation與pinning；summon reachable refs不得fallback latest。

## Gate C — 備戰與遭遇（HARD）

- [x] **T07 [HARD] 棋盤/人口/板凳 validator**
  - Covers：S2-AC-001–003
  - 驗收：all-error report、12/13、32 physical bound、compact order、population stress recompute。
- [x] **T08 [HARD] UnitMergeService 與守恆**
  - Covers：S2-AC-004、005
  - 驗收：1→2→3 chain、主體排序、serial、equipment/inventory/overflow、pool ledger、reload。
- [x] **T09 [HARD] Encounter compiler/preview**
  - Covers：S2-AC-006
  - 驗收：request source scan禁roster/build/RNG；BEI1/BSI1 strict-ASCII golden、collision fatal、summon per-source serial/active-key/failure precedence與rollback；Boss phase source；preview/setup/UI同generation。
- [x] **T10 [NORMAL] CommitBoardLayoutCommand**
  - Covers：S2-AC-003、016
  - 驗收：成功 single swap；validation/tmp/final-read failure zero mutation。

## Gate D — 模擬與效果（HARD）

- [x] **T11 [HARD] BattleSimulation lifecycle/state/tick pipeline**
  - Covers：S2-AC-008、011、018
  - 驗收：pure RefCounted、step=1 tick、UNINITIALIZED/RUNNING/FINISHED/FAILED exact lifecycle、fatal diagnostic/replay、typed state、budget accounting、1800 bound。
- [x] **T12 [HARD] target/path/movement/action progress**
  - Covers：S2-AC-009
  - 驗收：all tie fixtures、corner cut、batch occupancy、effect multi-cell move、progress cap/zero speed、stat recompute、cast lock/fizzle、first tick、one action/tick。
- [x] **T13 [HARD] damage/mana/shield/death/overtime/result**
  - Covers：S2-AC-010–012
  - 驗收：正負resist與post-resistance event、three damage types、wave damage/heal/shield algebra、overkill/killer/mana、duration expiry、boss phase、overtime、expedition damage。
- [x] **T14 [HARD] EffectResolver 與 runtime budget**
  - Covers：S2-AC-013、014
  - 驗收：9/10/9/4 matrix、source lifecycle matrix、typed event proposals、ProposalSourceCodec、summon ID/collision/rollback、finite enums、cycle/budget validator、unknown/partial/RNG rollback。
- [x] **T15 [HARD] BattleEvent/Result codec 與 canonical hash**
  - Covers：S2-AC-008、015
  - 驗收：14 event type/action payload round-trip、event mini-sequence與terminal=result invariant、六版本tuple、unknown negative、summary/full-result/receipt golden。

## Gate E — 交易、恢復與 Lab（HARD）

- [x] **T16 [HARD] StartCombatEvent/RecordBattleResultCommand**
  - Covers：S2-AC-016
  - 驗收：PREPARE→唯一BattleSetup envelope的combat_pending→唯一BattleResult的battle_result_pending；rederive envelope/receipt binding；expected/result/recomputed/receipt四hash逐欄相等negative；兩提交點fault injection；terminal outcome只在result save後發布；不做S3結算。
- [x] **T17 [HARD] CombatCoordinator replay**
  - Covers：S2-AC-008、016
  - 驗收：combat_pending reload重播；result pending不重跑；1×/4×/reload一致；committed result後才勝負呈現。
- [x] **T18 [NORMAL] 灰盒 Combat Lab**
  - Covers：S2-AC-006、017
  - 驗收：8×8/bench/preview/start/pause/speeds/detail/log；presentation source scan無simulation mutable read。
- [x] **T19 [NORMAL] 代理內容**
  - Covers：S2-AC-006、010、017
  - 驗收：8 playable、normal、two-phase boss、24 invariant fillers；ColorRect/Label only。

## Gate F — 驗證與收尾（HARD）

- [x] **T20 [HARD] 單元與整合測試**
  - Covers：S2-AC-001–017
  - 驗收：全部acceptance對應具名testcase；S2-AC-016另含schema2 migration pack/allowlist/preservation fixtures；GUT JUnit 0 failure/error/orphan。
- [x] **T21 [HARD] canonical fixtures**
  - Covers：S2-AC-004、008–015
  - 驗收：merge_and_pool、simultaneous_death、path_tie、boss_phase、random_target、effect_matrix、overtime golden。
- [x] **T22 [HARD] battle stress 與 10k soak**
  - Covers：S2-AC-018
  - 驗收：per-side max(16,version max)、64/entity max；10000 battle seed 全通；`soak.json` scope=combat-core 且 AC-030 downstream，可讀回且不覆寫全 run pass。
- [x] **T23 [HARD] runner/spec/acceptance contracts**
  - Covers：全部 S2 AC
  - 驗收：All包含Combat quick、不含假soak；Spec移除BattleSimulation/EffectResolver deferred，ShopService保留；`combat-acceptance.json`逐AC evidence，S2-AC-016不得缺任何migration negative。
- [x] **T24 [HARD] 最終獨立複檢**
  - 驗收：逐 requirements AC review；Blocker=0、Major=0；所有 finding 有 verdict/fix evidence。
- [x] **T25 [NORMAL] 文件同步與 read-back**
  - 驗收：README/CLAUDE/PROGRESS/tasks/Manifest 狀態與版本一致；UTF-8、Markdown、Mermaid、hash、links、`git diff --check` 通過。

## Dependency order

`T00→T01→T02→(T03,T04,T05)→T06→(T07,T08,T09)→T10→(T11,T12,T13,T14,T15)→(T16,T17)→(T18,T19)→(T20,T21,T22,T23)→T24→T25`

## Completion ledger

完成時此區必須列出：

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite All -GodotPath <Godot 4.7>`：exit 0，62.9 秒；Import／RunnerContract／Smoke／Gut／Content／Canonical／Combat／Spec 全通。artifact 位於 `artifacts/test/`。
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Soak -SeedCount 10000 -TimeoutSeconds 600 -GodotPath <Godot 4.7>`：exit 0，249 秒；10,000 seeds、0 failures、最大 final tick 22、3 個 result hashes、64 次 deterministic replay。32v32 起始／64 同時 entity stress 由 `combat-runner.json` 通過。
- GUT：190 tests／3115 assertions／0 failures／0 errors／0 orphans（`gut.xml`）。
- Canonical runner：5 cases／151 assertions；S1 U64／RuntimeKey／PCG32／BattleSetup v1 golden 保留，BattleResult summary `6248075fcbe65a43cda15b2cd4efe0ee241a89f50c830d337d9871c8adc9bb6e`、完整 result `03d9decb4aa4e26f66fd6f92a1c4464c00e82bc621082c4176ed0f4c64838788`、event stream `3c0c01b94ca8c727763cd117402a610c82dcb39b402747b99ad346003e749617`；merge/path/Boss/random/effect/overtime 具名 fixtures 由 GUT／Combat runner 鎖定。
- `combat-acceptance.json`：S2-AC-001–018 為 18／18 pass，`evidence_verified=true`；S3/S4/G1/G2 與 global AC-030 仍明列 downstream。
- `final-review.md`：Blocker 0／Major 0；已關閉 7 Major、1 Minor，均列需求、失敗情境與 regression evidence。

不得以本文件文字、手寫 JSON 或 skipped test 充當 executable evidence。
