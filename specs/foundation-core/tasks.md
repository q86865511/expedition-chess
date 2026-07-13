# S1 `foundation-core` 實作任務

> 狀態：`Approved / Implementation gate passed`
> 建立日期：2026-07-13
> 需求：[requirements.md](requirements.md) · 設計：[design.md](design.md)
> 任務標記：`HARD`＝架構／決定性／持久化風險；`NORMAL`＝明確實作／測試；`MECHANICAL`＝可機械驗證的搬運或文件同步。

## 1. 執行規則

- `S1-T00` 是硬 gate；三件套未經獨立複檢或仍有 Blocker/Major 時，不得開始 `S1-T01` 之後的程式工作。
- 任務依 dependency 執行；不得把 HARD task 再拆成語意不同的小切片或略過其 negative/fault tests。
- 每個 task 勾選前，必須把實際命令、exit code 與 artifact path 寫入 task 下方的「證據」欄；本檔初始不預填通過結果。
- 不建立 ShopService、BattleSimulation、EffectResolver 假成功 stub；相關 global AC 依 §2 集合 deferred。
- 任一 golden、schema、hash 或公開 API 語意需要改變時，先回寫 [design.md](design.md) 與主體架構決策，再重新複檢。

## 2. Global AC gate

三集合是 completion contract，不是說明文字；spec contract 與 final report 都必須驗證其互斥、數量及狀態。

| 集合 | 數量 | 固定成員 | S1 完成條件 |
|---|---:|---|---|
| **F** | 15 | AC-025、AC-026、AC-036、AC-039、AC-040、AC-051、AC-052、AC-054、AC-055、AC-063、AC-064、AC-068、AC-069、AC-070、AC-078 | 全部有 pass case 與 artifact。 |
| **X** | 7 | AC-016、AC-027、AC-034、AC-047、AC-065、AC-073、AC-075 | 明列 foundation assertions 全 pass；global AC 仍標 downstream。 |
| **D** | 11 | AC-007、AC-020、AC-023、AC-024、AC-035、AC-041、AC-046、AC-058、AC-066、AC-072、AC-076 | 全部 deferred，S1 artifact 不得出現 pass。 |

D owner：`007→S2`、`020→S3`、`023→S5`、`024→S2＋橫切 UI`、`035→S2/S3`、`041→S2/S3`、`046→S3/S4`、`058→S3`、`066→S2/S3/S4`、`072→S3/S4`、`076→S2/S3/S4`。X 的 AC-075 只通過 S1 clone/catalog/setup-input assertions，BattleResult 由 S2 收尾。

## 3. 任務清單

- [x] **S1-T00 [NORMAL] — 三件套獨立複檢 gate**
  - **Depends on**：無。
  - **交付**：以 `Blocker/Major/Minor/Question` 審查 requirements/design/tasks；修完所有 Blocker/Major，保留 evidence；三檔狀態由 reviewer 核可後才改成 `Approved`。
  - **Trace**：REQ-TECH-001–006、REQ-DATA-001–008、REQ-RNG-001–002、REQ-SAVE-001–006、REQ-CONTENT-001；S1-AC-001–023。
  - **驗證**：`rg -o "REQ-(TECH|DATA|RNG|SAVE|CONTENT)-[0-9]{3}" specs/foundation-core/requirements.md specs/foundation-core/tasks.md`，並執行本檔 §5 雙向覆蓋腳本。
  - **證據**：2026-07-13 由兩個獨立唯讀 Codex reviewer 完成差異收斂：`foundation_coverage=PASS`、`godot_gut_probe=PASS`，皆為 0 Blocker／0 Major；`content_codec_probe` 另以兩套 writer 重算 453/254/770-byte golden 一致。這是 S1 implementation gate 證據，不宣稱存在 Claude review report。機械讀回：23 REQ、23 S1-AC；`git diff --check` exit 0；Battle golden 1559 bytes/SHA=`e92f72...0922`；Content entry/manifest SHA=`45473b...5f65`/`a6b93f...f90c`。

