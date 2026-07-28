# G2 presentation-ui — 技術設計

> 建立日期：2026-07-26｜狀態：草稿（未核可）
> 對照：[requirements.md](requirements.md) R1～R14
> 既有基線：`app/app_root.gd`、`app/state/app_state_machine.gd`、
> `services/scene/scene_router_service.gd`、`scripts/dev/run/run_lab_session.gd`

## 架構概述

本片將 production composition 與 dev 灰盒分離，但不重做 domain。`ApplicationRoot` boot
先安裝正式內容、讀檔並安全組裝可續 run，畫面狀態固定停在 `MENU`；玩家之後才透過
typed App action 進 Continue 或 Camp。`RunPresentationSession` 從現有 RunLab 驅動邏輯抽出，
成為唯一正式 facade；所有畫面只讀 consumer-owned snapshot、只送 intent。

世界與 UI 分為 640×360 `SubViewport` 與 1280×720 reference `CanvasLayer`；
`SettingsRepository` 改為獨立原子持久化 typed snapshot，驅動 accessibility、locale 與
四個 audio bus。正式 localization／asset dependency port 取代 dev fake。

```text
ApplicationRoot
  ├─ ProjectContentBootstrap ── ContentRegistryService
  │    └─ ProjectContentDependencyPort ── LocalizationCatalog / ResourceLoader
  ├─ SaveRepository ── ProfileState + optional RunState
  ├─ AppStateMachine ── MENU / CAMP / RUN / RESULTS
  ├─ SceneRouterService ── ProductionScreen
  ├─ SettingsRepository ── SettingsSnapshot ── AudioCoordinator
  └─ RunPresentationSession
       ├─ RunController + RunCommandFactory + CombatCoordinator
       ├─ PresentationSnapshotBuilder ── consumer-owned DTO
       └─ BattlePlaybackController ── immutable event stream cursor
```

不新增 Autoload。既有五個 instance（ContentRegistry、SaveService、SettingsService、
AudioService、SceneRouter）維持上限。

## 需求對應表

| 需求 | 設計元素 | 說明 |
|---|---|---|
| R1 | `ProjectContentBootstrap`、`ProjectContentDependencyPort`、dependency scan | production 移除 dev bootstrap/fake |
| R2 | `ApplicationRoot._boot_to_menu()`、`AppStateMachine.BOOT_COMPLETED` | load/compose 與畫面導航分離 |
| R3 | `ApplicationRoot` menu／Camp start actions、PreparedRunCapability、recovery model | retained run 不被 Start 覆寫，Camp 可正式開局 |
| R4 | `ProductionSceneCatalog`、read-only staging、activation capability | 唯一 router 與 commit 後 intent activation |
| R5 | `RunPresentationSession`、typed intent/result/snapshot | UI 不碰 RunState 或 dev lab |
| R6 | `WorldViewportHost`、`UiScaleRoot`、stretch policy | 640×360 world＋1280×720 UI |
| R7 | `BattlePlaybackController`、`BattleTranscriptBuffer` | 私有 transcript、windowed playback |
| R8 | `SettingsSnapshot`、`SettingsRepository`、`SettingsApplicationCoordinator` | 全 adapter preflight→save→no-fail activation |
| R9 | `AudioCoordinator`、`AudioBusPort` | 四 bus 由 committed settings 驅動 |
| R10 | `LocalizationCatalog`、`LocalizationPort`、static gate | stable key、zh_TW/en 同集合 |
| R11 | theme tokens、focus graph、accessibility renderer | 四色覺、非色彩提示與縮放 |
| R12 | `PresentationErrorMapper`、diagnostic view | 保留 source code、fail-closed |
| R13 | `assets/pilot/` inventory＋provenance＋screenshot QA | 核可前只做樣板、不量產 |
| R14 | runner extensions、implementation review、雙審 | 自動與人工證據聚合 |

## 介面與資料模型

### 1. ApplicationRoot 與狀態機

既有 `ApplicationRoot`（`app/app_root.gd`）保留 composition owner；不把 repository、
registry 或 canonical state 暴露給 scene。新增／調整公開 API：

```gdscript
func open_main_menu() -> AppActionResult
func continue_active_run() -> AppActionResult
func open_camp() -> AppActionResult
func start_expedition(request: StartExpeditionRequest) -> AppActionResult
func return_to_menu() -> AppActionResult
func return_results_to_camp() -> AppActionResult
func return_results_to_menu() -> AppActionResult
func open_settings() -> AppActionResult
func close_settings() -> AppActionResult
func request_exit() -> AppActionResult
func discard_retained_run(token: RetainedRunRecoveryToken) -> AppActionResult
func current_menu_snapshot() -> MainMenuSnapshot
func current_run_presentation() -> RunPresentationSessionResult
```

`AppActionResult` 固定含 `ok: bool`、`committed: bool`、`presentation_ok: bool` 與
`error: DiagnosticError`；成功不以 null 作哨兵。這讓 save 已成功但 compose／route 失敗的
開局可如實回報，不把 post-commit failure 偽裝成零寫入。
`RunPresentationSessionResult` 是 try/from 慣例的 typed result，避免 public silent-null。

`AppEvent.Kind` 新增 `CONTINUE_RUN`、`RETURN_RESULTS_TO_CAMP` 與
`RETURN_RESULTS_TO_MENU`：

- `BOOT_COMPLETED`: BOOT→MENU，無 commit requirement。
- `CONTINUE_RUN`: MENU→RUN；只能由 AppRoot 以單次 `PreparedRunCapability` 呼叫。
- `OPEN_CAMP`: MENU→CAMP；AppRoot 先 fresh load 並確認 run status。
- `RETURN_TO_MENU`: CAMP／RUN→MENU；不寫 gameplay save。RUN 路徑釋放記憶體 session，
  但保留 active run，下一次 Continue fresh load／compose。
- `FINISH_RUN`: terminal/meta settlement save 成功後，`TerminalSettlementPresentationCapability`
  立即且不可失敗地
  revoke RUN writer lease、invalidate/release RunPresentationSession，再提交 RUN→RESULTS；
  不等待 RESULTS scene compose／bind／route。
- `RETURN_RESULTS_TO_CAMP`: RESULTS→CAMP；只在 terminal/meta settlement receipt 已提交且
  `ResultsPresentationSnapshot.can_exit_results=true` 時可 prepare，target subroute=`CAMP_WORLD`。
- `RETURN_RESULTS_TO_MENU`: RESULTS→MENU；前置相同，target subroute=`MENU_MAIN`。

兩個 RESULTS return event 都是 presentation-only，不再次 dispatch domain command、不再寫
gameplay save。App transition 與 target subroute candidate 全部 prepare 成功後才 atomic commit；
candidate/bind failure、重入或 stale token 保留 RESULTS state、scene 與 receipt。

`TerminalSettlementCoordinator` 使用固定鎖序取得 AppRoot process-local terminal single-flight，
preflight 一個不可失敗的 lease/session revoke plan，再取得 SaveRepository writer ownership。
它在同一 ownership 內執行 terminal/meta clone→apply→validate→atomic save；save 成功後由
repository 建立 internal-only、單次 `TerminalSettlementPresentationCapability`，綁 repository
identity、settlement operation epoch、run id、receipt id 與完整 committed-file SHA-256。
capability 不得返回 public caller；coordinator 仍持有 writer ownership時立即驗證／consume，
依 preflight plan revoke active RUN lease→invalidate/release session→安裝 clone-only
ResultsPresentationSnapshot→提交 App state RESULTS，最後才按反序釋放 repository ownership
與 terminal guard。全段同步、無 `await`；其他 public load/write 必須等 handoff 完成。

