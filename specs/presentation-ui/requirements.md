# G2 presentation-ui — 需求規格

> 建立日期：2026-07-26｜狀態：已合併（PR #5 @ 9362e7d；修正 PR #6 @ 5e78ccf）
> 對應全域 owner：REQ-UX-001、REQ-UX-002、REQ-UX-003、REQ-UX-005
> 全域 AC closure：AC-004、005、006、007、017、020、024、028、029、039、044、049、
> 055、065、070、072、075、076、077

## 概述

本片把 G1 的 dev 灰盒轉成可由玩家操作的 production presentation：啟動先進主選單，
由正式 facade 消費既有 command／ViewModel，提供完整場景 shell、像素世界與高解析 UI、
可持久化設定、音訊分流、localization、鍵盤焦點與戰鬥播放控制。同時先提交一組原創視覺
樣板，供使用者核定方向；完整內容、美術與音訊量產留給下一片。

## 範圍（含明確不做）

- 包含：production boot／menu／scene routing、`RunPresentationSession`、正式 Camp／Run／
  Results／Collection／五設施畫面、viewport 與 UI 縮放、typed settings、四 audio bus、
  localization catalog、無障礙、錯誤呈現、多解析度 screenshot QA、視覺樣板。
- 保留：本片唯一受支援的 dev CLI flag `--combat-lab`，但 production main path 不得引用
  dev script／scene。
- 明確不做：44 棋完整技能與資產量產、事件選擇 schema、save schema 4、content codec 3、
  正式 TUNE、30k balance soak、Windows export／CI、最低規格效能與 90 場真人 Gate。
- 本片不改 gameplay save schema 3、content codec 2、canonical simulation、RNG 或規則語意。

## 需求

### R1 Production 與 dev 邊界

在 production 啟動路徑下，系統應只依賴 `app/`、`domain/`、`services/`、`presentation/`、
正式 `scenes/` 與正式內容 bootstrap，不得載入或型別引用 `scripts/dev/`、`scenes/dev/`
或任何會無條件回 true 的 dev dependency fake。

驗收條件:

- 從 `app/main.tscn` 啟動至主選單、營地、Run、Results 的 dependency scan 為零 dev path。
- production content bootstrap 使用真實 `ContentDependencyPort`；缺 asset 或 localization key
  時回具名錯誤並使 boot／content gate 失敗。
- 本片唯一受支援的 dev CLI flag 為 `--combat-lab`；它仍可啟動，但必須改為消費相同
  `ProjectContentBootstrap` 與 production facade／battle ports，不得保留第二套內容安裝、
  command 建構或戰鬥規則流程。headless smoke 必須以 fake services 啟動此 flag 並證明 runner
  存活、入口可 bind、production dependency scan 仍為零 dev reference。

### R2 啟動固定進主選單

當 App boot 完成且存檔可讀時，系統應固定先進 `MENU` 並顯示主選單，不得因 active run
存在而自動切入 `RUN`，也不得自動切入 `CAMP`。

驗收條件:

- 無存檔時建立初始 profile 後停在 `MENU`；不自動進營地。
- 有可續 active run 時完成安全載入／組裝但停在 `MENU`，Continue 可用。
- 存檔 `INVALID` 或 I/O failure 維持 boot fail-closed；若 profile 可讀、只有 active run
  不相容，則只在 repository 能產生 opaque recovery token 時進 recovery menu，否則 boot_failed。

### R3 主選單動作與 retained run

當玩家在主選單選擇 Continue、Start、Settings 或 Exit 時，系統應以 App 狀態機與具名結果
執行對應動作；Start 不得覆寫任何 retained active run。

驗收條件:

- Continue 只在已安全組裝 active run 時進 `RUN`；無 run 或不可續時具名拒絕、零寫入。
- Continue 必須消耗由同一次 fresh load＋compose 產生、綁定 repository committed bytes 與
  run/content identity 的單次 `PreparedRunCapability`。Repository 對每次 public load/write
  推進 operation epoch；consume 在同一 operation ownership 內比對 epoch 並 fresh-read 完整
  committed file bytes SHA-256。返回 MENU、任何 load/write 或 bytes 改變都使舊 capability 失效。
- Start 只在 fresh load 明確 `RunStatus.NONE` 時進 `CAMP`；存在 decoded／preserved active run
  時拒絕覆寫並顯示 Continue 或 recovery。
- decoded active run 組裝失敗時以 expected-run-id；opaque incompatible run 以 byte digest recovery
  token 進只讀 recovery。token 一律綁 repository identity、operation epoch 與**完整 committed
  file bytes SHA-256**；opaque 路徑不得使用或猜測 run bytes digest。兩者明示棄置前都先封存
  原始 committed file bytes；取消、錯 token、run 已更換、archive 或 save failure 都須保留
  至少一份 byte-identical committed copy／archive，並可在重啟時決定性恢復。
  repository/root evidence 必須逐一覆蓋 decoded／opaque 的 wrong、stale、replaced token 與
  archive/save fault；UI confirmation evidence 另驗兩種 recovery 的 cancel 都是零 dispatch。
  兩份 evidence 分屬不同 wave/test manifest，不得靠同一測試後續加 assertion。
- 玩家在 CAMP 選定 commander 與 challenge 後，正式 UI 應以 typed
  `StartExpeditionRequest` 呼叫 ApplicationRoot；成功須原子提交 active run 並 CAMP→RUN，
  具名拒絕與 presentation failure 不得覆寫或重複建立 run。
- `PurchaseUnlock`、`StartExpedition`、decoded／opaque `DiscardActiveRun` 與後續所有 Camp writer
  必須使用同一個 repository-owned `CampMutationTransaction`。交易須在同一次 ownership 內
  fresh-read、比對 repository identity／operation epoch／完整 committed-file digest 與 typed
  run expectation，再 apply→validate→internal-save；期間不得 `await`、不得釋放 ownership，
  stale candidate 不得覆寫其他已提交 Camp mutation。
- Settings 可開啟／返回主選單；Exit 只在 `MENU_MAIN` 可用，且只發出一次可攔截的
  `exit_requested` signal，不得由 ApplicationRoot／screen 直接呼叫 `SceneTree.quit()`。
  signal 發出後 App state、route 與 save 必須不變；同一 pending request 的重複呼叫回
  `EXIT_REQUEST_ALREADY_PENDING`，錯 lifecycle 回既有 `APP_ACTION_NOT_AVAILABLE`，兩者都不得
  再發 signal。headless test 以 fake host 攔截 signal 並證明 runner 仍存活。

### R4 正式場景與路由

當 App／Run 狀態改變時，系統應由唯一 SceneRouter 切換正式場景，所有 gameplay 寫入仍經
既有 command 與 copy-validate-save-swap。

驗收條件:

- 正式 `scenes/` 至少包含主選單、3/4 營地、地圖、備戰＋商店＋構築、戰鬥、獎勵、
  結算、圖鑑及五設施面板。
- 圖鑑必須以 consumer-owned `CollectionViewModel` 呈現三類資料：發現／解鎖內容、配方、
  規則詞彙。三類都必須支援篩選、localized search 與鍵盤可達；內容與配方支援同類雙項比較，
  規則詞彙明定不可比較並回 typed `COLLECTION_CATEGORY_NOT_COMPARABLE`，且不得改變既有比較
  selection。ViewModel、query 與結果均為 deep clone，修改 UI draft 不得影響 registry、
  profile 或其他 consumer。
- CAMP↔MENU、MENU→RUN/CAMP、RUN↔MENU、RUN 子畫面、RUN→RESULTS、RESULTS→CAMP/MENU 的合法轉移
  都可操作；RESULTS→CAMP 與 RESULTS→MENU 必須是兩個 typed action/event，僅在終局／meta
  settlement 已提交後可用，兩者都不得再寫 gameplay save。非法 edge、重複或 stale action
  具名拒絕且畫面與 canonical state 不變。