- [x] **S1-T01 [MECHANICAL] — 鎖定並 vendor 工具鏈**
  - **Depends on**：S1-T00。
  - **交付**：建立 `toolchain.lock.json`、`tools/verify-toolchain.ps1`；將 GUT 9.7.1 與 MIT license 原樣 vendor；拒絕 non-ASCII/case-fold collision，依 ASCII-lowercase path＋original path tie-break排序，再 hash `original UTF-8 path + NUL + raw bytes + NUL`；不保存 `E:\Gut-9.7.1`。
  - **Trace**：REQ-TECH-001；S1-AC-001；F: AC-036。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/verify-toolchain.ps1 -GodotPath $env:GODOT_BIN`；預期 Godot `4.7.stable.official`/`b2ca...bf8`、GUT `9.7.1`/`94cf...8d2`。各修改一個 version/hash/vendor byte 的 fixture 必須回 2。
  - **證據**：2026-07-13 `-Suite All` 的 Toolchain gate exit 0；`artifacts/test/runner-execution.json` 讀回 Godot `4.7.stable.official`／`b2ca...bf8`、GUT `9.7.1`／259 files／`94cf...8d2`、`source=vendored`。RunnerContract 對 version、hash、source mutation 均要求 exit 2。

- [x] **S1-T02 [NORMAL] — 建立 Godot/AppRoot/Autoload 骨架**
  - **Depends on**：S1-T01。
  - **交付**：建立 project.godot、`Main/AppRoot/PresentationHost`、AppRoot composition root與五個允許的 Autoload；instance/class_name 使用 design §3.1 固定配對。
  - **Trace**：REQ-TECH-002、REQ-TECH-005；S1-AC-002、005；F: AC-039、AC-068。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Import` 及 `-Suite Smoke`；Autoload collision/extra singleton negative fixture 回 2。
  - **證據**：`-Suite Import` 與 `-Suite Smoke` exit 0；`artifacts/test/smoke.json` 為 10 cases／0 failures，完成 `main_scene`、`autoload_set`、`minimal_boot`。AppRoot 實際驗證 BOOT→MENU 且未建立 active run。

- [x] **S1-T03 [NORMAL] — Runner、watchdog 與 artifact 基礎**
  - **Depends on**：S1-T02。
  - **交付**：建立GUT/content/canonical/spec/smoke SceneTree runner與PS5.1 wrapper；GUT先import、禁native CLI，依序apply_options/headless ignore_pause/register_logger→GutMain/end_run→所有epilogue deregister，零測試=3，自寫/read-back JUnit；wrapper安全quoting、timeout taskkill/124，永遠寫execution artifact。
  - **Trace**：REQ-TECH-001、REQ-TECH-003、REQ-TECH-006；S1-AC-001、003、006；F: AC-036、AC-054；D: AC-076（只建 S1 service scan，不標 global pass）。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite RunnerContract`；pass/assertion/push_error-only/engine-error/pause-before-teardown/logger-cleanup/zero-test/infra/timeout覆蓋0/2/3/124；execution artifact每次可parse，timeout可無JUnit但不得假pass。
  - **證據**：`-Suite RunnerContract` exit 0；11 probes 實測 pass/pause/logger-cleanup=`0`、assertion/push_error/engine-error/orphan=`2`、zero-tests/infra/logger-leak=`3`、timeout=`124`。Pause 實際呼叫 `pause_before_teardown`；logger-leak 由同 process epilogue 偵測。具名 JUnit 位於 `artifacts/test/runner-contract-*.xml`。

- [x] **S1-T04 [HARD] — U64Bits 與 stable ID**
  - **Depends on**：S1-T03。
  - **交付**：以 hi/lo 32-bit + 16-bit multiplication limb 實作 immutable-style U64 value operations/strict hex codec；實作 stable ID regex、published ledger、alias/tombstone graph與 instance serial exhaustion guard。
  - **Trace**：REQ-DATA-003、REQ-RNG-002；S1-AC-009、016；F: AC-051、AC-052、AC-063。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Gut -TestPath res://tests/unit/common`；0、2^53±1、2^63、2^64-1、shift 0/31/32/63、carry/multiply及非法 hex/ID/alias cycle全部通過；from_u32任一limb越界回具名`U64CreateResult/U64_INVALID_LIMB`且無value。
  - **證據**：完整 `-Suite Gut` exit 0；`artifacts/test/gut.xml` 為 73 tests／667 assertions／0 failures／0 errors／0 orphans。`-Suite Canonical` 的 U64Bits/stable-id scope 通過，整體 4 cases／141 assertions。

