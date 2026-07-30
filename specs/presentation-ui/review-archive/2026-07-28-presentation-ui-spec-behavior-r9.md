# G2 presentation-ui R9 — Behavior / UX / Test Coverage Review

## Verdict

**NOT APPROVED — 3 named-test coverage findings**

`G2-R8-01` 的六組 retry-vs-Camp/Menu reentrant barriers 已完整修入 requirements、
design、T07、T09 與 named lifecycle test；但 R1、R3、R5 仍有三項明示行為可在現有
具名測試全綠時漏實作。

## Findings

| ID | Severity | File:line | Failure scenario | Proposed fix |
|---|---|---|---|---|
| G2-R9-B01 | Medium | `requirements.md:79`; `design.md:63-75,219-220,710-738`; `tasks.md:112-122` | 實作可讓 `request_exit()` 直接呼叫 `SceneTree.quit()`，或按鈕無反應；現有 named matrix 沒有驗「只發可攔截 request、不終止 runner」。T08 的「menu 四動作」也未鎖 signal／fake-host 語意。 | 新增 `test_exit_request_is_interceptable_and_does_not_quit_runner`，或明確併入 menu named test；驗 fake host 收到一次 request、runner 存活、App state／route／save 不變，重複或錯 lifecycle 回具名結果。 |
| G2-R9-B02 | Medium | `requirements.md:146-148`; `design.md:276-286,724`; `tasks.md:124-148` | `ABANDON_BOSS_RETRY` 已列為需 confirmation 的不可逆 intent，但 `test_irreversible_confirmation_cancel_and_exactly_once` 的輸入只明列 forge／relic replace／reward abandon。實作可讓 Boss retry 放棄在第一次按鍵直接 dispatch，而 full-intent test 仍通過。 | 將 `ABANDON_BOSS_RETRY` 明列進該 named test，逐一驗 begin 不寫、cancel 零 intent、confirm exactly-once、repeat/stale/換場 lease 拒絕。 |
| G2-R9-B03 | Minor | `requirements.md:35-38`; `design.md:712-723`; `tasks.md:18-23,40-46` | R1 要求明示 dev CLI 仍可啟動且共用 production facade，但 named matrix 只驗 production dependency graph；現有 Smoke 也只載 `app/main.tscn`。`--combat-lab` 等入口可壞掉或保留第二套流程而所有列名測試仍綠。 | 新增 dev-entry smoke named test，列舉受支援 CLI flags，以 fake services 啟動並驗其消費 production bootstrap/facade；T01/T04 分別負責 bootstrap 與 RunLab wrapper。 |

## Coverage checklist

- `G2-R8-01`：FIXED；repository ownership 前、CAS/release 後、candidate bind 中 ×
  Camp/Menu，共六組。
- Loser semantics：busy/stale typed error、零 gameplay save、零 route commit。
- Guard lifecycle：首次 fallback lease 驗證前取得，跨 repository unlock 持有，
  所有出口 finally-style 釋放。
- Results consistency：App state／route／唯一 lease 一致；transient failure 後
  fresh action 可成功。
- Boot/menu/continue/start/recovery、Camp transaction、scene lease/stale callback：
  已具名覆蓋。
- Settings clone/atomicity/single-flight、audio 四 bus、localization、
  keyboard/focus/accessibility：已具名覆蓋。
- Playback ownership/backpressure、pre/post commit error boundary、Collection clone/compare、
  combat inspection：已具名覆蓋。
- R1～R14 → Tasks：14/14；T00～T15 均有 Covers。
- Owning global AC：19/19，集合完整且無重複。

本次只讀審查，未修改 production／spec、commit、push 或 merge。
