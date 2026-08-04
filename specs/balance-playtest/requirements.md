# G2 balance-playtest — Requirements

狀態：APPROVED FOR IMPLEMENTATION（依使用者 2026-08-01 指示）

## 範圍

- 本片擁有 `REQ-PROD-002`、`REQ-PROD-004`，並重證 AC-001、002、008～013、
  019、030、045、048、056、059、062。
- AC-032 只建立匿名報告與 Windows provisional RC，維持 `PENDING_EXTERNAL`；
  30 人／90 場與真人 45–60 分鐘中位數由 `performance-release` 收口。
- 不新增後端、帳號、網路上傳、控制器支援、非決定性 gameplay entropy 或固定規則變更。

## BP-REQ

- **BP-REQ-001 Candidate**：每個候選必須以 `BalanceCandidateDescriptor v1` 記錄
  candidate ID、content version、manifest digest、RNG version、完整 TUNE entries 與
  canonical tune digest；任何 TUNE 值改動都必須產生新 ID/digest。
- **BP-REQ-002 Boundary**：TUNE 只含資料可調值；固定 tick、棋盤、排序、codec、claim、
  save 與 exactly-once 語意不得進候選清單或被 bot runner 改寫。
- **BP-REQ-003 Strategies**：固定 `tempo`、`economy`、`synergy` 三策略，共用 clone-only
  observation 與 typed action；非法 action 必須拒絕，平分以 stable ID 決勝。
- **BP-REQ-004 Production simulation**：runner 必須由 `ProjectContentBootstrap` 取得
  production pinned generation，並透過正式 map/economy/battle/settlement contracts；不得以
  `EconomyTestFixture`、synthetic soak content 或 wall clock 決定 gameplay。
- **BP-REQ-005 Cohort**：screening 為相同 1,000 seeds × 3；final 為相同 10,000 seeds × 3，
  共 30,000 strategy-seed cases。相同 candidate/strategy/seed 必須 replay digest 一致。
- **BP-REQ-006 Report**：`BalanceBotReport v1` 必須包含各策略 terminal/win、三幕到達、
  build/selection、資源、路線、失敗 seed、invariant failures 與 replay digest。
- **BP-REQ-007 Gate**：任一 build 通關率或選取率高出次名至少 20pp、任一策略少於
  500 terminal 或 50 wins、或任一死局／負資源／重複獎勵／遺失實體／非法地圖／replay
  drift，候選必須 FAIL。
- **BP-REQ-008 Session privacy**：`PlaytestSessionReport v1` 在完成、失敗、放棄時自動落到
  `user://playtest_reports/`；只含隨機 session ID、candidate/build、時間、路線、build 摘要、
  結果與具名錯誤，不含姓名、帳號、硬體序號、絕對路徑、IP 或上傳行為。
- **BP-REQ-009 RC**：本機可重現 Windows x86_64 ZIP 必須包含 EXE/PCK、授權、測試說明、
  SHA-256，並排除 tests/specs/.pipeline/raw attempts/dev scenes。CI 與正式 hardening 延至第四片。

## Acceptance

1. Candidate codec round-trip、排序與 digest 對輸入排列不敏感；缺欄位、重複 path、固定規則
   path 或錯 digest fail-closed。
2. 三策略對同一 observation 產生預期不同選擇；caller 修改回傳 action 不影響策略內部。
3. production bootstrap 缺內容、catalog generation 不符或 runner invariant 失敗時退出碼非零。
4. screening/final 報告精確標示 cohort、case count、candidate digest、gate reasons 與 AC 證據。
5. session codec 拒絕 future schema、非法 outcome、非匿名欄位與壞 JSON；writer 採 tmp→replace。
6. provisional ZIP 能以全新 profile 離線啟動、存讀、完成或放棄一局並寫出 report。