- [x] **S1-T05 [HARD] — RuntimeKeyCodec v1 與 ledger**
  - **Depends on**：S1-T04。
  - **交付**：建立六種 typed token、六種 per-kind schema/builder（raw token array不公開）、4-byte big-endian tuple codec、SHA-256 output、run/node golden、retry identity、serial與 tuple/key/payload uniqueness validator。
  - **Trace**：REQ-DATA-007；S1-AC-013；X: AC-073（S2/S3/S5 保留實際來源流程）。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Canonical -Case RuntimeKey`；六種 per-kind schema positive/wrong-count/tag/order negative、兩組權威 bytes/digest、duplicate tuple/key、digest mismatch、serial rollback/overflow均符合固定 error code且零 mutation。
  - **證據**：`-Suite Canonical` exit 0；`artifacts/test/canonical.json` 明列 `RuntimeKeyCodec-v1` completed，run/node golden、六種 typed tuple、negative ledger 與 serial assertions 均包含於 138 assertions。

- [x] **S1-T06 [HARD] — PCG32 與命名 stream**
  - **Depends on**：S1-T04。
  - **交付**：精確實作 PCG32、FNV-1a、SplitMix64、bounded rejection、snapshot、RngService map/shop/reward/combat派生；production static scan 禁止 Godot rand/time/Object ID gameplay entropy。
  - **Trace**：REQ-RNG-001、REQ-RNG-002；S1-AC-015、016；F: AC-063；X: AC-027；D: AC-007→S2、AC-041→S2/S3；AC-064由T08完成F gate。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Canonical -Case RngV1`；reference/derived-shop/bounded/counter/u64 boundary完全符合；synthetic map多抽不改其他 stream；實際 consumers 仍列 downstream。
  - **證據**：`-Suite Canonical` exit 0；`PCG32/RNG-v1` completed，reference/bounded/derived stream/counter vectors 通過。`-Suite Spec` source scan 同時拒絕 production `rand*`、Time 與 ObjectID gameplay entropy。

- [x] **S1-T07 [HARD] — Runtime DTO、deep-copy 與 Resolution union**
  - **Depends on**：S1-T04。
  - **交付**：建立 requirements/design 列出的 DTO與具名 result/error；validator只遞迴allowlisted typed value object並拒絕其他engine Object；所有nested collection deep clone；RosterState唯一容器owner；四個ResolutionState subclass與單一PendingRewardState。
  - **Trace**：REQ-TECH-003、REQ-TECH-006、REQ-DATA-002、REQ-DATA-004、REQ-SAVE-005；S1-AC-003、006、008、010、021；F: AC-040、AC-054、AC-055；D: AC-035、AC-066、AC-072、AC-076。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Gut -TestPath res://tests/unit/dto`；逐一對 design §5.1 每張 schema 表做 exact field/type/nullability/range/order static assertion、allowlisted DTO round-trip + clone mutation；`ContentSnapshotState` 只能由 pinned receipt factory 建立，驗證排序正規化、duplicate／非法 digest／receipt mismatch rejection，raw unsealed instance 不得通過 Save 或 RunSession；RunState.run key／每個 MapNode.node key逐欄重建且ID等於digest，任一 tuple 欄位或 digest 竄改失敗；unknown/missing/duplicate field、engine Object/multi payload、parallel pending boolean、top-level duplicate roster field皆失敗。
  - **證據**：完整 `-Suite Gut` exit 0（73／667／0 failures／0 orphans），涵蓋 DTO exact schema、clone isolation、四種 Resolution payload、46 個 Result constructor invariant 與 illegal engine object／parallel pending negative；`-Suite Spec` typed API/result/domain dependency scan exit 0。

