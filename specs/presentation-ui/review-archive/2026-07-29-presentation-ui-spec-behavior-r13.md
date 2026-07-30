# G2 `presentation-ui` Spec Review — Behavior R13

> Date: 2026-07-29
> Role: fresh read-only Codex reviewer B
> Verdict: `NOT APPROVED — 3 unresolved findings`

## Findings

| ID | Severity | file:line | Failure scenario | Proposed fix |
|---|---|---|---|---|
| `G2-R13-B01` | High | `specs/presentation-ui/requirements.md:135-144`; `specs/presentation-ui/design.md:254-268`; `specs/presentation-ui/tasks.md:210-222`; `tests/integration/presentation_ui_r12_playback/test_invalid_playback_multiplier_preserves_committed_session_ownership.gd:18-38`; `presentation/screens/live_screen_intent_port.gd:25-82` | R12-B01 的 locked test 直接建立 raw `RunPresentationSession` 並呼叫 `set_playback_speed()`，但正式 screen 依 R4/R5 不得取得 raw session，只能透過 lease-bound port。現有 `LiveScreenIntentPort` 只有 gameplay dispatch／confirmation，沒有 speed、pause 或 playback read/drain API；design 公開 session API也缺少 `set_playback_paused(bool)`。因此 invalid matrix 雖綠，正式戰鬥畫面仍無合法方式切換 1×/2×/4×或 pause/resume；實作者只能讓按鈕 no-op，或把 raw session/controller 洩漏給 screen，兩者都違反規格。 | 新增 lease-bound `LiveScreenPlaybackPort`，或在既有 live port 增加 typed playback methods，至少包含 `try_playback`、`set_speed`、`set_paused`、`drain_window`；每次操作先驗目前 `LiveScreenLease`／route generation。將 B01 named test改由此正式 port 執行 `0/-1/-4/3/5/8`、1×/2×/4×及 pause/resume，並驗 stale lease 回 `SCREEN_NOT_ACTIVE`、狀態不變、零 gameplay dispatch；另加入 production combat-screen binding smoke。 |
| `G2-R13-B02` | Medium | `specs/presentation-ui/requirements.md:304-311`; `specs/presentation-ui/design.md:783-785`; `specs/presentation-ui/tasks.md:224-244`; `.pipeline/reviews/2026-07-29-presentation-ui-r12-correction-decision.md:12`; `tests/runners/presentation_r12_accessibility_runner.gd:3-12,57-58,110-123`; `presentation/accessibility/accessibility_runtime_renderer.gd:170-174` | R12-B02 的 3 張 screenshot 全部來自 `tests/fixtures/presentation_r12_accessibility/accessibility_runtime_probe.tscn`；renderer 又硬依賴只存在於該 fixture 的 `MotionProbe`、`FlashProbe`、`ParticleProbe`、`DamageEvents`。唯讀搜尋未找到 production scene、AppRoot 或 settings runtime consumer 使用 `AccessibilityRuntimeRenderer`／`LocalizedTypographyPolicy`。因此實際正式畫面即使 reduced motion／flash／particles 或 density 設定完全 no-op，現有 4/4 GUT 與 3/3 PNG 仍會全綠；三個 reduced flag 的 screenshot 也只有「全部同時開啟」一例，無法逐項定位錯接。 | 明定並實作 production accessibility consumer/node contract，由 `SettingsApplicationCoordinator` 的 production binding 將 committed settings 套到實際正式 scene/effect hosts。新增 joint runtime test，透過正式 settings port 載入至少 RUN_COMBAT 與 tooltip/CJK 所在 production scene，逐項切換三個 reduced flag及 `off/reduced/full`，驗 concrete emitter/runtime state與規則文字；screenshot 至少能獨立判定 motion、flash、particles、density，而不是只拍 test fixture。Static gate 應確認所有需支援的 production scene 都有相容 binding。 |
| `G2-R13-B03` | Medium | `specs/presentation-ui/requirements.md:120-129`; `specs/presentation-ui/design.md:103-115`; `app/state/terminal_settlement_presentation_capability.gd:28-49`; `app/state/application_terminal_handoff_port.gd:32-88`; `tests/integration/presentation_ui_r12_terminal/test_terminal_handoff_captures_authoritative_snapshot_before_release.gd:135-155` | 規格要求 repository-issued terminal capability 是單次、在 writer ownership 內 consume，且不得帶出 transaction；但 split handoff evidence 在 ownership 釋放後仍把同一 capability 傳給 `present_installed_handoff()`／concrete presentation port。Capability 本身沒有 consumed state，`_matches()`／`_authorizes_snapshot()` 可重複成功，`ApplicationTerminalHandoffPort.commit_handoff()` 也可用同一 capability 再次 install＋present。現有 test 只驗一次成功，沒有 replay/reentrant matrix。若 adapter 保留或重送 capability，可能重複 application transition callback或 route commit，破壞單次 terminal handoff 與 receipt exactly-once 的可判定性。 | Terminal capability 僅在 writer ownership 內由 application layer原子 consume並永久失效；解鎖後 presentation 不再接收它。可改為 application port 內部持有 sealed installed handoff，並產生用途受限的 presentation activation token，或讓 `present_installed_handoff()` 無 capability 參數。Named test 加入 duplicate install、duplicate present、adapter reentry、stale capability與 direct `commit_handoff()` replay，驗 application transition／route各只提交一次，且 presentation port 永遠看不到 repository terminal capability。 |

## R12 finding disposition

| R12 finding | R13 判定 | 說明 |
|---|---|---|
| `G2-R12-A01` | `CLOSED_IN_SPEC — new R13-B03 at split boundary` | T00/T05/T07/T09 的 ownership DAG 已拆開；原始循環已消除。但新的 split contract 尚未封閉 capability 單次消耗與 transaction containment。 |
| `G2-R12-A02` | `CLOSED` | Requirements/design 已統一為 ownership 內 capture/install、release 後只呈現 installed clone；real repository/coordinator probe 證明競爭 load/save 不使 receipt/profile pair 漂移。 |
| `G2-R12-B01` | `UNRESOLVED` | Invalid multiplier raw-session matrix 本身通過，但正式 lease-bound screen path與 pause API缺失，玩家無法依允許邊界操作。 |
| `G2-R12-B02` | `UNRESOLVED` | Runtime fixture、tooltip與 CJK probe 有證據，但未接到 production scenes/settings binding，不能排除正式畫面 no-op。 |

## 實際檢查的矩陣與 evidence invariants

- `0/-1/-4/3/5/8`：locked test 有逐值 `PLAYBACK_SPEED_INVALID`、x2 speed、cursor、pause、transcript identity、event hash/order、save-facing snapshot與零 dispatch斷言。
- Terminal snapshot：authoritative committed candidate、receipt id、完整 file digest、profile clone、ownership release後 competing load/save與 presented clone一致性。
- Accessibility：三個 reduced flags 的個別 GUT切換、density `off/reduced/full`、tooltip `0/1/2/3`與 invalid no-partial、14個繁中 glyph、3張 GUI PNG。
- Manifest integrity：R12 terminal `2/2`、playback `2/2`、accessibility `6/6` SHA-256 全相符，零 missing/mismatch。
- AC traceability：19條 owning AC 在 design matrix 各有唯一列；R1～R14與 T00～T15 機械追溯仍完整。
- 未啟動 Godot、未修改任何檔案、未執行 Git mutation。