preflight／settlement save 前 failure 保留 RUN live state；save 一旦成功，handoff contract 的
意外 internal failure 也必須先 fail-closed revoke/invalidate 舊 RUN writer並由 committed bytes
進 `RESULTS_FALLBACK`，不得採一般 stale-zero-mutation 規則。terminal dispatch 只有在上述
handoff 完成後才返回 caller。

啟動流程不再用 `ACTIVE_RUN_LOADED` 自動導向 RUN。新增 `RunPreparationService`：

```gdscript
func prepare(load_result: LoadResult) -> PreparedRunResult
func consume(capability: PreparedRunCapability) -> PreparedRunConsumeResult
func revoke(capability: PreparedRunCapability) -> void
```

SaveRepository 維護 process-local `operation_epoch: int` 與不可序列化的
`repository_identity_token`。每個 public load/write operation 進入 writer ownership 時
先推進 epoch；LoadResult 捕捉成功完成時的 epoch。`prepare()` 必須消耗該 repository 發出的
active-run load capability，完成完整 committed file bytes SHA-256、run_id、manifest digest 與
facade compose，才登記不可由外部建構、單次使用的 `PreparedRunCapability`。

`consume()` 不呼叫 public `load()`；它以 `_claim_operation_if_epoch(expected_epoch)` 在相同
repository ownership 中檢查 identity／epoch，先推進 epoch使 capability 單次失效，再 internal
fresh-read authoritative committed source並比對完整 file digest、run_id、manifest。任一不符
回 stale error。BOOT 可先 prepare 並停 MENU；RUN→MENU、任何其他 load/write、repository rebind
或 bytes 改變都使舊 capability 失效並釋放 facade。下一次 Continue 必須 fresh load＋prepare。
不能只用 `_run_session != null` 或可偽造 bool 當資格。

### 2. Menu snapshot 與 recovery

```gdscript
class_name MainMenuSnapshot
var can_continue: bool
var can_start: bool
var has_recovery: bool
var active_run_id_display: String
var warning_key: StringName
```

- `RunStatus.NONE`：Start enabled、Continue disabled。
- `LOADED` 且 compose 成功：Continue enabled、Start disabled。
- decoded `LOADED` 但 compose 失敗：recovery enabled；Start disabled。token 帶 expected run_id、
  repository identity、operation epoch 與完整 committed file bytes SHA-256。
- `INCOMPATIBLE_PRESERVED`：SaveRepository 只在 profile 可讀且可取得 committed raw bytes 時產生
  opaque recovery token（repository identity＋operation epoch＋完整 committed file bytes SHA-256），
  不假造 decoded run_id，也沒有第二種 run-bytes digest。
- 明示棄置由 `CampMutationTransaction` 完全包在 SaveRepository 的既有 writer ownership 內：先以
  `_claim_operation_if_epoch(token.operation_epoch)` 比對後推進 epoch，再 fresh-read authoritative
  committed bytes、驗 SHA-256 token；以 digest 命名 `recovery/<sha256>.save`，先 copy 到 unique tmp、read-back、
  promote（同 digest 已存在且 bytes 相同視為冪等成功），再以既有 atomic save 只清 active run、
  保留 profile。不得使用會 move main 的現有 quarantine。

沿用既有 tmp→read-back→main→backup→tmp→main protocol，不虛構 OS-level atomic replace。
四個 authoritative base states：

1. `main old`（archive 尚未完成）；
2. `main old + archive`；
3. `main missing + backup old + archive`（rotate 後、promote 前）；
4. `main new + backup old + archive`。

每個 base state 都必須再與 `{none, archive_tmp, save_tmp, archive_tmp+save_tmp}` 殘留集合做
Cartesian fault matrix；tmp 不是 authoritative source。重啟時先驗證並選有效 main，否則選
byte-identical backup old；選定 authority 後，即使 main 有效也必須決定性清理或隔離所有
archive/save tmp residue，不可因 tmp 較新而自行 promote 或清掉 retained run。
並保留 active run 讓玩家重試。成功只有 base state 4。任一路徑至少保有 backup old 或 digest archive；
「main 必定存在」不是安全不變式。若連 token 都無法安全建立，維持 boot_failed。

### 2.1 CAMP 開局入口

`StartExpeditionRequest` 只含 `commander_id: StringName`、`challenge_level: int`。
所有 Camp writer 共用 internal `CampMutationTransaction`：

```gdscript
enum CampRunExpectationKind { NONE, DECODED_RUN_ID, OPAQUE_FILE_DIGEST }

class_name CampMutationExpectation
var kind: CampRunExpectationKind
var expected_run_id: String
var expected_committed_file_digest: String

func execute(
	expectation: CampMutationExpectation,
	mutation: CampMutationCommand
) -> CampMutationResult
```

`execute()` 取得 SaveRepository writer ownership 後，internal fresh-read authoritative bytes，
建立不可由外部建構的單次 `CampMutationCapability`。capability 綁 repository identity、
operation epoch、完整 committed-file SHA-256 與 expectation；在不釋放 ownership、不中途
`await` 的同步區段內依序 revalidate expectation→clone/apply→aggregate validate→internal
atomic save→consume capability，最後才釋放 ownership。`PurchaseUnlock`、
`StartExpeditionCommand`、decoded／opaque `DiscardActiveRunCommand` 與所有新增 Camp writer
都只能經此交易，不得使用「public load 後稍後 public save」。

expectation 規則：一般 unlock／start 使用 `NONE`；decoded discard 使用
`DECODED_RUN_ID + full file digest`；opaque discard 使用 `OPAQUE_FILE_DIGEST`，不猜 run id。
同程序內任何先行 repository operation 都使 epoch/digest stale 並零寫拒絕。跨程序共同寫同一
save 仍不在本片保證範圍；若未另加 OS file lock，正式文件與 diagnostic 必須明示不支援。

`ApplicationRoot.start_expedition()` 是正式 UI 唯一入口：

1. 驗 App state=CAMP，建立 `RunStatus.NONE` expectation。
2. 經 CampController 將既有 StartExpeditionCommand 交給 `CampMutationTransaction.execute()`。
3. save 成功即視為 `committed=true`；compose facade 並 prepare RUN scene／transition。
4. 成功 consume save/route token後 CAMP→RUN。
5. command 前失敗留 CAMP 且零寫；save 後 compose／route failure 保留已提交 active run，
   回 `committed=true, presentation_ok=false`，顯示 recovery／Continue，不重建第二個 run。

Exit 只發 `exit_requested` signal；production main 接 signal 呼叫 `SceneTree.quit()`，
headless test 以 fake host 驗 signal，不終止 runner。

### 3. RunPresentationSession

位置：`presentation/run/run_presentation_session.gd`。建構時要求已組裝的
`RunController`、`RunCommandFactory`、`CombatCoordinator`、pinned readers；無 lazy null。

```gdscript
signal snapshot_committed(snapshot: RunPresentationSnapshot)
signal presentation_error(error: DiagnosticError)

func snapshot() -> RunPresentationSnapshot
func reachable_nodes() -> Array[MapNodePresentation]
func dispatch(intent: RunPresentationIntent) -> RunPresentationResult
func try_playback() -> BattlePlaybackStateResult
func drain_playback_window(
	expected_identity: BattleTranscriptIdentity,
	max_count: int
) -> BattleEventWindowResult
func inspect_combat_unit(unit_serial: int) -> CombatUnitInspectionResult
```

