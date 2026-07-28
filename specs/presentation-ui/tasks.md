# G2 presentation-ui — 任務清單

> 建立日期：2026-07-26｜狀態：草稿（未核可）
> 對應需求：[requirements.md](requirements.md) R1～R14；設計依據：[design.md](design.md)
> 本檔為 pipeline 任務來源；核可前不得建立 TDD 紅燈或修改 production code。
> 勾選只由 pipeline 收尾回寫。

## Gate A — production 依賴與資料契約

- [ ] **T00 [NORMAL][TDD] Compile-safe typed contract scaffold**
  - Covers：R1、R2、R3、R4、R5、R7、R8、R9、R12；依賴：無
  - 驗收：測試代理先以 dynamic `load()`／Spec static inspection 建立 contract-red，不直接引用
    尚不存在的 `class_name`；實作只新增 compile-safe typed declarations、stable enum/string constants
    與 result/snapshot/request/capability/buffer skeleton，不實作行為；contract tests 綠後，
    T01～T12 的 behavioral test
    代理才可靜態引用型別並建立真正紅燈。GUT parser abort 不算有效 behavioral-red。

- [ ] **T01 [HARD][TDD] 正式 content bootstrap、dependency port 與 localization catalog**
  - Covers：R1、R10；依賴：T00
  - 驗收：`ProjectContentBootstrap` 移出 dev；production asset／localization dependency 真實查驗；
    `zh_TW` 預設且非空，`en` key set 完全相同；Build Lab 改消費同一 bootstrap；刪 asset／key
    使 Content gate 具名非零。檔案 owner 限 `app/content/`、localization、Build Lab adapter 與
    對應 tests；本任務不改 `app/app_root.gd`，production graph 最終接線由 T05。

- [ ] **T02 [HARD][TDD] SettingsSnapshot v1 與原子 SettingsRepository**
  - Covers：R8；依賴：T00
  - 驗收：stable string enums、四 bus `volume_bps`／mute 與安全 defaults 精確 round-trip；
    非法 enum／型別／範圍具名拒絕；injectable storage；tmp/read-back/promote/final fault 零 swap；
    corrupt schema-1 archive＋defaults；future schema 原 bytes 保留並鎖一般 save，只有 expected
    digest 明示 reset 且先 archive 才寫 v1；public input 全部 deep clone-in，load/current/result/
    signal 全部 deep clone-out，committed object graph 不外流；input mutation、雙 consumer alias
    回歸；Smoke/GUT 不碰真實 `user://`；gameplay schema 維持 3。

- [ ] **T03 [NORMAL][TDD] AudioCoordinator 四 bus adapter**
  - Covers：R9；依賴：T02
  - 驗收：Master／Music／SFX／UI volume_bps 與 mute 由 committed settings 重建；各 bus 獨立；
    `AudioBusPort.apply_batch()` 寫前 preflight 全 bus，缺 bus／before-commit adapter fault
    零 mutation；commit 段不可失敗；headless 用 fake audio port。

- [ ] **T04 [HARD][TDD] RunPresentationSession typed facade**
  - Covers：R5、R12；依賴：T00
  - 驗收：typed snapshot／intent／result 逐項對應全部既有玩家 command（含出售、鍛造、裝備、
    拆卸、各 reward/overflow、遺物替換／放棄）；所有 writer 只經擴充後 RunCommandFactory＋
    RunController；失敗保留前 snapshot 與 source diagnostics；snapshot/accessor/signal 每次 deep
    clone、雙 consumer 無 alias；no-playback typed result；RunLabSession 改 consumer／薄 wrapper。
    檔案 owner 限 `presentation/run/`、RunCommandFactory、RunLab wrapper 與 tests；不改 AppRoot。

## Gate B — App/menu/recovery 與正式場景

