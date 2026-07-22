# S3 `economy-expedition` 功能需求

> 狀態：`Stages 0–6 implemented / T00R and T11B independent review passed`
> 架構基線：`docs/game-architecture-spec.md` v0.2 Approved
> 範圍：S3 經濟與遠征結算；規則正文仍以架構規格為單一事實來源

## 1. 目標與邊界

S3 必須把 S1 的原子存檔交易與 S2 的 canonical `BattleResult` 接成可恢復遠征閉環：

`三幕地圖 → 首次節點收入與商店 → 備戰經濟操作 → 戰果 exactly-once 結算 → 持久獎勵 → 下一幕 MAP 或終局 RESULTS`

階段 0–6 已接通規格、typed domain 契約、戰鬥與非戰鬥節點、商店、戰果結算、持久獎勵、灰盒 Expedition Lab 與正式 S3 runner。獨立 T00R／T11B 已完成並保留於 `final-review.md`。

## 2. Traced requirements 與 clause ownership

S3 主要擁有 11 條架構需求：

| 群組 | 架構需求 |
|---|---|
| 遠征 | `REQ-RUN-001`–`REQ-RUN-005` |
| 經濟 | `REQ-ECON-001`–`REQ-ECON-004` |
| 獎勵 | `REQ-REWARD-001`–`REQ-REWARD-002` |

S3 同時收斂支援條款 `REQ-UNIT-002`，以及下游條款 `REQ-COMBAT-005/006`、`REQ-EFFECT-001`、`REQ-SAVE-002/004/005`、`REQ-DATA-007`、`REQ-RNG-001`、`REQ-TECH-004/006`。S3 擁有 reward unit／item／relic 的選擇、放棄、替換與 overflow 可恢復狀態機；S4 擁有正式裝備／遺物內容、效果與鍛造規則；S5 擁有 RESULTS 後的 Profile settlement。

## 3. S3 acceptance criteria

### S3-AC-001 — 三幕地圖決定性

- Given 固定 run seed、run ID 與 pinned map-node catalog
- When 生成完整遠征地圖
- Then 三幕各有開場普通戰、四層 2–3 候選、Boss 前休整與 Boss；所有路徑可達、每幕至少兩個分岔戰鬥、沒有連續三個相同非戰鬥節點
- Covers `REQ-RUN-001`–`REQ-RUN-003`

### S3-AC-002 — 節點首次收入與進入交易

- Given MAP 中可達且尚未 claim 的節點
- When 進入節點、重載或重試相同 transaction
- Then current node、收入、shop offers、RNG snapshot、receipt 與 PREPARE phase 只在 save 成功後一次發布；重載與 Boss retry 不重領
- Covers `REQ-RUN-004`、`REQ-RUN-005`

### S3-AC-003 — 收入公式

- Given 47 金、5 連勝與首次進入節點
- When 結算收入
- Then 依版本化資料得到 5 基礎＋4 利息＋2 連勝，並以 99 clamp
- Covers `REQ-ECON-002`、`REQ-ECON-003`

### S3-AC-004 — 五格商店與有限卡池

- Given pinned economy catalog、shop RNG 與有限卡池
- When 依 slot 0→4 產生 offer
- Then 先按等級抽 tier、再按剩餘實體副本加權抽 unit；每抽一張立即 reservation；無合法副本的 slot 省略但保留 slot identity；總副本守恆
- Covers `REQ-ECON-001`、`REQ-ECON-003`、`REQ-ECON-004`

### S3-AC-005 — 刷新 exactly-once

- Given 已提交 shop offers
- When 支付刷新、存檔失敗、重試或成功
- Then 舊 owner 在同一 draft 各釋放一次後才生成新 offers；失敗時金幣、卡池、owners、RNG、serial 全不變
- Covers `REQ-ECON-001`、`REQ-ECON-004`、`REQ-TECH-004`

### S3-AC-006 — 購買與自動合成