`RunPresentationIntent.Kind` 首片覆蓋既有可玩閉環：

- GENERATE_MAP、ENTER_NODE
- REFRESH_SHOP、BUY_UNIT、BUY_XP、SELL_UNIT、COMMIT_BOARD_LAYOUT
- FORGE_EQUIPMENT、EQUIP_ITEM、DISMANTLE_EQUIPMENT
- START_OR_RESUME_COMBAT、SETTLE_BATTLE
- RESOLVE_NON_COMBAT
- CHOOSE_STANDARD_REWARD、RESOLVE_UNIT_REWARD、RESOLVE_ITEM_REWARD、
  RESOLVE_RELIC_REWARD、ADVANCE_REWARD
- RESOLVE_UNIT_OVERFLOW、RESOLVE_ITEM_OVERFLOW、REPLACE_RELIC、ABANDON_RELIC
- ABANDON_BOSS_RETRY、SETTLE_TERMINAL_RUN

intent payload 使用具名 state，不暴露 Dictionary。Facade 的 dispatch：

1. 由目前 pinned snapshot 驗 lifecycle。
2. 以 `RunCommandFactory` 建 command；不直接改 RunState。
3. 經 RunController copy-validate-save-swap。
4. command 失敗時保留前一 snapshot，回 `committed=false` 與 source error／diagnostics。
5. command 成功後先標 `committed=true`，再 fresh build consumer-owned snapshot 並發一次
   `snapshot_committed`。
6. 若 commit 後 snapshot／route／render 失敗，不得回報成未提交或回滾；回
   `committed=true, presentation_ok=false`，進 refresh-required fallback，從 repository
   reload 新 committed state。

`RunPresentationSnapshot` 是 clone-only aggregate，含 run/app phase、manifest digest、map、
economy、roster、shop、encounter preview、reward／overflow、terminal summary 與可用 actions。
其 collection 全部 duplicate/deep rebuild。`snapshot()`、`reachable_nodes()`、signal payload
與 typed result 每次都重新 deep clone；兩個 consumer 修改各自副本不得互相 alias。
非 COMBAT lifecycle 的 `try_playback()` 回具名 `PLAYBACK_NOT_AVAILABLE`，不回 null／舊 controller。
任何 authoring `.tres` 只在 bootstrap 邊界存在。

`RunLabSession` 改為 `RunPresentationSession` 的薄 dev consumer，或讓 dev screen 直接 bind facade；
production assembly 不再宣告 `RunLabSession` 型別。

#### 3.1 不可逆操作確認

`ConfirmationDraft` 是 presentation-only typed state，含 operation kind、snapshot identity、
lifecycle、typed payload digest、screen lease id、route generation 與單次 nonce；它不含
writer reference。production 只能經 `LiveScreenIntentPort` begin/confirm/cancel。第一次操作
`FORGE_EQUIPMENT`、`REPLACE_RELIC`、`ABANDON_RELIC`、`ABANDON_BOSS_RETRY` 或其他 reward
abandon 只建立 draft，不 dispatch gameplay intent。`cancel_confirmation()` 清除 draft，
零 intent／零寫入；`confirm(draft)` 先驗 active lease／route generation、identity/lifecycle，
再原子消耗 nonce並 exactly-once dispatch 一次，重複／stale confirm 具名拒絕。
content-production 的 event choice 沿用同一
draft→confirm/cancel contract，不建立第二套 UI 語意。

#### 3.2 戰鬥單位檢視

`CombatUnitInspectionSnapshot` 是 clone-only DTO，含 `unit_serial`、source definition view、
目前 target、可見 stats、equipment、traits／羈絆與 statuses。滑鼠點選與鍵盤 previous/next selection
只更新 presentation selection；`inspect_combat_unit()` 從目前 committed playback/snapshot
重建 DTO，不呼叫 command factory、不派 gameplay intent。單位消失、identity stale 或非 COMBAT
時回具名結果，且不得殘留先前單位資料。

### 4. Production scene contract

新增 `presentation/screens/production_screen.gd`：

```gdscript
class_name ProductionScreen
extends Control
func bind(context: PresentationScreenContext) -> StringName
```

每個 screen context 是具名型別。Staged context 只含 clone-only snapshot/read ports；live
context 只增加 `LiveScreenIntentPort` 與 `LiveScreenNavigationPort`，兩者都綁不可偽造的
`LiveScreenLease(lease_id, parent_state, route_generation)`。production context 絕不包含 raw
`RunPresentationSession`、RunController 或 writer-capable facade；bind 過晚、重複或
context kind 不符回具名錯誤。`PresentationRouteState` 含 parent App state、route kind 與
monotonic route generation；`PresentationSubrouteToken` 由 SceneRouter 對 expected current
route 發出，單次使用、不可外部建構。合法矩陣：

| Parent App state | From | To／條件 |
|---|---|---|
| MENU | MENU_MAIN | SETTINGS |
| MENU | SETTINGS | MENU_MAIN |
| CAMP | CAMP_WORLD | FACILITY(kind)／COLLECTION |
| CAMP | FACILITY(kind)／COLLECTION | CAMP_WORLD |
| RUN | RUN_MAP／RUN_PREPARE／RUN_COMBAT／RUN_REWARD | 只能到 fresh committed `RunPresentationSnapshot.route_kind` 指定的 route |
| RESULTS | RESULTS | 跨 App state 到 CAMP_WORLD 或 MENU_MAIN；需 terminal/meta settlement receipt |
| RESULTS | RESULTS_FALLBACK | RESULTS（receipt-bound retry）／跨 App state 到 CAMP_WORLD 或 MENU_MAIN |
| Cross App state | MENU↔CAMP | target 分別為 MENU_MAIN／CAMP_WORLD |
| Cross App state | MENU→RUN、RUN→MENU | target 分別由 RunScreenRouteResolver／MENU_MAIN 決定 |
| Cross App state | RUN→RESULTS | target 固定 RESULTS |

RUN subroute 不允許 UI 任意指定下一畫面；`RunScreenRouteResolver` 只讀 fresh committed snapshot，
將 canonical lifecycle 映射為 MAP／PREPARE／COMBAT／REWARD，subroute token 綁 snapshot identity。
resolver target 等於目前 route 時回具名 `ROUTE_ALREADY_ACTIVE` 且不 swap；route kind、parent state、
generation 或 snapshot identity 任一 stale 都具名拒絕。
SceneRouter route protocol：

1. `prepare_presentation(scene, read_only_context)` 在 staging host instantiate、進樹、hidden bind
   並驗 route kind。`StagedScreenContext` 只有 deep-cloned snapshot／loc／theme read ports，
   不含 facade、command、navigation writer；commit 前 intent 回 `SCREEN_NOT_ACTIVE`。
2. SceneRouter 以 expected parent／route generation prepare 單次 subroute token；same-App-state
   route 只需此 token。跨 App state route 另由 AppStateMachine `prepare_transition(event)`
   驗 edge 並回單次 App transition token。
3. 所需 token 都有效後，ApplicationRoot 執行無外部 I/O 的 commit：套用 App token（若有）與
   subroute token、切換 candidate visibility/current child、消耗 `ScreenActivationCapability`
   建立新 `LiveScreenLease`，並在同一同步 commit 內 revoke 舊 lease。舊 lease 的所有
   intent/navigation port 每次呼叫都驗 active route generation，不符回 `SCREEN_NOT_ACTIVE`。