- [ ] **T05 [HARD][TDD] Boot→MENU、Prepared Continue、Camp start 與 return-to-menu lifecycle**
  - Covers：R2、R3、R4、R12；依賴：T01、T04
  - 驗收：本任務是 `app/app_root.gd`／AppStateMachine 的唯一 integration owner；no-save/run-free/
    active-run boot 都先 MENU；SaveRepository 每個 public load/write 推進 operation epoch；
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
    terminal save→internal capability consume→revoke RUN writer lease→invalidate/release session→
    RESULTS，最後才解鎖；capability 綁 repository identity/operation epoch/run id/receipt id/full
    digest且不外流，handoff 全段不得 await、terminal dispatch 不先返回。插入競爭 public
    load/write 必須等 handoff；意外 post-save handoff failure 也先 fail-closed revoke 再進 fallback；
    再交 T07/T09 組畫面；
    stale/偽造 capability、競爭 Camp writer、invalid/I/O 具名 fail-closed。

- [ ] **T06 [HARD][TDD] Retained-run recovery token 與 archive-before-clear**
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
    token 無法建立則 boot_failed。

- [ ] **T07 [HARD][TDD] ProductionScreen contract、scene catalog 與正式 scene shell**
  - Covers：R1、R4；依賴：T04、T05
  - 驗收：主選單、營地、Run container、地圖、備戰、戰鬥、獎勵、結算、圖鑑、設定與五設施
    場景可 load／bind；Collection scene 具搜尋／篩選／雙項比較 shell；staging candidate 只得
    read-only context，bind/_ready 嘗試 intent 回 `SCREEN_NOT_ACTIVE`；typed subroute state/token
    綁 parent App state＋route generation，明驗 MENU_MAIN↔SETTINGS、
    CAMP_WORLD↔FACILITY/COLLECTION、canonical snapshot 決定的 RUN 四 route；same-state 只需
    subroute token，跨 state 同時需 App＋target subroute token；commit 建新 LiveScreenLease 並
    revoke 舊 lease，舊 callback 一律 `SCREEN_NOT_ACTIVE`；RUN→RUN 共用同一 RunPresentationSession，
    真正離開 RUN 才 release；already-active、stale parent/generation/snapshot 具名拒絕；
    每個 precommit fault 保留舊 state/route/scene/lease/session；新增 typed RESULTS_FALLBACK
    route/install state 與只含 retry/Camp/Menu 的 ResultsFallbackNavigationPort，不建立 gameplay
    intent/session；retry token 綁 repository identity/receipt/full digest/fallback route generation
    與 retry-attempt generation；consume 在 repository read ownership 內 fresh-read 並重新比對
    authoritative receipt/full digest，任何 attempt 都 consume token、推進 attempt generation 並
    撤銷同代 sibling token，失敗後只可 fresh 取得下一代 token；兩個 exit 不依賴 RESULTS scene；
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

- [ ] **T08 [NORMAL][TDD] 正式 menu／camp start／settings／facilities UI**
  - Covers：R3、R4、R8、R9、R10、R11、R12；依賴：T02、T03、T07
  - 驗收：menu 四動作、SETTINGS open/back、3/4 營地熱區、五設施與 Collection open/back；
    illegal same-state subroute、stale lease 與 bind fault 具名拒絕；commander/challenge 形成 typed
    StartExpeditionRequest，成功進 RUN，具名拒絕留 CAMP；設定精確 enum/bps draft 只交
    SettingsApplicationCoordinator，locale 只可 `zh_TW|en` 且切換／重啟 round-trip；
    recovery confirm/localized error 可用；四 bus round-trip；Collection 以 cloned
    CollectionViewModel 完整呈現 discovered/unlocked content、recipes、rule glossary，三類皆可
    filter/search/鍵盤操作；content/recipe 同類可 compare，glossary/跨類 compare typed reject
    且 selection 不變；query/比較零寫入；鍵盤焦點完整；
    全部資料來自 typed snapshot／ViewModel。

