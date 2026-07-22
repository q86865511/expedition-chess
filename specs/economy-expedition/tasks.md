# S3 `economy-expedition` 實作任務

> 狀態：`Stages 0–6 completed / independent review passed`
> HARD/NORMAL 標記不可靜默降級。

## Gate A — 規格（階段 0）

- [x] **T00 [HARD] 建立三件套與雙向追溯**
  - Covers：RUN 5、ECON 4、REWARD 2 與 S2/S1 downstream clauses。
  - 驗收：full/partial/downstream 與 stages 0–6 邊界明列。
- [x] **T00R [HARD] 獨立規格複檢**
  - 驗收：第五輪 Blocker 0／Major 0／Minor 0，詳見 `final-review.md`。

## Gate B — Typed domain（階段 1）

- [x] **T01 [HARD] EconomyExpeditionCatalog v1**
  - 驗收：從 receipt `reward_table_ids` 與 pinned compiled view 解碼 economy、units、map nodes、RewardTableDef（含 conditions）；clone isolation，以及每類 wrong generation/category/payload negative。
- [x] **T02 [HARD] Income／Shop request-result-transaction-error**
  - 驗收：公開 API 全具名型別；service 不修改輸入；transaction 帶 RNG/serial/receipt identity。

## Gate C — 地圖與節點（階段 2）

- [x] **T03 [HARD] MapService v1**
  - 驗收：三幕、七層、2–3 寬度、全路徑可達與至少兩分岔戰鬥；相同 seed byte-equivalent。
- [x] **T04 [HARD] EnterNodeEvent 與 IncomeService**
  - 驗收：收入公式、一次 claim、shop 初始生成、save failure 零 mutation。

## Gate D — 商店經濟（階段 3）

- [x] **T05 [HARD] offer generation／refresh／reservation**
  - 驗收：tier→unit 加權、最多20次、空slot、refresh release、pool守恆與 RNG retry identity。
- [x] **T06 [HARD] BuyOfferCommand**
  - 驗收：stale/insufficient/no-space negative；reservation→held、unique ID、自動合成與 fault injection。
- [x] **T07 [HARD] SellUnitCommand**
  - 驗收：1/2/3星售價、副本歸池、裝備 inventory/overflow 與 layout 移除。
- [x] **T08 [NORMAL] BuyXpCommand**
  - 驗收：164 XP、跨級 overflow、9級停用、TUNE 無 UI/domain 重複常數。

## Gate E — 後續階段 4–6

- [x] **T09 [HARD] battle settlement／reward state machine／final exit**
- [x] **T10 [NORMAL] Expedition Lab**
- [x] **T11A [HARD] acceptance runner／10k soak／逐 AC 自我複檢**
- [x] **T11B [HARD] 獨立最終複檢**
  - 驗收：第五輪 Blocker 0／Major 0；唯一 evidence mapping 建議已在最終 artifact 前補齊，詳見 `final-review.md`。
- [x] **T12 [NORMAL] README／CLAUDE／PROGRESS 收尾**

## Dependency order

`T00→T01→T02→T03→T04→(T05,T08)→T06→T07→T09→T10→T11A→T12→(授權後 T00R/T11B)`

## Completion ledger

- [2026-07-18] 階段 0–3：`tools/run-tests.ps1 -Suite All` exit 0（68.9 秒）；GUT 198 tests／3373 assertions／0 failures／0 errors／0 orphans；Spec 3095 cases／0 failures。
- [2026-07-22] 階段 4–6 最終 executable evidence：`tools/run-tests.ps1 -Suite All` exit 0（187.5 秒）；GUT 228 tests／3681 assertions／0 failures／0 errors／0 orphans；Spec 3170 cases／0 failures；10,000-seed `ExpeditionSoak` exit 0（213 秒）、10,000 pool-conservation checks、64 deterministic replays／0 failures；`expedition-acceptance.json` 的 `evidence_verified=true`，S3-AC-001～011 為 11／11 pass。
- T00R／T11B 第五輪均為 Blocker 0／Major 0／Minor 0；最終 review 另修正 production runner transaction seam，並讓自製 runner script error 與 S3 acceptance 缺證直接使 `All` 非零。