4. RUN→RUN subroute 保留同一 `RunPresentationSession`；只有 parent state 從 RUN 變為非 RUN，
   才在舊 lease revoke 後 release session。其他 parent state 不持有 run session。

commit 前任何錯誤保留舊 App state、route、scene、lease、session；惡意／錯誤 candidate 在 bind/_ready 嘗試
dispatch 只得具名拒絕。commit 段只做已驗證的記憶體／SceneTree 操作，不回可失敗結果。
此 preservation policy 只適用尚未完成 terminal domain commit 的 route。terminal/meta
settlement save 成功後必須先撤銷 RUN writer lease/session 並提交 RESULTS；後續 scene failure
不得恢復 RUN live context。
Spec gate 另掃 production screen，不得 `get_node("/root/...")` 或型別引用 ApplicationRoot、
RunController、CampController、SaveRepository 等 writer；只能使用 staged/live context。
不得沿用目前「先 queue_free 舊畫面再 instantiate 新畫面」順序，也不以一長串 dev type cast。

`LiveScreenIntentPort` 是 production screen 唯一 gameplay writer port：

```gdscript
func dispatch(intent: RunPresentationIntent) -> RunPresentationResult
func begin_confirmation(intent: RunPresentationIntent) -> ConfirmationDraftResult
func confirm(draft: ConfirmationDraft) -> RunPresentationResult
func cancel(draft: ConfirmationDraft) -> ConfirmationCancelResult
```

每次呼叫先由 ApplicationRoot/SceneRouter lease registry 比對 lease id、parent state 與 active route
generation，再轉送 internal RunPresentationSession；不以 port 建構時的一次 bool 代替。lease
失效一律回 `SCREEN_NOT_ACTIVE`，不得觸碰 command factory。`ConfirmationDraft` 另綁 lease id
與 route generation；換場後即使透過新 port 提交舊 draft也視為 stale。navigation port 同規則。

`RESULTS_FALLBACK` 不建立 LiveScreenIntentPort，只建立
`ResultsFallbackNavigationPort`：

```gdscript
func prepare_retry() -> ResultsRenderRetryCapabilityResult
func retry(capability: ResultsRenderRetryCapability) -> AppActionResult
func return_to_camp() -> AppActionResult
func return_to_menu() -> AppActionResult
```

`ResultsRenderRetryCapability` 由 fresh committed repository read 發出，單次使用且綁 repository
identity、receipt id、完整 committed-file digest、fallback route generation 與獨立的
`retry_attempt_generation`。`retry()` 與兩個 exit 共用 non-reentrant AppRoot
results-action single-flight；每個 public action 的第一個同步步驟是取得 guard，之後才驗
fallback lease／route generation。guard 從首次驗證一路持有到 App state、presentation route
與 live/fallback lease 的最終 commit 或 failure cleanup，repository ownership 的取得／釋放
不影響 guard；所有出口 finally-style 釋放，全段不得 `await`。無法取得 guard 的 reentrant
caller 在任何 save／candidate mutation 前回 `RESULTS_ACTION_IN_PROGRESS`。

`retry()` 在 guard 內取得 repository read ownership，並在 ownership 內
fresh-read authoritative committed bytes，重新比對 repository identity、receipt id 與完整
file digest，並從該次 read 建立 clone-only ResultsPresentationSnapshot。無論比對成功、stale、
I/O failure 或稍後 presentation failure，此次 attempt 都會原子 consume token、推進
`retry_attempt_generation` 並撤銷舊 generation 全部 sibling token，才釋放 repository ownership。
比對失敗具名拒絕並保持 fallback；比對成功後才以捕捉的 fresh snapshot prepare/bind RESULTS
candidate，成功才 RESULTS_FALLBACK→RESULTS。prepare/bind failure 保持原 fallback lease，
下一次 `prepare_retry()` 必須 fresh-read 並發下一代 token。兩個 return action 沿用 RESULTS
typed event、零新 save，不依賴 RESULTS scene 安裝成功。results-only port 每次呼叫仍驗
fallback lease；鍵盤焦點固定包含 retry、Camp、Menu。

`test_results_fallback_retry_and_exit_lifecycle` 必須以可重入 probe 分別在三個 barrier 注入
Return to Camp 與 Return to Menu：retry 取得 repository ownership 前、authoritative CAS
完成且 repository ownership 已釋放後、以及 RESULTS candidate bind 中。六個 loser 都必須
回 `RESULTS_ACTION_IN_PROGRESS`（若 barrier 前 lease 已被外部撤銷則回既有 stale/lease error），
不得寫 gameplay save或提交 route；outer retry 完成或失敗後，App state、route 與唯一 live
lease 必須一致。另注入 transient bind failure，驗 guard 已釋放且下一個 fresh exit／retry
能成功，防止 busy guard 永久卡死。

正式場景：

| Route | Scene |
|---|---|
| MENU | `scenes/menu/main_menu.tscn` |
| CAMP | `scenes/camp/camp.tscn` |
| MAP | `scenes/run/map/map.tscn` |
| PREPARE | `scenes/run/prepare/prepare.tscn` |
| COMBAT | `scenes/run/combat/combat.tscn` |
| REWARD | `scenes/run/reward/reward.tscn` |
| RESULTS | `scenes/results/results.tscn` |
| COLLECTION | `scenes/collection/collection.tscn` |
| FACILITY | `scenes/camp/facilities/{expedition_gate,commander_hall,collection_hall,unlock_workshop,challenge_monument}.tscn` |
| SETTINGS | `scenes/settings/settings.tscn` |

「備戰／商店／構築」共用 PREPARE 世界場景，以 UI panel route 切換，避免複製 board authority。
3/4 營地先以固定互動熱區；自由移動角色與完整環境量產在第二片。

Collection screen 只接收 cloned `CollectionViewModel` 與 presentation-local
`CollectionQueryDraft`。category enum 固定為 `DISCOVERED_CONTENT|RECIPE|RULE_GLOSSARY`；三類
資料都進 localized text search、category/detail filter 與鍵盤焦點圖。DISCOVERED_CONTENT 與
RECIPE 只允許同 category 的兩項並排比較；RULE_GLOSSARY 或跨 category compare 回
`COLLECTION_CATEGORY_NOT_COMPARABLE` 並保留既有 selection。清除／修改 query 或 comparison
selection 不派 gameplay intent、不改 profile。每次結果與 comparison snapshot 都 deep clone，
並提供鍵盤可達的搜尋框、篩選器、結果列與比較區。

### 5. Content bootstrap、asset 與 localization

把 `scripts/dev/build_lab/build_lab_content_bootstrap.gd` 的 production 邏輯移至
`app/content/project_content_bootstrap.gd`，回傳 `ProjectContentSnapshot`。Build Lab 改呼叫
同一 bootstrap。

`ProjectContentDependencyPort`：

```gdscript
func asset_exists(path: String) -> bool
func localization_key_exists(key: StringName) -> bool
```

asset 使用 `ResourceLoader.exists()`／受控檔案檢查；localization 由
`LocalizationCatalog.has_key()` 查驗。不得以 constant true 實作。catalog tracked source
採 UTF-8 JSON 或 CSV，import 後仍以 stable key 解析；合法 locale wire set 固定且僅為
`zh_TW|en`，`zh_TW` 是預設，`en` key set 必相等。

