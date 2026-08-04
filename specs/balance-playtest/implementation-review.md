# G2 balance-playtest — Implementation review

日期：2026-08-01  
狀態：**NOT APPROVED / FINDINGS OPEN**

兩位 reviewer 皆為獨立、唯讀審查；未修改檔案，未執行 commit、push、merge 或 deploy。
審查後主線只立即修正 packager 的 destructive path containment；其餘行為 finding 保持
OPEN，第三切片不得 closure。

## 共同 blocking findings

| ID | Severity | Location | Finding | 狀態 |
|---|---|---|---|---|
| BP-IR-001 | CRITICAL | `application/balance/balance_production_case_driver.gd:23-95` | 每 case 只跑一次商店與每幕一場代表戰鬥；未經完整 21-node route、formal commands/economy/settlement/reward/save-reload/Boss retry，typed action 亦未套用。30k 的 90,000 戰全勝、gold=20、hp=100 不能作平衡證據。 | OPEN |
| BP-IR-002 | HIGH | `application/balance/balance_production_case_driver.gd:23-27` | `run_id` 含 strategy，MapService RNG context 因而不同；三策略不是相同 world cohort。 | OPEN |
| BP-IR-003 | HIGH | `tools/balance/package-rc.ps1` | exported RC smoke 只有 fresh-profile boot；沒有 start→save→restart/load→terminal/abandon→report codec read-back。 | OPEN |
| BP-IR-004 | HIGH | `domain/balance/balance_bot_case_result.gd`、`balance_bot_report.gd` | Gate 依賴 caller 自填 failure code，未由 DTO/report 強制負資源、死局、重複獎勵、遺失實體、非法地圖 proof。 | OPEN |
| BP-IR-005 | HIGH | `domain/balance/balance_tune_inventory.gd`、scanner | candidate ID 固定 `balance.g2.rc1`，失敗候選未 immutable 留存；scanner 漏 `cells` TUNE，fixed-rule registry 亦不一致。 | OPEN |
| BP-IR-006 | HIGH | session report DTO/codec/AppRoot | 多收精確 `started_at_utc`，stable-ID/path-like 值未 fail-closed；Boss retry abandon 會被 meta settlement 壓成 failed。 | OPEN |
| BP-IR-007 | HIGH | balance tests | driver 只驗 preload；缺 full expedition、action apply、Boss retry、save/reload 與 AppRoot 三 terminal outcome exactly-once 報告整合測試。 | OPEN |
| BP-IR-008 | HIGH | artifacts/pipeline | 30k、All、soak、RC 未綁同一 source manifest；修正後須凍結 source 並完整重跑 3k／30k／package pipeline。 | OPEN |

## 其他 findings

- `run-final-cohort.ps1` 應驗證每策略恰為 10,000 個唯一 seeds，且三策略 seed
  set/cohort digest 完全相同；目前只驗總數與最低樣本。
- route 應以 stable route signature／act-layer-kind 聚合，不應以每局唯一 runtime node digest
  產生 90,000 個低資訊 key；resource curve 需包含過程曲線而非只看 terminal mean。
- export 應排除無 runtime 依賴的 `addons/gut/**`，並加入 PCK inventory 禁入清單驗證。
- packager 原本以 `StartsWith(artifacts\rc)` 判 containment，可能誤收 `rc-backup` sibling；
  已改為要求 `artifacts\rc\` 尾端 separator 且禁止 target 等於 RC root；parser 與
  `artifacts\rc-backup` negative test 均 PASS，**CLOSED**。

## 已確認通過的證據

- screening：1,000 shared seed labels × 3，artifact gate PASS（但受 BP-IR-001/002 限制）。
- final artifact：10,000 labels × 3＝30,000 cases、三策略各 10,000 terminal/wins、
  0 failed seeds、`AC-032=PENDING_EXTERNAL`（但不得視為有效 full-expedition balance gate）。
- fresh All：19 runner steps、exit 0；GUT 1,103/1,103 tests、22,105 assertions。
- fresh ExpeditionSoak：10,000 seeds／10,000 cases／0 failures。
- Windows ZIP 頂層只含 EXE、PCK、`PLAYTEST.md`、`PLAYTEST-LICENSES.txt`；SHA-256
  `6b618627d749b2861afd88b3d2a0bb519abb221dffe072bc102b7ef28fb0b840`。
- fresh-profile exported boot：exit 0、無 script/parser/bootstrap ERROR；這不是互動式 RC smoke。

## Gate decision

`T09` 不勾選，Git gate 封鎖。必須先關閉 BP-IR-001～008，重跑所有受影響證據並再做
兩位 fresh implementation reviewers；AC-032 仍固定 `PENDING_EXTERNAL`。

## Phase 0 初版收尾紀錄（2026-08-04；非審查裁決）

本段只記錄交給 fresh reviewers 的新實作與證據，不變更上方歷史 finding 狀態，亦不自行
核可。本文件整體仍為 **NOT APPROVED / FINDINGS OPEN**；BP-IR-001～008 是否關閉由後續
兩位獨立 fresh reviewers 逐條裁決。

- Runtime source commit：`6b072f8be1be39f5ee0644e5b2d7ab4d4960756e`。
- Source manifest：`artifacts/rc/source-manifest.json`，SHA-256
  `345bb6c4f3c1a06b64dc346110832fb4e26792b8a5f6f75ef4922b222bd40b26`；final All、
  ExpeditionSoak 與 RC wrappers 皆綁同一 SHA。
- BP-IR-001／002／004／007 待審材料：frozen 3k #2 為 1,000 shared seeds × 三策略、
  3,000/3,000 terminal、150/150 replay 零 drift、0 failure、完整 21-node production
  composition 與 authoritative proof；artifact SHA 在收尾前後不變。24-case NUL 等價
  另為 24/24 replay digest 完全一致。
- BP-IR-003 待審材料：三個實際匯出 EXE 程序完成 start→save→restart/load→natural
  RESULTS→第二 run→restart/retained-run abandon；兩份 `victory`／`abandoned` report 均經
  `PlaytestSessionReportCodecV1.try_decode()` 讀回。見 `artifacts/rc/rc-evidence.json`。
- BP-IR-005／006 待審材料：candidate 由 tune digest 衍生並 append-only；匯出 RC 使用
  application 內 sealed candidate，逐一核對 content/manifest/candidate/tune identity；PCK
  不匯出 `specs/`。匿名 session codec、hour bucket、path-like fail-closed 與三 terminal
  outcome tests 收錄於 final All。
- BP-IR-008 待審材料：final All 9 steps，GUT 1,126 tests／22,224 assertions／
  0 failures/errors/orphans、NUL 0；ExpeditionSoak 10,000 seeds／10,000 cases／10,000 pool
  checks、64 replays、40,000 build operations、0 failures；PCK 2,988 files、禁入清單 0，
  ZIP 四個頂層檔案且 SHA read-back 通過。
- `AC-030` 依 `rewrite-plan.md` 附錄 D 保持 `PARTIAL / DEFERRED_PHASE2`；`AC-032`
  保持 `PENDING_EXTERNAL`。Phase 0 證據收尾完成不等同整片完成。

下一步只交接兩位 fresh reviewers 與使用者確認；本輪未執行任何 reviewer、push、PR 或 merge。