- 同一 App state 內的畫面切換必須使用綁定 parent App state 與目前 route generation 的單次
  presentation subroute token；合法矩陣至少涵蓋 MENU_MAIN↔SETTINGS、
  CAMP_WORLD↔FACILITY/COLLECTION，以及由 committed Run snapshot 決定的
  RUN_MAP／RUN_PREPARE／RUN_COMBAT／RUN_REWARD。跨 App state route 必須同時具備 App
  transition token 與目標 subroute token，不得 special-case 繞過 atomic route。
- UI 修改 snapshot／DTO 不影響 ProfileState／RunState；場景 script 不直接寫 canonical state。
- 路由必須先 prepare／instantiate／bind candidate，再驗證狀態／subroute token 並 atomic swap；
  任一步失敗都保留舊 App state、scene、screen lease 與 session。swap commit 必須撤銷舊
  `LiveScreenLease`，使舊 callback 的 intent/navigation 一律回 `SCREEN_NOT_ACTIVE`。
  RUN→RUN 子畫面沿用同一 `RunPresentationSession`；只有真正離開 RUN 才釋放 session。
- 上述「failure 保留舊 live lease/session」只適用 domain precommit route。terminal/meta
  settlement save 一旦成功，必須在任何可能失敗的 RESULTS compose／bind／route 前立即撤銷
  舊 RUN writer lease、invalidate/release `RunPresentationSession`，並以 repository-issued
  單次 `TerminalSettlementPresentationCapability` 將 App state 提交為 RESULTS。capability 必須
  綁 repository identity、settlement operation epoch、run id、receipt id 與完整 committed-file
  digest，不可由 presentation 建構或帶出 transaction。terminal settlement commit→capability
  consume→lease revoke→session invalidation→RESULTS 必須位於同一 AppRoot terminal single-flight
  與 repository writer ownership，中途不得解鎖或接受其他 public load/write。後續失敗只能保留
  舊 scene 作唯讀 fallback；所有舊 gameplay／
  confirmation／navigation callback 都回 `SCREEN_NOT_ACTIVE`，不得復活已清除 run。
- staging candidate 只能取得 read-only context，不得持有 command facade／writer；scene 與
  App state commit 完成後才以單次 activation capability 注入 live intent port。commit 前呼叫
  intent 必須具名拒絕且 gameplay save 不變。
- production screen script 不得自行查找 AppRoot／RunController／CampController／SaveRepository
  等 writer；static dependency gate 必須阻止繞過 staged/live context 的直接引用。
- production screen 不得取得或保留 raw `RunPresentationSession`、RunController 或其他
  writer-capable facade；唯一寫入口是綁定目前 `LiveScreenLease`／route generation 的 typed
  `LiveScreenIntentPort`。所有 dispatch、confirmation begin/confirm/cancel 與 navigation
  每次都先驗 lease；舊 port 即使 underlying session 仍供新 RUN 畫面使用也必須具名拒絕。
- 戰鬥畫面的 playback read／speed／pause／drain 只能經 lease-bound
  `LiveScreenPlaybackPort`；port 每次驗目前 `LiveScreenLease`、parent state 與 route generation，
  不得把 raw RunPresentationSession、BattlePlaybackController 或 buffer 交給 screen。stale
  port 一律回 `SCREEN_NOT_ACTIVE` 且不改 playback、canonical state 或 save。

### R5 RunPresentationSession

於 active run 期間，ApplicationRoot 應以唯一 `RunPresentationSession` 建立 consumer-owned
typed snapshot 並處理 typed intent；正式 screen 只能透過 lease-bound read/intent ports 間接
使用它，不得取得 raw session、依賴 `RunLabSession` 或直接持有 RunState／authoring Resource。

