# presentation-ui SDD architecture review R7

**NOT APPROVED**

## G2-R6-01 read-back

- **FIXED**
  - `TerminalSettlementCoordinator` 使用固定鎖序：先取得 AppRoot terminal single-flight，再取得
    SaveRepository writer ownership。
  - clone→apply→validate→save、internal capability issue/consume、RUN lease revoke、session
    invalidate/release 及 RESULTS state transition 全在同一 ownership 內同步完成，無 `await`，
    capability 不外流。
  - 競爭 public load/write 必須等 handoff 完成；tasks 已要求注入此競爭情境。
  - save 後 internal handoff 意外失敗不再套用 stale-zero-mutation，而是先撤銷舊
    writer/session 並進 `RESULTS_FALLBACK`。
  - fallback 不持有 gameplay session/intent；舊 callback 與 confirmation 均拒絕，save 維持
    無 active run，receipt/reward exactly-once。

## 新 finding

### G2-R7-01 — Medium — fallback retry token 的 committed-file digest 未在 consume 時重新對 authoritative bytes 驗證

證據：

- `specs/presentation-ui/requirements.md:156-161`
- `specs/presentation-ui/design.md:369-383`
- `specs/presentation-ui/tasks.md:95-98`
- `specs/presentation-ui/tasks.md:127-132`

`prepare_retry()` 會由 fresh committed read 建立綁 full-file digest 的單次 token，但 `retry()`
目前只規定「consume token，再 prepare/bind candidate」，未要求在 repository ownership 內
fresh-read 並重新比對 receipt 與完整檔案 digest。現有測試也只有 stale/repeat token 與
transient/persistent scene fault，沒有 consume 前的競爭 write。

可重現情境：

1. fallback 於 committed bytes A 上取得 token，內含 digest A 與 receipt R。
2. consume 前，另一同程序 public writer 提交 bytes B；receipt R 仍存在，但 profile 或其他
   committed 資料已變更。
3. `retry()` 只驗 token registry／fallback generation 並 consume，未重讀 repository。
4. 系統可用 A 的 results/profile snapshot 成功切回 RESULTS，畫面與 authoritative bytes B
   不一致；token 所宣稱的 full-digest binding 實際沒有 CAS 效果。

最小修正：

- `retry()` 必須在 repository read ownership 內原子執行：驗 repository identity 與 fallback
  generation→fresh-read authoritative committed bytes→比對 full digest 及 receipt id→consume token。
- digest／receipt 不符或 I/O failure 時保持 `RESULTS_FALLBACK`，使該 token 失效，並讓下一次
  `prepare_retry()` 重新 fresh-read 後發新 token。
- retry attempt 失敗後應推進 fallback attempt generation 或明確撤銷同 generation 所有尚未
  consume 的 token，避免先前批次取得的 sibling token 繞過「失敗後 fresh 取得」。
- T07/T09 新增 consume 前競爭 write、receipt 更換、read fault 與兩個同 generation token 的紅燈。

## 其餘檢查

- 固定鎖序未發現反向取得 repository→terminal guard 的規格路徑；preflight revoke plan 置於
  取得 repository ownership 前。
- terminal capability 不可帶出 transaction，未發現新的 ownership gap。
- `LiveScreenIntentPort` 已封閉 raw session bypass。
- fallback 安裝、零-save Camp/Menu exit、舊 writer 失效及 postcommit failure 分類一致。
- Settings、Camp、transcript與 recovery 契約未發現新退化。

## Residual risks

- 跨程序共同寫入與 OS file lock 仍明確不在本片範圍。
- durability 不包含 directory `fsync` 或裝置斷電保證。
- RESULTS postcommit failure 只能提供安全唯讀 fallback，不能保證瞬時視覺原子性。

除 **G2-R7-01** 外，沒有其他 unresolved correctness／data-safety finding。修正 retry consume
的 authoritative digest／receipt 驗證與 generation 失效規則前，不足以進 TDD。
