# G2 presentation-ui — 任務清單

> 建立日期：2026-07-26｜狀態：T00～T15 已合併（PR #5／PR #6）
> 對應需求：[requirements.md](requirements.md) R1～R14；設計依據：[design.md](design.md)
> 本檔為 pipeline 任務來源；核可前不得建立 TDD 紅燈或修改 production code。
> 勾選只由 pipeline 收尾回寫。

## Gate A — production 依賴與資料契約

- [x] **T00 [NORMAL][TDD] Compile-safe typed contract scaffold**
  - Covers：R1、R2、R3、R4、R5、R7、R8、R9、R12；依賴：無
  - 驗收：測試代理先以 dynamic `load()`／Spec static inspection 建立 contract-red，不直接引用
    尚不存在的 `class_name`；實作只新增 compile-safe typed declarations、stable enum/string constants
    與 result/snapshot/request/capability/buffer skeleton（含可注入的
    `SettingsApplicationPort`、`ApplicationTerminalHandoffPort` 與
    `TerminalPresentationHandoffPort` typed contract），不實作行為；contract tests 綠後，
    T01～T12 的 behavioral test
    代理才可靜態引用型別並建立真正紅燈。GUT parser abort 不算有效 behavioral-red。

- [x] **T01 [HARD][TDD] 正式 content bootstrap、dependency port 與 localization catalog**
  - Covers：R1、R10；依賴：T00
  - 驗收：`ProjectContentBootstrap` 移出 dev；production asset／localization dependency 真實查驗；
    `zh_TW` 預設且非空，`en` key set 完全相同；Build Lab 改消費同一 bootstrap；刪 asset／key
    使 Content gate 具名非零。檔案 owner 限 `app/content/`、localization、Build Lab adapter 與
    對應 component tests；提供可注入且可計數的 production bootstrap／receipt component，
    供 T05 integrated CLI smoke 驗 bootstrap 僅執行一次。本任務不改 `app/app_root.gd`，
    不負責 CLI parse／route／bind；production graph 最終接線由 T05。

- [x] **T02 [HARD][TDD] SettingsSnapshot v1 與原子 SettingsRepository**
  - Covers：R8；依賴：T00
  - 驗收：stable string enums、四 bus `volume_bps`／mute 與安全 defaults 精確 round-trip；
    非法 enum／型別／範圍具名拒絕；injectable storage；tmp/read-back/promote/final fault 零 swap；
    corrupt schema-1 archive＋defaults；future schema 原 bytes 保留並鎖一般 save，只有 expected
    digest 明示 reset 且先 archive 才寫 v1；public input 全部 deep clone-in，load/current/result/
    signal 全部 deep clone-out，committed object graph 不外流；input mutation、雙 consumer alias
    回歸；Smoke/GUT 不碰真實 `user://`；gameplay schema 維持 3。

- [x] **T03 [NORMAL][TDD] AudioCoordinator 四 bus adapter**
  - Covers：R9；依賴：T02
  - 驗收：Master／Music／SFX／UI volume_bps 與 mute 由 committed settings 重建；各 bus 獨立；
    `AudioBusPort.apply_batch()` 寫前 preflight 全 bus，缺 bus／before-commit adapter fault
    零 mutation；commit 段不可失敗；headless 用 fake audio port。

- [x] **T04 [HARD][TDD] RunPresentationSession typed facade**
  - Covers：R1、R5、R12；依賴：T00
  - 驗收：typed snapshot／intent／result 逐項對應全部既有玩家 command（含出售、鍛造、裝備、
    拆卸、各 reward/overflow、遺物替換／放棄）；所有 writer 只經擴充後 RunCommandFactory＋
    RunController；失敗保留前 snapshot 與 source diagnostics；snapshot/accessor/signal 每次 deep
    clone、雙 consumer 無 alias；no-playback typed result；RunLabSession 改 consumer／薄 wrapper。
    Combat Lab／Run Lab dev wrapper 不得保留第二套 command／battle 規則流程；
    component test 驗 wrapper 只消費 production facade／battle ports；exact allowlist parse、
    入口 bind 與完整 `test_supported_dev_cli_entries_consume_production_facade` 由 T05 負責。
    檔案 owner 限 `presentation/run/`、RunCommandFactory、RunLab／CombatLab wrapper 與 tests；
    不改 AppRoot。

