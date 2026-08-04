# HANDOFF — Claude／Codex 分工與交接指引

> 建立於 2026-07-22（使用者裁決）。本檔是兩個 AI 協作者之間的分工契約與接手入口；專案進度見 `PROGRESS.md`，規格單一事實來源見 `docs/game-architecture/`。

## 0. 2026-08-04 balance-playtest Phase 0 收尾接手點

- 基線：PR #8 已合併，第三切片分支為 `codex/g2-balance-playtest`，起點
  `master@bf818fb`；目前未 commit、未 push、未建立 PR。
- 里程碑：附錄 A/B/C 修正全數落地並經 Claude 核驗；**3k screening #2 gate PASS**
  （candidate `balance.g2.7d47fada8091`、12 分片、10.1 小時、3,000/3,000 terminal、
  150/150 replay 零 drift、economy 1,000 勝、dominance 15.8pp、
  source freeze `5982d579…0758`）。舊接手點
  `.pipeline/balance-playtest/PAUSE-2026-08-03-appendix-c.md` 所列阻擋均已解除。
- 使用者裁決（2026-08-04）：大樣本統計（10k/30k）延後至 Phase 2 平衡收斂後執行；
  本切片以 3k #2 作 screening 證據收尾。Phase 0~3 執行計畫見 `specs/g2-roadmap.md` §9，
  收尾 checklist 見 `specs/balance-playtest/rewrite-plan.md` 附錄 D。
- Phase 0 待辦：tier2+ 入樣補證 → Part D 證據鏈（RC 重打包、全鏈路 smoke、
  source manifest、export 排除與 PCK inventory）→ NUL 修正合入 → 文件回寫 →
  兩位 fresh reviewer 重審 → 使用者確認 Git。早前雙審的 NOT APPROVED 針對重寫前
  實作，其 blockers 已由重寫解除；收尾仍須 fresh 雙審，未 closure 前不得宣稱
  本片或 G2 complete。
- 重要修正備忘：production battle catalog 需納入 encounter roots，否則正式
  NodeEntry／EncounterCompiler 會以 `ENCOUNTER_RULE_MISSING` fail closed；
  `domain/run/controller/run_commit_clock.gd` 的 `now_unix()`（+3 行加法式儀器支援）
  須在雙審變更說明中列明。
- 平衡訊號留檔（Phase 2 迭代起點，非收尾 blocker）：economy 100% 全勝（XP 性價比）、
  tempo/synergy 不買 XP、verdant 77% 居首、Act 1 Boss 仍是唯一過濾器（BP-SI-004）、
  shadow build 0.16%（池構成）。

## 1. 分工邊界

| 負責方 | 範圍 |
|---|---|
| **Claude** | 程式邏輯與架構：`domain/`、`services/`、`content/`（定義、註冊表、驗證器、內容邏輯）、`app/`、全部測試與 runner、**ViewModel／介面層**（UI 可消費的資料介面與快照、場景骨架、`SceneRouter` 路由、事件訂閱）、開發用灰盒 Lab（`scenes/dev/`）。 |
| **Codex** | 表現與體驗：正式畫面的視覺呈現、佈局、動畫、美術素材（像素圖、圖示、字型）、音效／音樂、UX 打磨與易用性調整。 |

- 灰盒 Lab（Combat Lab／Expedition Lab／Build Lab）是開發驗證工具，**不是**正式 UI；Codex 建正式畫面時以 Lab 展示的操作流與 ViewModel 為參照，不必沿用其外觀。
- 內容數值（TUNE 標記者）屬遊戲設計，目前由 Claude 隨切片授權佔位值；最終平衡屬下游調整，任一方發現數值問題記入 PROGRESS.md 待辦而非默改。

## 2. Presentation 消費契約（Codex 建 UI 時必守）

依 spec §8.5 與 REQ-TECH-004（違反即審查退回）：