驗收條件:

- facade 覆蓋全部既有玩家操作：地圖生成／進入、刷新、購買、買 XP、出售、棋盤提交、
  鍛造、裝備、拆卸、非戰鬥解算、戰鬥開始／續跑／結算、standard／unit／item／relic
  reward 選擇與前進、unit/item overflow、遺物替換／放棄、Boss retry 放棄與終局結算。
- 每個寫入 intent 只建構／派送既有 command；失敗回具名 typed error 且不部分更新 UI snapshot。
- 讀取結果帶 pinned manifest digest／catalog generation；修改其 scalar 或 collection 不影響
  registry、active run、manifest digest 或 canonical 戰果。
- `RunLabSession` 成為 facade 的 dev consumer 或薄 wrapper，不保留另一套流程語意。
- `snapshot()`、signal payload 及所有 collection accessor 每次都回 deep clone；合法「目前沒有
  playback」狀態以 typed result 表示，不得回 null、buffer reference 或殘留的舊 controller。
- 鍛造、遺物替換、放棄遺物與 `ABANDON_BOSS_RETRY` 等不可逆操作必須先建立 typed
  confirmation draft；
  cancel 不派送 intent／不寫入，confirm 只能消耗 draft 並 exactly-once 派送一次。第二片的
  event choice 必須重用同一 confirmation contract。`ABANDON_BOSS_RETRY` 必須逐一驗 begin
  零寫、cancel 零 intent、confirm exactly-once，以及 repeat／stale／換場 lease 拒絕。
- 戰鬥畫面必須能以滑鼠或鍵盤選取單位並查看 typed `CombatUnitInspectionSnapshot`，至少包含
  source、target、stats、equipment、traits 與 statuses；檢視與選取純唯讀，不得產生 gameplay intent。
- terminal/meta settlement 成功後，RESULTS 只能從已提交 settlement result／receipt 與
  同一次 repository writer ownership 內的 authoritative committed candidate/bytes 建立
  receipt／完整 file digest 綁定、clone-only `ResultsPresentationSnapshot`；不得在 ownership
  釋放後以 public load 重建，也不得讀取或持有結算前 RunPresentationSession。AppRoot 必須在
  ownership 內先撤銷 lease/session、consume capability、安裝該 snapshot 並提交 RESULTS state，
  才能釋放 repository ownership；解鎖後 scene compose／bind／route 只能取得已安裝 snapshot
  的 fresh clone。Terminal intent dispatch 在上述同步 no-fail handoff 完成前不得返回舊
  screen，且全段不得 `await`。即使解鎖後插入競爭 load/write，已安裝與後續呈現的
  receipt/profile pair 仍須一致；route failure 時存檔仍無 active run，receipt／reward exactly-once。
- RESULTS compose／bind／route 失敗時，presentation route 必須進 typed `RESULTS_FALLBACK`，
  App state 維持 RESULTS。fallback 只取得 receipt-bound results-only navigation port，提供
  retry render、Return to Camp、Return to Menu；不得取得 gameplay intent/session。每次 retry
  必須先取得綁 repository identity、receipt id、完整 committed-file digest、fallback route
  generation 與 retry-attempt generation 的單次 capability。consume 必須位於 repository read
  ownership 內，fresh-read authoritative committed bytes 並重新比對 receipt 與完整 digest；
  stale、receipt/digest mismatch、I/O failure 或重複使用皆具名拒絕且維持 fallback。每次
  consume attempt 不論驗證或後續 presentation 成敗，都必須推進 retry-attempt generation 並
  撤銷同 generation 的所有 sibling token；失敗後只能 fresh 取得下一代 token。持續 fault 下
  兩個鍵盤 exit 仍可用，且所有操作零新 gameplay save。
