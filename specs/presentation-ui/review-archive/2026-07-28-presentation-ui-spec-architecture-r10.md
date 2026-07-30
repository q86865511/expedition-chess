# G2 presentation-ui R10 — Architecture / Data Safety / Concurrency Review

## Verdict

**NOT APPROVED — 2 unresolved ownership／wave findings**

R9-B01～B03 的行為契約本身已補齊，但 B01、B03 的 AppRoot 實作責任未配置到唯一
integration owner，會讓 gated TDD 無法在不違反檔案 ownership 的前提下轉綠。

## Findings

| ID | Severity | File:line | Failure scenario | Proposed fix |
|---|---|---|---|---|
| `G2-R10-A01` | Medium | `specs/presentation-ui/design.md:228-234`; `tasks.md:18-24,41-75,223-238`; `app/app_root.gd:111-113,275-285` | `--combat-lab` 的 parse／route 位於 AppRoot。T01、T04 被要求讓 integrated CLI smoke 通過，卻都明禁修改 AppRoot；T05 才是唯一 AppRoot owner，但 Covers、驗收及 R1→Tasks 均未納入 CLI/R1。結果是 wave1 測試無法合法轉綠，或 worker 必須重開重疊 ownership。T04 實際承擔 R1 named test，但其 Covers 只有 R5/R12，雙向追溯也漏 T04。 | T01 僅交付 bootstrap/receipt component；T04 僅交付 facade、battle ports 與 dev wrapper component；把 composition-root CLI 接線及 integrated smoke 明確交 T05，T05 加入 R1 Covers／驗收，R1→Tasks 加 T04/T05。wave1 只鎖 component green，完整 CLI smoke 在 T05 整合後轉綠；指定單一 test-file owner。 |
| `G2-R10-A02` | Medium | `specs/presentation-ui/design.md:62-75,219-226`; `tasks.md:55-75,117-124,225-226`; `app/app_root.gd:18-20,90-125` | B01 要求 `ApplicationRoot.request_exit()`、pending guard 與 signal，但修訂只把 named behavior 放進 T08；T05 宣告是 AppRoot 唯一 owner卻未列 Exit。T05 可依現有驗收完成而漏掉 root API，之後 T08 不是無法讓測試綠，就是必須違反 sole-owner 規則修改 AppRoot。 | T05 明列擁有 `request_exit()`、`exit_requested`、pending/lifecycle validation 與 root behavioral test；T08 僅擁有 MENU button、production host quit binding 及既有 fake-host runner smoke。保持只有 host 能呼叫 `SceneTree.quit()`。 |

## Coverage checklist

- R9-B01 行為完整；僅 ownership 未封閉。
- R9-B02：`ABANDON_BOSS_RETRY` exactly-once matrix PASS。
- R9-B03 行為完整；僅 integration ownership／追溯未封閉。
- Repository ownership／CAS、lock ordering、recovery、terminal/results、lease/session/capability、
  clone/version boundary 均 PASS。
- `git diff --check` 通過。

本次只讀審查，未修改、commit、push 或 merge。