- [ ] **T09 [HARD][TDD] 正式 Run 子畫面與 command-only 閉環**
  - Covers：R4、R5、R10、R11、R12；依賴：T04、T07
  - 驗收：Map→Prepare/shop/build→Combat→Reward/overflow→下一節點→terminal Results 可由正式 UI
    完成；出售／鍛造／裝備／拆卸／遺物替換與放棄皆有入口；敵情、技能、羈絆、裝備／遺物、
    錯誤碼可見；鍛造、遺物替換、放棄遺物／Boss retry 先建 typed confirmation draft，
    cancel 零 intent/零寫、confirm exactly-once、重複/stale confirm 具名拒絕；戰鬥提供滑鼠＋鍵盤
    unit selection 與只讀 CombatUnitInspectionSnapshot（source/target/stats/equipment/traits/statuses），
    inspection 不進 command factory；RUN 子畫面依 fresh canonical route resolver 換場並沿用同一
    session，舊 screen lease 換場後不可 dispatch；RESULTS 的 CAMP／MENU 兩個鍵盤可達 action
    均不再寫 save，candidate/bind failure 留 RESULTS；所有 action 對應 facade intent；
    stale／illegal action 零 canonical mutation；
    terminal settlement save 成功後，在同一 joint ownership 內、任何 RESULTS compose/bind/route
    前立即 revoke RUN writer lease、invalidate/release session 並進 RESULTS；Results snapshot 只由
    committed result/receipt＋fresh profile clone 重建。注入 RESULTS route fault 後舊 scene
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
    AC-004 列出全部非法部署原因、AC-005 顯示 12 人上限／超員拒絕、AC-049 UI 不複製 TUNE。

## Gate C — 渲染、播放與無障礙

- [ ] **T10 [HARD][TDD] 640×360 world／1280×720 UI 與多解析度 policy**
  - Covers：R6、R11；依賴：T07
  - 驗收：固定 world SubViewport、nearest、pixel snap、整數倍率／letterbox；UI reference layer
    支援 100/125/150%；1280×720、1920×1080、2560×1440、4:3／16:10 下無必要裁切；
    三 scale 的 pointer→board tile／camp hotspot／UI control round-trip 命中同一目標。

- [ ] **T11 [HARD][TDD] BattlePlaybackController 與 commit-before-present**
  - Covers：R7；依賴：T04、T09
  - 驗收：production canonical simulation 固定 1×；RecordBattleResult final save 成功前 transcript
    只在私有 PendingBattleTranscriptAccumulator 且公開事件=0，save fault 丟棄且不 present；
    成功後 seal/transfer 並清空 accumulator，由 RunPresentationSession 私有 BattleTranscriptBuffer
    成為 raw events 唯一 owner；try_playback 只回 cloned state/identity、不回 controller/buffer，
    drain 只經 session-mediated identity check 且 deep clone window≤4096；pause／1×／2×／4×只動
    cursor；buffer 綁 run/setup/result/resolution identity；event count≤hashed event_budget、encoded byte
    budget=`min(event_budget×1024,64MiB)`；超限保留 committed result、釋放 buffer＋summary warning；
    backpressure 不丟／不重排；換 battle／離場／revoke 釋放；result-pending 重載不虛構 transcript。

- [ ] **T12 [HARD][TDD] SettingsApplicationCoordinator、accessibility 與 error mapping**
  - Covers：R8、R9、R10、R11、R12；依賴：T01、T03、T08、T09、T10
  - 驗收：SettingsApplicationCoordinator 入口 clone/normalize candidate，以 non-reentrant
    single-flight 同步包住全流程且不得 await；theme／viewport／localization／audio 各收 private
    plan clone，activation token 按值捕捉並綁 candidate digest，不得 alias caller/repository；
    每次 preflight 後重算其 input clone digest，未改且全 token digest 相同才 repository commit，
    之後固定順序 no-fail activation；input mutation、
    雙 consumer、惡意 preflight mutator、reentrant／競爭 apply、各 preflight/save fault
    均具名拒絕且零 runtime mutation；意外 post-commit diagnostic 保留 committed settings、進 safe fallback
    並 fresh rebuild 全 consumer；screen 直接呼 SettingsRepository 由 static gate 阻止。
    default/protanopia/deuteranopia/tritanopia 下敵我、羈絆、稀有度、傷害、危險狀態
    不只靠顏色；reduced motion/flash/particles 與 off/reduced/full 傷害數字密度生效；主要操作
    鍵盤可達；locale wire set 精確 `zh_TW|en`，其他值具名拒絕，UI 切換與 restart round-trip；
    tooltip 最多兩層；pre-commit failure 保留舊 state，post-commit route/render
    failure 保留新 commit＋fallback 且 retry/reload 可恢復；message 與 source code 同時可讀。

