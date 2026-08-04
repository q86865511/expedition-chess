# Balance Playtest 規格議題

> 狀態：OPEN。以下議題由 `rewrite-plan.md` 附錄 B 裁決為本輪只記錄、不實作；不得以
> balance driver 的局部 workaround 改寫正式 `domain/run/` 或 `domain/battle/` 行為。
> Phase 對應（2026-08-04 使用者裁決，見 `specs/g2-roadmap.md` §9）：各議題的解除
> 排入 Phase 1 `difficulty-curve` 機制切片；逐條標註於下。

## BP-SI-001 — Challenge run operation 與 global source lifecycle 衝突

- 現況：既有 challenge 鏈要求覆蓋 `ShopSurchargeOperationDef` 與
  `DrainExpeditionHpOperationDef`，但 `combat-core/design.md` §7.2/§236 禁止 challenge
  global source 攜帶 run operation。
- 缺口：`domain/run/economy/node_entry_service.gd` 尚未把 challenge 的 run-layer modifier
  與 battle effect source 分流；把 run intent 塞進 `BattleSetup` 會在 EffectResolver lifecycle
  被拒絕。
- 本輪裁決：`slice_challenge_affix_01/02/03` 移出 challenge unlock 的 `modifier_refs`；
  ContentValidator 暫時只要求鏈上仍有合法 battle track，不再要求 surcharge/drain 桶。
- 後續方向：規格化 run-layer challenge modifier 的擁有者、觸發時點、exactly-once receipt
  與 save/reload 語意，再恢復相應的 coverage gate。
- Phase 對應：Phase 1（`difficulty-curve`）。

## BP-SI-002 — Global move 型詞綴目前不可表達

- 現況：`slice_challenge_affix_02` 以 `MoveOperationDef` 表達敵方開場位移。
- 衝突：global source lifecycle 禁止 `move/summon`，因為兩者需要 entity source；現行 schema
  又沒有「對敵方每個 entity materialize 一個 move source」的 authoring 表達。
- 本輪裁決：該 effect 保留為未連線內容並移出 challenge 鏈，不修改 EffectResolver。
- 後續方向：另立規格決定 encounter materialization、合法 target 與 deterministic ordering。
- Phase 對應：Phase 1（`difficulty-curve`）。

## BP-SI-003 — `reachable_nodes()` 是拓撲可達，不是當前 frontier

- 現況：`MapState.reachable_nodes()` 會包含歷史分支中拓撲仍可達的節點，不能直接視為
  下一步可進入集合。
- 本輪裁決：balance driver 只從上一節點直接相鄰的 frontier 選擇；不修改 domain API。
- 後續方向：若正式 UI 也需要 current frontier，另立具名查詢或明確文件化既有 API 語意，
  避免 UI/AI 再次把 topology reachability 當作 transition eligibility。
- Phase 對應：Phase 1 或按需（正式 UI 觸及時提前）。

## BP-SI-004 — Act 2/3 難度曲線未接入

- 現況：首輪 3k 敗局全部集中在 `route.act1.layer6.boss`；通過 Act 1 的樣本條件勝率
  為 100%，synergy 勝者全數滿血結束。`slice_boss_1/2` 雖已有內容，但 map node 仍只引用
  `encounter.slice_boss_0`，normal/elite/boss encounter 也未隨 act 成長。
- 缺口：這不是單一 TUNE 值能修復；需要定義跨幕 encounter 選擇、敵方編成與成長規則。
- 本輪裁決：不修改 `domain/run/` 或 `domain/battle/`；保留首輪與重跑逐幕快照作為後續規格輸入。
- Phase 對應：Phase 1（`difficulty-curve`）核心項。

## BP-SI-005 — Trait 門檻沒有階梯效果

- 現況：2/4/6 三個門檻指向同一 effect，且 `stacking=replace`，因此 2 隻與 6 隻的實際
  效果相同。
- 缺口：需要新增分段 effect 內容並明確定義各門檻的替換或疊加語意。
- 本輪裁決：只記錄，不以 driver 或臨時倍數模擬階梯效果。
- Phase 對應：Phase 1（`difficulty-curve`）。

## BP-SI-006 — Balance runner 的逐幕與 stable ID 可觀測性

- 現況：首輪 case proof 缺少逐幕 gold/HP/roster/board，且購買與獎勵選取曾以 offer 或
  reservation owner 雜湊計數，無法直接回答死亡時編成與高階單位採用率。
- 本輪處置：driver/report 增加 per-act 快照、動作計數，單位購買與 reward 優先記錄正式
  content stable ID；opaque ID 數量另行 fail-visible 呈現。這只擴充證據，不改正式規則。
- 後續方向：若正式 telemetry 需要同類資料，另訂隱私與 schema 版本，不直接重用本地 runner。
- Phase 對應：Phase 1 前置，可隨 Phase 0 順做（僅擴充 runner 證據欄位）。

## BP-SI-007 — 同一 process 內的執行歷史影響 case 勝負（已實證並修復，2026-08-04）

- 現象：`(tempo, seed 48)` 單獨執行為 7 節點 HP 0 敗局；同一份程式碼在全套 GUT
  同 process 內執行則走完 21 節點 HP 72 勝局（driver／domain／content 雜湊相同）。
- **根因（已實證）**：`Array[StringName].sort()` 依 interned 指標位址排序而非字典序
  （獨立 Godot 腳本以兩種 intern 順序得出兩種皆非字典序的結果）。8 個 RNG 池餵入端
  （unit 池、map node 池、reward table、node choice、三星合成 ×2、鍛造表、遺物表）
  使用裸 `sort()`，process 歷史因此成為隱形亂源。
- **修復（使用者授權 domain 修改）**：新增共用 `StableNameSort`
  （`domain/common/stable_name_sort.gd`，`String` 字典序比較），上述 8 處＋
  1 處 presentation 顯示排序（`run_presentation_session.gd`）改用之；全庫其餘裸
  `sort()` 逐一查證為 `Array[String]`/`Array[int]`（本即字典序）不需修；驗序端
  （run_state_validator、battle 各 validator）原本就用 String 比較，無寫入/驗證分歧。
  回歸測試：`tests/unit/common/test_stable_name_sort.gd`、
  `tests/unit/economy_expediton/test_economy_catalog_builder_sort_order.gd`（含變異驗證）。
- **影響揭露**：修復屬「指標序→字典序」一次性遷移，同 seed 的地圖／商店／戰局結果
  自此與修復前不同；3k screening #2 以凍結快照身分保留（見 evidence-lock.md），
  **不得作為修復後版本的回歸對照組**；Phase 2 於乾淨 HEAD 重建平衡基線。
- 邊界釐清（歷史證據有效性）：3k sharded runner 的 per-process case 順序由分片規則
  固定、in-run replay 同 process 執行，故其「150/150 零 drift」與 NUL 等價證據在其
  凍結版本內仍成立。
