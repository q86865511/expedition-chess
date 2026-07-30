# G2 presentation-ui 規格審查紀錄

> 日期：2026-07-26（2026-07-28 修訂）
> 分支：`codex/g2-presentation-ui`
> 基準：`93f68ceaf65b6de430f09b8526ebcfb97c79c5c5`（已重放至最新 master）
> 目前 Gate：`USER OVERRIDE — R12/R13 REVIEW_DEFERRED; IMPLEMENTATION_AUTHORIZED_WITH_KNOWN_RISK`

本檔保存可提交、可由下一位協作者直接讀取的規格審查狀態。`.pipeline/reviews/` 保留各 reviewer
原文，但屬本機 pipeline artifact；本檔才是 Git checkpoint 內的交接摘要。

## 裁決帳本

| Review | 使用者裁決 | 結果 |
|---|---|---|
| R1 | 14 項全部依建議修正 | 已回寫 SDD |
| R2 | 7 項全部依建議修正 | 已回寫 SDD |
| R3 | 7 項全部依建議修正 | 已回寫 SDD |
| R4 | 4 項全部依建議修正 | 已回寫 SDD |
| R5 | 3 項全部依建議修正 | 已回寫 SDD |
| R6 | 2 項全部依建議修正 | 已回寫 SDD |
| R7 | 1 項全部依建議修正 | 已回寫 SDD |
| R8 | 2026-07-26 先記錄；2026-07-28 使用者要求接手解決 | finding 已回寫 SDD，待 fresh R9 |
| R9 | 3 項全部依建議修正 | 已回寫 SDD，待 fresh R10 |
| R10 | 2 項整合建議全部依建議修正 | 已回寫 SDD，待 fresh R11 |
| R11 | 架構 1 項、行為 2 項 Medium finding 全部採納 | 已回寫 SDD，待 fresh R12 |
| R12 | 架構 2 項、行為 2 項 Medium finding | 使用者指示記錄並交由 Claude 修正 |

## R8 結果

- 架構／資料安全審查：`APPROVED — zero unresolved findings`；確認 `G2-R7-01` 已修復。
- 行為／UX 審查：`NOT APPROVED`；確認 `G2-R7-01` 已修復，但新增以下一項 Medium finding。

### G2-R8-01 — retry 與 Camp／Menu exit 的 single-flight 缺少競爭測試

**狀態：`RESOLVED_IN_SDD_PENDING_R9`**

目前 design 已要求 retry、Return to Camp、Return to Menu 共用 AppRoot
results-action single-flight，但 named test 尚未鎖定 guard 的完整生命週期。

可重現情境：

1. retry 完成 authoritative CAS 並釋放 repository read ownership。
2. retry 正在 prepare／bind RESULTS candidate。
3. fallback 的 Return to Camp 或 Return to Menu 重入。
4. 若 guard 遺漏或在 repository unlock 時提早釋放，exit 可先提交，外層 retry 再提交 RESULTS，
   造成錯誤最終 route 或 App state／route／lease 不一致。

建議修正：

- requirements、design、T07、T09 與 `test_results_fallback_retry_and_exit_lifecycle` 明列
  retry-vs-Camp 及 retry-vs-Menu 的 reentrant barriers。
- barriers 至少涵蓋取得 repository ownership 前、CAS/repository release 後與 candidate bind 中。
- results-action single-flight 從首次 fallback lease 驗證持有到最終 route commit／failure，
  全段不得 `await`。
- 同一時間只允許一個 action 前進；loser 回 typed busy／stale error，不得產生 gameplay save。
- 驗證 App state、presentation route、lease 一致；transient route failure 後 guard 必須釋放，
  讓後續合法 action 成功。

### 2026-07-28 修正與稽查結果

- `requirements.md` 已將 non-reentrant results-action guard 定義為在首次 fallback lease 驗證前
  取得，持有至最終 route commit／failure cleanup；repository unlock 不得提早釋放，全段無
  `await`。
