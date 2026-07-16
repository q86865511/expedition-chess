# S2 `combat-core` 功能需求

> 狀態：`Approved`
> 架構基線：`docs/game-architecture-spec.md` v0.2 候選
> 範圍：S2 最小戰鬥閉環；規則正文仍以架構規格為單一事實來源

## 1. 目標與邊界

S2 必須交付可恢復閉環：

`PREPARE 合法佈陣 → 提交 combat_pending → 自動戰鬥 → 提交 battle_result_pending → 重載重播得到相同結果`

本文件不重述遊戲規則，只定義 S2 對架構需求的實作深度、可觀察契約與驗收證據。S3 才套用遠征 HP、收入、獎勵與 Boss 重戰；S4 才接入正式羈絆、裝備與遺物來源。

## 2. Traced requirements 與 clause ownership

S2 對齊以下 16 條架構需求；其中 12 條可在本切片完整驗收，4 條只能完成戰鬥側子條款，global REQ 必須維持 `partial/downstream`，不得由 S2 artifact 假稱完整通過：

| 群組 | 架構需求 |
|---|---|
| 棋盤與人口 | `REQ-BOARD-001`、`REQ-BOARD-002`、`REQ-BOARD-003`、`REQ-BOARD-004` |
| 棋子與守恆 | `REQ-UNIT-001`、`REQ-UNIT-002` |
| 戰鬥 | `REQ-COMBAT-001`、`REQ-COMBAT-002`、`REQ-COMBAT-003`、`REQ-COMBAT-004`、`REQ-COMBAT-005`、`REQ-COMBAT-006` |
| 遭遇 | `REQ-ENEMY-001`、`REQ-ENEMY-002` |
| 效果 | `REQ-EFFECT-001`、`REQ-EFFECT-002` |

| Verdict | Requirements | S2 / downstream 邊界 |
|---|---|---|
| S2 full | BOARD-001–004、UNIT-001、COMBAT-001–004、ENEMY-001–002、EFFECT-002 | S2 可單獨完成全部條款 |
| S2 partial | UNIT-002 | S2 完成升星、裝備搬移、存讀守恆；出售／金幣由 S3/S4 |
| S2 partial | COMBAT-005 | S2 產生公式值；S3 才實際扣 HP 與前進 |
| S2 partial | COMBAT-006 | S2 保證不結算且 result 不重跑；S3 才驗收入／獎勵 exactly-once 與 Boss 重戰目的地 |
| S2 partial | EFFECT-001 | S2 禁止直接 mutation 並保存 claim descriptor；S3 才綁 node claim key 並 exactly-once 提交 |

## 3. S2 acceptance criteria

### S2-AC-001 — 完整棋盤診斷

- Given 一份同時含超員、敵方半場、重疊、缺失 unit reference 與超過 32 格的佈陣
- When 執行備戰驗證
- Then 以固定排序一次回報全部具名錯誤，且不得建立或保存 BattleSetup
- Covers `REQ-BOARD-001`、`REQ-BOARD-002`

### S2-AC-002 — 人口來源與版本壓測

- Given base level 9 與三個已提交 `+1` PopulationSourceSnapshot
- When 驗證 12 與 13 個非召喚部署單位
- Then 12 合法、13 為 OVER_CAPACITY；來源不得被固定常數截斷，content report 的 version maximum 與 stress minimum 可重算
- Covers `REQ-BOARD-003`、`REQ-BOARD-004`

### S2-AC-003 — 板凳順序與原子佈陣

- Given 九格板凳含空位與一份新的完整 layout
- When 緊縮或 dispatch `CommitBoardLayoutCommand`
- Then 板凳保持玩家的左至右順序、移除空位、最多九格，完整 layout 只在 validation 與 save 成功後一次交換
- Covers `REQ-BOARD-002`、`REQ-UNIT-002`

### S2-AC-004 — 連鎖升星與副本守恆

- Given 九個同名一星棋子、棋盤／板凳混合位置及固定 acquired serial
- When 執行 merge service
- Then 依棋盤、格位、板凳、instance ID 選主體並產生一個三星；held copies 不變，星級代表副本總數前後相同
- Covers `REQ-UNIT-001`、`REQ-UNIT-002`

### S2-AC-005 — 裝備搬移與 overflow

- Given 三個待合成棋子合計超過三件裝備且含 unique_group 衝突
- When 完成合成、存檔與重載
- Then 主體原槽保留，其餘依被消耗棋子及槽位順序進 inventory／overflow，不取代、不銷毀、不複製
- Covers `REQ-UNIT-002`