- repository-issued `TerminalSettlementPresentationCapability` 只能在 writer ownership 內由
  application layer 原子 consume 一次，consume 後永久失效，且不得傳入解鎖後的 presentation
  adapter。AppRoot 安裝 RESULTS state/snapshot 成功後另發單次
  `InstalledResultsPresentationCapability`，綁 installed snapshot digest、RESULTS state 與
  target/fallback route generation；T07 adapter 只能消耗後者。duplicate install/present、
  direct replay、錯 snapshot、stale generation 與 reentrant activation 都具名拒絕且不更換
  state、route 或 lease。
- fallback retry capability 分別綁 installed settlement digest 與本次 current repository
  observation digest。repository read 只驗 current digest、receipt 存在性與 retry generation；
  candidate 永遠取 AppRoot installed Results snapshot 的 fresh clone，不得從 read result 重建。
  合法的 unrelated post-settlement profile write 不得使 fresh retry 永久失效或漂移 receipt/profile pair。
- retry、Return to Camp 與 Return to Menu 必須共用 non-reentrant AppRoot results-action
  single-flight。每個 action 在首次 fallback lease／route generation 驗證前取得 guard，並持有到
  最終 App state／presentation route／live lease commit 或 failure cleanup 完成；repository
  ownership 的取得或釋放不得縮短 guard 生命週期，全段不得 `await`。在取得 repository ownership
  前、authoritative CAS 後／repository release 後、以及 RESULTS 或 exit candidate bind 中發生的
  retry-vs-Camp／retry-vs-Menu 重入，loser 必須回 typed `RESULTS_ACTION_IN_PROGRESS` 或既有
  stale/lease error，且零 gameplay save、零 route commit。每個出口都必須保持 App state、
  presentation route 與 live/fallback lease 一致並 finally-style 釋放 guard；transient route
  failure 後，下一個 fresh 合法 action 必須可以成功取得 guard。

### R6 世界與 UI 分離渲染

在 720p、1080p 與 1440p 視窗下，系統應以 640×360 `SubViewport` 渲染世界，使用
nearest-neighbor 與整數縮放；UI 應在獨立 1280×720 reference `CanvasLayer` 排版。

驗收條件:

- 世界 viewport 固定 640×360，texture filter 為 nearest；整數倍率可用時不採非整數世界縮放。
- 1280×720、1920×1080、2560×1440 screenshot 中世界像素邊界無模糊，必要 UI 不裁切。
- 非 16:9 或不足整數倍率時採 letterbox／安全區，不拉伸世界；UI 仍可操作。
- `PresentationHost`、active `ProductionScreen` 與 production accessibility runtime 必須在
  掛載後使用完整可見 viewport；視窗 resize 後三層同步更新。renderer 收到 zero-size root
  必須回 `ACCESSIBILITY_ROOT_SIZE_INVALID`，不得靜默假設 1280×720 形成假綠。
- 720p／1080p／1440p、非 16:9 與 100／125／150% UI scale 下，pointer→world tile、
  pointer→camp hotspot 及 pointer→UI control 的座標映射皆命中同一目標。

### R7 決定性戰鬥播放控制

當玩家暫停或選擇 1×、2×、4×時，系統應只改變 BattleEvent 的 presentation 消費速率，
不得改變模擬 tick、事件內容、事件順序、BattleResult 或 canonical hash。

驗收條件:

- 同 setup／seed 在 1×、2×、4×與播放中 pause/resume 後，result、event sequence、摘要 hash 相同。
- RecordBattleResult 最終提交前，完整 transcript 只存在私有
  `PendingBattleTranscriptAccumulator`，公開事件數必為 0；
  save failure 不得讓玩家看到未提交戰鬥。
- pause 時模擬結果與事件資料已提交邏輯不被撤回；只停止 presentation cursor 前進。
- 不接受 0、負值或未支援正倍率；`0/-1/-4/3/5/8` named matrix 均回
  `PLAYBACK_SPEED_INVALID`，且保持目前倍率、cursor、pause、result identity、event
  bytes/order/hash、save-facing snapshot 與 transcript ownership，並產生零 gameplay dispatch。