## Gate B — App/menu/recovery 與正式場景

- [x] **T05 [HARD][TDD] Boot→MENU、Prepared Continue、Camp start 與 return-to-menu lifecycle**
  - Covers：R1、R2、R3、R4、R12；依賴：T01、T04
  - 驗收：本任務是 `app/app_root.gd`／AppStateMachine 的唯一 integration owner；no-save/run-free/
    active-run boot 都先 MENU；SaveRepository 每個 public load/write 推進 operation epoch；
    exact dev CLI allowlist 僅 `--combat-lab`，AppRoot 負責 parse／route／bind T01 production
    bootstrap 與 T04 production facade/battle ports；本任務單獨擁有 integrated test file
    `test_supported_dev_cli_entries_consume_production_facade`，驗 bootstrap 一次、無第二套規則、
    runner 存活，且該 smoke 只要求在 T05 完成後轉綠；
    RunPreparationService 以 repository identity／epoch／完整 committed file digest／run／manifest
    產單次 capability，consume ownership 內 fresh-read；Start 只在 `RunStatus.NONE` 進 CAMP；
    PurchaseUnlock／StartExpedition／decoded/opaque DiscardActiveRun 與所有 Camp writer 一律經
    repository-owned CampMutationTransaction；在同一次 ownership 內 fresh-read、比對
    identity/epoch/full digest/typed expectation、apply/validate/internal-save，全段不得 await；
    `start_expedition(StartExpeditionRequest)` 原子建立唯一 run 並 CAMP→RUN，
    pre-commit failure 零寫、post-commit compose/route failure 保留 run＋recovery；RUN→MENU 後
    revoke/release；RESULTS→CAMP 與 RESULTS→MENU 是兩個 typed event，僅 terminal/meta receipt
    已提交時可用且不再寫 save，成功分別進 CAMP_WORLD／MENU_MAIN，重入/stale/bind fault 保留
    RESULTS；本任務新增 TerminalSettlementCoordinator，固定鎖序取得 AppRoot terminal
    single-flight＋SaveRepository writer ownership，preflight revoke plan 後在同一 ownership 內
    terminal save→由 authoritative committed candidate/bytes 捕捉 receipt/full-digest-bound
    clone-only Results snapshot→internal capability consume→revoke RUN writer lease→
    invalidate/release session→以 `ApplicationTerminalHandoffPort` 安裝 App state RESULTS，最後
    才解鎖；capability 綁 repository identity/operation epoch/run id/receipt id/full
    digest且不外流，handoff 全段不得 await、terminal dispatch 不先返回。T05 只用 injectable
    fake presentation port 驗 AppRoot guard/repository/state/session ownership，不實作
    SceneRouter/lease/fallback concrete adapter。插入競爭 public
    load/write 必須等 handoff；意外 post-save handoff failure 也先 fail-closed revoke 再進 fallback；
    SaveRepository internal factory 發出的 TerminalSettlementPresentationCapability 必須在
    ownership 內原子 consume並永久失效，不得保存或交給解鎖後 adapter；AppRoot install 後另發
    InstalledResultsPresentationCapability，綁 installed digest/RESULTS state/route generation；
    再交 T07/T09 組畫面；
    新增 `exit_requested` signal、`request_exit()` 與 pending guard：只在 MENU_MAIN 可用，首次
    合法呼叫發一次 signal，重複 pending 回 `EXIT_REQUEST_ALREADY_PENDING`，錯 lifecycle 回
    `APP_ACTION_NOT_AVAILABLE`；signal 前後 state/route/live lease/save digest 不變，AppRoot
    絕不直接 `SceneTree.quit()`。T05 單獨擁有 root test file
    `test_exit_request_root_contract_is_single_flight_and_interceptable`；該檔在 wave2 鎖定後，
    T08 不得修改；
    stale/偽造 capability、競爭 Camp writer、invalid/I/O 具名 fail-closed。