1. **只持 clone／snapshot**：presentation 一律經 ViewModel 或 RunController 提供的 read-only snapshot 讀狀態，不得保留任何 domain 可變引用、不得跨操作快取 domain 物件。
2. **寫操作一律經 RunController command**：所有玩家操作（買賣、鍛造、換裝、遺物選擇…）呼叫既有 command，由 copy-validate-save-swap 交易提交；UI 不得直接改 `RunState` 或任何 domain 狀態。
3. **不得使用 Godot `rand*`／時間／Object ID 產生 gameplay entropy**：純視覺抖動可用本地亂數但不得回寫 domain；一切 gameplay 決定性亂數走 `RngService` 具名 stream。
4. **不得讀 latest catalog**：內容一律經 pinned canonical snapshot（`ContentRegistry` generation pin）；UI 顯示的門檻／數值必須與模擬消費同一份 compiled snapshot（例：羈絆預覽用 `BattleSetupSourceCompiler` 的產物）。
5. **Autoload 維持既有五個**（`ContentRegistry`、`SaveService`、`SettingsService`、`AudioService`、`SceneRouter`），不新增。
6. 驗證失敗 command 會回具名 error——UI 負責呈現，不得吞掉或繞過（例如 overflow tray 未清空時開戰被拒是設計行為）。
   - **具名原因的讀法**：頂層 `CommandError.code` 對所有拒絕一律是 `APPLY_FAILED`；具體原因（如 `EQUIP_ITEM_SLOTS_FULL`、`RESOLVE_OVERFLOW_ITEM_NOT_IN_TRAY`）在 `error.diagnostic_values` 中 key 為 `source_code` 的診斷字串——UI 分流訊息請讀這裡。
7. **讀取節奏**：ViewModel 每次讀取都回完整 deep-clone snapshot——請「操作後刷新」，不要逐幀輪詢（避免高頻深拷貝的效能壓力）。ViewModel 建構時持有 pinned catalog/規則表的私有 clone；catalog 世代更換（新 run／熱重載）時請重建 ViewModel 實例，勿沿用舊物件。

**ViewModel 入口清單**（S4 起提供，Codex 換皮起點）：
- `TraitPreviewViewModel`（`presentation/viewmodels/trait_preview_view_model.gd`） — 羈絆面板（當前計數／下一門檻／效果，與實戰同源）
- `ForgeViewModel`（`presentation/viewmodels/forge_view_model.gd`） — 鍛造介面（零件清單、配方預覽）
- `InventoryViewModel`（`presentation/viewmodels/inventory_view_model.gd`） — 物品庫／棋子裝備／overflow tray
- `RelicSlotViewModel`（`presentation/viewmodels/relic_slot_view_model.gd`） — 遺物槽序與第六件替換
- `CampViewModel`（`presentation/viewmodels/camp_view_model.gd`） — 營地五設施的單一 ProfileState 投影
- `ExpeditionGateViewModel`／`CommanderHallViewModel`／`CollectionViewModel`／`UnlockWorkshopViewModel`／`ChallengeMonumentViewModel` — S5 局外成長各設施讀取介面
- （S2/S3 既有）戰鬥 event/result clone、商店 offer 表、地圖節點狀態——見各 Lab 的 session/presentation 腳本示範消費方式

## 3. 進度地圖（接手時從這裡看）

| 切片 | 狀態 | 規格 | 完成證據 |
|---|---|---|---|
| S1 `foundation-core` | ✅ 完成 | `specs/foundation-core/` | PROGRESS 2026-07-13 條目；`foundation-acceptance.json`（無獨立 final-review，複檢結論僅載於 PROGRESS——歷史事實，如實記載） |
| S2 `combat-core` | ✅ 完成，複檢 PASS | `specs/combat-core/`（含 final-review.md） | `artifacts/test/`、10,000-seed soak |
| S3 `economy-expedition` | ✅ 完成，複檢 PASS | `specs/economy-expedition/`（final-review.md＋implementation-review.md） | 11/11 S3-AC evidence、10,000-seed ExpeditionSoak |
| S4 `build-systems` | ✅ 完成（2026-07-24） | `specs/build-systems/`（三件套＋implementation-review.md） | 12/12 任務、13/13 S4-AC、Gut 399/399、10,000-seed 構築 soak、8 份雙審紀錄（`.pipeline/reviews/` 本機） |
| S5 `meta-progression` | ✅ 實作完成（2026-07-26） | `specs/meta-progression/`（三件套＋implementation-review.md） | T01～T12、S5-AC 14/14、Gut 737/737、10k ExpeditionSoak、All exit 0、W5 R4 雙審零未決 |
| PROD／SCOPE／UX／QA 橫切 15 REQ | ✅ `content-production` 本地 fully closed（未提交） | `specs/g2-roadmap.md`、`specs/content-production/` | `codex/g2-content-production-closure`；44 adopted＋14 rejected；Gut 281/1093、10k soak、All exit 0；acceptance 21＋1 PASS／fully_closed=true |