### S2-AC-006 — 敵情權威快照

- Given pinned catalog、EncounterDef、明確 source spawn 的 Boss phase 與玩家 roster A
- When 編譯 preview/setup，再只替換 roster／羈絆／裝備為 B
- Then encounter request 與敵軍不因玩家 build 改變；Combat Lab 與 simulation 使用同一 EncounterPreviewSnapshot generation
- Covers `REQ-COMBAT-001`、`REQ-ENEMY-001`、`REQ-ENEMY-002`

### S2-AC-007 — Setup v2 相容性

- Given S1 setup v1 golden 與一份 setup schema v2
- When 執行 codec 與 hash 測試
- Then v1 bytes/hash完全不變；v2頂層仍為原11欄、hashed effect assignments唯一保存category/side/owner/slot並可在reload重建相同source order；seed/hash不在inputs且combat stream在hash後派生
- Covers `REQ-COMBAT-002`、`REQ-COMBAT-003`

### S2-AC-008 — 固定 tick 決定性

- Given相同 pinned setup、combat snapshot、simulation version
- When 以逐 tick、1×、4×與 crash/reload 重播執行
- Then BattleResult、ordered BattleEvent stream、summary hash 與完整 result hash 完全相同
- Covers `REQ-COMBAT-002`、`REQ-COMBAT-003`

### S2-AC-009 — 行動、鎖敵、尋路與移動裁決

- Given path tie、target tie、同格移動競爭、被占格與對角 corner-cut fixture
- When 執行固定 tick
- Then 依架構固定排序產生唯一 target/path/move；禁止 swap、跟入批次開始時佔用格或以 Dictionary/SceneTree 順序裁決
- Covers `REQ-BOARD-001`、`REQ-COMBAT-003`

### S2-AC-010 — 傷害、法力、死亡與 Boss phase

- Given 正負護甲／魔抗、shield、同批致死、damage mana、cast delay 及兩階段 Boss fixture
- When 執行效果與傷害批次
- Then 整數公式、回魔、shield 消耗、同批死亡與 source-bound Boss phase 均符合 v0.2；死亡 trigger 完成後才判定結果
- Covers `REQ-COMBAT-002`、`REQ-COMBAT-003`、`REQ-ENEMY-002`

### S2-AC-011 — 決勝期與唯一結果

- Given 雙方在 1,200 tick 仍存活、同 tick 全滅與 1,800 tick 尚未分勝負三種 fixture
- When 模擬到終點
- Then overtime 每 20 tick 依規則施加，所有場次最晚 1,800 tick 結束；同 tick 全滅與 hard timeout 均為玩家戰敗
- Covers `REQ-COMBAT-004`

### S2-AC-012 — 遠征傷害 proposal 數值

- Given各幕普通／Boss 戰敗且有 encounter-origin 與 summon 存活者
- When 建立 BattleResult
- Then expedition_damage 只計 encounter-origin 存活敵軍，使用 setup snapshot 的幕基礎、每敵人 2 與 Boss 10；S2 不實際扣 HP
- Covers `REQ-COMBAT-005`、`REQ-COMBAT-006`

### S2-AC-013 — EffectResolver 完整矩陣

- Given 九種 trigger、十種 condition、九種 battle operation、四種 stacking 與首版全部有限 enum fixture
- When resolve 各正反案例
- Then 合法案例產生具型別 local operation／proposal／event；未知 enum、target、operation、越界或 budget 超限回具名 error，且不得部分套用、推進 RNG 或 sequence
- Covers `REQ-EFFECT-001`、`REQ-EFFECT-002`

### S2-AC-014 — 有界 trigger 與 proposal descriptor

- Given可形成 trigger cycle 的內容與三種合法 scalar run intent
- When 執行 content validation、戰敗重播與勝利 result 產生
- Then 無有限 max uses 的 cycle 被拒；runtime budget 為第二防線；proposal 只保存 claim descriptor，不直接改 RunState 或建立 node claim key
- Covers `REQ-EFFECT-001`、`REQ-EFFECT-002`

### S2-AC-015 — 事件與結果 codec

- Given每種 BattleEvent type、未知 type、錯誤 payload 與固定 canonical battle
- When round-trip 並計算 hash
- Then schema/欄位/排序固定、未知資料拒絕；sequence 全域遞增；summary hash 綁 setup hash 與完整 ordered event bytes
- Covers `REQ-COMBAT-002`、`REQ-EFFECT-002`

### S2-AC-016 — 可恢復交易閉環

