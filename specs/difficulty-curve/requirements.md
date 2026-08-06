# G2 difficulty-curve — Requirements

狀態：APPROVED FOR IMPLEMENTATION（依使用者 2026-08-04 指示）

## 範圍

- 本片擁有新增的 `REQ-ENEMY-003`，並重證 AC-050、AC-079；同時解除
  `specs/balance-playtest/spec-issues.md` 的 BP-SI-001、BP-SI-004、BP-SI-005 與
  BP-SI-006 的 (i)(ii) 兩項。
- 本片是 `specs/g2-roadmap.md` §9 Phase 1 的機制切片：只移除平衡迴圈的結構性天花板，
  不做數值收斂；TUNE 迭代與收斂判準屬 Phase 2。
- 明列不做：
  - BP-SI-002（global move 型詞綴）——`slice_challenge_affix_02` 維持未連線內容，
    EffectResolver 與 encounter materialization 一律不動，該議題續 OPEN。
  - BP-SI-006 的 (iii)(iv) 選配欄位、以及任何正式 telemetry schema。
  - 10,000／30,000 seeds 大樣本 cohort 與正式平衡基線（Phase 2）。
  - 美術、UI、音效、localization 以外的呈現層改動；新增後端、帳號或網路上傳。
  - 固定規則變更：tick、棋盤、排序、codec、claim、save、exactly-once 語意與 RNG
    stream 集合皆不得因本片改變。

## DC-REQ

- **DC-REQ-001 Act scaling**：`CombatConfigDef` 必須以 per-act 基點值宣告敵方
  `health/attack/armor/magic_resist` 的成長乘數（act1 恆等 10000），並在
  `EncounterCompiler` 疊乘於既有星級 `_scaled` 之後；`attack_speed_milli`、
  `move_speed_milli`、`attack_range_cells`、`start_mana`、`max_mana` 不得被 act 乘數改變。
  縮放後值必須通過既有 i32 與值域守衛，且不得新增任何 RNG draw。
- **DC-REQ-002 Boss 映射**：Boss 節點的 encounter 必須由 `node.act_index` 決定性映射至
  `encounter.slice_boss_0/1/2`（act1/2/3），同一 (act_index, node_id) 永遠得到同一
  encounter ID。map node schema 與 `generator_ref` 內容不得為此新增欄位；
  `slice_boss_1/2` 必須進入 pinned `required_battle_ids` 集合，否則 Boss 節點必須以既有
  具名錯誤 fail-closed，不得 fallback 回 `slice_boss_0`。
- **DC-REQ-003 多敵編成**：`slice_normal`、`slice_elite`、`slice_boss_0/1/2` 必須各自
  authoring 多隻 `EnemySpawnDef`，spawn_key 唯一、格位不重疊且全部落在敵方半場
  （`logical_y` 4–7）。編成內容（單位、星級、格位）為 TUNE；`EncounterDef` schema 與
  compiler 皆不得為此改動。
- **DC-REQ-004 Trait 階梯**：12 個 trait 各自既有的三階 `required_count` 門檻（本片只改
  `effect_refs`，不改門檻值；一／二階皆為 2／4，第三階 `faction_shadow`／
  `role_mystic`／`role_sentinel`／`role_trickster`／`role_warden` 五者為 5、其餘七個
  trait 為 6）必須各自指向強度遞增的獨立 effect，且第 n 階與第 n+1 階的數值嚴格遞增。
  `stacking` 維持 `replace`，`BattleSetupSourceCompiler` 取最高達標階的既有語意不得
  改變（零程式改動）；新增 effect 必須有完整 `zh_TW`／`en` loc key。
- **DC-REQ-005 Tier-1 池**：tier-1 單位池的 faction trait 分布必須讓每個 faction 都能在
  tier-1 內湊出 2 門檻；重標後全庫每個 faction 的成員數仍須 ≥6，使 2／4／6 三階皆可達成。
- **DC-REQ-006 Challenge 回鏈**：`slice_challenge_affix_01/03` 必須回到 challenge unlock 的
  `modifier_refs`，`ContentValidator` 必須回復軌 A／經濟壓力（ShopSurcharge）／遠征傷害
  （DrainExpeditionHp）三桶覆蓋 gate。run-layer challenge modifier 由既有
  `RunModifierTable` 軌 B always-active 路徑消費；EffectResolver、global source lifecycle
  與 `BattleSetup` 的 challenge 禁令為 scoped——僅當 challenge 來源的 effect 同時攜帶
  `battle_operations`（因此會被 pin 進 battle catalog／setup，即「雙軌」）時才拒絕再
  攜帶 `run_operations`；純 `run_operations` 的 challenge 詞綴（如 ShopSurcharge／
  DrainExpeditionHp）不進 `BattleSetup`，由軌 B 消費，不受此條禁令限制（與
  `specs/combat-core/design.md:117／:236` 的作用域限定一致，見 design.md「決定性與
  失敗政策」段與 `content_validator.gd:1097-1101`）；`encounter_affix` 的 RunOperation
  禁令為 category-based 無條件禁止（不依 source_side），不得放寬；side-based 的通用
  enemy-side 禁令不在本條範圍（如未來需要須另行明文新增，見 design.md 對應段）。