- [x] **S1-T08 [HARD] — CanonicalBattleCodec 與 setup hash builder**
  - **Depends on**：S1-T06、S1-T07。
  - **交付**：固定 11 欄 typed codec、排序/escaping/hash、EncounterPreview唯一敵方權威、trusted validator 專屬 validation receipt gate及 hash後 combat stream派生；builder 不接受 caller authority；不建立模擬。
  - **Trace**：REQ-DATA-005、REQ-RNG-001；S1-AC-011、015；F: AC-064；D: AC-041→S2/S3。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Canonical -Case BattleSetupV1`；11欄及每種nested DTO逐欄round-trip/negative（含 effective `move_speed_milli`）；fixture恰1559 bytes且SHA=`e92f72...0922`；改站位／移速必改hash，只改shop refresh不改，enemy等於preview，inputs無seed/hash且seed於hash後派生；原 receipt 搭配竄改 inputs、foreign authority receipt 與直接建構 receipt 均拒絕，Spec scan 封鎖 production issuance boundary。
  - **證據**：`-Suite Canonical` exit 0；`CanonicalBattleCodec-v1` completed，1559 bytes 與 SHA `e92f72...0922` golden 一致，foreign validation receipt、enemy preview authority、hash-before-combat-stream negative 均通過；BattleResult 維持 deferred。

- [x] **S1-T09 [HARD] — Authoring Resource 與 ContentRegistry generations**
  - **Depends on**：S1-T04、S1-T07。
  - **交付**：建立15種ContentDefinition、typed operation、`ContentCanonicalCodec v1`專用encoder/decoder與golden、deterministic compiler、catalog/digest、ContentRef、deep-copy view、latest handle、digest lease與A/B retention。
  - **Trace**：REQ-DATA-001、REQ-DATA-008；S1-AC-007、014；F: AC-078；X: AC-075→S2 canonical BattleResult；D: AC-024→S2＋橫切 UI。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Gut -TestPath res://tests/unit/content_registry`；逐類round-trip 15 payload、全部`2000..200f` subrecord及`3001..3009/3101..3107` operation，並靜態比對每欄scalar/collection wire tag；453/254/770-byte golden逐byte一致。UnitDef negative 必含缺移速、缺/重複星級、倍率越界、未知 basic-attack/shop-condition。其餘 negative 固定涵蓋magic/version/tag/type、field缺少/重複/非遞增/tag錯、trailing/截斷/上限、每種list/set排序與duplicate、category/payload mismatch、alias/tombstone衝突、entry/manifest digest與index缺多重複；entry resource schema 與 catalog schema 的 encode/decode 均拒絕非 v1，且 entry/index 同為 v2 仍失敗；每個schema逐欄mutation都必須改digest或回固定error。另驗full latest與filtered pinned generation digest分離、selection active IDs與entry-index全集一致、config子集、缺依賴、receipt/digest mismatch、fresh registry只含full latest時以persisted selection重建相同filtered digest、clone isolation、A/B pinning；BattleResult維持S2 downstream。
  - **證據**：完整 GUT 與 Content runner 均 exit 0。`content-validation.json` 明列 codec golden/negative matrix、payload schema round-trip、generation pinning、transaction rollback、alias/tombstone migration；453/254/770-byte golden 由測試逐 byte 驗證。