- 正式 RUN_COMBAT screen 必須只綁 `LiveScreenPlaybackPort` 操作 1×／2×／4×、
  pause/resume 與 drain；換場後舊 port 的合法與非法命令都回 `SCREEN_NOT_ACTIVE`。
- 已提交 result 重載而沒有 transcript 時只顯示 committed summary，不虛構重播。私有 transcript
  受 canonical `event_budget`（目前預設 16384）限制；公開待處理 window 不超過 4096，
  超限時以 backpressure 分批，不丟失或重排規則事件。
- final save 成功後 accumulator 必須以 seal／ownership transfer 移交事件並立即清空，完整事件
  此後只能由 `RunPresentationSession` 私有的唯一 `BattleTranscriptBuffer` 持有，並綁 run_id、
  battle setup hash、committed result digest 與 resolution identity。`try_playback()` 只能回
  cloned state／identity；UI 只能透過 session-mediated API 取得 deep-cloned drain window，
  不得取得 buffer、controller 或 raw events reference。
  buffer byte budget 為 `min(event_budget × 1024, 64 MiB)`。超出時不得影響已提交 canonical result，
  應釋放 transcript、顯示 committed summary 並回具名 presentation warning。

### R8 Typed 持久化設定

當玩家修改設定時，系統應驗證 `SettingsSnapshot`，以獨立原子存檔持久化，成功後一次 swap；
重啟應恢復最後成功值。

驗收條件:

- 欄位使用 stable string wire value：UI scale `100|125|150`、色覺模式
  `default|protanopia|deuteranopia|tritanopia`、damage number density
  `off|reduced|full`、reduced motion／flash／particles；Master／Music／SFX／UI 各自有
  `volume_bps`（0～10000）與 `muted`。
- locale 的合法 stable wire set 精確為 `zh_TW|en`；其他值一律具名拒絕。安全預設為
  `zh_TW`、100%、default、三個 reduced=false、density=full、四 bus
  volume_bps=10000 且 muted=false。
- repository 對不在集合的 enum、範圍外整數、缺欄或錯型別一律具名拒絕，不自行 clamp；
  UI editor 可在建立 candidate 前限制輸入。
- SettingsRepository 的所有 public save/reset input 必須 deep clone-in；load/current/save/reset
  result 與 signal payload 必須 deep clone-out。UI draft、caller candidate、committed snapshot、
  adapter plan/token 與兩個 consumer 間不得共享可變 object graph。
- tmp write／read-back／promote 任一 fault 都不 swap；重新啟動讀回前一 committed snapshot。
- settings 檔損壞時保留診斷副本、載入安全預設並顯示非阻斷 warning；不得改 gameplay save。
- 讀到高於目前支援的 settings schema 時回 `UNSUPPORTED_FUTURE_VERSION`，原 bytes 不 quarantine、
  不覆寫；本次執行使用安全預設並顯示 warning，且一般 save 被鎖住。只有玩家明示
  reset incompatible settings，並以 expected bytes digest 比對、先封存原檔後，才能寫入 v1。
- presentation 不得直接呼叫 SettingsRepository writer。`SettingsApplicationCoordinator`
  的每次 `apply()` 必須在入口 deep clone／normalize candidate，並以 process-local single-flight、
  non-reentrant ownership 同步涵蓋 preflight→save→activation，全段不得 `await`。Theme、viewport、
  localization、audio adapter 只能收到各自的 private plan clone；coordinator 必須在 preflight
  後重新計算該 clone digest，任何 adapter mutation 都具名拒絕。activation token 必須按值捕捉
  並綁 canonical candidate digest，不得保留 caller snapshot reference。全部 preflight token
  驗 digest 後才提交 repository；提交後只執行不可失敗 activation。競爭／重入 apply 具名拒絕；
  preflight／save failure 零 runtime 變更；不可預期的 post-commit presentation failure 保留
  committed settings，進安全 fallback，並從 repository 重建全部 consumer。