本片先填可運作文字，第二片只可修改 value，不可任意改 key。玩家可見 error 經
`PresentationErrorMapper` 以 `error.<source_code>` 查表，diagnostic panel仍保留原碼。

### 6. Viewport、theme 與 scaling

`WorldViewportHost`：

- `SubViewport.size = Vector2i(640, 360)`。
- 2D texture filter nearest，pixel snap 開啟。
- 視窗可容納整數倍率時取最大整數倍率；其餘 letterbox，不對 world texture 做任意拉伸。

`UiScaleRoot`：

- reference rect 1280×720，置於獨立 `CanvasLayer`。
- UI scale token 1.0／1.25／1.5；以 layout container＋safe margins 重排，不單純放大整棵樹。
- screenshot runner 固定測 1280×720、1920×1080、2560×1440，以及 150% 最壞字串。

Theme 不把敵我關係／稀有度／羈絆／傷害／危險狀態只編成顏色；每種狀態另有
icon、輪廓、pattern、方向標記或短標籤。
色覺 enum 為 DEFAULT、PROTANOPIA、DEUTERANOPIA、TRITANOPIA。

`WorldViewportHost` 提供單一 `WindowCoordinateMapper`，把 viewport letterbox rect、world scale、
UI reference transform 與 UI scale 納入 pointer mapping；測試矩陣涵蓋三解析度、4:3／16:10、
三 UI scale，並對 board tile、camp hotspot、UI control 做 round-trip hit assertion。

### 7. SettingsRepository

```gdscript
class_name SettingsSnapshot
var schema_version: int = 1
var locale: StringName = &"zh_TW"
var ui_scale_percent: int = 100
var color_vision_mode: StringName = &"default"
var reduced_motion: bool = false
var reduced_flash: bool = false
var reduced_particles: bool = false
var damage_number_density: StringName = &"full"
var master_volume_bps: int = 10000
var master_muted: bool = false
var music_volume_bps: int = 10000
var music_muted: bool = false
var sfx_volume_bps: int = 10000
var sfx_muted: bool = false
var ui_volume_bps: int = 10000
var ui_muted: bool = false
```

`SettingsRepository` 依 `SaveRepository` 同紀律實作獨立 `user://settings-v1.json`：
clone→validate→tmp write→read-back→promote→final read-back→swap。使用獨立
`SettingsStoragePort` 與 Fake，不能借 gameplay SaveRepository 寫入 profile。

`SettingsSnapshot` 視為可變 DTO：所有 public save/reset input 先 deep clone-in；`load()`、
`current_snapshot()`、save/reset result 與 signal payload 每次 deep clone-out。Repository 的
committed instance 永不外流，UI draft 與任何 consumer 不能持有同一 object graph。canonical
UTF-8 encoding 的 SHA-256 作 candidate digest；同值 snapshot 必得相同 digest。

wire enum 固定為 stable string：locale `zh_TW|en`、color vision 四值、density
`off|reduced|full`；不得持久化 Godot enum ordinal。UI scale 只接受 100／125／150；
四個 volume 只接受 0..10000 整數，
repository 對非法值／型別具名拒絕、不 clamp。

損壞 schema-1 設定不是 gameplay progress：原檔 copy 到 diagnostics archive 後回
`SettingsLoadResult`（safe defaults＋warning）。`schema_version > 1` 則回
`UNSUPPORTED_FUTURE_VERSION`，保留原 bytes、不 archive、不覆寫，本次僅使用 safe defaults，
並使一般 `save()` 回 `SETTINGS_FUTURE_VERSION_PRESERVED`。只有
`reset_incompatible_settings(expected_digest)` fresh 比對、先 copy/read-back/promote 原 bytes
到 digest archive 後，才解除 write lock 並寫 v1 defaults。I/O fault 維持記憶體／磁碟舊值。
測試不讀寫真實 `user://`。

### 8. AudioCoordinator

新增 `AudioBusKind {MASTER, MUSIC, SFX, UI}` 與 `AudioBusPort.apply_batch()`。Coordinator 只消費已驗證、
已提交的 SettingsSnapshot，把 0..10000 bps 轉 dB；0 或對應 muted=true 套 mute。
Godot adapter 在寫入前 preflight 四 bus 與全部值；通過後的四個 AudioServer assignment
是 batch commit 的不可失敗段。任一 bus 缺失／注入 adapter failure 都在 mutation 前回具名 error，
禁止部分套用。headless Fake 以 before-commit fault 驗零 mutation。

### 9. SettingsApplicationCoordinator

presentation 只透過 coordinator 寫設定，不能先 `SettingsRepository.save()` 再逐一套 consumer：

```gdscript
func apply(candidate: SettingsSnapshot) -> SettingsApplicationResult
```

流程：

1. 以 process-local `_apply_in_progress` 取得 non-reentrant single-flight ownership；已持有時
   在任何 mutation 前回 `SETTINGS_APPLY_IN_PROGRESS`。整段同步執行且不得 `await`。
2. deep clone-in candidate，normalize 成 coordinator-private `SettingsNormalizedPlan`，
   validate 後計算 canonical candidate digest；caller 後續 mutation 不影響 plan。
3. Theme、WorldViewport/UI scale、Localization、Audio 四 adapter 各自收到獨立 private plan
   clone並 `preflight(plan) -> SettingsAdapterActivationResult`；token 只能按值捕捉 primitive
   assignments 與 candidate digest，不得持有 caller／repository／plan snapshot reference。
4. 每個 preflight 返回後，coordinator 對其輸入 clone 重算 canonical digest；任一 preflight
   failure、clone digest 改變或 token digest 不符都丟棄全部 token，repository 與 runtime
   consumers 全不變。
5. 全部 token digest 相同後才由 SettingsRepository atomic save/swap；save input 再 clone-in，
   save failure 同樣零 runtime mutation。
6. save 成功後依固定順序 theme→viewport→localization→audio 執行 token 的 no-fail `activate()`。
   activation 只做 preflight 已驗證的記憶體／Godot property assignments，不再查資源或回 error。
7. 若 adapter 違反 no-fail contract 產生不可預期 post-commit diagnostic，不回滾 committed settings；
   coordinator 進 safe theme／720p／zh_TW／audio-safe fallback，fresh-read repository 後重新
   preflight 全 consumer，並回 `committed=true, presentation_ok=false`。
8. 所有出口以 finally-style release single-flight ownership；result 與 committed snapshot
   clone-out。main-thread callback 造成的 reentrant apply 仍具名拒絕，不排隊、不覆蓋。

`SettingsRepository.save()` 對 presentation 為 internal port；static gate 阻止 screen 直接呼叫。
整合 fault test 逐一命中四 adapter preflight、repository 每個 fault 與 post-commit fallback。

### 10. BattlePlaybackController

production 不呼叫 `CombatCoordinator.set_speed()`；canonical simulation 固定 1×。Coordinator
在 `RecordBattleResultCommand` 的 final save 成功前把完整 transcript 留在私有
`PendingBattleTranscriptAccumulator`，不得 publish signal／公開 accessor。save failure 時
丟棄 accumulator 且公開事件數必為 0。final save 成功後才 seal accumulator，將 event storage
以 ownership transfer 移入 `RunPresentationSession` 私有的唯一 `BattleTranscriptBuffer`，
並立即清空／revoke accumulator；不得以 deep clone 留下第二份 owner。
playback controller 只持 presentation state：

```gdscript
var cursor: int
var speed: PlaybackSpeed # X1/X2/X4
var paused: bool
var presentation_accumulator_ms: float
var transcript_identity: BattleTranscriptIdentity
```