- Given PREPARE run 與可 fault-inject 的 SaveRepository
- When 依序 dispatch 完整 layout、transition StartCombatEvent、dispatch RecordBattleResultCommand，並在 setup/result 每個提交點失敗或 crash/load
- Then save成功前canonical state/phase/serial/RNG/events不變；combat_pending可重播；expected/result/recomputed/receipt四個result hash必須相等；battle_result_pending不重跑且結果只提交一次
- Given schema 0/1/2 fixtures、old v1 generation、allowlisted CombatConfig/Boss mapping及缺件負例
- When 執行 0→1→2、1→2、2→2 migration
- Then idle MAP且無node/preview的active run只在BSM1/CGM1/CGR1 canonical digest與allowlist逐欄通過後原子轉v2並產receipt；PREPARE、任何preview/pending或缺generation/config/mapping/digest一律保留profile與原檔並標 `incompatible_preserved`，不得讀latest或猜值
- Covers `REQ-COMBAT-002`、`REQ-COMBAT-006`、`REQ-EFFECT-001`
- Compatibility note：上述 migration 是S2 schema2 HARD gate evidence，不宣稱完整擁有全域 `REQ-SAVE-003`；`combat-acceptance.json` 必須逐fixture附executable evidence。

### S2-AC-017 — 灰盒 Combat Lab

- Given八隻代理棋子、普通遭遇與兩階段 Boss
- When 使用 8×8 佈陣、預覽、開始、暫停、1×/2×/4×、資訊與 event log
- Then 操作閉環可完成；presentation 只消費 setup 與 event copy，不讀 simulation mutable state，也不提供戰中規則操作
- Covers `REQ-COMBAT-001`、`REQ-COMBAT-002`、`REQ-ENEMY-002`

### S2-AC-018 — Canonical 與 soak gate

- Given canonical fixtures 及至少每方 16 起始單位／64 同時實體壓力設定
- When 執行快速 regression 與 `-Suite Soak -SeedCount 10000`
- Then所有 seed 在 1,800 tick 內結束，且無重疊、entity 遺失、非法事件順序、超界資源、RNG 漂移；runner 寫出 `scope=combat-core/global_ac_030=downstream` 的版本化證據並遵守 0/2/3/124
- Covers `REQ-BOARD-004`、`REQ-COMBAT-002`、`REQ-COMBAT-003`、`REQ-COMBAT-004`

## 4. Global AC ownership

| Global AC | S2 verdict |
|---|---|
| `AC-004`、`AC-005`、`AC-006`、`AC-007`、`AC-008`、`AC-014`、`AC-024`、`AC-031`、`AC-034`、`AC-041`、`AC-050`、`AC-056`、`AC-060`、`AC-064`、`AC-067`、`AC-075`、`AC-076` | S2 可完成其戰鬥／備戰範圍；性能 AC 的真實最低 PC／60 FPS 部分仍屬 G1/G2 presentation downstream |
| `AC-009`、`AC-010`、`AC-019`、`AC-035`、`AC-059`、`AC-066`、`AC-074` | S2 僅產生/保存 result 或 proposal；S3 才完成 exactly-once 結算，artifact 必須標 downstream |
| `AC-013`、`AC-015`、`AC-017`、`AC-058`、`AC-072` | S2 只驗 merge/裝備搬移/人口 snapshot 的局部守恆；商店出售、正式羈絆與裝備流程由 S3/S4 擁有 |

## 5. 非目標

- 不實作 ShopService、節點收入、遠征 HP 實際扣除、獎勵生成/領取、Boss 重戰狀態結算。
- 不實作鍛造、裝備操作 UI、正式羈絆、遺物或指揮官內容來源。
- 不建立正式像素美術、正式平衡、三幕可玩內容或發布 build。
- 不將 skipped/downstream 驗收標記為 pass。

## 6. 完成定義

1. S2-AC-001–018 都有具名 executable evidence 或明確 downstream verdict。
2. 16 條 traced REQ 均有 clause-level verdict 且雙向追溯無孤兒；12 條 S2-full 才可標 pass，4 條 partial 必須同時保存通過的 S2 子驗收與未完成的 downstream owner。
3. `-Suite All` 與獨立 10,000-seed soak 都成功；GUT 有 JUnit XML。
4. `combat-acceptance.json` 可由 runner 重建且不引用手寫 pass。
5. 依本文件逐條獨立複檢為 Blocker 0、Major 0。
6. README、CLAUDE、PROGRESS、架構 Manifest 與 tasks 證據同步；不 commit、push、merge 或發布。