- Settings screen 只依賴可注入的 typed `SettingsApplicationPort`。T08 以 fake port 鎖定
  draft、typed submit、error mapping 與 focus 的 component behavior；T12 才綁定 concrete
  `SettingsApplicationCoordinator`，並負責 locale restart、四 bus/runtime apply 與 production
  wiring 的整合證據。T08 不得為了提早轉綠而實作或直連 T12 ownership。

### R9 AudioCoordinator 分 bus 控制

當設定音量或 mute 改變時，`AudioCoordinator` 應分別控制 Master、Music、SFX、UI bus，
並由已提交的 SettingsSnapshot 重建。

驗收條件:

- 四 bus 可獨立設定與 mute；調整一個 bus 不改其他 bus 的 snapshot。
- 重新載入設定後四 bus 的有效音量一致；不存在 bus 時回具名錯誤，不 silent no-op。
- `AudioBusPort` 須提供 atomic batch apply；套用前 preflight 四個 bus 與全部值，任一 bus 缺失
  或 adapter failure 時四個 bus 全部維持前一有效狀態，不得先改前三個再失敗。
- headless 測試使用 fake audio port，不依賴實體音訊裝置。

### R10 Production localization

當任何正式場景、tooltip、內容名稱或錯誤訊息顯示玩家文字時，系統應以 stable
localization key 經 dependency port 解析；預設 locale 為 `zh_TW`。

驗收條件:

- `zh_TW` 每個必要 key 有非空值，`en` 具有完全相同 key 集合。
- Settings UI 只能在 `zh_TW|en` 間切換；切換成功後立即套用，重啟仍讀回同一 locale；
  任何其他 locale wire value 必須由 repository 具名拒絕。
- 靜態掃描正式場景／script／ContentDefinition 不得出現硬編碼玩家文字；`.gd` 必須涵蓋
  英文／混合語言直接寫入 `text`、`tooltip_text`、`placeholder_text`、`add_item`、
  `set_item_text` 等 player-visible sink。空值、localization resolver 與純格式 token 不誤判。
- 缺 key 時開發 build 顯示 key 本身並回可診斷 issue；Content gate 非零退出。
- 本片先提供全部 key 的可運作繁中／英文文字；第二片可潤飾內容，但不得改 stable key。

### R11 無障礙與正式輸入

在滑鼠＋鍵盤正式輸入下，系統應讓所有主要操作具有可見焦點路徑，且所有影響決策的資訊
同時提供圖形、文字、符號或形狀等非色彩提示。

驗收條件:

- 100／125／150% UI 下可只用鍵盤走完主選單、營地五設施、地圖、備戰、戰鬥控制、
  獎勵與結算；焦點不陷入隱藏／disabled control。
- focus graph 使用正式 route kind，完整覆蓋 conditional MENU、Settings、五設施、
  RUN_MAP／PREPARE／COMBAT／REWARD、RUN_ROUTE_FALLBACK、RESULTS／RESULTS_FALLBACK
  的可見 action；不得以舊抽象 route 子集通過 static gate。每個 action id 必須映射為
  唯一、跨 relocalize／route rebuild 穩定的具名 Control。
- 四種色覺模式中，敵我關係、羈絆、稀有度、傷害類型與危險狀態不只靠顏色區分。
- reduced motion／flash／particles 開啟後，runtime report 與 screenshot 必須分別證明對應
  effect flag 生效且規則資訊仍可讀；傷害數字密度 `off|reduced|full` 必須有具名 runtime
  matrix，且 disabled/reduced 路徑不得殘留粒子或數字 emitter。