每 frame 依 speed 增加可消費事件數／時間窗，但不呼叫 gameplay RNG、不修改 event、
不重排同 tick sequence。換倍率與 pause 不寫 gameplay save。

`BattleTranscriptBuffer` 是 commit 後完整 events 的唯一 owner，constructor 只接受 seal 後
移交且 final save 已成功的
`run_id + battle_setup_hash + committed_result_digest + resolution_identity + transferred event storage`。
它不暴露 raw array，也不放入任何 public result。`try_playback()` 只回 cloned
`BattlePlaybackState`／identity，不回 controller 或 buffer；UI 透過
`RunPresentationSession.drain_playback_window(expected_identity, max_count)`，由 session 以
private cursor 呼叫 buffer 並回 deep clone。`max_count` 只接受 1..4096。換新 battle、離開
COMBAT、session revoke 或 result acknowledge 都立即釋放 buffer。

事件數上限取 hashed `BattleRulesSnapshot.event_budget`（預設 16384）；byte budget 固定為
`min(event_budget * 1024, 64 * 1024 * 1024)`，以 canonical event codec encoded bytes 計算。
超 byte budget 時不影響已提交 result：釋放 transcript、回
`PRESENTATION_TRANSCRIPT_MEMORY_BUDGET_EXCEEDED` warning 並顯示 committed summary。
公開 queue 是最多 4096 的 sliding window，以 backpressure 補入，不丟失規則事件。
canonical simulation 因 event budget 失敗則沿用既有 typed error，不產生 result／公開 transcript。

`BattleResultPendingResolutionState` 重載時沒有 transcript authority，只顯示 committed summary；
不得從 latest catalog、wall clock 或重新模擬虛構重播。完整重播僅限同程序成功提交後的 buffer。

## 關鍵流程

### Boot → Menu

1. 綁定五個既有 service；正式 bootstrap 驗 asset／loc dependency 並安裝 generation。
2. `SaveRepository.load()`：NOT_FOUND 才建立 profile；INVALID/I/O 直接 boot failure。
3. LOADED run：`RunPreparationService.prepare(load_result)` 消耗 load capability、compose facade
   並登記單次 PreparedRunCapability；失敗則保存 recovery state。
4. AppStateMachine `BOOT_COMPLETED`，固定進 MENU。
5. SceneRouter 掛 `main_menu.tscn`，用 `MainMenuSnapshot` 決定 Continue／Start／Recovery。

### Continue／Start

- Continue：fresh load／prepare（若 boot capability 仍有效可直接用）→prepare scene/transition
  candidate→單次 consume capability→commit MENU→RUN；任一步失敗保留 MENU。零 save。
- RUN→MENU：先 prepare menu candidate；commit 後 revoke capability、釋放 session。下一次
  Continue 必須 fresh load／prepare，不能重用舊 facade。
- Start：fresh load。只有 `RunStatus.NONE` 才 `OPEN_CAMP`；任何 retained run 都具名拒絕。
- CAMP 開局：Camp screen 建 `StartExpeditionRequest(commander_id, challenge_level)`→
  ApplicationRoot 建 NONE expectation→CampController 的 CampMutationTransaction。transaction
  ownership 內 fresh-read/revalidate/apply/validate/internal-save；save 前 failure 留 CAMP；save 後
  compose／route failure 保留 committed run 並顯示 recovery，不再次 dispatch。
- Recovery discard：decoded token 比 expected id＋file digest，opaque token 比 file digest；
  repository mutex 內 fresh-read authoritative committed source→copy/read-back/promote digest
  archive→既有 clear-run save→刷新 menu。重複確認同 digest archive 冪等；任何 crash/fault
  落在 §2 明列的 base state×tmp residue matrix，重啟由 valid main 或 backup old 決定性恢復，
  再清理／隔離所有 residue。

### Screen route／Results return

- same-App-state route：prepare candidate＋parent-bound subroute token→commit 新 route／scene／
  `LiveScreenLease` 並 revoke 舊 lease；RUN→RUN 保留同一 RunPresentationSession。
- cross-App-state route：另 prepare App transition token與 target subroute token；任一 prepare/bind
  failure 保留舊 state／route／scene／lease／session。離開 RUN 時才在 lease revoke 後 release session。
- RESULTS 的 CAMP／MENU action 都先驗已提交 terminal/meta receipt，分別 prepare
  `RETURN_RESULTS_TO_CAMP + CAMP_WORLD` 或 `RETURN_RESULTS_TO_MENU + MENU_MAIN`；兩者零新 save，
  candidate/bind failure 留 RESULTS，舊按鈕 callback 因 lease revoked 不得重入。
- terminal postcommit：TerminalSettlementCoordinator 持有 AppRoot guard＋repository ownership，
  settlement save success→internal 驗證／consume `TerminalSettlementPresentationCapability`→
  立即 revoke RUN `LiveScreenLease`→invalidate/release RunPresentationSession→將 App state 設
  RESULTS→釋放 ownership→以 committed
  settlement result/receipt＋fresh profile 建 clone-only ResultsPresentationSnapshot→prepare/bind
  RESULTS scene。後段 failure 保留舊 scene 但切成無 intent/navigation 的 read-only fallback，
  安裝 `RESULTS_FALLBACK` results-only port；不得重建 active run 或重送 settlement。

### UI intent

Screen 建 typed intent→若不可逆則先建立 confirmation draft→confirm exactly-once→facade
lifecycle check→command factory→RunController transaction→成功重建 snapshot→route/render；
cancel 零 dispatch。戰鬥 inspection 與 Collection query/compare 只讀 clone，不進 command factory。
失敗映射 loc error並保留前 snapshot。

### Settings

Settings screen 編輯獨立 draft→`SettingsApplicationCoordinator.apply()` 取得 single-flight→
clone/normalize＋digest→四 adapter 各自 private plan preflight→驗四 token digest→repository
clone-in/validate/atomic commit→四 token no-fail activation→發 clone-out `settings_committed`。
reentrant／競爭 apply、token mismatch、preflight/save failure 零 runtime mutation；意外
post-commit diagnostic 保留 committed snapshot，進 safe fallback 並 fresh rebuild 全 consumer。

## 版本策略

| 契約 | 本片決策 |
|---|---|
| Gameplay save schema | 維持 3；不改 ProfileState/RunState wire |
| Content codec | 維持 2；第二片才升 3 |
| Settings schema | 新增獨立 settings schema 1；stable string enum＋bps，future version 保留原 bytes |
| Localization catalog | 新增 catalog schema 1；stable key，第二片只潤飾 value |
| Presentation snapshot | v1，非持久化；每次從 pinned canonical view 重建 |
| Battle canonical | 不變；playback speed 不進 setup/result/hash |

## 取捨與替代方案

- 採用：先安全 load/compose，再固定進 MENU。這保留 fail-closed 與 Continue 即時性，又不讓 boot
  自動跳畫面。
- 捨棄：boot 先進 MENU、按 Continue 才第一次 load。這會把內容／存檔致命錯誤延後，並使 Start
  與 retained run race 更難封鎖。
- 採用：抽出 production facade，dev Lab 作 consumer。
- 捨棄：把 `RunLabSession` 搬名後直接當 production API；其 `buy_first_offer`、
  `resolve_rewards` 等灰盒 convenience 不是玩家 intent 契約。
