# G2 presentation-ui Spec Review — Architecture R13

> Date: 2026-07-29
> Role: fresh read-only Codex reviewer
> Verdict: `NOT APPROVED — 3 unresolved findings`

## Findings

| ID | Severity | file:line | Failure scenario | Proposed fix |
|---|---|---|---|---|
| `G2-R13-A01` | Medium | `specs/presentation-ui/requirements.md:123-127,164-170`; `specs/presentation-ui/design.md:103-115`; `specs/presentation-ui/tasks.md:75-85,179-185`; sanity evidence: `app/state/application_terminal_handoff_port.gd:32-78`, `app/state/terminal_settlement_presentation_capability.gd:28-49`, `app/state/terminal_settlement_coordinator.gd:76-100,120-135` | SDD 要求 repository-issued、單次 `TerminalSettlementPresentationCapability` 在 writer ownership 內被 consume；但 split handoff 又把同一 capability 保存至解鎖後，再交給 concrete presentation adapter 驗證。若 capability 真正於 application install 時消耗，解鎖後 presentation 必然失敗；若像目前 signature 一樣只 `_matches/_authorizes_snapshot` 而不消耗，原 capability 可重播 root/route handoff、重新建立 lease 或安裝 stale snapshot。現有 R12 測試只驗 authorize，未驗 issue authority、atomic consume 或 replay rejection。 | 將 repository authority 與 presentation activation 分成兩個 token：SaveRepository 在 writer ownership 內發出並原子消耗 `TerminalSettlementPresentationCapability`，只授權 AppRoot 安裝 RESULTS；成功安裝後由 AppRoot 發出另一個單次、綁 installed snapshot digest／RESULTS state／route generation 的 `InstalledResultsPresentationCapability` 給 T07 adapter。Terminal capability 不得跨 repository unlock。新增 named joint test，驗 terminal token replay、presentation token repeat、錯 snapshot 與 stale generation 全拒絕，且不更換 state/route/lease。 |
| `G2-R13-A02` | Medium | `specs/presentation-ui/requirements.md:164-180`; `specs/presentation-ui/design.md:416-423,672-680,832-840`; `specs/presentation-ui/tasks.md:179-190` | R12-A02 的修正要求解鎖後所有 RESULTS compose/bind/route 只能使用 AppRoot 已安裝 snapshot 的 clone，不得 public-read 重建；但 retry 設計仍明訂在後續 repository read ownership 內「從 fresh read 建立」新的 `ResultsPresentationSnapshot`。因此同一 SDD 同時要求禁止與允許 post-release reconstruction。若 terminal release 後插入 profile write，retry 可能改用不同 profile pair；若 token 固定舊 full digest，則 legitimate retry 會因任何後續 write 永久拒絕，且 installed snapshot 無法被用來恢復畫面。 | retry 的 repository read 僅用於 receipt/full-digest CAS 與 capability generation 驗證；CAS 成功後，scene candidate 必須取得 AppRoot installed snapshot 的 fresh clone，不得從 read result 重建。若產品意圖允許更新 snapshot，則需另定明確的 root snapshot replacement transaction、版本與 atomic install 規則；不可同時保留「installed clone only」承諾。同步修正 requirements、design、T07/T09 與 retry named test。 |
| `G2-R13-A03` | Medium | `specs/presentation-ui/design.md:117-120,397-433,672-680`; `specs/presentation-ui/tasks.md:120-131,179-195`; `.pipeline/reviews/2026-07-29-presentation-ui-r12-correction-decision.md:9-10`; sanity evidence: `presentation/screens/scene_router_terminal_presentation_handoff_adapter.gd:24-60`, `presentation/screens/results_fallback_navigation_port.gd:4-27`, `tests/integration/presentation_ui_r12_terminal/test_terminal_handoff_captures_authoritative_snapshot_before_release.gd:11-68,106-184` | R12 decision 宣稱 T07 concrete adapter 與 T09 production joint evidence 已封閉 A01/A02，但 supplemental test 使用的是兩個 test fake port，未接 production `SceneRouterTerminalPresentationHandoffAdapter`。目前 concrete adapter 在 RESULTS install 失敗時只回 presentation failure，沒有安裝 `RESULTS_FALLBACK` scene、fallback lease 或 results-only navigation port；`ResultsFallbackNavigationPort` 四個 action 仍固定回 NOT_IMPLEMENTED。terminal save 已提交且 RUN writer/session 已撤銷後若 RESULTS bind/route 失敗，App state 可能已是 RESULTS，但畫面仍是無 writer 的舊 RUN scene，retry/Camp/Menu 全不可用，形成 postcommit soft lock。 | T09 production joint test 必須使用實際 AppRoot＋ApplicationTerminalHandoffPort＋SceneRouter adapter，注入 RESULTS instantiate/bind/install fault，驗 adapter atomic 安裝 `RESULTS_FALLBACK`、啟用唯一 fallback lease、舊 RUN callbacks 全拒絕，且 retry/Camp/Menu port 可操作。實作具 receipt/digest/route-generation CAS、results-action single-flight 與 retry token lifecycle 的 concrete `ResultsFallbackNavigationPort`；只有該 production joint test 綠後，R12 correction decision 才可宣稱 behavioral closure。 |

## R12 closure status

| R12 finding | R13 status | Assessment |
|---|---|---|
| `G2-R12-A01` | `UNRESOLVED` | 文件中的 wave DAG 已消除 T05↔T07 前置循環，但 terminal authority 與 post-release activation 仍共用同一 capability；所稱 production joint evidence實際只使用 test fake。 |
| `G2-R12-A02` | `UNRESOLVED` | 初次 handoff capture/install 邊界已修正，但 retry 路徑仍在 release 後重建 Results snapshot，與 installed-clone-only contract 衝突。 |
| `G2-R12-B01` | `CLOSED` | requirements、design、T11 與 named test 均明列 `0/-1/-4/3/5/8`；實際 test 鎖定 speed/cursor/pause/result/event/save/transcript ownership 與零 gameplay dispatch。 |
| `G2-R12-B02` | `CLOSED` | requirements、design、T12/T14 ownership 與 runtime tests已涵蓋三種 reduced flag、三種 density、tooltip depth guard、zh_TW CJK font/glyph evidence。 |

## 已檢查的高風險 invariants

- T00 → T05 fake application handoff → T07 concrete presentation adapter → T09 joint integration 的文字依賴 DAG 已無前置循環。
- terminal save、snapshot capture、AppRoot install 都被要求位於同一次 writer ownership 且不得 `await`。
- initial Results snapshot 綁 run id、receipt id、完整 committed-file digest 與 clone-only profile。
- terminal commit 後舊 RUN lease/session 不允許復活，postcommit failure 不回滾 settlement。
- RESULTS retry/Camp/Menu 共用 non-reentrant guard，文件保留六組重入 barrier。
- production screen 不取得 raw repository、RunController 或 RunPresentationSession writer。
- Camp mutation、Prepared Continue、recovery token 的 repository identity／epoch／full-file digest 邊界未因 R12 修訂退化。
- B01 playback rejection與 B02 accessibility evidence未發現新的架構／資料安全缺口。
