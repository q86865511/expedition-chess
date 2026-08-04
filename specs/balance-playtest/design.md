# G2 balance-playtest — Design

## 資料與介面

- `BalanceCandidateDescriptor`／`BalanceTuneEntry` 是 typed value objects；
  `BalanceCandidateCodecV1` 是 Dictionary/JSON 唯一邊界。tune digest 對依 path 排序後的
  length-prefixed UTF-8 fragments 做 SHA-256。
- Candidate archive 的 flat JSON 是 append-only；同 tune digest 套用至不同 pinned manifest
  時，以完整 manifest digest 建立 immutable revision。只有既有 descriptor 可 decode、完整
  tune digest 相同且 manifest 不同時允許分流；同 manifest byte conflict 一律拒絕。
- `BalanceBotObservation` 只持數值 snapshot 與 cloned `BalanceBotAction`；
  `BalanceBotStrategy.try_choose_action()` 使用固定權重與 stable-ID tie-break；無合法
  action 時以 `null` 具名表示拒絕，呼叫端不得靜默 fallback。
- `BalancePlaytestRunner` 只從 production bootstrap result 取得 catalog、receipt、battle rules、
  relic table 與 commander；每個 case 建 fresh run，執行三幕 route/economy/combat/settlement，
  結果送入 `BalanceBotReport` 聚合器。
- `PlaytestSessionReportCodecV1` 與 `PlaytestSessionReportWriter` 位於 application 邊界；
  AppRoot 只在 durable terminal handoff 後呼叫 writer，寫檔失敗不得回滾 gameplay commit。

## 決定性與失敗政策

- 三策略不持有 RNG；世界只使用既有 map/shop/reward/combat named streams。
- bot score 使用整數：tempo=`5T+E+S`、economy=`T+5E+S`、synergy=`T+E+5S`；
  action 必須 legal 且 cost≤gold，分數相同取字典序較小 stable ID。
- 所有 catalog、observation、action、report 皆 clone-in/out。generation mismatch、非法狀態、
  無合法 action、runner timeout 或 invariant violation 都記 failure seed 並讓 gate FAIL。
- screening 只淘汰候選；final 30k 才可產 provisional RC。AC-032 永遠不由 bot 時間完成。

## RC

- `export_presets.cfg` 提供 provisional Windows Desktop preset；`tools/balance/package-rc.ps1`
  驗證 Godot 4.7、執行 gates、匯出至暫存目錄、smoke、封裝 ZIP 與 `.sha256`。
- preset 只匯出 production runtime；原始生成 attempts、測試、規格、pipeline 與 dev scenes 排除。
- 報告目錄留在 `user://`，ZIP 內附 `PLAYTEST.md` 說明人工回傳 JSON；無網路程式碼。
