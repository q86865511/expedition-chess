# G2 presentation-ui R9 — Architecture / Data Safety / Concurrency Review

## Verdict

**APPROVED — zero unresolved findings**

`G2-R8-01` 已完整封閉；本次 fresh R9 架構／資料安全／併發複審未發現 blocker、major、
medium 或 minor finding。

## Findings

| Severity | File:line | Failure scenario | Proposed fix |
|---|---|---|---|
| none | — | — | — |

## Coverage checklist

- `G2-R8-01`
  - Guard 在首次 fallback lease／route-generation 驗證前取得：
    `requirements.md:166-174`、`design.md:379-386`。
  - Guard 持有至 route commit／failure cleanup；repository unlock 不縮短生命週期；
    全段無 `await`。
  - retry-vs-Camp/Menu 各三個 barrier，共六組：repository ownership 前、
    CAS＋release 後、candidate bind 中：`design.md:399-405`。
  - Loser 回 `RESULTS_ACTION_IN_PROGRESS` 或既有 stale/lease error；
    零 gameplay save、零 route commit。
  - 明驗 App state／presentation route／唯一 lease 一致。
  - finally-style 釋放 guard；transient bind failure 後 fresh retry/exit 可恢復。
  - T07、T09 與 named lifecycle test 均有對應驗收：
    `tasks.md:101-105,140-148`、`design.md:727`。
- Repository ownership／CAS
  - Prepared run 綁 repository identity／epoch／完整 committed-file digest，
    consume 在 ownership 內 fresh-read。
  - 全部 Camp writer 共用單次 repository-owned transaction，無 load→unlock→save 空窗。
  - Terminal save→internal capability consume→lease revoke→session invalidation→RESULTS
    保持固定 AppRoot→repository 鎖序與同一 ownership。
  - Results retry 在 read ownership 內驗 receipt/full digest，所有 attempt 推進 generation
    並撤銷 siblings。
- Save／recovery
  - decoded/opaque token 邊界一致；opaque 不猜 run id 或 run-bytes digest。
  - archive-before-clear 不 move main；四個 authoritative base state × 四種 tmp residue
    已分配 T06 fault matrix。
  - restart 先選有效 main，否則 byte-identical backup；tmp 不升格為 authority。
- Lease／session／capability
  - Staging context 唯讀，正式 screen 無 raw repository/controller/session。
  - 每次 intent/navigation/confirmation 都重驗 live lease；RUN→RUN 保留 session，
    離開 RUN 才釋放。
  - Terminal postcommit 不復活 RUN；fallback 僅有 receipt-bound retry/Camp/Menu port。
- Clone／版本／可測性
  - Gameplay schema 3、content codec 2 維持不變；settings schema 1 獨立。
  - Snapshot、signal、result、settings public 邊界均 clone-in/out；
    transcript 為唯一 owner transfer。
  - R1～R14、T00～T15 與 19 條 owning AC 的 evidence ownership 均有對應，
    未見 requirement drift。

本次只讀審查，未修改 production／spec、commit、push 或 merge。