- `design.md` 已定義 loser error、finally-style release、App state／route／lease 一致性，並把
  retry-vs-Camp 與 retry-vs-Menu 各自在 repository ownership 前、CAS/repository release 後、
  candidate bind 中的六組 barrier 寫入 named lifecycle test。
- T07 與 T09 已納入相同 lifecycle、零 gameplay save／零 route commit、transient failure 後可
  重新取得 guard 的驗收條件。
- 本次 Codex consistency audit 確認 finding 的五個指定落點均已覆蓋；這不是 fresh R9 的兩份
  獨立 reviewer 結果，不將 SDD 標為 Approved。

## 強制下一步

1. 以修訂後的 requirements／design／tasks 執行 fresh R9 雙獨立規格複審。
2. 只有兩份 R9 review 都為 zero unresolved findings，才可把 SDD 標為 Approved，並建立 TDD
   紅燈與 SHA-256 manifest。

本次修正不代表 SDD 核可，不得標示 `presentation-ui` implementation started／complete。

## R9 結果

- 架構／資料安全／併發審查：`APPROVED — zero unresolved findings`；確認
  `G2-R8-01` 已完整封閉。
- 行為／UX／測試審查：`NOT APPROVED`；`G2-R8-01` 已修復，但新增三個 named-test
  coverage findings。

| Finding | Severity | 使用者裁決 | 修正 |
|---|---|---|---|
| `G2-R9-B01` Exit 可攔截 request／runner 存活未具名鎖定 | Medium | 全部採納 | requirements/design 已回寫；R11 再拆為 T05 root 與 T08 host 兩份 immutable tests |
| `G2-R9-B02` `ABANDON_BOSS_RETRY` 未進 confirmation named matrix | Medium | 全部採納 | requirements、design、T09 與既有 irreversible confirmation test 已回寫 |
| `G2-R9-B03` dev CLI 未證明共用 production bootstrap/facade | Minor | 全部採納 | exact allowlist `--combat-lab`、T01／T04 與 dev-entry smoke 已回寫 |

### 強制下一步

1. 以本輪修訂後 SDD 執行 fresh R10 架構與行為雙獨立複審。
2. 只有兩份 R10 都為 zero unresolved findings，才可把 SDD 標為 Approved 並建立 T00 紅燈。

R9 修正不代表 SDD 核可；production implementation 與 TDD 仍為 not started。

## R10 結果

- 架構與行為兩份審查皆為 `NOT APPROVED`，但 findings 收斂為相同兩個 AppRoot
  ownership／wave 缺口。

| Consolidated finding | Severity | 使用者裁決 | 修正 |
|---|---|---|---|
| Exit root API 與 pending lifecycle 未分配給唯一 AppRoot owner T05 | Medium | 全部採納 | T05 擁有 signal／API／guard／root behavior；T08 僅 UI button／host binding／smoke |
| `--combat-lab` integrated smoke 與 CLI composition 未分配給 T05 | Medium | 全部採納 | T01 bootstrap component、T04 facade/dev wrapper component、T05 exact allowlist parse/route/bind 與單一 integrated test owner；R1 追溯補 T04/T05 |

### 強制下一步

1. 以 ownership 修訂後 SDD 執行 fresh R11 架構與行為雙獨立複審。
2. 只有兩份 R11 都為 zero unresolved findings，才可把 SDD 標為 Approved 並建立 T00 紅燈。

R10 修正不代表 SDD 核可；production implementation 與 TDD 仍為 not started。

## R11 結果

- 架構／資料安全／併發審查：`NOT APPROVED`，1 項 Medium finding。
- 行為／UX／測試完整性審查：`NOT APPROVED`，2 項 Medium findings。

| Finding | Severity | 狀態 | 建議修正 |
|---|---|---|---|
| `G2-R11-A01` Exit 同一 named test 跨 T05/T08 兩個 wave，與 SHA manifest 鎖定衝突 | Medium | 全部採納 | 已拆成 T05 root-contract test 與 T08 button/host smoke，各自由自身 wave 鎖定 |
| `G2-R11-B01` T08 settings UI 驗收依賴後置 T12 concrete coordinator | Medium | 全部採納 | T08 改用 fake typed port 做 component evidence；T12 擁有 coordinator、restart/bus round-trip 與 production wiring |
| `G2-R11-B02` decoded/opaque recovery 的取消與 fault-preservation 缺 fresh named matrix | Medium | 全部採納 | T06 repository/recovery fault-preservation named test；T08 獨立 confirmation cancel component evidence |

