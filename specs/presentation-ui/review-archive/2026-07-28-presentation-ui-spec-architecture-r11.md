# G2 presentation-ui Spec Review — Architecture R11

> Date: 2026-07-28
> Role: fresh read-only Codex reviewer
> Verdict: `NOT APPROVED — 1 unresolved finding`

## Finding

| ID | Severity | file:line | Failure scenario | Proposed fix |
|---|---|---|---|---|
| `G2-R11-A01` | Medium | `specs/presentation-ui/tasks.md:83-84,130-133,236-243`; `specs/presentation-ui/design.md:736` | 同一具名測試 `test_exit_request_is_interceptable_and_does_not_quit_runner` 同時分配給 wave2/T05 的 root behavior 與 wave3/T08 的 UI/host smoke。若 T05 建立並鎖定該測試，T08 後續補 UI/host assertions 會改變已鎖定 SHA-256；若 wave2 一開始就包含完整 UI/host assertions，T08 尚未實作時 wave2 無法轉綠。因此目前無法同時遵守逐 wave green 與 manifest 不變兩項 Gate。 | 明定兩個獨立測試檔與名稱，例如 T05 鎖定 `test_exit_request_root_contract_is_single_flight_and_interceptable`，T08 另鎖定 `test_exit_button_host_binding_keeps_fake_runner_alive`；design 測試矩陣分列兩筆。兩者共同構成 R3 Exit evidence，但不得在 T08 修改 T05 manifest 內測試。 |

## Coverage checklist

- R10 AppRoot ownership：T05 明確是 AppRoot/AppStateMachine 唯一 integration owner；Exit
  signal/API/pending guard 與 CLI parse/route/bind 均已移至 T05。
- T01/T04 邊界：僅負責 bootstrap、facade、battle ports 與 dev wrapper components，明確不得
  修改 AppRoot。
- T08 邊界：只負責 Exit button、production host binding 與 fake-host smoke，明確不得修改
  AppRoot。
- R1 traceability：T04/T05 已同時納入 Covers 與 R→Tasks。
- R9 回歸：Exit typed lifecycle、`ABANDON_BOSS_RETRY` confirmation matrix、
  `--combat-lab` exact allowlist 與 production facade/bootstrap 契約均仍完整。
- 已查 repository identity/epoch/full-file CAS、Camp writer transaction、recovery 4×4 crash
  matrix、terminal joint ownership、RESULTS 六組重入 barrier、fixed lock ordering/no-await、
  settings single-flight、session/lease/capability clone boundaries；未發現其他未決問題。
- T00～T15 DAG 與 production ownership 除上述 Exit 測試跨 wave 鎖定衝突外可執行。

## Review limitation

指定的 `prompts/spec-review.md` 不存在於 worktree 或 Git history；本次改依
`requirements.md`、SDD 三件套與 claude-harness review rubric 執行。