- **content-production 最終閉環（2026-08-01）**：Claude 全批 T18A review
  已落 `.pipeline/content-production/reviews/t18a-full-batch-claude-review.md`；Codex
  依決定回寫 ledger 44 adopted＋14 rejected，inventory status=`adopted`，並以
  adopted source 重建 44 portraits／atlases／SpriteFrames、Camp 與五張 shared
  atlas。T20 維持 R9，5 music／21 SFX 已重生為 48kHz/stereo/OGG q0.5，解碼
  peak/seam/bus 全通過。fresh Gut 281/1093、10k ExpeditionSoak、All exit 0；
  acceptance 21＋1 全 PASS、`blocked_row_ids=[]`、`fully_closed=true`。
  工作樹位於 `codex/g2-content-production-closure` 且未提交（後由 PR #8 合併）；
  後續切片順序依 `specs/g2-roadmap.md` §9 的 Phase 0~3 計畫（balance-playtest 收尾 →
  difficulty-curve 機制切片 → 平衡迭代迴圈＋大樣本 → performance-release）。
- 測試 gate：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite All`（其餘 suite 見專案 `CLAUDE.md`）。`artifacts/test/` 為本機驗證輸出。
- 表現層現況：production scene catalog/shell、typed router/lease、settings/audio、
  真 SubViewport/UI layer、playback/accessibility、formal typed controls 與 T13
  原創像素 pilot 已建立，pilot 已獲使用者核可。R16 findings closure 與 T15
  final evidence 已完成；使用者明示不做 R17；PR #5 與 merge 後修正 PR #6
  均已合併。完整內容／資產量產已由 `codex/g2-content-production` 啟動。
- **T11 內容缺口修復記錄**（S4 wave4 收尾，2026-07-23）：Build Lab（T11）首次把 `content/packs/vertical_slice/` 餵進 production `EconomyExpeditionCatalogBuilder`／`ContentRegistryReceiptAdapter` 後，暴露兩個此前從未被真正觸發過的內容缺口，已一併修復：(1) `economy_configs/slice_default.tres` 原缺 `layer_income`／`xp_thresholds`，被 builder 判定不合法而驗證器當時未攔——`content/validation/content_validator.gd:298` 已補上與 builder 一致的必填欄位檢查（新增 `CONTENT_ECONOMY_CONFIG_INCOMPLETE`）；(2) 雙 pack 合併後完全沒有 `meta_reward_table` 分類內容，導致 `ContentRegistryReceiptAdapter` 的 save/load 在 receipt 重建階段必定失敗（`PINNED_CATALOG_REFERENCE_MISSING`）——已新增 `meta_reward_tables/slice_default.tres` 佔位內容＋驗證器 `CONTENT_META_REWARD_TABLE_MISSING` 規則。細節見 `content/packs/vertical_slice/README.md`「T11 wave4 內容缺口修復」與 `scripts/dev/build_lab/build_lab_content_bootstrap.gd:14` 註解。

## 4. 雙方工作流

- **Claude**：功能片走 `specs/<切片>/` 三件套（逐段核可）→ 依 tasks 波次實作（TDD 分代理：測試先行→紅證據→實作轉綠→fresh 重驗）→ 雙審（Sonnet 5 一審＋Opus 4.8 二審，兩獨立 session；使用者裁決不用 Codex review）→ 更新 PROGRESS.md 與本檔。
- **Codex**：接手 UI 時（1）讀本檔 §2 契約與 §3 進度地圖；（2）從對應 Lab 的 session 腳本看 ViewModel 消費示範；（3）正式場景放 `scenes/`（非 `scenes/dev/`），經 `SceneRouter` 掛入；（4）改動不得觸碰 `domain/`／`services/` 邏輯——需要新資料介面時，在 PROGRESS.md 待辦記需求由 Claude 補 ViewModel；（5）改動後跑 `-Suite All` 確認灰盒與邏輯測試不受影響。
- **G2 使用者新裁決（2026-07-26）**：四切片由 Codex 依 SDD＋TDD＋雙審完整交付，所需 `domain/`／`services/`／`app/` 變更已在各片規格內授權；上一條「Codex 不碰邏輯層」只描述 G1 時期分工，不限制已核可的 G2 任務。
- 規格／數值變更：先改 `docs/game-architecture/` 對應章節＋§14 追溯矩陣，再改程式（見專案 `CLAUDE.md`）。
- **S5 接線完成記錄**：`RunCommandFactory` 已成為 `GenerateExpeditionMapCommand`／`RefreshShopCommand`／`SettleBattleResultCommand`／`EnterNodeEvent` 的唯一正式建構點，顯式注入非 null `relic_table` 與 pinned generation；`test_run_command_factory*.gd`、Run 灰盒與 10k soak 已鎖定此契約。
- **Retained run／Camp transaction 契約**：PurchaseUnlock、StartExpedition、decoded／opaque DiscardActiveRun 與所有 Camp writer 共用 repository-owned `CampMutationTransaction`，在單次 ownership 內 fresh-read、比對 identity／epoch／完整 committed-file digest／typed expectation，再 apply→validate→internal-save；不得跨 `await` 或先 public load 後稍後 public save。G2 recovery token 一律綁 repository identity、operation epoch 與**完整 committed file bytes SHA-256**；decoded composition failure 額外綁 expected run-id，opaque `INCOMPATIBLE_PRESERVED` 不猜 run-id、也不使用 run-bytes digest。確認後在同一 writer ownership 內先 copy→read-back→promote digest archive，再 clear-run save；不得 move main。Crash matrix 為四個 authoritative base states×none/archive_tmp/save_tmp/both residue；重啟先選 valid main，否則 valid backup，再一律清理／隔離 tmp 並保留 run。安全不變式是至少一份 byte-identical backup/archive，而非 main 永遠存在。token 無法建立仍 boot failure；未加 OS file lock 的跨程序共同寫檔不在本片支援範圍。
- **Scene／settings ownership 契約**：same-App-state 畫面切換使用綁 parent state＋route generation 的 subroute token；每個正式畫面只持可撤銷 LiveScreenLease，以及每次驗 lease 的 LiveScreenIntentPort/NavigationPort，raw RunPresentationSession 不外流。RUN 子畫面換場沿用同一 session。terminal settlement 的 save commit→internal capability consume→RUN writer lease revoke→session invalidation→RESULTS transition 必須保持同一 AppRoot terminal single-flight＋SaveRepository writer ownership、固定鎖序且全段無 `await`；postcommit presentation failure 只能進 typed `RESULTS_FALLBACK`。其 results-only retry token 綁 repository／receipt／完整 committed-file digest／fallback route generation／retry-attempt generation，consume 在 repository read ownership 內 fresh-read authoritative bytes 作 CAS；每次 attempt 推進 generation 並撤銷同代 sibling token，另提供零新 save 的 Camp／Menu exit。RESULTS→CAMP／MENU 是分離 typed event。SettingsRepository public 邊界一律 clone-in/out；SettingsApplicationCoordinator 以 single-flight 同步包住 clone/normalize→四 adapter preflight→save→activation，token 按值捕捉並綁 candidate digest。
- **R8 修正後交接（2026-07-28）**：`G2-R8-01` 已在 requirements／design／T07／T09 與 `test_results_fallback_retry_and_exit_lifecycle` 補齊 retry-vs-Camp/Menu 六組 reentrant barrier。results-action guard 在首次 fallback lease 驗證前取得，跨 repository unlock 持有至 route commit/failure cleanup；loser typed busy/stale 且零 save／route commit，並驗 App state／route／lease 一致與 failure 後 guard 釋放。分支已重放到最新 master；下一步只做 fresh R9 雙獨立規格複審，兩份皆 zero unresolved findings 前不得建立 TDD 紅燈或宣稱 SDD Approved。詳見 `specs/presentation-ui/review-log.md`。
- **R9 修正後交接（2026-07-28）**：使用者全採納 R9-B01～B03。Exit 的 named test 鎖定 MENU_MAIN-only、可攔截 single signal、pending／錯 lifecycle typed reject、state/route/save 不變與 runner 存活；`ABANDON_BOSS_RETRY` 已進 confirmation exactly-once 矩陣；dev CLI exact allowlist `--combat-lab` 必須共用 production bootstrap/facade。下一步只做 fresh R10 雙獨立規格複審；通過前不得建立 T00 紅燈。
- **R10 ownership 修正後交接（2026-07-28）**：Exit root API／pending lifecycle 與 `--combat-lab` composition/integrated smoke 均交 T05 這個唯一 AppRoot owner；T01 只做 bootstrap component、T04 只做 facade/dev wrapper component、T08 只做 UI button/host smoke。R1 Covers 與雙向追溯已補 T04/T05；下一步只做 fresh R11 雙審，通過前不得建立 T00 紅燈。
- **R11 硬停交接（2026-07-28）**：fresh 雙審新增 3 項 Medium findings：Exit 同一 named test 跨 T05/T08 wave 與 manifest SHA lock 衝突；T08 settings UI 驗收依賴後置 T12 concrete coordinator；AC-070 decoded/opaque recovery 的 cancel/wrong token/replacement/archive/save fault preservation 缺 fresh named matrix。等待使用者裁決；採納項修正後必須 fresh R12 雙審，通過前不得進 TDD。
- **R11 修正後交接（2026-07-28）**：使用者全採納三項 finding。Exit 拆為 T05 root contract 與 T08 button/host smoke 兩個 immutable test；T08 settings 只消費 injected typed port，T12 才做 concrete coordinator、restart/四 bus production integration；T06 鎖 decoded/opaque wrong/stale/replaced token 與 archive/save fault preservation，T08 另鎖 cancel 零 dispatch。下一步只做 fresh R12 雙審，通過前不得進 TDD。
- **R12 硬停交接（2026-07-28）**：R11 三項修正確認封閉，但 fresh R12 新增 4 項 Medium findings：T05/T07 terminal handoff ownership/DAG 循環、Results snapshot authoritative commit boundary 矛盾、playback invalid multiplier 缺 matrix、reduced effects/density/tooltip/CJK 缺具名 evidence。等待使用者裁決；採納項修正後必須 fresh R13 雙審，通過前不得進 TDD。
- **R12 → Claude 工作單（2026-07-28）**：使用者指示保留 R12 findings 待修並交由 Claude 完成。依 `specs/presentation-ui/review-log.md` 四項 proposed fix 修訂 requirements/design/tasks；先跑 `git diff --check`＋Spec，再做 fresh R13 架構與行為雙審。兩份 reviewer 原文與決策表必須先同步 `.pipeline/reviews/`、review-log、PROGRESS、HANDOFF、roadmap；雙 zero findings 前不得標 SDD Approved 或開始 TDD。
- **Review Gate override（2026-07-28）**：使用者後續明確要求審查先跳過並繼續下一步。本地 fresh baseline、TDD 與 implementation 可先進行；R12 四項仍 unresolved、R13 延後未取消，最遲在 T15/Git 前補齊。此指示不放行 stage、commit、push、PR 或 merge。
- **wave0/T00 交接（2026-07-28）**：fresh baseline 為 Import/Spec/10k ExpeditionSoak/All 全綠；contract red 有效且 SHA manifest 鎖定。T00 新增 35 個 compile-safe contract/supporting classes、AppEvent 三個 stable kinds，未實作 runtime behavior。主迴圈重驗限定 GUT 4/4（276 assertions）、Spec 3481 cases 與 All 741 tests/9608 assertions 全綠；下一步為 wave1 T01/T02/T04 behavioral red。
- **wave1/T01、T02、T04 交接（2026-07-28）**：五份 behavioral tests 的有效紅燈與 SHA manifest 已保存且主迴圈重算一致。T01 完成 production bootstrap、210-key `zh_TW|en` catalog 與 Build Lab adapter；T02 完成 injectable schema-1 原子 repository、fault recovery、future/corrupt 保留與 clone-only 邊界；T04 完成 24-intent typed facade/factory、pre/post-commit result 與 Run/Combat Lab 薄包裝。限定測試分別 7/7（464）、4/4（403）、12/12（55）；wave-end All exit 0，Gut 764/764（10530 assertions、零 failures/errors/orphans）、Spec 3555 cases。下一步為 wave2 T03/T05 behavioral red；T05 green 後才開始 T06。R12/R13 與 Git gate 仍維持延後未取消。
- **wave2/T03、T05 交接（2026-07-28）**：T03 typed 四 bus atomic audio 4/4（93）；原測試 helper 與 fake public API 不合格的兩次 manifest 已留撤銷與替換證據。T05 完成固定 Boot→MENU、typed lifecycle/exit、repository identity/epoch、共享 Camp transaction、prepared capability 與 terminal skeleton，7/7（159）。public API、舊 boot test、opaque LoadResult invariant 與 discard 診斷回歸修正後，All exit 0，Gut 767/767（10687 assertions）、Spec 3622 cases。T06 現可獨占 recovery/archive-before-clear；R12-A01/A02 未因 skeleton 實作而視為 resolved。
- **wave2/T06 與整波交接（2026-07-28）**：有效 red 為 2 tests/155 assertions（首跑 parser＋16 orphans 已拒收）；green 為 2/2、300 assertions。完成 decoded/opaque digest-bound token、writer CAS、copy/readback/promote archive-before-clear、同 digest 冪等、全 archive/save fault preservation 與 4×4 restart residue cleanup；tmp 不升格、profile/retained run 不丟。12 份 wave2 locked hashes 全一致；最終 All 769/769（10987 assertions）、Spec 3628 cases。下一步 wave3 T07 scene/router/lease contract；R12-A02 仍 unresolved。
- **wave3/T07 core 交接（2026-07-29）**：15 條正式 scene catalog/shell、staged read-only context、typed subroute token/coordinator、LiveScreenLease registry 與 stale port rejection 已落地；SceneRouter 先 instantiate/hidden bind 後 atomic swap，fault 保留舊 child，retired child 維持 owner 至 deferred free；AppRoot Boot→MENU_MAIN、CAMP_WORLD 與 RUN phase/RESULTS route 不再使用 dev casts。component 6/6（184）、integration 2/2（30）。稽查另發現舊 All 會在兩個 AppRoot scripts parse failure 時仍 exit 0，已同步非 locked callers/expectations；最終 All 為 158 scripts、785/785、11313 assertions，無 parse/load/unexpected/orphan。下一步 T08/T09 red；R12-A01/A02 仍由 Claude 接手。
- **wave3/T08、T09 component 交接（2026-07-29）**：T08 4/4（59）完成 Collection clone-only browser、MENU injected exit、decoded/opaque recovery cancel 與 typed settings port；T09 3/3（121）完成 19 reversible intent allowlist、四項 irreversible exactly-once confirmation 與 combat read-only inspection。T09 captured integer counter 假失敗已撤銷，改 `Array[int]` 後暫移 production 重建 exact-hash red，再恢復取 green；final manifests 相符。All exit 0，Gut 792/792（11493）。broader scene composition、R12-A01/A02 terminal/results 與 fresh R13 仍保留；目前進入 wave4 T10/T11 red。
- **wave4/T10～T12 交接（2026-07-29）**：T10 4/4（225）完成 640×360 world／1280×720 UI policy 與座標映射；T11 8/8（234）完成 commit-before-present、private transcript、identity/backpressure/budget 與 cursor-only speed/pause；T12 settings 4/4（295）、accessibility/error 8/8（362）、runtime 2/2（817），完成 concrete adapters、AppRoot typed port 與 production load/rebuild、locale/UI scale/四 bus round-trip。runtime 首次 green 10 orphan 只補 test lifecycle `autofree` 並撤銷舊 manifest；20 個 final hash 全一致。public untyped helper 的單一 Spec failure 已修，最終 All exit 0，Gut 818/818（13426）、Spec 3662。rebuild adapter `void` 診斷傳播列 residual risk；R12/R13/Git gate 維持延後。下一步 wave5 T13/T14，T13 後硬停等使用者核可。
- **wave5/T13 user-approved＋T14 green 交接（2026-07-29）**：T13 已產出五角色 20 張透明 64×64 方向 sprite、5 張 256×256 portrait、營地、core UI、多解析度／比例與四色覺 screenshots；validator 讀回 36 hashes、0 issues、1 項 `PUI_PILOT_SEED_NOT_EXPOSED` warning。使用者明示核可候選並接受此 warning；ImageGen 未暴露原生 seed，未虛構數值，完整 prompt、call id、處理參數與 SHA 已留存。T14 valid red 為 11/11 missing-validator assertions，green 11/11（175），6/6 locked hash 相符；production static gate exit 0、零 issue。wave5 All exit 0，Gut 829/829（13601）、Spec 3662。wave6/T15 驗證已放行；`content-production`、R12/R13/implementation review 與 Git gate 仍未放行。
- **wave6/T15 fresh baseline＋AC audit 交接（2026-07-29）**：fresh Gut、Smoke、Content、Canonical、Combat、Expedition、Spec、All 與 10k ExpeditionSoak 九組皆 exit 0；Gut 829/829（13601）、Spec 3662、soak 10000 seeds／40000 build operations。T13 approved validator、T14 production static gate 皆綠；19 active manifests 74/74 entries 相符。19-row 初審發現正式非 terminal scenes、runtime screenshots 與 exact cross-layer evidence 缺口，已開 supplemental behavioral red，故 T15 不勾。R12 四項、fresh R13／implementation 雙審仍由 Claude 封閉；不得進 Git 或下一切片。
- **wave6/T15 supplemental 收尾（2026-07-29）**：補正式 CAMP 五設施與 RUN_PREPARE/COMBAT/REWARD composition、pinned content/TUNE projection、720p/1080p/1440p×四色覺 runtime captures；limited green 3/3（256）＋4/4（183），12/12 PNG 零 issue。final 九組 suites 全 exit 0，Gut 836/836（14072）、Spec 3667、10k soak 零 failure；static gate 零 issue，21 active manifests 84/84。Godot 原生 crash 根因、dummy orphan、空白首幀與兩份 manifest revocation 已完整留痕。自動化證據已完成，但 R12 四項、fresh R13 與兩份 implementation review 仍交 Claude；T15 不勾，Git／下一切片不放行。
- **R15 修正完成／R16 工作單（2026-07-29）**：R12～R15 findings 均已採納落地；R15 valid green 為 architecture 1/1（11）、terminal 3/3（62）、behavior 8/8（152）。fresh Gut 239 scripts、932/932（16123），10k ExpeditionSoak zero failures；AppRoot-owned SubViewport/UI、atomic retry/terminal seal、formal typed controls、focus/modal 與 zero-size fail-closed 已接 production。runtime machine gate 加強後先重現 4:3 overflow 與 125/150% CJK/action overlap，再修到 10/10 zero issues並人工 read-back；39 manifests 151/151 references match。下一手直接做兩位 fresh read-only R16 reviewers；若有 finding 可修後做 R17/R18，但最多三輪，R18 後停止並寫殘餘風險，不開 R19。任何結果先同步 review-log／PROGRESS／HANDOFF／roadmap；使用者確認前不做 Git，`content-production` 不開始。
- **R16 雙審後暫停（2026-07-29）**：R16 architecture 為 2 High＋1 Medium、behavior 為 4 High＋2 Medium，NOT APPROVED。合併待修：split retry API、真 world viewport/target hit、真 inspection equipment/target、COMBAT overlay 遮蔽、authoritative PREPARE validation、PREPARE/COLLECTION/RESULTS 閉環、Settings editor focus、authoritative non-color semantics。使用者要關機，故此處硬停；尚未建 red、未修 production、未跑 gate、未開 R17。下次從 R16 red/fix 開始，review budget 尚餘 R17/R18；不做 Git、不進 content-production。
- **R16 closure／T15 final（2026-07-30）**：八個 R16 合併修正群組均已
  behavioral red→green；architecture 4、formal 5、viewport 4 tests 全綠。
  final Gut 243 scripts、945/945（16295）、Spec 3696、All exit 0、10k
  ExpeditionSoak zero failures、static gate zero issues；42 manifests／155/155
  references match。使用者明示 R16 後不再次雙審，故未開 R17；原 R16
  `NOT APPROVED` 報告維持歷史原文，closure table 在
  `.pipeline/reviews/2026-07-30-presentation-ui-r16-closure.md`。使用者已通過
  Git 發布 gate；PR #5 已合併為 9362e7d，merge 後 UI 審查修正亦由
  PR #6 合併為 5e78ccf。`content-production` 已從該最新 master 建立。