完整 reviewer 原文：

- `.pipeline/reviews/2026-07-28-presentation-ui-spec-architecture-r11.md`
- `.pipeline/reviews/2026-07-28-presentation-ui-spec-behavior-r11.md`

### 強制下一步

1. 以本輪修訂後 SDD 由兩個 fresh reviewer 做 R12 雙審。
2. R12 兩份皆 zero unresolved findings 前，不得標 SDD Approved、建立 T00 紅燈或進入
   production implementation。

R11 使用者裁決（2026-07-28）：三項 findings 全部採納；上述修正已回寫，但不構成 SDD 核可。

## R12 結果

- R11 三項修正均由兩份 fresh review 確認封閉。
- 架構／資料安全／併發審查：`NOT APPROVED`，2 項新的 Medium findings。
- 行為／UX／測試完整性審查：`NOT APPROVED`，2 項新的 Medium findings。

| Finding | Severity | 狀態 | 建議修正 |
|---|---|---|---|
| `G2-R12-A01` T05/T07 terminal route/lease ownership 與 DAG 形成前置循環 | Medium | 已採納並修正，待 R13 | T00 split ports；T05 fake-port root evidence；T07 concrete adapter；T09 production joint test |
| `G2-R12-A02` Results snapshot 在 repository ownership 內外的建構時點矛盾 | Medium | 已採納並修正，待 R13 | ownership 內捕捉並安裝 receipt/full-digest/profile-bound snapshot；解鎖後只呈現 installed clone；加入 competing operation probe |
| `G2-R12-B01` playback invalid multiplier 缺 named matrix | Medium | 已採納並修正，待 R13 | `0/-1/-4/3/5/8` typed reject；鎖定 speed/cursor/pause/result/event/save/transcript ownership 與零 dispatch |
| `G2-R12-B02` reduced effects/density/tooltip/CJK 缺具名 runtime/static/screenshot evidence | Medium | 已採納並修正，待 R13 | runtime matrix、tooltip guard、SystemFont CJK glyph probe 與三張 GUI screenshot |

完整 reviewer 原文：

- `.pipeline/reviews/2026-07-28-presentation-ui-spec-architecture-r12.md`
- `.pipeline/reviews/2026-07-28-presentation-ui-spec-behavior-r12.md`

### 強制下一步

1. 由 Claude 依本節四項 finding 修訂 requirements／design／tasks；不得先做 TDD 或 production。
2. 修訂後先跑 `git diff --check` 與 Spec gate，再由兩個 fresh reviewer 做 R13 雙審。
3. R13 兩份原文與彙整決策表必須先回寫 `.pipeline/reviews/`、本檔、`PROGRESS.md`、
   `HANDOFF.md` 與 `specs/g2-roadmap.md`。
4. R13 兩份皆 zero unresolved findings 前，不得標 SDD Approved、建立 T00 紅燈或進入
   production implementation。

使用者交接指示（2026-07-28）：R12 findings 保留為待修正，下一手交由 Claude 完成；本輪不由
Codex 代修，也不將「交接」解讀為核可或允許略過 fresh R13。

## Review Gate override

使用者後續明確指示（2026-07-28）：審查部分先跳過，繼續下一步。故 pipeline 可先執行
fresh baseline 與 T00 之後的實作，但：

- R12 四項 finding 仍是 unresolved，不標示 SDD Approved／resolved。
- fresh R13 延後，不取消；最遲須在 T15 implementation review／Git 前補做。
- 實作若觸及 terminal handoff、Results snapshot、playback multiplier 或 accessibility evidence，
  必須保留 R12 風險標記，不得用測試綠冒充規格缺口已裁決。
