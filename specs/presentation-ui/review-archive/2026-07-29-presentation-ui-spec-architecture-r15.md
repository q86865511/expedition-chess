# G2 `presentation-ui` R15 Architecture／Data Safety／Lifecycle Review

> Verdict: `NOT APPROVED — 3 High / 2 Medium unresolved findings`

本輪為唯讀審查；未修改檔案、未執行 Godot、未做任何 Git 寫入。未將未來
`content-production` 工作列為 finding。

## Findings

### G2-R15-A01 — High：RESULTS retry 的 AppRoot single-flight guard 取得過晚

- Exact file:line:
  - `presentation/screens/results_fallback_navigation_port.gd:62-80`
  - `presentation/screens/results_fallback_navigation_port.gd:83-85`
  - `presentation/screens/results_fallback_navigation_port.gd:163-173`
  - `app/app_root.gd:1571-1582`
  - `services/save/save_repository.gd:500-534`
- Failure scenario: `prepare_retry()` 先呼叫 `issue_retry_capability()`，repository writer ownership 已開始，
  但 AppRoot action guard 要到後續 `retry()` 才取得。若 capability issuance、repository callback 或
  fault-injection path 重入 Camp/Menu，重入動作可先取得 root guard 並離開 RESULTS；原 retry 並未在
  第一次 lease/route/repository authority 操作前回 `RESULTS_ACTION_IN_PROGRESS`，所以交易並非真正
  單一原子 single-flight。
- Violated requirement:
  - `requirements.md:199-205`
  - `design.md:426-451,809`
- Proposed fix: 由 AppRoot 提供單一同步 retry transaction，先取得 root guard，再 issue/consume CAS
  capability、建立 candidate、stage/commit route，最後才釋放 guard。移除公開
  `prepare_retry()`／`retry()` 分割，或讓 prepare 回傳由 AppRoot 持有 guard 的 opaque operation。
- Required regression evidence: repository ownership 前、issue/observation CAS、ownership release 後、
  capability consume/CAS、candidate bind、route commit/failure 六個 barrier 注入 Camp/Menu 與 sibling
  retry 重入；loser 全回 busy/stale，零 save/state/route/lease mutation，所有錯誤後 guard 釋放。

### G2-R15-A02 — High：terminal postcommit fail-closed 仍依賴第二張可失敗 capability，且未撤銷實際 RUN lease

- Exact file:line:
  - `app/state/terminal_settlement_coordinator.gd:89-118`
  - `app/state/terminal_settlement_coordinator.gd:139-150`
  - `app/state/terminal_settlement_coordinator.gd:163-195`
  - `app/app_root.gd:1010-1018`
  - `app/app_root.gd:1679-1684`
  - `presentation/screens/live_screen_intent_port.gd:8-35`
- Failure scenario: durable terminal save 成功後，primary capability 失敗會改走 fallback capability；若
  fallback issue/consume 或 fail-closed App install callback 也失敗，流程只清除 AppRoot references。
  `_revoke_run_writers()` 未直接呼叫 `_live_lease_registry.revoke_active()`；舊
  `LiveScreenIntentPort` 仍保有 raw session，lease 尚 active 時可能繼續送命令，造成 durable save 已提交
  但 state/route/lease 分裂。
- Violated requirement:
  - `requirements.md:120-129,171-175`
  - `design.md:103-130,394-396,691-702`
- Proposed fix: irreversible save 前預建 no-fail AppRoot revoke/install plan。save 成功後先直接撤銷
  active live lease，再以不依賴第二次 repository proof issuance 的 application-local authority 封存
  RESULTS state/snapshot；跨 boundary proof 不得成為 fail-closed state/lease revocation 的前提。
- Required regression evidence: fallback issue null、consume false、fail-closed callback 缺失/失敗、
  installed capability invalid、RESULTS／RESULTS_FALLBACK 雙 scene fault；每種均證明 save/receipt/reward
  exactly-once、App state RESULTS、RUN lease/session不存在，舊 intent/confirmation/navigation/playback
  ports 全回 `SCREEN_NOT_ACTIVE`。

### G2-R15-A03 — High：production 缺少實際 viewport ownership；目前只有 policy math，且 window size 僅取樣一次

- Exact file:line:
  - `app/main.tscn:5-17`
  - `presentation/viewport/world_viewport_host.gd:1-31`
  - `presentation/viewport/ui_scale_root.gd:1-94`
  - `app/app_root.gd:272-282`
  - `services/settings/adapters/viewport_settings_adapter.gd:7-10,59-68,84-103,118-127`
