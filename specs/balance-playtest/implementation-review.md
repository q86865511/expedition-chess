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

## Phase 0 收尾雙審結果與修復（2026-08-04）

上一節交接的兩位獨立 fresh reviewer（A／B）已完成收尾審查，原文見
`.pipeline/balance-playtest/reviews/phase0-final-review-A.md`、
`.pipeline/balance-playtest/reviews/phase0-final-review-B.md`。**兩份皆 NOT APPROVED**：

- Reviewer A：F01（高，1 條）＋F02～F10（中／低，9 條），共 10 條。阻擋項為 F01
  （driver 整合測試缺席）、F02／F03（sealed candidate 靜默失效模式）、F04／F05
  （frozen 3k 產自 dirty 工作樹、tasks.md 未依附錄 D 回寫）。
- Reviewer B：B-01～B-10，共 10 條。Verdict 列 B-01（gate 證據不入版控無法覆核）、
  B-03（localization `.raw` 無守門）、B-05（BP-IR-007 未以可重跑測試關閉）需裁決或補件；
  B-02／B-04（行為缺口）另列為需修正。

使用者裁決：**全修＋證據採「鎖定檔＋記錄限制」方案**（不重跑 3k screening 或 RC，
以 SHA-256 鎖定現有證據並明列限制，取代「必須可由 commit 重算」的原始假設）。
本輪已修復的項目：

- **B-04**（final gate 繞過）：`tools/run-tests.ps1` 的 `--final` 觸發條件由
  `$SeedCount -eq 10000` 改為 `$SeedCount -ge 10000`，避免 Phase 2 大樣本執行在未達成
  `FINAL_CASE_COUNT` 時被 screening gate 靜默判定 PASS。
- **B-03**（localization `.raw` 無守門）：`tools/content-production/export-localization-catalog.gd`
  改為同步寫出 `.csv` 與 `.csv.raw`（byte-identical），並新增
  `tests/unit/presentation_ui_content/test_localization_catalog_raw_parity.gd` 以
  SHA-256 相等斷言鎖住兩檔同步。
- **F05／B-10**（tasks.md／CLAUDE.md 回寫）：`specs/balance-playtest/tasks.md` 補齊
  T03／T07 勾選與交付證據引用、T08 依 `rewrite-plan.md` 附錄 D 註記延後理由、T09
  記錄雙審 NOT APPROVED 與修復進行中；`CLAUDE.md` 常用指令節補上 `BalancePlaytest`
  targeted suite 用法與單一 runner 清單項目。
- **F04／B-01**（gate 證據不可覆核）：新建 `specs/balance-playtest/evidence-lock.md`，
  以現場實算的 SHA-256 鎖定 3k screening #2 的關鍵證據（screening artifact、
  source-freeze、12 個 shard json）並記錄四點已知限制（dirty 工作樹產生、本機限定
  產物不入版控、Phase 2 將於乾淨 HEAD 重建、未來 driver 修正會改變 replay digest）；
  `evidence-index.md` 已加一行指向該檔。

（上段為 Z2 文件回寫當下的快照，其「不涵蓋」敘述已過時，保留供歷程追溯。）

### 全量修復與閉環複核（2026-08-04 追記）

使用者裁決「全修」後，兩份審查的全部 20 條 findings 已由四個並行工作包＋主迴圈
補丁完成修復：F01（整合測試四檔＋變異證據）、F02～F10、B-01～B-10（詳見兩份審查檔
的「## 閉環複核」段）。另完成新立案 BP-SI-007 的根因實證與修復（StringName 裸排序
指標序 → `StableNameSort` 字典序，使用者授權 domain 修正；詳見 `spec-issues.md`
BP-SI-007 與 `evidence-lock.md` 限制第 5 點）。修復後 fresh 驗證：All 1,155 tests／
22,449 assertions／0 failures、10k ExpeditionSoak 10,000/10,000 passed。
閉環複核結果：reviewer B **APPROVED**（B-01～B-10 全 closed，附 N-01～N-04 機械性
收尾，均已處理）；reviewer A 首輪閉環 **NOT APPROVED**（F07 漏修——已補修
`playtest_session_report.gd` 逐 codepoint 檢查＋非 ASCII 拒收測試；N1 CRLF 已還原；
N2 文件矛盾即本段修正），已送 A 複核三處。最終狀態以 A 的複核 verdict 為準。