- 採用：settings 獨立原子 repository。
- 捨棄：把設定塞進 ProfileState；會不必要 bump gameplay schema 且增加進度存檔風險。
- 採用：先完整 scene shell＋視覺樣板，使用者核可後量產。
- 捨棄：第一片直接量產 32 棋；方向錯誤時返工成本不可接受。

## 風險

- 現有 S5 測試鎖定 boot 直入 CAMP／RUN；本片是已核可 G2 語意變更，必須先新增／更新紅燈
  測試證明 MENU 行為，不可只改 production 讓舊測試失真。
- `INCOMPATIBLE_PRESERVED` 無 decoded run_id；本片須新增 full committed-file digest token 與
  archive-before-clear 交易，不得誤接 expected-id discard。第四片的 signed migration bridge
  仍負責可遷移 active run，不取代玩家明示棄置。
- 既有 save rotation 可短暫 main missing；安全不變式是 backup old 或 digest archive 至少一份
  byte-identical，而非 main 永遠存在。restart repair 與每個 crash state 都是 T06 硬 Gate。
- Godot FileAccess 沒有可攜 fsync 契約；本片 durability 證據以 close＋read-back＋restart fault
  matrix 為界，實體斷電 cache 行為列 release 殘餘風險，不宣稱超出 runtime API 的保證。
- 150% 繁中與巢狀 tooltip 易造成 720p overflow；最壞字串 screenshot 為硬 Gate。
- Godot SubViewport／CanvasLayer input transform 易錯；用座標映射整合測試與三解析度 screenshot。
- presentation event queue 可能落後；本片量 queue telemetry 但 AC-031 由第四片最低規格實機收口。
- typed contract 尚不存在會使 GUT parser abort；T00 先用 dynamic load／static contract test
  建 compile-safe skeleton，再由後續 behavioral-red manifest 鎖定真正行為。parser abort
  不算有效 behavioral red。
- 視覺樣板可能不被使用者接受；硬停且不量產，保留可替換 token／atlas contract。

## 測試策略

測試框架與指令：GUT 9.7.1＋既有 PowerShell runner。Godot 路徑由 `-GodotPath` 傳入，
不得寫入 repository。TDD red／green 與 SHA-256 manifest 存 `.pipeline/tdd/`。

| R# | 測試案例名 | 輸入/前置 | 預期結果 | 層級 |
|---|---|---|---|---|
| R1 | `test_production_dependency_graph_has_no_dev_paths` | main scene＋production scripts | dev references=0；真 dependency 缺漏具名失敗 | Spec＋Content |
| R2 | `test_boot_always_routes_to_menu` | no-save／run-free／active-run fixtures | 三者成功 boot 都停 MENU；致命 load fail-closed | GUT＋Smoke |
| R3 | `test_menu_continue_start_and_recovery_are_guarded` | NONE／LOADED／compose-failed／preserved＋operation epoch | consume 鎖內 fresh digest；任一其他 load/write 使 capability stale | GUT＋整合 |
| R3 | `test_camp_start_expedition_typed_transaction_and_route` | commander/challenge success＋domain/compose/route faults | success 建唯一 run→RUN；pre 零寫；post 保留 committed run＋recovery | GUT＋Smoke |
| R3 | `test_all_camp_writers_share_atomic_repository_transaction` | unlock/start/decoded discard/opaque discard＋競爭 operation | ownership 內 fresh-read→expectation→apply/validate/save；stale 零寫 | GUT＋整合 |
| R3 | `test_recovery_restart_cartesian_tmp_residue_matrix` | 四 base states×none/archive_tmp/save_tmp/both | main 優先否則 backup；所有 residue 清理/隔離；retained run 不丟 | GUT＋整合 |
| R4 | `test_formal_scene_routes_and_command_only_writes` | route／非法 edge／惡意 staging screen／prepare-bind fault | staging intent 拒絕；failure 保留舊三件套；commit 後才 activate | GUT＋Smoke |
| R4 | `test_parent_bound_subroute_tokens_and_screen_leases` | MENU/CAMP/RUN same-state routes＋stale old callback | 合法矩陣 atomic swap；舊 lease 拒絕；RUN session continuity | GUT＋Smoke |
| R4 | `test_results_return_actions_are_distinct_and_atomic` | RESULTS→CAMP/MENU＋keyboard/reentry/bind fault | 正確 target；零新 save；failure 保留 RESULTS | GUT＋Smoke |
| R4 | `test_live_screen_intent_port_rejects_stale_dispatch_and_confirmation` | 舊 context/port＋RUN session continuity＋舊 draft | navigation/dispatch/confirmation 全 SCREEN_NOT_ACTIVE | GUT＋整合 |
| R4 | `test_collection_filter_search_compare_is_clone_only` | content/recipe/glossary＋filter/search/compare＋鍵盤 | 三類齊全；compare capability typed；修改 draft/view 不回寫 | GUT＋Smoke |
| R5 | `test_run_presentation_session_dispatches_all_typed_intents` | 全 command 對照 success/failure＋雙 consumer | intent 無缺口；deep clone 無 alias；no playback 為 typed result | GUT |
| R5 | `test_irreversible_confirmation_cancel_and_exactly_once` | forge/relic replace/reward abandon＋cancel/repeat/stale | cancel 零 intent；confirm 一次；重複/stale 具名拒絕 | GUT＋Smoke |
| R5 | `test_combat_unit_inspection_is_typed_and_read_only` | mouse/keyboard selection＋消失/stale/non-COMBAT | 六類資訊可見；零 command intent；舊資料不殘留 | GUT＋Smoke |
| R5 | `test_terminal_postcommit_revokes_run_writers_before_results_route` | settlement success＋consume 前競爭 load/write＋RESULTS fault＋舊 callback | joint ownership 無空窗；RESULTS/FALLBACK；無 active run；receipt exactly-once | GUT＋Smoke |
| R5 | `test_results_fallback_retry_and_exit_lifecycle` | transient/persistent route fault＋consume 前競爭 write／receipt change／read fault＋stale/repeat/sibling token＋keyboard；retry 取得 repository ownership 前、CAS/repository release 後、candidate bind 中各注入 Camp/Menu 重入 | ownership 內 fresh CAS；guard 全程持有且六個 loser typed busy/stale、零 route/save；attempt generation 撤銷 siblings；App state/route/lease 一致；fault 後 guard 釋放且 fresh retry/exit 可恢復；舊 RUN port 拒絕 | GUT＋Smoke |
| R6 | `test_world_viewport_ui_and_pointer_mapping_contract` | 三解析度＋非 16:9＋三 scale | render 正確且 world/hotspot/UI hit target 一致 | Smoke＋整合＋screenshot |
| R7 | `test_playback_commit_speed_pause_and_backpressure` | 同 setup/seed、save fault、reload、1×/2×/4×、16384 events | precommit accumulator 私有；commit 後 transfer 唯一 owner；session drain≤4096；hash/順序相同 | Combat＋Canonical |
| R7 | `test_transcript_memory_budget_falls_back_to_committed_summary` | encoded transcript 超 `min(event_budget×1024,64MiB)` | canonical result 保留；buffer 釋放；具名 warning＋summary | GUT＋整合 |
| R8 | `test_settings_repository_atomic_round_trip_and_faults` | 全欄位／locale／fault／corrupt／future＋input/consumer mutation | clone-in/out 無 alias；exact reject；fault 零 swap；future bytes 保留 | GUT |
| R8 | `test_settings_application_coordinator_two_phase_apply` | adapter faults/mutator＋save fault＋reentrant/競爭 apply＋post diagnostic | single-flight；digest-bound token；pre/save 零 runtime；post 保留 commit＋重建 | GUT＋整合 |
| R9 | `test_audio_coordinator_applies_four_buses_atomically` | 四 bus volume/mute＋缺 bus／before-commit fault | round-trip；preflight；失敗四 bus 全不變 | GUT |
| R10 | `test_localization_catalog_key_sets_and_no_hardcoded_text` | exact zh_TW/en set＋正式 scene/content scan | key set 相等、繁中非空、其他 locale 拒絕、缺 key 非零、硬編碼=0 | Content＋Spec |
| R11 | `test_keyboard_focus_accessibility_and_scale_contract` | 主要畫面×3 scale×4 color modes | 敵我等資訊有非色彩提示、focus 可達、無裁切 | Smoke＋visual |
| R12 | `test_presentation_errors_distinguish_commit_boundary` | pre/post commit route/bind/I/O/lifecycle fail | pre 保留舊 state；post 保留新 commit＋fallback＋可 reload | GUT＋整合 |
| R13 | `pilot_asset_inventory_and_visual_review` | 核可樣板 inventory＋images＋provenance | 數量／尺寸／透明／色盤／原創性／screenshots 全 PASS | 靜態＋人工 |
| R14 | `presentation_slice_release_gate` | fresh suites、10k soak、雙審、review ledger | 全部有新鮮證據；任一缺漏保持 FAIL | 實跑＋人工 |