- 本 override 只放行本地、可逆的 implementation；不放行 stage、commit、push、PR 或 merge。

## R12 修正與 R13 前置稽查（2026-07-29）

使用者已將 review ownership 交回 Codex，並要求持續修正與 fresh review，直到沒有新 finding。
R12 四項均採納，修正決策與證據彙整於：

- `.pipeline/reviews/2026-07-29-presentation-ui-r12-correction-decision.md`

本輪修正結果：

- A01/A02：application install 與 concrete presentation port 已拆分；authoritative Results
  snapshot 在 repository writer ownership 內捕捉並安裝，解鎖後 presentation 只取得 installed
  clone。限定 GUT 2/2、45/45。
- B01：session-mediated playback speed API 與 `0/-1/-4/3/5/8` matrix 已綠，1/1、89/89。
- B02：effects/density/tooltip/CJK runtime contract 已綠，4/4、118/118；GUI runner 3/3 PNG、
  zero issues，繁中 probe 14 glyphs、missing=[]。
- 所有無效 parser red、fixture encoding error、closure capture error與 first-frame black capture
  都有明示 manifest revocation，不計入有效 red/green。

以上仍不構成 SDD Approved。下一步是 fresh R13 架構與行為雙 reviewer；任一 finding 都回到
修正與下一個 fresh review round，直到兩份皆 zero unresolved findings。

## R13 結果

- 架構／資料安全／併發：`NOT APPROVED`，3 項 Medium。
- 行為／UX／evidence：`NOT APPROVED`，1 項 High、2 項 Medium。
- 使用者已指示 Codex 持續自行 review 到沒有新問題；本輪 6 項全部採納並進入 supplemental
  TDD，完成後必須由兩位全新 reviewer 執行 R14。

| Finding | Severity | 決策 | 修正方向 |
|---|---|---|---|
| `G2-R13-A01` / `G2-R13-B03` terminal capability 跨 unlock 且可 replay | Medium | 採納 | repository terminal token ownership 內 consume；另發 installed presentation token；duplicate/stale/reentrant matrix |
| `G2-R13-A02` retry fresh-read snapshot 與 installed-clone-only 衝突 | Medium | 採納 | read 只做 current observation CAS；candidate 固定取 AppRoot installed clone；分離 settlement/current digest |
| `G2-R13-A03` production fallback joint evidence 實為 fake，fault 會 soft-lock | Medium | 採納 | real application＋concrete adapter joint test；atomic fallback scene/lease；可用 results-only port |
| `G2-R13-B01` playback 只有 raw session test，正式 screen 無 lease-bound 控制 | High | 採納 | LiveScreenPlaybackPort＋typed pause＋RUN_COMBAT binding/stale lease matrix |
| `G2-R13-B02` accessibility 只接 test fixture，production 可 no-op | Medium | 採納 | production settings consumer/scene host binding、individual flag screenshots、static coverage gate |

完整 reviewer 原文：

- `.pipeline/reviews/2026-07-29-presentation-ui-spec-architecture-r13.md`
- `.pipeline/reviews/2026-07-29-presentation-ui-spec-behavior-r13.md`

R13 不構成 SDD 核可。所有修正與 valid red/green evidence 完成後，R14 必須使用兩位未參與
實作、也未參與 R13 的 fresh read-only reviewer。

## R14 結果

- 架構／資料安全／併發：`NOT APPROVED`，5 項（4 High、1 Medium）。
- 行為／UX／evidence：`NOT APPROVED`，7 項（3 High、4 Medium）。
- 使用者已將 review ownership 交回 Codex 並要求持續到沒有新 finding；本輪 findings
  全部採納，完成修正後必須改由未參與 R14／修正的兩位 fresh reviewer 執行 R15。