- [x] **T06 [HARD][TDD] Retained-run recovery token 與 archive-before-clear**
  - Covers：R3、R12；依賴：T05
  - 驗收：全流程在 SaveRepository writer mutex；decoded/opaque token 都含 repository identity、
    operation epoch、**完整 committed file bytes SHA-256**，decoded 額外含 expected run id，
    opaque 不含 run digest；fresh authoritative source 比對後 copy→digest tmp archive→read-back
    →promote，禁止 move main，再沿用 clear-run save。同 digest冪等；逐點 fault/crash 明驗四個
    base state `main old`、`main old+archive`、`main missing+backup old+archive`、
    `main new+backup old+archive` 各自乘上 none/archive_tmp/save_tmp/both residue；
    restart 有效 main 優先，否則 backup old repair並保留 run；main 有效時也清理／隔離 residue，
    tmp 不得自行 promote 成 authority；
    另一 load/write 使 token stale；recovery claim ownership 內先比對再推進 epoch；profile 不變，
    token 無法建立則 boot_failed。T06 單獨擁有 repository/recovery test file
    `test_recovery_discard_rejects_stale_tokens_and_preserves_committed_copy_on_faults`，逐一驗
    decoded/opaque wrong、stale、replaced token 與 archive/save fault 都零 clear、profile 不變、
    至少一份 byte-identical committed copy 存活且 restart 可恢復；T08 不修改此 test manifest。

- [x] **T07 [HARD][TDD] ProductionScreen contract、scene catalog 與正式 scene shell**
  - Covers：R1、R4；依賴：T04、T05
  - 驗收：主選單、營地、Run container、地圖、備戰、戰鬥、獎勵、結算、圖鑑、設定與五設施
    場景可 load／bind；Collection scene 具搜尋／篩選／雙項比較 shell；staging candidate 只得
    read-only context，bind/_ready 嘗試 intent 回 `SCREEN_NOT_ACTIVE`；typed subroute state/token
    綁 parent App state＋route generation，明驗 MENU_MAIN↔SETTINGS、
    CAMP_WORLD↔FACILITY/COLLECTION、canonical snapshot 決定的 RUN 四 route；same-state 只需
    subroute token，跨 state 同時需 App＋target subroute token；commit 建新 LiveScreenLease 並
    revoke 舊 lease，舊 callback 一律 `SCREEN_NOT_ACTIVE`；RUN→RUN 共用同一 RunPresentationSession，
    真正離開 RUN 才 release；already-active、stale parent/generation/snapshot 具名拒絕；
    每個 precommit fault 保留舊 state/route/scene/lease/session；T07 單獨擁有
    `TerminalPresentationHandoffPort` 的 SceneRouter/lease/fallback concrete adapter；新增 typed RESULTS_FALLBACK
    route/install state 與只含 retry/Camp/Menu 的 ResultsFallbackNavigationPort，不建立 gameplay
    intent/session；retry token 綁 repository identity/receipt/full digest/fallback route generation
    與 retry-attempt generation；consume 在 repository read ownership 內 fresh-read 並重新比對
    authoritative receipt/full digest，任何 attempt 都 consume token、推進 attempt generation 並
    撤銷同代 sibling token，失敗後只可 fresh 取得下一代 token；兩個 exit 不依賴 RESULTS scene；
    retry capability 分離 installed settlement digest 與 current observation digest；read ownership
    只做 receipt/current digest/generation CAS，scene candidate 只取 AppRoot installed snapshot clone；
    concrete adapter 的 RESULTS fault 必須 atomic install fallback scene、唯一 fallback lease 與
    可用 results-only retry/Camp/Menu port，不得留下舊 RUN soft-lock；
    retry/Camp/Menu 共用 non-reentrant results-action guard，必須在首次 fallback lease 驗證前取得，
    並持有到最終 route commit/failure cleanup；repository unlock 不得釋放 guard，全段不得 await；
    在 repository ownership 前、CAS/repository release 後、candidate bind 中的 Camp/Menu 重入
    loser 回 typed busy/stale、零 gameplay save／零 route commit；所有出口維持 App state/route/
    lease 一致並釋放 guard，transient failure 後 fresh action 可再次前進；
    production screen context
    絕不含 raw RunPresentationSession/RunController/facade，唯一 writer 為每次驗
    lease id/parent/generation 的 typed LiveScreenIntentPort；舊 port 的 navigation、dispatch、
    confirmation begin/confirm/cancel 全拒絕；production screen 不得查找／引用 AppRoot、RunController、
    CampController、SaveRepository writer；AppRoot 不以 dev type-cast 綁 screen。
  - 2026-07-30 final evidence：catalog/shell、staged context、typed route/lease/ports、
    SceneRouter atomic install、AppRoot production routes、atomic RESULTS_FALLBACK retry 與
    六組 retry-vs-Camp/Menu reentrancy barrier 均綠；R16-A01 已封閉，納入 final Gut／All／Spec。