- Failure scenario: production tree 沒有 `SubViewport`、`SubViewportContainer` 或 `CanvasLayer`。
  `WorldViewportHost`／`UiScaleRoot` 都只是 `RefCounted` 計算物件，未擁有實際 render/input layer。
  AppRoot 啟動時只讀一次 window size，adapter 永久持有固定 `_window_size`；同一實例 resize 後
  world scaling、UI layout 與 pointer mapper 可能持續使用舊尺寸。
- Violated requirement:
  - `requirements.md:210-221`
  - `design.md:511-523`
- Proposed fix: 建立 ApplicationRoot-owned world `SubViewport`／container 與獨立 UI
  `CanvasLayer`／root；加入 viewport resize coordinator，原子更新 world/UI/mapper；adapter
  preflight/activation 取得當下尺寸，不捕捉建構時尺寸。
- Required regression evidence: 真 AppRoot scene tree ownership；同一 boot instance 依序 resize
  720p→4:3→1080p→16:10→1440p，逐次驗實際 viewport nodes、mapper、nearest/integer scale、
  required controls clipping 與 input roundtrip；screenshots 必須來自真 SubViewport texture/UI layer。

### G2-R15-A04 — Medium：zero-size `UiProbe` 仍靜默回退 1280×720

- Exact file:line:
  - `presentation/accessibility/accessibility_runtime_renderer.gd:194-202,470-477`
  - `tests/integration/presentation_ui_r14_self_audit/test_accessibility_root_size_contract.gd:4-28`
- Failure scenario: 外層 root 非零，但內層 `UiProbe` zero-size 時，clipping helper 使用虛構
  `Vector2(1280,720)`，可產生 false-green；現有測試未命中此 helper。
- Violated requirement:
  - `requirements.md:219-220`
  - `design.md:714-716`
- Proposed fix: 移除 fallback；bounds root 缺失或 zero-size 時，`runtime_report()` fail closed 並傳
  `ACCESSIBILITY_ROOT_SIZE_INVALID`。`design_size` 只可用於明示 detached evidence mode。
- Required regression evidence: 非零 host＋zero probe、resize-to-zero、缺 probe 均回精確 typed error；
  valid root/probe 使用實際 viewport bounds並準確偵測裁切。

### G2-R15-A05 — Medium：R14 B07／T15 canonical ledger 過期且互相矛盾

- Exact file:line:
  - `.pipeline/t15/ac-evidence-ledger.md:4-69`
  - `.pipeline/t15/manifest-audit.md:7-24`
  - `.pipeline/t15/final-automation-evidence.md:4-35`
  - `specs/presentation-ui/review-log.md:254-270`
- Failure scenario: canonical ledger仍標 R12 deferred/gap；manifest audit為21/84，final automation為
  836 tests，但 review-log為920 tests、36/107。不同 canonical artifact 對相同 completion state
  給相反結論，無法驗 merge readiness。
- Violated requirement:
  - `requirements.md:370-379`
  - `tasks.md:297-310`
- Proposed fix: 其餘修正後重建三份 T15 canonical files；19 AC逐列 final
  PASS/FAIL/adjudication，manifest為目前36/107，所有數字連到同一次 fresh run/read-back，舊數字明標
  historical。
- Required regression evidence: deterministic manifest audit 107/107；文件一致性檢查 T15 ledger、
  fresh summary、review-log的test/assertion/manifest/revocation數字。本輪唯讀 SHA 稽核為
  36 manifests、107 entries、107 matches、0 mismatch、0 missing、107 unique paths。

## 已確認封閉的 R14 findings

- R14-A01：terminal digest 不再 post-save reread；postcommit fail-closed 仍受 R15-A02 影響。
- R14-A02：route generation authority drift 已封閉。
- R14-A03/B01：staged-to-live production activation 已接 typed ports/concrete composition；玩家可操作
  表面完整度另由 R15-B01追蹤。
- R14-A04/B02：一般 route precommit staging已封閉；retry guard ordering由 R15-A01重開。
- R14-A05：production screen raw authority leakage已封閉。
- R14-B03：雙 RESULTS scene fault的舊 route lease已在 adapter先撤銷；fallback proof失效仍由
  R15-A02追蹤。
- R14-B04：visible text localization已封閉。
- R14-B05：settings/accessibility joint wiring已封閉。
- R14-B06：layered runtime matrix evidence存在；不等同實際 viewport ownership，亦未覆蓋zero probe。
- R14-B07：未封閉，由 R15-A05接續。

## Evidence limitations

本輪遵守唯讀限制，未執行 Godot。SaveRepository ownership/CAS、terminal capability binding、
settings single-flight 與現有 manifest SHA integrity 已抽查；未發現除上述 findings 外的新缺口。