| Finding | Severity | 決策 | 修正方向 |
|---|---|---|---|
| `G2-R14-A01` post-save digest 重讀 fault 會留下 RUN soft lock | High | 採納 | 直接沿用 authoritative commit result；所有 postcommit fault fail-closed 安裝 sealed RESULTS/fallback |
| `G2-R14-A02` application／adapter route generation 跨局漂移 | High | 採納 | route generation 收斂為單一 transaction authority；加入同 AppRoot 連續兩局 joint test |
| `G2-R14-A03/B01` production staged→live activation 與真 controls 未接通 | High | 採納 | AppRoot／SceneRouter 正式注入 clone-only models 與 lease-bound intent/navigation/playback ports |
| `G2-R14-A04/B02` AppRoot transition 先於 route 且 results guard 可繞過 | High | 採納 | AppRoot-owned results single-flight；stage/bind 成功後才原子提交 state/route/lease |
| `G2-R14-A05` raw session surface 與 static gate allowlist 不完整 | Medium | 採納 | 移除 staged/public raw session，擴充 writer/facade static gate negative fixtures |
| `G2-R14-B03` RESULTS＋fallback 雙 fault 未撤銷 RUN lease | High | 採納 | postcommit route 前 fail-closed revoke；雙 fault typed host fallback 與 stale callback matrix |
| `G2-R14-B04` static gate 漏掉英文 player-visible hardcode | Medium | 採納 | production text 全走 localization key；擴充 scene/text 負向 gate |
| `G2-R14-B05` accessibility 缺 AppRoot→Settings→SceneRouter joint evidence | Medium | 採納 | 真 AppRoot settings port、route replacement/reload、production node screenshot |
| `G2-R14-B06` runtime matrix 仍是 fixture／缺比例與 UI scale | Medium | 採納 | 真 production scenes 覆蓋 720/1080/1440、4:3/16:10、100/125/150%、四色覺 |
| `G2-R14-B07` T15 ledger／manifest／交接數字過期 | Medium | 採納 | final gates 後重建 19-row ledger 與所有進度／交接文件 |

完整 reviewer 原文：

- `.pipeline/reviews/2026-07-29-presentation-ui-spec-architecture-r14.md`
- `.pipeline/reviews/2026-07-29-presentation-ui-spec-behavior-r14.md`

R14 不構成 SDD 核可。R15 必須使用兩位未參與實作、R14 或本輪修正的 fresh read-only reviewer；
任一新 finding 都回到修正與下一個 fresh review round。

## R14 修正與 R15 前置稽查（2026-07-29）

R14 十項 finding 已全部落地，另由主迴圈 self-audit 發現並修正四項 supplemental 缺口：

- SceneRouter active screen full-rect、production accessibility zero-size fail-closed；
- dotted action id 的穩定唯一 Control name；
- focus graph／static collector 對齊全部正式 route/action；
- `.gd` 英文／混合 visible sink 納入 localization static gate。

valid supplemental red 為 2 scripts／4 tests 全紅；green 為 4/4、49 assertions，2/2 test
manifest SHA 相符。fresh All exit 0：Gut 920/920（15898 assertions）、Spec 3694 cases；
36 manifests／107 entries 全相符。fresh ExpeditionSoak 10000 seeds、10000 pool checks、
64 deterministic replays、40000 build operations、零 failures。最終 AppRoot accessibility
joint 4/4（115），Windows production renderer 10/10 cases、零 clipping／零 issues。

以上只代表 R15 前置修正與 evidence 完整，不自行標記 review approved。下一步仍須由兩位
未參與 R14、修正或 self-audit 的 fresh read-only reviewer 執行 R15。

## R15 結果

- 架構／資料安全／lifecycle：`NOT APPROVED`，5 項（3 High、2 Medium）。
- 行為／UX／accessibility／evidence：`NOT APPROVED`，6 項（2 High、4 Medium）。
- 兩份審查有三組重疊 finding；合併後共 8 個修正群組。使用者已要求 Codex 自行 review
  到沒有新 finding，本輪全部採納。完成 valid red／green 與 fresh gates 後，必須由兩位未參與
  R15 或修正的 fresh reviewer 執行 R16。