- [x] **T08 [NORMAL][TDD] 正式 menu／camp start／settings／facilities UI**
  - Covers：R3、R4、R8、R9、R10、R11、R12；依賴：T02、T03、T07
  - 驗收：menu 四動作、SETTINGS open/back、3/4 營地熱區、五設施與 Collection open/back；
    T08 不修改 AppRoot；Exit 只負責 MENU button、production host 的 signal→`SceneTree.quit()`
    binding 與獨立 fake-host smoke。沿用 T05 的 `request_exit()`／pending guard；T08 單獨擁有
    `test_exit_button_host_binding_keeps_fake_runner_alive`，驗 runner 存活、按鈕不直接 quit、
    host 收一次 request、state/route/save 不變，且不得修改 T05 的 root test；
    illegal same-state subroute、stale lease 與 bind fault 具名拒絕；commander/challenge 形成 typed
    StartExpeditionRequest，成功進 RUN，具名拒絕留 CAMP；設定 UI 只依賴 injected typed
    `SettingsApplicationPort`，以 fake port 的
    `test_settings_screen_submits_typed_draft_through_injected_port` 鎖定精確 enum/bps draft、
    typed submit、error 顯示與 keyboard focus；T08 不實作、不直接取得 concrete coordinator
    或 repository，locale restart、四 bus/runtime round-trip 與 production wiring 全由 T12；
    decoded/opaque recovery confirmation 以 injected fake recovery port 完成
    `test_recovery_confirmation_cancel_is_zero_dispatch`，begin/cancel 對兩路徑都零 submit／零
    clear intent，localized error/draft state 可恢復；Collection 以 cloned
    CollectionViewModel 完整呈現 discovered/unlocked content、recipes、rule glossary，三類皆可
    filter/search/鍵盤操作；content/recipe 同類可 compare，glossary/跨類 compare typed reject
    且 selection 不變；query/比較零寫入；鍵盤焦點完整；
    全部資料來自 typed snapshot／ViewModel。
  - 2026-07-30 final evidence：Collection clone-only browser、production content/recipe/glossary
    projection、injected MENU exit、decoded/opaque recovery cancel、typed settings draft/port/
    error/focus 與 T12 concrete wiring 均完成；R16-B03/B05 已封閉，納入 final Gut／All／Spec。

