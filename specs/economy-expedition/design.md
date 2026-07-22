# S3 `economy-expedition` 技術設計

> 狀態：`Stages 0–6 implemented / independent review passed`
> 對應需求：[requirements.md](requirements.md)

## 1. 設計目標

S3 沿用 `RunController` copy-validate-save-swap、pinned content generation、PCG32 具名 stream、RuntimeKey v1 與 save schema 2。Domain service 只讀 snapshot 並回傳 typed transaction；只有 command/event 把 transaction 套入 draft。

## 2. 版本策略

| 契約 | 版本 | 決策 |
|---|---:|---|
| save schema | 2 | 現有 EconomyState／UnitPool／reservation／receipt 已足夠，不新增 wire 欄位 |
| economy runtime catalog | 1 | 從 pinned `EconomyConfigDef`、UnitDef、MapNodeDef、RewardTableDef compiled view 與 receipt `reward_table_ids` 解碼 |
| map generation | 1 | PCG32 `map` stream，完整三幕一次生成 |
| shop generation | 1 | PCG32 `shop` stream，tier→剩餘副本加權 unit |
| runtime keys | 1 | node／reservation_owner／transaction 沿用既有 canonical tuple |

空 shop slot 以缺少該 `slot_index` 的 offer 表示；`EconomyState.shop_offers` 為按 slot 遞增的 0–5 筆集合，避免 sentinel Unit ID 與 save schema bump。

## 3. 模組

```text
ContentRegistryService
  -> EconomyExpeditionCatalogBuilder -> EconomyExpeditionCatalog
RngService(map) -> MapService -> MapState
IncomeService -> IncomeTransaction
ShopService -> ShopTransaction
RunController
  -> EnterNodeEvent
  -> RefreshShopCommand / BuyOfferCommand / SellUnitCommand / BuyXpCommand
```

`EconomyExpeditionCatalog` 保存 manifest digest、`EconomyConfigRule`、可售 `ShopUnitRule`、帶 generator ID 的 `MapNodeRule` 與 `RewardTableRule`。builder 只能解碼 receipt 指定的 `reward_table_ids`；不得保存 Resource 或 latest-catalog lookup。

## 4. 地圖生成

每幕固定七層：`normal(1) → branch(2–3) ×4 → rest(1) → boss(1)`。分岔第 1、3 層全部為 normal／elite，確保任一路徑至少兩場分岔戰；第 2、4 層由 merchant/event/treasure 決定性抽取。相鄰層全連接，幕 Boss 連下一幕 opening。所有 node key 由 `(run_id,act,kind,layer,slot)` 建立，payload digest 綁 manifest、definition 與 node identity。

## 5. 節點進入與收入

`EnterNodeEvent` 驗證 MAP、idle resolution 與 reachability，在單一 draft 中：

1. 僅 normal／elite／boss 戰鬥節點由 pinned `MapNodeRule.generator_id` 取得同 generation `EncounterDef` compiled rule，以 `EncounterCompiler` 建立並持久化 `encounter_preview`；node kind 與 encounter kind 必須相符；merchant／event／rest／treasure 保留各自 node content，不要求 EncounterDef；
2. 設 current node／act；
3. 若尚未 claim，`IncomeService` 依 pre-gold 計算基礎、利息、連勝，建立 transaction receipt 並加入 sorted claim set；
4. 若 shop 尚未生成，`ShopService.generate_offers()` 產生 offers／reservation owners；
5. 回傳 draft，RunController 才在 save 成功後設定 PREPARE 並發布；`StartCombatEvent` 只讀該 preview，不可另走 Lab／fixture 捷徑。

## 6. ShopService

### 6.1 生成與刷新

slot 0→4：按等級 odds 以 basis-point draw 選 tier，再按同 tier `remaining_copies` 加權抽 unit。抽中立即 `remaining--/reserved++` 並建立 owner。tier 無副本最多重抽 20 次；仍失敗省略該 slot。刷新先按 owner 釋放舊 offers，再扣金與生成新 offers，全部在一份 transaction draft。

### 6.2 購買

以 offer ID 與 ACTIVE owner 雙重驗證 stale request。成功後扣金、`reserved--/held++`、owner→CONSUMED、建立 `u_<serial>`、加入 bench，再使用 S2 `UnitMergeService` 完成連鎖合成。最終 bench 超過九格則整筆拒絕。

### 6.3 出售

