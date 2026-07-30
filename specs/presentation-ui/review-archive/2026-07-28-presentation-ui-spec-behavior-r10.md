# G2 presentation-ui R10 — Behavior / UX / Test Coverage Review

## Verdict

**NOT APPROVED — 2 Medium unresolved findings**

R9-B02 已完整封閉；R9-B01、B03 的行為／named-test 內容已寫清楚，但 production 實作
ownership 尚未落到唯一能修改 `ApplicationRoot` 的 T05。

## Findings

| ID | Severity | File:line | Failure scenario | Proposed fix |
|---|---|---|---|---|
| `G2-R10-B01` | Medium | `design.md:219-226`; `tasks.md:55-75,117-124` | Exit 契約要求新增 `ApplicationRoot.request_exit()`、pending guard 與 signal；但 T05 是 AppRoot 唯一 integration owner，驗收卻未分配 Exit。T08 只分配 UI／named test，若遵守 ownership 就不能新增 AppRoot API；若修改 AppRoot 又違反 pipeline scope。 | 在 T05 明列：新增 `exit_requested`、`request_exit()`、MENU_MAIN lifecycle、pending exactly-once guard、typed errors、state/route/lease/save 不變；T08 只負責按鈕、fake-host smoke 與 runner 存活。named test 由 T05 unit＋T08 smoke 共同提供 evidence。 |
| `G2-R10-B02` | Medium | `requirements.md:39-42`; `design.md:228-234`; `tasks.md:18-24,41-51,55-75,237-240`; `app/app_root.gd:111-119,275-285` | CLI 解析／`--combat-lab` 啟動位於 AppRoot，但 full smoke 只分配 T01/T04，兩者都明定不得改 AppRoot。T01/T04 即使完成 bootstrap/facade wrapper，也無法讓「以 flag 啟動、bind、bootstrap exactly once」的 named smoke 轉綠。另 T04 實際承擔 R1 facade 共用，卻只 Covers R5/R12，R→Tasks 也漏 T04/T05。 | T01 保留 bootstrap component test、T04 保留 facade/Combat Lab wrapper component test；把 composition-root exact allowlist、CLI launch/bind 與完整 named smoke 明列給 T05。將 T04、T05 加入 R1 Covers／R→Tasks，完整 smoke 標為 T05 後置整合 gate。 |

## Coverage checklist

- R9-B01 行為完整；production ownership 未封閉。
- R9-B02：`ABANDON_BOSS_RETRY` confirmation matrix PASS。
- R9-B03 行為完整；task ordering／ownership 未封閉。
- 其餘 boot/menu/camp/run/results/recovery、confirmation、accessibility/localization、
  pre/post commit、terminal/results six barriers 均具名覆蓋。
- 19 條 owning global AC evidence matrix：19/19，無重複。

本次只讀審查，未修改、commit、push 或 merge。