- [x] **T09 [HARD][TDD] 正式 Run 子畫面與 command-only 閉環**
  - Covers：R4、R5、R10、R11、R12；依賴：T04、T07
  - 驗收：Map→Prepare/shop/build→Combat→Reward/overflow→下一節點→terminal Results 可由正式 UI
    完成；出售／鍛造／裝備／拆卸／遺物替換與放棄皆有入口；敵情、技能、羈絆、裝備／遺物、
    錯誤碼可見；鍛造、遺物替換、放棄遺物／`ABANDON_BOSS_RETRY` 先建 typed confirmation draft，
    `test_irreversible_confirmation_cancel_and_exactly_once` 對 Boss retry 明驗 begin/cancel
    零 intent/零寫、confirm exactly-once、repeat/stale/換場 lease 具名拒絕；戰鬥提供滑鼠＋鍵盤
    unit selection 與只讀 CombatUnitInspectionSnapshot（source/target/stats/equipment/traits/statuses），
    inspection 不進 command factory；RUN 子畫面依 fresh canonical route resolver 換場並沿用同一
    session，舊 screen lease 換場後不可 dispatch；RESULTS 的 CAMP／MENU 兩個鍵盤可達 action
    均不再寫 save，candidate/bind failure 留 RESULTS；所有 action 對應 facade intent；
    stale／illegal action 零 canonical mutation；
    terminal settlement save 成功後，在同一 joint ownership 內、任何 RESULTS compose/bind/route
    前從 authoritative committed candidate/bytes 捕捉 receipt/full-digest-bound Results snapshot，
    立即 revoke RUN writer lease、invalidate/release session、安裝 snapshot 並進 RESULTS；解鎖後
    concrete adapter 只取得 installed snapshot clone，不得 public-read repository。T09 單獨擁有
    `test_terminal_handoff_captures_authoritative_snapshot_before_release` production joint test，
    在 release 後、compose 前插入 competing load/write，驗 AppRoot installed 與 scene-presented
    receipt/profile pair 不漂移。注入 RESULTS route fault後舊 scene
    進 RESULTS_FALLBACK；舊 callback/confirmation 回 SCREEN_NOT_ACTIVE，save 無 active run，
    receipt/reward exactly-once。retry transient fault 可成功進 RESULTS；persistent fault 下鍵盤
    Camp/Menu 仍可退出且零新 save；retry/exit stale/repeat 具名拒絕；retry consume 前插入
    competing write、receipt replacement、repository read fault 與同 generation 雙 token，
    驗 fresh authoritative CAS、failure 保持 fallback、attempt generation 前進且 sibling token
    失效，下一次只能 fresh 取新 token；`test_results_fallback_retry_and_exit_lifecycle` 以
    reentrant probe 在取得 repository ownership 前、CAS/repository release 後與 candidate bind
    中，分別注入 Camp/Menu（六組 barrier），驗 loser typed busy/stale、零 gameplay save／零
    route commit、outer action 後 App state/route/lease 一致；transient bind failure 後 guard
    必須釋放，下一個 fresh retry 或 exit 可成功；
    production joint replay matrix 明驗 terminal capability duplicate install/direct replay、
    adapter reentry、installed capability duplicate/wrong snapshot/stale generation 全具名拒絕，
    App transition與route各 exactly-once；
    AC-004 列出全部非法部署原因、AC-005 顯示 12 人上限／超員拒絕、AC-049 UI 不複製 TUNE。
  - 2026-07-30 final evidence：19 reversible intent route allowlist、四項 irreversible
    exactly-once confirmation、clone-only combat inspection、正式 Run/Results composition、
    terminal/Results authority、committed two-sided inspection 與 accessibility damage-event
    semantics 均完成；R16-A02/A03/B01/B02/B04/B06 已封閉，納入 final Gut／All／Spec。

## Gate C — 渲染、播放與無障礙

- [x] **T10 [HARD][TDD] 640×360 world／1280×720 UI 與多解析度 policy**
  - Covers：R6、R11；依賴：T07
  - 驗收：固定 world SubViewport、nearest、pixel snap、整數倍率／letterbox；UI reference layer
    支援 100/125/150%；1280×720、1920×1080、2560×1440、4:3／16:10 下無必要裁切；
    三 scale 的 pointer→board tile／camp hotspot／UI control round-trip 命中同一目標。