按星級代表副本數歸池，售價使用版本化 unit cost。綁定物品依原 slot 順序解除，優先放 inventory，剩餘進 sorted overflow；unit 從 board／bench／instances 移除。

### 6.4 XP

扣除版本化成本後循序套用門檻；跨級保留 XP，9 級設為 0 並停用後續購買。

## 7. 原子性與 identity

每個成功 economy operation 配一個 `TransactionKeyState` 與 SHA-256 payload digest。reservation owner 與 receipt 均依 digest 排序。service 從不修改 request；command 只有在 transaction 完整成功後替換 draft 子狀態。validation／save／read-back 失敗由既有 RunController 丟棄整份 draft。

## 8. 戰果與獎勵狀態機

`BattleSettlementService` 只消費 canonical `battle_result_pending`。戰敗丟棄 proposals、扣 HP、更新 streak／幕補助；普通／菁英與 HP 歸零路徑完成節點並釋放 shop，Boss 且 HP 大於零則保留同一 node、income claim 與 shop 回 PREPARE。勝利只提交白名單 scalar claim，建立第一個已持久化 reward stage 後才進 REWARD。

`RewardService` 使用獨立 `reward` RNG 產生標準／遺物三選一。標準 table 只能含非 relic 候選且至少一個無條件非棋子 fallback；relic table 只能含 relic 且至少一個無條件 fallback；event grant 可使用非 relic 的無條件 fallback，包含 unit-only 強制棋子 table。若 unit-only event 的實體卡池已耗盡，runtime 不虛構副本，改為持久化固定的零效果 EVENT choice，玩家確認後沿相同 final-exit 交易離場；此 deterministic fallback 不消耗 reward RNG 以外的狀態。candidate conditions 由 pinned compiled payload 解碼，S3 v1 支援 `roster_space_at_least`、`inventory_space_at_least`、`expedition_hp_below`、`pool_copies_at_least`，以當前持久狀態在抽權重前決定性過濾；未知、形狀錯誤或缺少對應 stage 無條件 fallback 的 table 由 content gate 拒絕。未選棋子 owner 在 choice 交易釋放；已選棋子、item overflow 與滿五遺物分別進可恢復 subphase。菁英 standard 完成後原子建立 relic stage並保留 shop；只有最後 stage 與 overflow 全部解決後才釋放 shop、完成節點。第一、二幕 Boss 返回 MAP；第三幕 Boss 或 HP 歸零進不可逆 `RESULTS`，S5 再處理 Profile settlement。

merchant／rest 由 `ResolveNonCombatNodeCommand` 原子完成節點（rest 同步治療）；event／treasure 由同一 command 建立已持久化 `EVENT_GRANT`，再沿用 choice／unit reservation／overflow／final exit 流程，確保非戰鬥層不會停死在 PREPARE。

Expedition Lab 僅是灰盒展示控制面，不作 domain correctness 證據；正式 production seam 由 RunController integration 與 `Expedition` runner 驗證 map→node entry→persisted preview→combat start。`ExpeditionSoak` 對 10,000 seeds 驗證完整拓樸、全相鄰層 edge、owner↔offer 雙向 ledger 與 pool aggregate；acceptance 聚合器另檢查 soak artifact 新鮮度。

## 9. 需求追溯

| Requirement | Design | Tasks |
|---|---|---|
| RUN-001–003 | §4 | T03 |
| RUN-004–005 | §5、§7 | T04 |
| ECON-001 | §6、§7 | T05–T08 |
| ECON-002 | §5、§8 | T04、T09 |
| ECON-003 | §2、§3、§6 | T01、T05–T08 |
| ECON-004 | §6.1、§7、§8 | T05、T09 |
| REWARD-001–002 | §8 | T09–T11 |
| UNIT-002 | §6.2–6.3 | T06–T07 |
| COMBAT-005–006 | §8 | T09 |
| EFFECT-001 | §8 | T09 |
| SAVE-002/004/005 | §5、§7–8 | T04–T11 |
| DATA-007 | §2–3、§8 | T01、T09 |
| RNG-001 | §2、§4、§6、§8 | T03、T05、T09、T11 |
| TECH-004/006 | §5、§7、§10 | T04–T11 |

## 10. Failure policy

未知 generation、缺 config、非法 odds／pool、stale offer、serial exhaustion、owner conflict、RNG failure、資源不足與 roster 不可完成均回具名 error；不得 assert crash、silent null、部分 mutation 或成功訊號。
