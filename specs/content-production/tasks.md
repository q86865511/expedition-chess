# G2 content-production — 任務清單

> 建立日期：2026-07-31｜狀態：APPROVED / IMPLEMENTING
> 對應：[requirements.md](requirements.md) R1～R14
> 設計：[design.md](design.md)
> 勾選只由主流程在 fresh evidence 存在後回寫。
>
> **2026-08-01 回勾**:Claude 接手完成實作與 T25 三輪雙審(closure 見
> review-log.md 與 `.pipeline/content-production/reviews/`);fresh 證據=
> 全 Gut 281 scripts/1091 tests、10k ExpeditionSoak exit 0、-Suite All exit 0、
> `artifacts/test/content-production-acceptance.json`(verified=true)。
> 未勾項均 blocked-on-codex/使用者:T18/T18A(人工採納 gate 未執行,
> inventory status=generated、attempt ledger 缺檔)、T20(generator 已存在但
> 輸出 44.1kHz/8s/q0.8/mono 不符 R9 的 48kHz/20-40s/q0.5/stereo,待重生成
> 或修規格)。acceptance 的 AC-033/038/REQ-PROD-001/REQ-SCOPE-002 對應
> blocked,gate 判定機械化,資產採納完成後自動翻綠。

## Gate A — SDD 與 baseline

- [x] **T00 [MECHANICAL / 免 TDD]** 收斂 PR #5／#6、roadmap、progress、
  handoff 與 presentation 狀態；記錄 `master@5e78ccf` baseline。
- [x] **T01 [HARD / 免 TDD]** requirements／design／tasks 經兩位獨立
  read-only reviewer 審查；最多三輪，Blocker／Major 歸零才可進 Wave 1。

## Wave 1 — Codec、定義、localization、tooltip

- [x] **T02 [HARD / TDD]** 鎖定 codec 3 category／field schema、unknown/
  duplicate/tamper、V1/V2 golden 不變與 V3 round-trip red manifest。
- [x] **T03 [HARD / TDD]** 實作 ContentCanonicalCodecV3、
  ContentDefinitionCompilerV3、新三種 definition 與 Unit/Effect 欄位。
- [x] **T04 [NORMAL / TDD]** 鎖定 localization parity、duplicate/blank/
  unsupported、PR #6 emergency keys 與 no-hardcoded-text red manifest。
- [x] **T05 [NORMAL / TDD]** 實作版本化 catalog loader，保留
  LocalizationCatalog public API 與早期 recovery fallback。
- [x] **T06 [HARD / TDD]** 鎖定 pinned tooltip 同源數值、clone isolation、
  localization 與 depth ≤2；實作 tooltip catalog／formatter。
- [x] **T07 [NORMAL / TDD]** 擴充 ContentDependencyPort／validator，
  覆蓋新 category、assets、localization 與 commander passive single-side。

## Wave 2 — Save schema 4 與 migration

- [x] **T08 [HARD / TDD]** 鎖定 schema 4 wire、ContentSnapshotState versions、
  NodeChoicePendingState、current idempotence 與 schema 0→4 sequence。
- [x] **T09 [HARD / TDD]** 實作 schema 3→4 codec／migration／validator。
- [x] **T10 [HARD / TDD]** 建立 ContentGenerationMigrationPackV2；
  鎖定 allowlist、exact target、alias/tombstone、tamper/missing/ambiguous、
  safe／unsafe active run 與 byte preservation。
- [x] **T11 [NORMAL / TDD]** 建立 `5ddf80a`、`9362e7d`、`5e78ccf`
  不可變 fixtures、hash manifest 與舊 fixture regression。

## Wave 3 — 44 單位與事件選項

- [x] **T12 [MECHANICAL / TDD]** 鎖定 44 UnitDef 一對一 ability/effect/
  presentation references、primary effect 不重複 graph、32/12 分布、cost、
  traits、6 elite affix、3 boss、至少一個多 phase boss 與不改 stats/economy。
- [x] **T13 [NORMAL / TDD]** 量產44 AbilityDef、44 primary EffectDef、
  supplementary typed effects、正式localization/tooltip keys，並author至少一個
  多phase Boss encounter/preview/effect order，使T12 red manifest轉綠。
- [x] **T14 [HARD / TDD]** 鎖定 12 event、rest 2、treasure ≥3、
  commit-before-present、confirmation exactly-once、stale/repeat/fault。