- [x] **T11 [HARD][TDD] BattlePlaybackController 與 commit-before-present**
  - Covers：R7；依賴：T04、T09
  - 驗收：production canonical simulation 固定 1×；RecordBattleResult final save 成功前 transcript
    只在私有 PendingBattleTranscriptAccumulator 且公開事件=0，save fault 丟棄且不 present；
    成功後 seal/transfer 並清空 accumulator，由 RunPresentationSession 私有 BattleTranscriptBuffer
    成為 raw events 唯一 owner；try_playback 只回 cloned state/identity、不回 controller/buffer，
    drain 只經 session-mediated identity check 且 deep clone window≤4096；pause／1×／2×／4×只動
    cursor；buffer 綁 run/setup/result/resolution identity；event count≤hashed event_budget、encoded byte
    budget=`min(event_budget×1024,64MiB)`；超限保留 committed result、釋放 buffer＋summary warning；
    backpressure 不丟／不重排；換 battle／離場／revoke 釋放；result-pending 重載不虛構 transcript。
    `test_invalid_playback_multiplier_preserves_committed_session_ownership` 固定測
    `0/-1/-4/3/5/8`，一律 typed reject，並鎖 speed/cursor/pause/result identity/event
    bytes/order/hash/save-facing snapshot/transcript ownership 與零 gameplay dispatch。
    T11/T09 共同交付 lease-bound LiveScreenPlaybackPort，公開 try/set speed/set paused/drain，
    每次驗 lease/parent/generation；production RUN_COMBAT screen binding smoke不得取得 raw
    session/controller，stale port一律 SCREEN_NOT_ACTIVE。

- [x] **T12 [HARD][TDD] SettingsApplicationCoordinator、accessibility 與 error mapping**
  - Covers：R8、R9、R10、R11、R12；依賴：T01、T03、T08、T09、T10
  - 驗收：SettingsApplicationCoordinator 入口 clone/normalize candidate，以 non-reentrant
    single-flight 同步包住全流程且不得 await；theme／viewport／localization／audio 各收 private
    plan clone，activation token 按值捕捉並綁 candidate digest，不得 alias caller/repository；
    每次 preflight 後重算其 input clone digest，未改且全 token digest 相同才 repository commit，
    之後固定順序 no-fail activation；input mutation、
    雙 consumer、惡意 preflight mutator、reentrant／競爭 apply、各 preflight/save fault
    均具名拒絕且零 runtime mutation；意外 post-commit diagnostic 保留 committed settings、進 safe fallback
    並 fresh rebuild 全 consumer；screen 直接呼 SettingsRepository 由 static gate 阻止。
    T12 實作 `SettingsApplicationPort` 的 production binding，單獨擁有
    `test_settings_production_binding_round_trips_locale_and_four_buses`；以 concrete coordinator
    驗 locale `zh_TW|en` 切換／restart round-trip、四 bus volume/mute/runtime apply 與 committed
    snapshot 重建。T12 不修改 T08 已鎖定的 component test；
    default/protanopia/deuteranopia/tritanopia 下敵我、羈絆、稀有度、傷害、危險狀態
    不只靠顏色；reduced motion/flash/particles 與 off/reduced/full 傷害數字密度生效；主要操作
    鍵盤可達；locale wire set 精確 `zh_TW|en`，其他值具名拒絕，UI 切換與 restart round-trip；
    named runtime/static/screenshot evidence 必須覆蓋 reduced motion/flash/particles true/false、
    damage density off/reduced/full、tooltip depth 0/1/2/3（>2 具名拒絕且無部分套用）及
    zh_TW 長文 CJK runtime glyph/font fallback；tooltip 最多兩層；pre-commit failure 保留舊 state，post-commit route/render
    failure 保留新 commit＋fallback 且 retry/reload 可恢復；message 與 source code 同時可讀。
    evidence 必須透過 production PresentationSettingsRuntimeConsumer/SettingsApplicationPort載入
    真 RUN_COMBAT 與 production tooltip/CJK host，三個 reduced flag各有 runtime report與
    screenshot，density三值對 concrete emitter生效；static gate拒絕 fixture-only或缺 binding scene。
  - 完成證據（2026-07-29）：T10 4/4（225）、T11 8/8（234）、T12 settings
    4/4（295）、accessibility 8/8（362）、runtime integration 2/2（817）；五份
    wave4 manifest 共 20 個 hash 全相符。最終 All exit 0，Gut 818/818（13426）、
    Spec 3662 cases。runtime integration 首次 green 的 10 個 test-owned Node orphan
    以 lifecycle-only `autofree` 修正並留下 manifest revocation；未改行為斷言。
    既有 rebuild adapter `void` 契約的診斷傳播列 residual risk；R12/R13 不因此視為通過。