- Given 有效 offer、足夠金幣與可完成的 roster 位置
- When 購買
- Then reservation 轉 held、建立唯一 unit instance、依 S2 規則連鎖合成、金幣與卡池守恆；stale offer、金幣不足或最終無位置時零 mutation
- Covers `REQ-ECON-001`、`REQ-UNIT-002`、`REQ-TECH-006`

### S3-AC-007 — 出售

- Given 一至三星棋子，可能帶有綁定裝備
- When 出售
- Then 依 `cost / 3×cost-1 / 9×cost-3` 結算、代表副本歸池；裝備依 slot 進 inventory／overflow，棋子從 board／bench 移除
- Covers `REQ-ECON-001`、`REQ-UNIT-002`

### S3-AC-008 — 購買 XP

- Given 等級 3、0 XP 與足夠金幣
- When 重複購買並跨級
- Then 使用版本化門檻保留溢出、正好可累積至 9 級；9 級操作停用且不扣金
- Covers `REQ-ECON-003`

### S3-AC-009 — 戰敗與 Boss retry（階段 4）

- Given canonical battle_result_pending
- When 結算一般／菁英／Boss 戰敗
- Then HP、streak、補助與目的地 exactly-once；Boss retry 保留 offers 且不發收入、proposal 或 reward
- Covers `REQ-COMBAT-005`、`REQ-COMBAT-006`、`REQ-ECON-002`

### S3-AC-010 — 勝利 proposal 與 reward（階段 4–5）

- Given 勝利 result 與 scalar proposals
- When crash/load/retry 結算
- Then 每個 node claim key 最多提交一次，候選在顯示前持久化且只能領一次
- Covers `REQ-EFFECT-001`、`REQ-REWARD-001`

### S3-AC-011 — Reward overflow 與離場（階段 5）

- Given 滿 roster／inventory 與多 stage 獎勵
- When 選擇、overflow 解決與最終離場
- Then 同一 subphase 可恢復，沒有軟鎖或靜默遺失；shop reservation 只在最後離場釋放
- Covers `REQ-REWARD-002`、`REQ-ECON-004`

## 4. Global AC ownership

| Verdict | Global AC |
|---|---|
| S3 stages 0–3 executable | `AC-001`、`AC-002`、`AC-003`、`AC-011`、`AC-013`、`AC-027`、`AC-045`、`AC-048`、`AC-049`、`AC-062`、`AC-065`、`AC-073`、`AC-076` 的地圖／收入／商店子條款 |
| S3 stages 4–6 executable | `AC-009`、`AC-010`、`AC-012`、`AC-019`、`AC-020`、`AC-035`、`AC-057`、`AC-058`、`AC-059`、`AC-067`、`AC-074` 的 S3 戰果、獎勵、恢復與 scalar claim 子條款 |
| S3 elite crash/load | `AC-066` 的菁英 standard→relic 多階段持久化與失敗回滾條款 |
| S4 shared/downstream | `AC-017`、`AC-046`、`AC-072` 的正式裝備／遺物內容與效果條款 |
| G1/G2 downstream | `AC-030` 完整 run soak、正式 UI 與最低規格效能 |

## 5. 非目標

- 不完成正式鍛造、正式遺物內容／效果、營地、RESULTS 後 Profile settlement 或正式像素 UI；遺物選擇／替換／放棄的可恢復狀態機屬 S3。
- 不把 partial/downstream 驗收寫成 pass。

## 6. 完成定義

1. 三件套對 11 條主要 REQ 雙向覆蓋，階段狀態不混淆。
2. 階段 0–3 的 domain service、RunController command/event 與 fault-injection 測試通過。
3. map／shop／reward／combat RNG 隔離；交易失敗不推進 RNG 或 serial。
4. `-Suite All` 通過；S3 acceptance artifact 只能聚合具名 executable evidence。
5. 10,000-seed economy-expedition soak 與逐 S3-AC artifact 必須通過；T00R／T11B 均須為 Blocker 0／Major 0。