- [x] **T15 [HARD / TDD]** 實作 NodeChoiceSetDef 內容、
  NodeChoicePendingState、committed receipt/result、三種 typed outcome、
  dismantle-service exit、CommitNodeChoiceCommand 與 RUN overlay。
- [x] **T16 [NORMAL / TDD]** 重跑 validator mutation matrix與
  event/merchant/rest/treasure/forge/equipment/relic fault matrix。

## Wave 4 — 圖像、音訊與 provenance

- [x] **T17 [NORMAL / TDD]** 先建立 production asset validator red：
  inventory、count、dimension、alpha/chroma、frame map、hash、reference、
  perceptual distinction、OGG、loop/peak/bus。
- [ ] **T18 [MECHANICAL / 免 TDD]** 依T13方向每單位至少一次built-in ImageGen；
  每attempt獨立call並保存prompt/call/provenance，初始狀態僅generated。
- [ ] **T18A [HARD / 免 TDD]** 由獨立唯讀 reviewer 做 originality、
  silhouette、weapon/role、direction/action coverage人工gate；reviewer只輸出
  decision table，由主流程回寫attempt ledger。Rejected回T18新call重試，
  每單位恰一個adopted才可進T19/T21；production inventory只含adopted。
- [x] **T19 [NORMAL / TDD]** 實作 deterministic processor，輸出 44 portrait、
  44 atlas／SpriteFrames、5 shared atlas 與 camp environment。
- [ ] **T20 [NORMAL / TDD]** 實作固定種子音訊 generator 與鎖定 encoder，
  輸出 5 loops／21 SFX／AudioCueDefs。
- [x] **T21 [NORMAL / TDD]** 將正式 content references 全部切到 production
  assets；pilot 僅留作 reference/provenance。

## Wave 5 — Presentation、AC 與 final gate

- [x] **T22 [HARD / TDD]** 接入 committed battle event VFX/audio/tooltip，
  證明 canonical result、playback、settle/retry／resume 不變。
- [x] **T23 [NORMAL / TDD]** 跑多解析度、四色覺、focus、status/modal、
  route fallback、正式 choice overlay 與 screenshot gates。
- [x] **T24 [HARD / TDD]** 聚合 18 條 global AC 與 3 條橫切 REQ，
  加依賴 `REQ-CONTENT-001`，產出 acceptance JSON，逐列證明原始
  Given/When/Then 全子句、test/evidence/hash 與 read-back。
- [x] **T25 [HARD / 免 TDD]** 兩位獨立 implementation reviewer 對照
  requirements／design／tasks／tests／diff；最多三輪。
- [x] **T26 [MECHANICAL / 免 TDD]** fresh 跑 targeted suites、Content、
  ContentDependencyPort、Canonical、save、runtime、asset、localization、
  presentation static/runtime/screenshot、All 與 10k ExpeditionSoak；
  保存各 command、exit code、report path/hash 並驗 runner/report contract；
  不跑 30k。
- [x] **T27 [MECHANICAL / 免 TDD]** 更新 implementation review、roadmap、
  PROGRESS、HANDOFF、implementation slices，read-back review decision table、
  fixture/asset hashes 與限制，停在未提交 Git／PR gate。

## Wave checkpoint（每 wave 強制）

每個 wave 最後一個 task 只有在以下三項同時存在才可勾選：

1. targeted green 與截至該 wave 的 regression green；
2. red manifest 在 green 後 SHA-256 read-back 未變；
3. command、exit code、artifact path/hash 已寫入 `.pipeline/content-production/`。

## 雙向 traceability

| Requirement / AC | Owning tasks |
|---|---|
| R1 | T02、T03、T08～T11 |
| R2～R3、REQ-CONTENT-001 | T07、T12、T13、T16 |
| R4 | T14～T16 |
| R5 | T04～T06 |
| R6 | T22、T23 |
| R7 | T08～T11、T15 |
| R8～R10 | T17～T21 |
| R11 | T02～T26 與每 wave checkpoint |
| R12 | T01、T18A、T25 |
| R13／18 AC | T16、T22～T24、T26 |
| R14 | T24～T27 |

反向依賴：T03←T02；T05←T04；T09←T08；T10←T09；T11←T10；
T13←T12；T15←T14；T18←T17；T18A←T18；T19/T21←T18A；
T22←T21；T24←T22/T23；T25←T24；T26←T25；T27←T26。