## Gate D — 視覺樣板與靜態 QA

- [x] **T13 [NORMAL][免TDD：藝術產出以 deterministic asset validator、render screenshot 與人工核可驗收] 原創視覺樣板**
  - Covers：R13；依賴：T10、T12
  - 驗收：費用 1／3／5 玩家棋各一、1 怪物、1 Boss、3/4 營地一角與核心 UI 成品；
    64px board canvas／portrait／方向示意、透明邊界、色盤、縮放、引用、重複度與原創性初審通過；
    prompt／seed／處理參數／provenance 完整；未採用大型原稿不進 Git；多解析度／四色覺
    screenshots 提交後硬停等待使用者核可，未核可不得啟動第二片量產。
  - 完成證據（2026-07-29，使用者明示核可）：五角色各四方向 64×64＋portrait、營地、
    core UI、五種 viewport 與四色覺 screenshots 已產生；deterministic asset validator
    36 hashes／0 issues，All 829/829（13601）。built-in ImageGen 不暴露 seed，已以完整
    prompt、call id、處理參數與 SHA-256 留 provenance warning；使用者明示接受此限制。
    `user_approved=true`，wave6/T15 可開始；`content-production` 與 Git 仍未獲授權。

- [x] **T14 [NORMAL][TDD] Production dependency、localization、accessibility 靜態 Gate**
  - Covers：R1、R6、R10、R11；依賴：T01、T07、T10、T12
  - 驗收：掃描 production dev reference、硬編碼玩家文字、loc key parity、asset refs、focus graph、
    viewport/filter/theme tokens、UI TUNE duplicate、screen→writer direct dependency；有效候選
    退出 0，逐項破壞 fixture 回具名 issue與非零退出碼。`.gd` 英文 text／tooltip／add_item
    sink 必須被拒絕；focus collector 必須比對全部正式 route/action，不得只驗 legacy 子集。
  - 完成證據（2026-07-29）：valid red 11/11 missing-validator assertions；原 green 11/11、
    175 assertions、6/6 locked hashes。R14 self-audit 另以 4/4、49 assertions 鎖定 `.gd`
    英文 visible sink、正式 focus graph、action name uniqueness 與 zero-size fail-closed；
    實際專案 headless gate read-back
    `{"ok":true,"exit_code":0,"issues":[],"accessibility_binding_count":1}`。

## Gate E — Fresh 驗證、雙審與交接