- tooltip 巢狀規則詞彙最多兩層；超過兩層以具名拒絕且不部分套用。繁中長文 probe 必須以
  engine/runtime font fallback 產出可讀 CJK glyph report，並納入 static gate 與 screenshot evidence。
- 上述 evidence 必須載入真 production RUN_COMBAT 與 production tooltip/CJK host，並透過
  AppRoot 使用的 `PresentationSettingsRuntimeConsumer`／SettingsApplicationPort 套用 committed
  settings；只對 test fixture 生效不算通過。motion、flash、particles 必須各有獨立 toggle
  screenshot/report，static gate 必須拒絕缺少 production accessibility binding 的正式 scene。

### R12 錯誤、recovery 與玩家可見性

當任何 presentation intent、場景 binding、內容依賴、存檔或 lifecycle 操作失敗時，系統應
保留 authoritative state，並把具名 source error 映射為 localization key 顯示。

驗收條件:

- 缺 ID、非法 transition、stale offer、I/O failure、錯誤 lifecycle 與場景 binding failure
  都顯示可診斷錯誤，不 assert crash、不 silent null。
- UI 不以泛化 `APP_FAILED` 蓋掉來源 error code；diagnostic 可讀原始具名碼。
- command／save 提交前的 failure 必須保留舊 canonical state、serial、RNG、事件與 committed save。
- command 已成功提交後才發生的 route／bind／render failure 不得回滾或偽裝提交失敗；系統保留
  新 committed state，顯示安全 fallback 與 source error，並讓 retry／reload 從新狀態恢復。

### R13 原創視覺樣板

在進入完整美術量產前，系統應提交一組「高辨識戰棋奇幻」原創樣板供使用者核可。

驗收條件:

- 樣板含費用 1／3／5 各一位玩家棋、1 怪物、1 Boss、3/4 營地一角，以及核心 UI
  （panel、button、keyboard focus、tooltip、resource bar、狀態／稀有度非色彩符號）。
- 每個角色提供 64px 棋盤畫布方向示意與 portrait；像素化、透明邊界、色盤與縮放 QA 通過。
- 保存核可成品、prompt／seed／處理參數與 provenance；未採用大型原稿不進 Git。
- 完成多解析度與四色覺模式 screenshot QA、原創性初審後停下；使用者未核可不得量產。

### R14 Presentation release gate

當本片準備交付時，系統應 fresh 執行所有自動化、視覺與文件 gate，並由兩位獨立 reviewer
對照本規格與設計複審。

驗收條件:

- Gut、Smoke、Content、Canonical、Combat、Expedition、Spec 與 `-Suite All` 全綠。
- 10,000-seed ExpeditionSoak 全綠；presentation 變更不得使 canonical artifact 改變。
- visual/accessibility/localization/static dependency/screenshot gate 有可 read-back artifact。
- implementation review 必須有「19 條 owning global AC→R→task→fresh production evidence」
  矩陣；不得直接沿用 G1 灰盒 PASS。尤其 AC-004／005 的全部非法部署原因與 12 人上限 UI、
  AC-049 的 UI 無複製 TUNE static test 必須有新證據。
- 每條 R1～R14 與本片 owning global AC 都有 PASS／FAIL；缺證據者不得標完成。
- reviewer 有新問題立即交使用者裁決，未裁決不得 commit／PR／merge。

## 非功能需求

- Godot 4.7 stable、GDScript typed public API、現有五個 Autoload 上限不變。
- production UI 不得產生 gameplay entropy，不得依 wall clock／Object ID 決定規則結果。
- 所有跨畫面 DTO 可序列化為 JSON 基本型別，不含 Node、Resource、Callable 或 SceneTree path。
- 720p 是必要可操作下限；本片不宣稱最低規格效能 AC-031 完成。
- 所有本地路徑、Godot executable 與測試者資訊不得寫入 tracked production data。

## 開放問題

無。視覺樣板的美術方向核可屬實作中的既定硬 Gate，不是規格缺口。
