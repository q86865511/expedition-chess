# G2 presentation-ui Spec Review — Architecture R12

> Date: 2026-07-28
> Role: fresh read-only Codex reviewer
> Verdict: `NOT APPROVED — 2 unresolved findings`

## Findings

| ID | Severity | file:line | Failure scenario | Proposed fix |
|---|---|---|---|---|
| `G2-R12-A01` | Medium | `specs/presentation-ui/tasks.md:57,74,105,115,245` | wave2 的 T05 必須完成 terminal save→revoke `LiveScreenLease`→安裝 RESULTS／fallback，且是 AppRoot 唯一 integration owner；但 `LiveScreenLease`、`RESULTS_FALLBACK`、results-action guard 與 production router contract 要到依賴 T05 的 wave3 T07 才實作。T05 若以 stub 轉綠，無法證明 production joint handoff；若直接實作 route/lease，會侵入 T07 ownership；T07 若回頭接 AppRoot，又違反 T05 唯一 owner，造成 wave gate 或 immutable manifest 無法依聲明執行。 | 在 T00 明定 injectable typed `TerminalPresentationHandoffPort`／`PresentationLifecyclePort` scaffold。T05 僅擁有 AppRoot guard、repository transaction、App state/session lifecycle，使用 fake port 完成 root component evidence；T07 實作 concrete SceneRouter/lease/fallback adapter；T09 擁有 production joint-integration named test。另一可行方案是把 T07 的 route/lease primitive 拆成 T05 前置任務，再把 scene shell 留在 wave3。需同步標明檔案 owner、test owner 與 wave manifest。 |
| `G2-R12-A02` | Medium | `specs/presentation-ui/design.md:103,109,111,667,670` | §1 要求仍持有 repository writer ownership 時安裝 clone-only `ResultsPresentationSnapshot`，最後才解鎖；關鍵流程卻寫成先釋放 ownership，再以 fresh profile 建 snapshot。若依後者實作，release 後插入 public load/write 或 committed bytes 改變，可能讓 snapshot 的 profile 與 settlement receipt/digest 不屬於同一 authoritative commit；若 fresh read 發生 I/O fault，App state 已是 RESULTS、RUN writer 已撤銷，卻沒有前段所承諾的已安裝 snapshot。 | 統一為：在 terminal save 成功後、仍持有 writer ownership 時，由該次 authoritative committed candidate/bytes 建立並捕捉 receipt/digest-bound clone-only Results snapshot，先安裝 root RESULTS state，再解鎖；後續 scene prepare/bind 只能 clone 已捕捉 snapshot，不再重新 public-read。並在 `test_terminal_postcommit_revokes_run_writers_before_results_route` 加入 repository release 後、RESULTS candidate compose 前的 competing load/write probe，證明 receipt/profile pair 不漂移。 |

## Coverage checklist

- PASS：R11 Exit 已拆成 T05 root contract 與 T08 host smoke，測試檔、wave manifest、owner 均分離。
- PASS：R11 settings 已由 T00 port scaffold、T08 fake-port component、T12 concrete
  coordinator／production wiring 分層。
- PASS：R11 recovery 已由 T06 repository fault-preservation 與 T08 cancel-zero-dispatch
  兩份獨立 evidence 封閉。
- PASS：R9/R10 的 Exit、`ABANDON_BOSS_RETRY`、`--combat-lab` exact allowlist 與 AppRoot
  ownership 修正仍一致。
- PASS：repository epoch/full-file CAS、Camp writer transaction、recovery 4×4 restart matrix、
  decoded/opaque preservation 均有追溯。
- PASS：RESULTS retry-vs-Camp/Menu 六組 barrier、settings single-flight、lease/capability/session、
  clone/version boundaries 均有契約。
- PASS：Owning global AC matrix 19 列，R1～R14 均有 task 追溯。
- FAIL：T05/T07 production handoff DAG／ownership 尚不可依 wave gate 執行。
- FAIL：terminal Results snapshot 的 authoritative commit boundary 尚未唯一化。