## Gate D — 視覺樣板與靜態 QA

- [ ] **T13 [NORMAL][免TDD：藝術產出以 deterministic asset validator、render screenshot 與人工核可驗收] 原創視覺樣板**
  - Covers：R13；依賴：T10、T12
  - 驗收：費用 1／3／5 玩家棋各一、1 怪物、1 Boss、3/4 營地一角與核心 UI 成品；
    64px board canvas／portrait／方向示意、透明邊界、色盤、縮放、引用、重複度與原創性初審通過；
    prompt／seed／處理參數／provenance 完整；未採用大型原稿不進 Git；多解析度／四色覺
    screenshots 提交後硬停等待使用者核可，未核可不得啟動第二片量產。

- [ ] **T14 [NORMAL][TDD] Production dependency、localization、accessibility 靜態 Gate**
  - Covers：R1、R6、R10、R11；依賴：T01、T07、T10、T12
  - 驗收：掃描 production dev reference、硬編碼玩家文字、loc key parity、asset refs、focus graph、
    viewport/filter/theme tokens、UI TUNE duplicate、screen→writer direct dependency；有效候選
    退出 0，逐項破壞 fixture 回具名 issue與非零退出碼。

## Gate E — Fresh 驗證、雙審與交接

- [ ] **T15 [NORMAL][免TDD：整合 gate 與證據彙整本身不是新行為] 全 suite、soak、視覺 QA 與 implementation review**
  - Covers：R14 與 R1～R13 回歸；依賴：T00～T14
  - 驗收：fresh Gut、Smoke、Content、Canonical、Combat、Expedition、Spec、All 與 10k
    ExpeditionSoak 全綠；manifest SHA-256 相符；visual/accessibility/localization screenshot artifact
    完整；兩份獨立 implementation review 無未決 finding；依 design 的 19 列建立
    `global AC→R→task→fresh production evidence` ledger，不得沿用 G1 PASS；更新 roadmap、
    PROGRESS、HANDOFF、implementation-slices、README、CLAUDE 與 `.pipeline` 後停下等待使用者
    Git 確認。

## Dependency order

- wave0：T00 contract-red→compile-safe scaffold green；之後才建立 behavioral-red tests。
- wave1：T01、T02、T04（互不重疊：T01 app/content，T02 services/settings，T04 presentation/run；
  三者都不得修改 AppRoot）。
- wave2：T03；T01/T04 完成後由 T05 單獨擁有 AppRoot integration；完成後 T06。
- wave3：T07；完成後 T08、T09（screen ownership 不重疊）。
- wave4：T10、T11；完成後 T12。
- wave5：T13、T14；T13 完成即進視覺樣板使用者核可 Gate。
- wave6：T15。

每個 TDD wave 先由測試代理產 `.pipeline/tdd/pui-wN-{red,tests.manifest}.txt`；測試鎖定後
實作代理不得修改該 manifest 內測試。主迴圈 fresh 重跑綠並驗 SHA-256。

## 雙向覆蓋檢查

- R→Tasks：R1→T00/T01/T07/T14；R2→T00/T05；R3→T00/T05/T06/T08；R4→T00/T05/T07/T08/T09；
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
