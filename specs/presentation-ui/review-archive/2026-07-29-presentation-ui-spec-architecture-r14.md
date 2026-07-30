# G2 `presentation-ui` Spec／Implementation Consistency Review — Architecture R14

> Verdict: `NOT APPROVED — 5 unresolved findings`

## Findings

`High | app/state/terminal_settlement_coordinator.gd:70-130; services/save/save_repository.gd:339-390 | terminal save 成功後，coordinator 仍以 `_committed_file_digest()` 再讀 storage 兩次來 issue／consume capability；任一次 post-save read fault 都會令 capability 無效。之後程式先撤銷 RUN writer/session，再於 capability-invalid 分支直接返回，卻沒有安裝 App state RESULTS 或 RESULTS_FALLBACK，留下 state=RUN、存檔已結算、但 writer/session 已消失的 soft lock，違反 tasks T05「意外 post-save handoff failure 也先 fail-closed revoke 再進 fallback」及 R12 postcommit fallback 規則。 | 讓 `_save_while_owned()` 的 authoritative committed result/bytes/digest 直接供 snapshot 與 capability 使用，避免 commit 後重新讀檔；一旦 save 已提交，所有 capability/callback 異常出口都必須先安裝 sealed RESULTS state/snapshot 並建立可操作的 RESULTS_FALLBACK，再釋放 ownership。新增 digest-read fault、capability issue/consume fault與 application-install fault matrix，驗 state/route/lease、receipt與 reward exactly-once。`

`High | app/state/application_terminal_handoff_port.gd:55-60; presentation/screens/scene_router_terminal_presentation_handoff_adapter.gd:44-58,91-109; app/app_root.gd:526-547 | ApplicationTerminalHandoffPort 每次 terminal install 都把 `_next_route_generation` 加一，但 concrete adapter 的 `_route_generation` 只有 retry 成功時才加一，正常 RESULTS install／exit 都不前進；而 AppRoot 會跨多次 expedition 重用同一 coordinator、application port 與 adapter。第一局 capability generation=1 可成功，第二局 capability generation=2 必然被仍期待 generation=1 的 adapter 拒絕，且拒絕發生在 fallback scene 安裝前，第二局結算後會停留在失效 RUN 畫面。 | 將 route generation 收斂到單一 route transaction authority；installed capability 應綁實際 prepared target generation，adapter 在每次 RESULTS／fallback／exit commit 後同步推進或重新取得 generation，不得各自維護漂移的 counter。新增同一 AppRoot 連續兩局 start→settle→Camp/Menu→start→settle 的 production joint test，驗兩次 route、lease、snapshot及 replay/stale rejection。`

`High | services/scene/scene_router_service.gd:27-59; presentation/screens/staged_screen_context.gd:10-21; presentation/screens/production_screen.gd:19-29; presentation/screens/run_combat_screen.gd:10-23; app/app_root.gd:776-810 | 實際 AppRoot→SceneRouter production 路徑只建立 snapshot-only StagedScreenContext 並呼叫 base `bind()`；全 production tree 沒有建立 ScreenActivationCapability、LiveScreenIntentPort 或 LiveScreenPlaybackPort，也沒有呼叫各 RUN screen 的 `compose()`／`bind_playback_port()`。R13 playback evidence 是測試直接手動 new port 再 bind screen，因此即使它全綠，正式 RUN_COMBAT 仍永遠沒有 playback port，其他正式 RUN screen 也沒有合法 gameplay intent writer；staged→live activation、stale lease及正式玩家流程實際未接通。 | 在 ApplicationRoot／SceneRouter 實作完整 staged→prepared route→atomic live activation：staged candidate 只收 clone/read context，route commit 後以不可偽造 capability 建立當代 lease-bound intent/navigation/playback ports並注入相符 screen；離場同步 revoke。新增從真 AppRoot boot/start/continue 進 RUN_MAP/PREPARE/COMBAT/REWARD 的 production joint test，直接操作真 screen，並驗舊 screen/port stale。`

`High | app/app_root.gd:550-578; presentation/screens/results_fallback_navigation_port.gd:55-106,135-164 | retry/Camp/Menu 的 single-flight 只存在 ResultsFallbackNavigationPort，不在規格要求的 AppRoot results-action authority；AppRoot 的 public return actions 可繞過 port guard。且 Camp action先提交 RESULTS→CAMP 再 route，route fault 無法保留 RESULTS；Menu action更完全未呼叫 `_route_for_state()`，卻回 success，port 隨後撤銷 RESULTS lease，造成 state=MENU、畫面仍是 RESULTS/RESULTS_FALLBACK 且無有效 lease。重入時若直接呼叫 AppRoot exit，retry 還可在 state 已離開 RESULTS 後重新安裝 RESULTS route/lease。 | 建立 AppRoot-owned non-reentrant results action coordinator，所有 normal/fallback retry與兩個 public exit action都委派同一 guard；先 stage target scene與準備 App/subroute token，再同步提交 state/route/lease，任何 bind/route fault保留 RESULTS與原 lease。Menu、Camp 都必須明確 commit MENU_MAIN/CAMP_WORLD。補真 AppRoot 六 barrier direct-call、Camp/Menu bind fault、成功 target及零 save evidence。`

`Medium | presentation/screens/presentation_route_coordinator.gd:15-18,27-53,91-133; presentation/screens/staged_screen_context.gd:4-17; tools/presentation_ui_static_gate.gd:502-533 | PresentationRouteCoordinator 公開 `active_session()` 直接回傳 raw RunPresentationSession，StagedScreenContext 也仍公開保留 `run_session` 與 generic `intent_port` 欄位，與 design「staged context 只有 clone-only snapshot/read ports、production context 絕不包含 raw session」矛盾。Static gate 的 screen writer 掃描只阻擋 SaveRepository、SettingsRepository、RunController，未阻擋 RunPresentationSession、RunCommandFactory、ApplicationRoot、CampController，所以這個 raw-session surface 仍會通過 gate。 | 移除 `active_session()` 與 StagedScreenContext 的 raw writer/session 欄位；session continuity 留在不可被 screen 取得的 application/route owner，screen 只收具名 staged/live context。擴充 static gate 禁止完整 writer/facade type set，並加負向 fixture證明每一種 raw dependency 都使 gate 非零退出。`

## 已檢查範圍

- 對照 `requirements.md`、`design.md`、`tasks.md`、`review-log.md`、`g2-roadmap.md`。
- 追查 R13 architecture／behavior findings 的 terminal authority split、retry observation CAS、production fallback、playback port、accessibility production binding。
- 讀取相對 base `93f68ceaf65b6de430f09b8526ebcfb97c79c5c5` 的完整狀態與重點 production/test diff。
- 檢查 repository identity／epoch、terminal capability consume、installed clone、retry single-flight、settings two-phase、recovery/archive及 static gate。
- `git diff --check` 無 whitespace error。
- 依指示未平行執行 Godot，且全程未修改檔案。

## 殘餘風險

修正上述 findings 後，fresh reviewer 應特別重查多局 terminal lifecycle、真 AppRoot route activation，以及 AppRoot-owned results action guard；現有多份 supplemental green evidence主要驗 isolated port／手動 composition，不能取代這三條 production joint path。