- **DC-REQ-007 觀測性**：balance driver 的每一條獎勵／購買選取都必須記錄正式 content
  stable ID；無法取得 stable ID 時必須計入既有 opaque 計數並 fail-visible，不得以
  `reward.kind.N` 之類佔位字串混入 stable ID 統計。`BalanceBotActSnapshot` 必須額外保存
  per-act 戰鬥勝／敗場數與死亡節點 ID，並進入 canonical token。
- **DC-REQ-008 Per-act 淘汰 gate**：`BalanceBotReport` 必須新增
  `BALANCE_ACT_ELIMINATION_FLAT` gate reason——當 cohort `seed_count` ≥ 1000 且所有敗局
  集中於單一幕時 FAIL；`seed_count` < 1000 時不啟用。GDScript 與
  `tools/balance/act-elimination-gate.ps1`（由 `run-sharded-cohort.ps1` dot-source
  接線）兩份實作必須對同一份 golden 輸入的
  act-curve gate 段（`BALANCE_ACT_` 前綴）reason 集合與 `act_curve` token 產生逐字相同
  的結果（PS 聚合端與 GDScript 各自另有其餘既有 gate reason，不要求全集相同）。

## Acceptance

1. 固定 encounter 與星級，只改變 `act_index`：act1 的敵方 `health/attack/armor/magic_resist`
   等於星級縮放值本身，act2／act3 等於再乘上對應 bps 後的整數值；`attack_speed_milli`、
   `move_speed_milli`、`attack_range_cells`、`start_mana`、`max_mana` 三幕完全相同；
   同一輸入重複編譯 byte-identical 且 RNG counter 不變。（DC-REQ-001）
2. 同一 run seed 走完三幕，三個 Boss 節點分別編譯出 `encounter.slice_boss_0/1/2`；
   將 `slice_boss_1` 自 pinned 集合移除會使 act2 Boss 節點以具名錯誤拒絕進入，
   而不是取得 `slice_boss_0`。（DC-REQ-002）
3. 五個 encounter 編譯後的敵方單位數分別為 2／3／3／4／5，spawn_key 無重複、
   `(logical_y, logical_x)` 無碰撞且全部 `logical_y` ≥ 4；內容驗證器對重複 spawn_key
   或越界格位以非零碼拒絕。（DC-REQ-003）
4. 對同一 trait 依其既有三階 `required_count` 門檻（2／4／6，`faction_shadow`／
   `role_mystic`／`role_sentinel`／`role_trickster`／`role_warden` 五者為 2／4／5）
   分別部署對應人數的不同成員：三次得到不同的 effect ID 與嚴格遞增的數值，
   `TraitBattleSnapshot.tier` 分別為 1／2／3；刪除任一新增 loc key 會使 localization
   靜態驗證非零退出。（DC-REQ-004）
5. 掃描全庫 `UnitDef.trait_refs`：每個 faction trait 的成員數 ≥6，且 tier-1 子集內每個
   faction 至少有 2 名成員。（DC-REQ-005）
6. challenge 等級 1–5 的 unlock 鏈上，`modifier_refs` 覆蓋軌 A、ShopSurcharge 與
   DrainExpeditionHp 三桶；移除任一桶會使 `CONTENT_CHALLENGE_AFFIX_COVERAGE` 觸發。
   同時 challenge global source 仍不得攜帶 RunOperation 進入 `BattleSetup`，
   該負向案例維持紅。（DC-REQ-006）
7. reward 選取在 `content_id` 存在時記正式 content stable ID；`GOLD`／`EVENT` 等結構上
   無 content ID 的獎勵種類記 `reward.kind.N` 佔位字串，且該路徑必須同時計入既有 opaque
   計數並 fail-visible（不得混入 stable ID 統計冒充可回溯 ID）；driver 端
   reservation_owner／offer 類選取的 opaque 計數為 0；per-act 快照含各幕 battle
   win/loss 與死亡節點 ID，且 canonical token 隨這些欄位改變。（DC-REQ-007；原「opaque
   計數為 0」表述已依 T11 F1/#1 修正——`RewardOfferState.RewardKind` 的 GOLD／EVENT
   結構上沒有 content stable ID，該表述在出貨資料上不可達，見 evidence-index.md
   DC-REQ-007 列）
8. 以「敗局全部集中 act1」的 golden cohort 輸入，`seed_count=1000` 時兩份實作都輸出
   `BALANCE_ACT_ELIMINATION_FLAT`，`seed_count=999` 時兩份都不輸出；同一 golden 的
   act-curve gate 段（`BALANCE_ACT_` 前綴）reason 集合與 `act_curve` token 在 GDScript
   與 PowerShell 兩側逐字相同（T08 已證：要求「完整 gate reason 集合」兩側逐字相同在
   結構上不可達——PS 聚合端與 GDScript 各自持有對方沒有的既有 reason）。（DC-REQ-008）