R13 為藝術資產，免 TDD；以 deterministic asset validator、render screenshot 與人工核可替代。
R14 是證據聚合，免 TDD；其餘 R1～R12 先由測試代理建立紅燈並鎖 SHA-256。

### Owning global AC fresh evidence matrix

| Global AC | R | Task | 本片必要的新鮮 production evidence |
|---|---|---|---|
| AC-004 | R4/R5 | T09 | 正式 prepare UI 列出全部非法部署原因並阻止 intent |
| AC-005 | R4/R5 | T09 | 12 人上限／移除來源後超員提示與 start 拒絕 |
| AC-006 | R5/R11 | T09/T12 | 正式敵情、技能、羈絆、目標、Boss 階段可見 |
| AC-007 | R7 | T11 | 1×／4×／reload 的 result、event summary/hash 相同 |
| AC-017 | R5 | T04/T09 | 正式換裝／出售／拆卸與 overflow 無軟鎖 |
| AC-020 | R5 | T04/T09 | reward 重載候選相同且只領一次 |
| AC-024 | R1/R5/R10 | T01/T04/T14 | UI 與模擬同 pinned view、無 authoring Resource |
| AC-028 | R6 | T10 | 720p／1080p／1440p screenshot |
| AC-029 | R8/R11 | T08/T12 | 四色覺＋150% UI 非色彩／focus |
| AC-039 | R3/R4/R5 | T05/T07/T09 | 合法 transition only、非法 intent 與 DTO mutation 拒絕 |
| AC-044 | R4 | T08 | 正式五設施同一 ProfileState view |
| AC-049 | R5/R10 | T04/T14 | UI/static scan 無複製 TUNE；改值後顯示同步 |
| AC-055 | R5 | T04/T09 | roster 單一 authority、UI clone 不共享集合 |
| AC-065 | R5/R12 | T04/T09 | UI mutation／save faults 零部分變更 |
| AC-070 | R3/R12 | T06 | decoded/opaque cancel、錯 token、archive-before-clear fault matrix |
| AC-072 | R5 | T04/T09 | 多 stage reward／overflow 正式操作可恢復 |
| AC-075 | R1/R5 | T04/T14 | 修改 definition view 不影響 registry/digest/result |
| AC-076 | R5/R12 | T04/T12 | 公開 presentation API 具名 error、無 silent null |
| AC-077 | R10 | T01/T14 | 正式 scene/content 無硬編碼且 zh_TW/en key parity |

## Failure policy

- presentation 公開 API 只回 typed result／具名 error；不得 silent null、assert crash 或吞來源碼。
- gameplay writer 維持 copy-validate-save-swap；UI snapshot mutation 永不回寫。
- settings writer 只能由 SettingsApplicationCoordinator 呼叫；adapter preflight/save fault
  零 runtime mutation，post-commit diagnostic 保留新 snapshot並重建全部 consumer。
  SettingsRepository 全部 public 邊界 clone-in/out；coordinator 以 non-reentrant single-flight
  包住 clone/normalize→preflight→save→activation，token 按值捕捉並綁 digest。
- pre-commit failure 保留舊 canonical；post-commit presentation failure 保留新 committed state，
  顯示 fallback 並由 retry/reload 恢復，不回滾 exactly-once writer。
- SceneRouter staging context 唯讀；candidate/bind failure 保留舊 state／route／scene／lease／session。
  same-state route 用 parent-bound subroute token，cross-state 同時用 App＋target subroute token；
  commit 建新 LiveScreenLease 並撤銷舊 lease。RUN→RUN 保留 session，離開 RUN 才釋放。
- production screen 只持 lease-bound LiveScreenIntentPort/NavigationPort，不得持 raw session/facade；
  每次 navigation、dispatch、confirmation 都驗 active lease/route generation。
- generic route preservation 只適用 domain precommit。terminal settlement commit 後立即 revoke
  RUN writer lease、invalidate/release session並進 RESULTS；commit 到 handoff 全部在同一 AppRoot
  terminal guard＋repository writer ownership，其他 public operation 不得插入。presentation
  failure 進 typed RESULTS_FALLBACK，只暴露 receipt-bound retry與零-save Camp/Menu navigation；
  Results snapshot 只從 committed receipt/result＋fresh profile clone 重建。fallback retry
  consume 必須在 repository read ownership 內 fresh-read 後以 receipt＋完整 file digest 作
  CAS；每次 attempt 都推進 retry-attempt generation並撤銷同代 sibling token。
- RESULTS→CAMP／MENU 是分離 typed event，只在已提交 terminal/meta receipt 後執行且零新 save；
  route failure 保留 RESULTS。
- localization/asset dependency 缺漏使 Content／boot gate 失敗，不以 dev fake 放行。
- PreparedRunCapability 綁 repository identity／operation epoch／完整 committed file digest；
  consume ownership 內 fresh-read，不符即 stale。
- decoded recovery 額外比對 expected-run-id；opaque recovery 只比對完整 committed file digest，
  不存在 run-bytes digest。archive-before-clear crash 以 §2 四個 base state×四種 tmp residue
  表示，但至少有 byte-identical backup old 或 archive；不一致不刪、不猜，tmp 永不自行升格。
- 所有 Camp writer 只能由 CampMutationTransaction 在單次 repository ownership 內完成
  fresh-read→expectation→apply/validate→internal-save；中途不得 await。跨程序同檔寫入未受 OS
  file lock 保護，明確不在本片支援範圍。
- PendingBattleTranscriptAccumulator 僅存 precommit events；save success 後 ownership transfer
  到 session-private BattleTranscriptBuffer 並清空 accumulator。public result 不得回 buffer／
  controller；identity 不符、window 超 4096 或 lifecycle 已釋放皆具名拒絕。
- 不可逆操作未確認不得 dispatch；confirmation cancel 零寫，confirm token 僅可消耗一次。
- locale wire value 只允許 `zh_TW|en`；Collection 三類資料、query/compare 與 combat inspection
  都是 clone-only presentation state，不得進 command writer；glossary/跨類 comparison typed reject。