- [x] **S1-T10 [HARD] — §11.2 內容驗證器與 synthetic slice**
  - **Depends on**：S1-T05、S1-T09。
  - **交付**：依design鎖定的content分類、Effect enum/range與stable error完整實作invariant；production/fake port、valid 32-unit fixture與一 invariant 一 mutation；summon有限bound/無鏈無循環、最大同時實體與壓測下限納入report。
  - **Trace**：REQ-CONTENT-001、REQ-DATA-001、REQ-DATA-007；S1-AC-007、013、023；X: AC-016、AC-034、AC-047、AC-073。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Content`；valid回0；逐一mutation玩家/怪物/elite-affix/Boss/event分類、trigger/condition/stacking/operation/range/claim-context及§11.2全部bullet，回2並比對exact診斷與排序。人口/實體bound可重算；S2仍負責實際壓測。
  - **證據**：`-Suite Content` exit 0；`artifacts/test/content-validation.json` 為 39 cases／0 failures，valid fixture、population recompute 與逐 invariant mutation 皆具名完成；formal content、battle entity stress、gameplay soak 明列 deferred。

- [x] **S1-T11 [HARD] — SaveJsonCodec、schema migration 與不相容 run**
  - **Depends on**：S1-T05、S1-T07、S1-T09。
  - **交付**：schema v1 typed encode/decode、每個持久u64欄位16-hex、schema0→1 registry、alias及非必要/必要tombstone兩分支、profile/run split status、archive-before-abandon flow。
  - **Trace**：REQ-DATA-002、REQ-DATA-003、REQ-DATA-006、REQ-SAVE-003、REQ-SAVE-005；S1-AC-008、009、012、019、021；F: AC-025、AC-040、AC-051、AC-052、AC-070、AC-078；D: AC-023。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Gut -TestPath res://tests/unit/save_codec`；逐一比對 design §5.1/§5.2/§5.3/§7.1 的 schema v1 root/nested exact key set、field order/type/nullability/range，unknown/missing/duplicate key皆固定 error；run/node key typed tuple＋digest round-trip與cross-field equality必驗；ContentSnapshotProbe逐欄驗證後以fake receipt port重建或隔離，禁止只用digest lookup，五種PinnedCatalogReceiptError逐一映射incompatible_preserved diagnostic；parse-invalid的source schema必為Unknown、合法schema 0必為Known(0)；0→1冪等；每個持久u64欄位逐一跑六個邊界且只用16-hex；非必要tombstone安全載入與必要active-run tombstone隔離兩分支；缺digest保留profile+原檔。
  - **證據**：完整 GUT exit 0，涵蓋 strict UTF-8 bytes、schema 0→1 冪等、16-hex u64、exact key set、alias／tombstone與 `incompatible_preserved`；真實 ContentRegistry adapter／catalog lease 整合案例亦通過。

- [x] **S1-T12 [HARD] — SaveStoragePort 與原子 SaveRepository**
  - **Depends on**：S1-T11。
  - **交付**：同directory/volume的production/fake port、`operation/path/occurrence` journal、repository-wide短鎖`_operation_in_progress` guard、private owned repair、tmp read-back、rotation、final verify/restore與main-first load；區分首次與已有committed invariant。
  - **Trace**：REQ-SAVE-001、REQ-SAVE-006；S1-AC-017、022；F: AC-026、AC-069。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Gut -TestPath res://tests/integration/save_repository`；由無故障journal枚舉每個 invocation逐點注入；跨/same-thread的save→save/save→load/load→save/repair-load→save在storage前回`SAVE_BUSY/LOAD_BUSY`且只有一journal；已有committed時任一fault仍至少一份，首次提交前可零份但tmp不算、成功後main有效。
  - **證據**：targeted `-Suite Gut -TestPath res://tests/integration/save_repository` exit 0（14 tests／204 assertions／0 orphans）；完整 JUnit亦通過。逐 journal invocation fault、main/backup rotation、final read-back、reentrant busy 與 FileSaveStorage port contract 均被執行。

- [x] **S1-T13 [HARD] — App/Run FSM 與 copy-validate-save-swap**
  - **Depends on**：S1-T07、S1-T12。
  - **交付**：AppStateMachine、RunEvent edge/guard、RunSession private canonical owner、RunController共同 transaction pipeline、post-swap typed signal與test-only mutation command。
  - **Trace**：REQ-TECH-002、REQ-TECH-004、REQ-TECH-006、REQ-SAVE-004；S1-AC-002、004、006、020；F: AC-039；X: AC-065；D: AC-046、AC-076。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Gut -TestPath res://tests/integration/run_controller`；所有合法/非法edge；validation/tmp/final-read failure時state/serial/RNG/signal全不變；成功僅single swap；view mutation隔離。AC-065 global仍保留S3實際購買command。
  - **證據**：targeted RunController integration 與完整 GUT 均 exit 0；合法／非法 edge、repository-issued one-time commit capability、validation/save failure零 mutation、catalog pin、single swap及 publish listener reentrancy assertions 通過。