| Finding | Severity | 決策 | 修正方向 |
|---|---|---|---|
| `G2-R15-A01` RESULTS retry root guard 取得晚於 capability issuance／repository ownership | High | 採納 | AppRoot-owned 單一同步 retry transaction；guard 包住 issue、CAS、bind 與 route commit 全段 |
| `G2-R15-A02` terminal postcommit fail-closed 仍依賴可失敗 fallback proof | High | 採納 | irreversible save 前預建 no-fail revoke/install plan；save 後直接 revoke live lease 並封存 RESULTS |
| `G2-R15-A03/B02` production 缺真 SubViewport／CanvasLayer ownership、resize 與真 hit-test | High | 採納 | AppRoot-owned world/UI layers＋中央 resize coordinator；runtime evidence 改驗真 nodes／targets／scale |
| `G2-R15-B01` 正式 CAMP／RUN／RESULTS controls 與 typed data 閉環不完整 | High | 採納 | clone-only models 驅動真 selector／list／editor／inspection／offers／receipt controls，移除 hidden select-first 假閉環 |
| `G2-R15-B03` focus graph 無 production consumer，recovery modal 無 trap／restore | Medium | 採納 | active/blocked focus graph實際套用；modal停用背景 input並在關閉後還原 trigger focus |
| `G2-R15-A04/B04` zero-size `UiProbe` 仍隱式假設 1280×720 | Medium | 採納 | runtime report 對 missing／zero probe fail closed，移除 clipping fallback |
| `G2-R15-B05` terminal RESULTS＋fallback 雙 fault stale callback matrix 缺 evidence | Medium | 採納 | 真 production雙 fault test，驗 gameplay／navigation／confirmation／playback ports全部失效 |
| `G2-R15-A05/B06` T15 ledger／manifest／automation／log互相矛盾 | Medium | 採納 | 全修後重跑 fresh gates、保存完整成功 log/hash，重建19-row final ledger與交接文件 |

完整 reviewer 原文：

- `.pipeline/reviews/2026-07-29-presentation-ui-spec-architecture-r15.md`
- `.pipeline/reviews/2026-07-29-presentation-ui-spec-behavior-r15.md`

R15 不構成 SDD／implementation approval。下一步先建立有效 behavioral red，再依 ownership
分批修正；所有 manifests、fresh automation、runtime screenshots 與 canonical evidence 同步後
執行 fresh R16 雙審。

使用者於 2026-07-29 追加 review budget：本輪修正完成後可直接進下一 fresh run；後續雙審
不再無限循環，最多執行 R16、R17、R18 三輪。若 R18 仍有新 finding，停止啟動下一輪 reviewer，
將未解項、證據、風險與建議修正完整寫入進度／交接文件，交由下一 run 接續。

## R15 修正完成與 R16 前置證據（2026-07-29）

R15 八個合併修正群組已全部落地：

- retry transaction 在 AppRoot guard 內涵蓋 capability issue、repository CAS、
  installed clone consume、candidate bind、route commit 與 cleanup；
- terminal durable save 後直接撤銷 live lease/session 並封存 application-local
  RESULTS，fallback authority fault 不再讓 RUN callback 復活；
- `app/main.tscn` 具 AppRoot-owned 640×360 `SubViewport`、1280×720 UI layer
  與 resize coordinator；UI scale 改動真 control metrics；
- CAMP／MAP／PREPARE／COMBAT／REWARD 改用 clone-only typed selectors、
  inspection、capacity/overflow issues 與 offers，不再 hidden select-first；
- KeyboardFocusGraph 已由 production screen 消費，recovery modal 會停用背景
  focus/input、trap 焦點並關閉後還原 trigger；
- missing／zero-size `UiProbe` 精確 fail closed；
- RESULTS＋fallback 雙 fault 會撤銷 gameplay/navigation/confirmation/playback
  callback；
- 19-row ledger、manifest audit、runtime 與 automation evidence 已重建。

有效 R15 green：

- architecture retry 1/1、11 assertions；
- terminal 3/3、62 assertions；
- behavior 8/8、152 assertions；
- 三份 R15 manifests 9/9 locked hashes 未變。