- [x] **T15 [NORMAL][免TDD：整合 gate 與證據彙整本身不是新行為] 全 suite、soak、視覺 QA 與 implementation review**
  - Covers：R14 與 R1～R13 回歸；依賴：T00～T14
  - 驗收：fresh Gut、Smoke、Content、Canonical、Combat、Expedition、Spec、All 與 10k
    ExpeditionSoak 全綠；manifest SHA-256 相符；visual/accessibility/localization screenshot artifact
    完整；兩份獨立 implementation review 無未決 finding；依 design 的 19 列建立
    `global AC→R→task→fresh production evidence` ledger，不得沿用 G1 PASS；更新 roadmap、
    PROGRESS、HANDOFF、implementation-slices、README、CLAUDE 與 `.pipeline` 後停下等待使用者
    Git 確認。
  - 完成候選證據（2026-07-29，checkbox 先保持未勾等待 R16）：R12～R15 findings
    均已採納並修正；fresh Gut 239 scripts、932/932 tests、16123 assertions，
    production runtime 10/10 screenshots／zero issues，T13 validator 36 hashes／
    zero issues／`user_approved=true`，T14 static gate `ok=true`／zero issues。
    ExpeditionSoak 10000 seeds／10000 pool checks／64 replays／40000 build operations／
    zero failures；39 manifests 共 151/151 references（134 unique paths）相符。
    19-row ledger 全列為 `PROVISIONAL PASS pending fresh R16`。依使用者 review budget，
    fresh 雙審最多只執行 R16～R18；R18 後仍有 finding 則停止並交接，不開 R19。
  - 最終完成證據（2026-07-30）：R16 findings 全部採納並以 architecture 4 tests、
    formal 5 tests、viewport 4 tests 封閉。使用者明示 R16 後直接進下一步、
    不再次雙審，故保留原 R16 `NOT APPROVED` 報告並另建 closure decision table，
    未啟動 R17。final Gut 243 scripts、945/945 tests、16295 assertions、
    0 failures/errors/orphans；Spec 3696；Smoke/Content/Canonical/Combat/
    Expedition/All 皆 exit 0；ExpeditionSoak 10000 seeds／40000 build operations
    zero failures；static gate zero issues；42 manifests／155/155 references
    （138 unique paths）相符。19-row ledger 依使用者 override 與 fresh closure evidence
    改為 final PASS。Git 仍停在使用者確認 gate。

## Dependency order

- wave0：T00 contract-red→compile-safe scaffold green；之後才建立 behavioral-red tests。
- wave1：T01、T02、T04（互不重疊：T01 app/content component，T02 services/settings，
  T04 presentation/run facade＋dev wrapper component；三者都不得修改 AppRoot）。
- wave2：T03；T01/T04 完成後由 T05 單獨擁有 AppRoot integration 與 fake terminal port
  component；完成後 T06。
- wave3：T07 取得 concrete SceneRouter/lease/fallback adapter ownership；完成後 T08、T09
  （screen ownership 不重疊），T09 負責 T05 application handoff 與 T07 concrete adapter 的
  production joint test。
- wave4：T10、T11；完成後 T12。
- wave5：T13、T14；T13 完成即進視覺樣板使用者核可 Gate。
- wave6：T15。

每個 TDD wave 先由測試代理產 `.pipeline/tdd/pui-wN-{red,tests.manifest}.txt`；測試鎖定後
實作代理不得修改該 manifest 內測試。主迴圈 fresh 重跑綠並驗 SHA-256。

## 雙向覆蓋檢查

- R→Tasks：R1→T00/T01/T04/T05/T07/T14；R2→T00/T05；R3→T00/T05/T06/T08；R4→T00/T05/T07/T08/T09；
  R5→T00/T04/T09；R6→T10/T14；R7→T00/T11；R8→T00/T02/T08/T12；R9→T00/T03/T08/T12；
  R10→T01/T08/T09/T12/T14；R11→T08/T09/T10/T12/T14；R12→T00/T04/T05/T06/T08/T09/T12；
  R13→T13；R14→T15。
- Tasks→R：T00～T15 的 Covers 均非空。
- 未覆蓋 R：0；孤兒任務：0。

## 完成定義

- 全部任務勾選完成，且各驗收有 fresh 證據。
- TDD 紅綠證據與 tests manifest 經主迴圈 read-back。
- requirements R1～R14 與本片 global AC closure 全部有 PASS；缺證據即 FAIL。
- 視覺樣板已取得使用者明示核可；未核可不進 content-production。
- 兩位獨立 reviewer 無未決 finding，或所有 finding 已由使用者逐項裁決並完成新一輪驗證。
- 文件同步完成；使用者確認前不 stage、commit、push、PR 或 merge。