- [x] **S1-T14 [HARD] — SAVE-002 retry identity gate**
  - **Depends on**：S1-T08、S1-T12、S1-T13。
  - **交付**：為 `idle/combat_pending/battle_result_pending/reward_pending` 各建立含完整 key/ledger 的 fixture與 deterministic retry harness；只驗表示與恢復 identity，不執行 gameplay結算。
  - **Trace**：REQ-SAVE-002、REQ-SAVE-005、REQ-DATA-007、REQ-RNG-001；S1-AC-013、015、018、021；X: AC-073；D: AC-020→S3、AC-035→S2/S3、AC-046→S3/S4、AC-058→S3、AC-066→S2/S3/S4、AC-072→S3/S4。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Gut -TestPath res://tests/integration/resolution_retry`；每個 kind連續 `save→load→retry→save→load`，seed、candidate、reservation、transaction、claim、receipt typed tuple/digest/canonical bytes與key count等值，serial/counter不前進、無新key。
  - **證據**：targeted `-Suite Gut -TestPath res://tests/integration/resolution_retry` exit 0（1 test／16 assertions／0 orphans）；四種 Resolution kind 的 save/load/retry identity 與 counter/key 不前進通過。

- [x] **S1-T15 [NORMAL] — Spec contract/static gates**
  - **Depends on**：S1-T03、S1-T09、S1-T13、S1-T14。
  - **交付**：manifest 12章/18 section/ID/link/hash validator；公開API typed scan、Autoload/class_name collision、forbidden Dictionary/rand/dependency scan；F/X/D=15/7/11集合validator與stable error constant scan。
  - **Trace**：REQ-TECH-003、REQ-TECH-005、REQ-TECH-006、REQ-DATA-001、REQ-DATA-002、REQ-RNG-001；S1-AC-003、005、006、007、008、015；F: AC-040、AC-054、AC-068；D: AC-076。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Spec`；F/X/D恰15/7/11、互斥聯集33；缺檔/重複/清單外/壞連結/API collision各回2。
  - **證據**：`-Suite Spec` exit 0；`artifacts/test/spec-contract.json` 為 1826 cases／0 failures，完成 manifest、links、IDs、traceability、aggregate hash、source contracts；F/X/D 恰 15/7/11。

- [x] **S1-T16 [NORMAL] — 全套整合與 no-fake-pass gate**
  - **Depends on**：S1-T01–T15。
  - **交付**：執行 import/smoke/GUT/content/canonical/spec；artifact 明列 completed/deferred scopes，GUT輸出JUnit；AC-075 canonical BattleResult及soak/event hash維持downstream，不假pass。
  - **Trace**：全部23 REQ；S1-AC-001–023；F/X/D完整集合。
  - **驗證**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite All`；全部S1 runner回0。另跑故障模式確認2/3/124；artifact schema/版本/測試數可重讀。
  - **證據**：2026-07-13 `tools/run-tests.ps1 -Suite All` exit 0；`runner-execution.json` read-back 包含 Toolchain、Import、RunnerContract、Smoke、Gut、Content、Canonical、Spec。`foundation-acceptance.json` schema v2 對每個 F/X 綁具名 testcase/scope，內建缺 scope mutation 必須回 not-verified；最終 F=15 pass、X=7 foundation-pass/downstream-pending、D=11 downstream-deferred。限縮獨立 regression review 對原 17 項 Major 判定 17/17 Closed、0 Blocker／0 Major。