人工 runtime read-back 又發現原 probe 漏掉 4:3 long typed label overflow 與
125/150% CJK/action rect overlap。先擴充真 framebuffer probe 取得兩份有效 red，
再修正 scene safe column、label wrapping、title placement；最終 production
runtime 10/10、zero clipping／zero issues，人工檢視 4:3、125%、150% 與色覺
sample 無新問題。普通執行 stderr 仍有固定的 Godot 4.7 script shutdown
`5385 ObjectDB / 92 resources` 診斷；verbose 證明類型為 5277 `RefCounted`、
92 `GDScript`、15 `RegEx` 與 1 `GDScriptNativeClass`，沒有 leaked
Node／Control／Viewport，完整診斷保存在 runtime verbose logs。

fresh aggregate：

- Gut 239 scripts、932/932、16123 assertions；
- ExpeditionSoak 10000 seeds、10000 pool checks、64 replays、
  40000 build operations、zero failures；
- production static gate `ok=true`、`exit_code=0`、`issues=[]`；
- 39 manifests／151 references／134 unique paths，151/151 hash match。

以上仍不自行構成 implementation approval。下一步直接進 fresh R16 架構與行為雙審；
review budget 仍固定為 R16～R18，R18 後不再啟動 R19。

## R16 結果與暫停點（2026-07-29）

- Architecture/data-safety：`NOT APPROVED`，2 High＋1 Medium。
- Behavior/UX/accessibility/evidence：`NOT APPROVED`，4 High＋2 Medium。
- 合併後待修群組：split retry public surface；真 world SubViewport／pointer
  target；真 session inspection equipment/跨陣營 target；COMBAT overlay occlusion；
  authoritative PREPARE validation；PREPARE/COLLECTION/RESULTS 玩家閉環；
  Settings editor focus traversal；authoritative non-color semantics。
- 完整報告：
  - `.pipeline/reviews/2026-07-29-presentation-ui-spec-architecture-r16.md`
  - `.pipeline/reviews/2026-07-29-presentation-ui-spec-behavior-r16.md`

使用者要求在此暫停關機。尚未建立 R16 behavioral red、尚未修 production、
尚未重跑任何 gate、尚未啟動 R17。下次從「合併 R16 findings→建立有效 red→
分 ownership 修正→fresh gates→R17」開始。review budget 尚餘 R17、R18。

## R16 finding closure 與 review override（2026-07-30）

使用者恢復工作後明示：R16 findings 全部採納；R16 修正與驗證完成後直接進下一步，
不再次雙審、不啟動 R17。R16 原始兩份 `NOT APPROVED` 報告保持歷史原文；closure
decision table 另存：

- `.pipeline/reviews/2026-07-30-presentation-ui-r16-closure.md`

八個合併修正群組均已落地：

- public split retry surface 移除，AppRoot Camp/Menu 三 barrier×兩 action 共六組重入封鎖；
- 真 world SubViewport／targets／pointer hit 與 fixed Canvas transform；
- committed player-first 雙方 combat inspection projection；
- COMBAT accessibility overlay 不遮蔽、不攔截 typed controls；
- PREPARE 使用與正式 commit 同源的 authoritative validation report；
- PREPARE、COLLECTION、RESULTS/FALLBACK formal loops 接 production data；
- Settings 15 個 editor 全部進 focus traversal；
- ally/enemy/trait/rarity/danger/damage semantics 綁 typed ID、文字與 pattern，
  四色覺只改 palette。

R16 targeted architecture／formal／viewport 共 13 tests 全綠。final candidate：
Gut 243 scripts、945/945、16295 assertions、零 failures/errors/orphans；Spec 3696；
Smoke、Content、Canonical、Combat、Expedition、All 皆 exit 0；ExpeditionSoak
10000 seeds／10000 pool checks／64 replays／40000 build operations／零 failures；
static gate zero issues；42 manifests／155 references 全相符。

依使用者 override，本輪不產生 R17／R18 reviewer 報告，也不把主迴圈 closure 冒充
fresh zero-finding review。下一步是 T15 文件／Git handoff；使用者確認前仍不得 stage、
commit、push、PR 或 merge，且 `content-production` 必須等本片合併後才可開始。
