# presentation-ui SDD architecture review R8

**APPROVED — zero unresolved findings**

## G2-R7-01 read-back

- **FIXED**
  - Retry capability 現綁 repository identity、receipt id、完整 committed-file digest、fallback
    route generation 及獨立 retry-attempt generation：`design.md:379-381`。
  - `retry()` 於 repository read ownership 內 fresh-read authoritative bytes，重新比對
    identity／receipt／digest，並從同一次 read 捕捉 clone-only snapshot：
    `design.md:381-387`。
  - stale、mismatch、I/O 及 presentation failure 都 consume token、推進 attempt generation
    並撤銷同代 siblings：`requirements.md:159-164`、`design.md:384-389`。
  - 失敗後只能 fresh-read 取得下一代 token；persistent fault 仍可零-save 退出 Camp/Menu。
  - T07/T09 與測試矩陣已納入競爭 write、receipt replacement、read fault、雙 sibling token、
    generation 前進及 exactly-once 驗證：`tasks.md:95-100,133-138`、`design.md:713`。

## Fresh scan

- Terminal settlement 固定鎖序為 AppRoot terminal guard→repository writer ownership，無反向
  鎖序路徑；commit 到 lease/session 撤銷與 RESULTS handoff 無 ownership gap。
- Capability 為 repository internal-only，未發現外流或 presentation 偽造路徑。
- post-save internal failure必先撤銷 RUN writer/session，再進 results-only fallback；不會復活
  active run。
- Retry 與兩個 exit 共用 results-action single-flight；fallback lease、route generation 及一般
  atomic route token 共同阻止 retry／exit 混合提交。
- Repository CAS 完成後使用同一次 fresh read 的 clone-only snapshot 建立 candidate。其後競爭
  writer 最多使畫面成為較舊但自洽的唯讀 point-in-time snapshot，不會產生 canonical mutation
  或 alias。
- Retry 成功才切換 RESULTS；prepare/bind failure 保留原 fallback lease。所有 attempt 已先推進
  generation，舊 token 及 siblings 無法重用。
- `RESULTS_FALLBACK` 不建立 gameplay intent/session；舊 RUN 與 fallback stale ports 均受 lease
  registry 阻擋。
- Receipt/reward 只由 terminal transaction 寫入；retry 與 exits 全為零-save，exactly-once 邊界
  一致。
- Settings、Camp transaction、transcript ownership 及 recovery matrix 未發現退化。
- tasks 與測試策略足以直接建立鎖序、競爭、I/O、generation、stale callback 與 receipt
  exactly-once 紅燈。

## Residual risks

- 跨程序共同寫入及 OS file locking 仍明確不在本片範圍。
- durability 不涵蓋 directory `fsync` 或裝置層斷電保證。
- Repository CAS 後若另有合法 writer 提交，RESULTS 可能暫時顯示較舊但 digest-bound、內部
  一致的唯讀 snapshot；下一次 retry／navigation 會重新取得 authoritative state。這不是資料
  安全缺口。

規格已足以進入 TDD。