- [x] **S1-T17 [MECHANICAL] — 文件狀態、Manifest 與進度同步**
  - **Depends on**：S1-T16。
  - **交付**：repo-owned spec validator通過後，將架構文件狀態改 `Approved`、重算只涵蓋12章的aggregate SHA、更新manifest預期section/ID/Mermaid數；同步 README/CLAUDE/PROGRESS與三件套狀態，記錄外部複檢已完成及S1實際證據，不虛構Claude report。
  - **Trace**：全部23 REQ；F/X/D completion contract。
  - **驗證**：重新執行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite Spec` 與 `-Suite All`；`git diff --check`；人工讀回 README/CLAUDE/PROGRESS/manifest 狀態與hash。
  - **證據**：12 章與入口狀態已改 `v0.1 / Approved`；Manifest schema v2 固定 12 files／18 sections／3 Mermaid／74 REQ／78 AC／13 DEC／6 ASM／12 RSK，aggregate SHA=`e6c49846...0cc9a2`。README／CLAUDE／PROGRESS 已同步；Spec 與 All 均 exit 0，`git diff --check` 於同步前後重跑。

## 4. Dependency critical path

```text
T00 → T01 → T02 → T03 → T04
T04 → T05 ─┬→ T10
T04 → T06 ─┴→ T08 ───────────┐
T04 → T07 → T09 → T11 → T12 → T13 → T14 → T15 → T16 → T17
                └→ T10 ────────────────────────────────┘
```

T05、T06、T07 在 T04 後可平行；T08、T09 可在各自依賴完成後平行；T10 與 T11 可在 T09 後平行。整合者不得在共享基礎型別尚未穩定時讓 worker 同時修改相同檔案。

## 5. 23 REQ 雙向覆蓋

| 需求 | Requirements 驗收 | Design | Tasks owner |
|---|---|---|---|
| REQ-TECH-001 | S1-AC-001 | §3、§10 | T01、T03、T16 |
| REQ-TECH-002 | S1-AC-002 | §2、§8 | T02、T13 |
| REQ-TECH-003 | S1-AC-003 | §5、§9、§10 | T03、T07、T15 |
| REQ-TECH-004 | S1-AC-004 | §8 | T13 |
| REQ-TECH-005 | S1-AC-005 | §3 | T02、T15 |
| REQ-TECH-006 | S1-AC-006 | §9 | T03、T07、T13、T15 |
| REQ-DATA-001 | S1-AC-007 | §6 | T09、T10、T15 |
| REQ-DATA-002 | S1-AC-008 | §5、§7 | T07、T11、T15 |
| REQ-DATA-003 | S1-AC-009 | §4、§7 | T04、T11 |
| REQ-DATA-004 | S1-AC-010 | §5 | T07 |
| REQ-DATA-005 | S1-AC-011 | §5 | T08 |
| REQ-DATA-006 | S1-AC-012 | §5、§7 | T11 |
| REQ-DATA-007 | S1-AC-013 | §4 | T05、T10、T14 |
| REQ-DATA-008 | S1-AC-014 | §6 | T09 |
| REQ-RNG-001 | S1-AC-015 | §4、§5 | T06、T08、T14、T15 |
| REQ-RNG-002 | S1-AC-016 | §4 | T04、T06 |
| REQ-SAVE-001 | S1-AC-017 | §7 | T12 |
| REQ-SAVE-002 | S1-AC-018 | §5、§8 | T14 |
| REQ-SAVE-003 | S1-AC-019 | §7 | T11 |
| REQ-SAVE-004 | S1-AC-020 | §8 | T13 |
| REQ-SAVE-005 | S1-AC-021 | §5 | T07、T11、T14 |
| REQ-SAVE-006 | S1-AC-022 | §7 | T12 |
| REQ-CONTENT-001 | S1-AC-023 | §6 | T10 |

機器檢查必須從權威清單建立 expected set，分別解析 requirements 表與本表：缺少、範圍外 `REQ-*`、重複 owner row 或兩集合不相等均回 2。正文中為 trace 而重複出現 ID 合法，但 coverage table 每個 expected ID 必須恰一列。

## 6. S1 收尾判準

- T00–T17 非 deferred 工作全部有實際證據且已勾選。
- 23 REQ coverage table 恰一列、requirements/design/tasks 三向一致。
- F=15 全 pass；X=7 的 foundation assertions 全 pass且 downstream owner保留；D=11 全 deferred且沒有 pass artifact。
- Godot/GUT version與SHA逐字符合、所有 runner/artifact/read-back成功。
- S1 沒有戰鬥結果、商店交易、效果解析、正式內容、正式UI、soak或可玩性完成宣告。
- 不 commit、push、merge、設定remote或部署；Git發布另行授權。
