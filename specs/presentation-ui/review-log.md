# G2 presentation-ui 規格審查紀錄

> 日期：2026-07-26（2026-07-28 修訂）
> 分支：`codex/g2-presentation-ui`
> 基準：`93f68ceaf65b6de430f09b8526ebcfb97c79c5c5`（已重放至最新 master）
> 目前 Gate：`AMENDED — G2-R8-01 RESOLVED_IN_SDD_PENDING_R9`

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
