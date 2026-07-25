# S5 meta-progression 功能需求

> 狀態：已核可（2026-07-24）
> 對應需求：REQ-META-001~004（擁有權見 §2）
> 架構基線：`docs/game-architecture/04-content-and-meta-progression.md` §7（:63-113）、`docs/game-architecture/08-testing-and-acceptance.md`（AC-021/022/023/042/043/044/061/073）、`docs/game-architecture/10-traceability-matrix.md:39-41`
> 撰寫慣例照 `specs/build-systems/requirements.md`；S5-AC 的 Given-When-Then 為 TDD 測試翻譯的直接來源。

## 1. 目標與邊界

S5 補上局外層：營地五設施、指揮官選擇與被動生效、挑戰階級與詞綴、解鎖/購買、圖鑑發現、
MetaRewardTableDef 結算與 run_id receipt exactly-once、AppRoot 正式 composition root 接線與 Camp 灰盒。
完成後達 G1「全系統切片」門檻的 S5 份額（§3.2）。

明確不做：正式 UI 視覺與營地自由移動場景（Codex；灰盒僅功能載體）、詞綴/獎勵數值平衡（TUNE）、
多存檔槽、meta.currency 世界觀正式命名、32 棋子完整美術（橫切 SCOPE-002）。

使用者裁決（2026-07-24）：挑戰詞綴全部機械生效（含負向 run 機制雙軌）；圖鑑發現局內即時標記；
AppRoot 正式接線＋Camp 灰盒入本片；指揮官被動經遺物作用點機制實際生效。

## 2. Traced requirements 與 clause ownership

| 架構 REQ | 主題 | 本片擁有權 |
|---|---|---|
| REQ-META-001 | 營地五類功能入口（§7.1 五設施＋狀態欄） | full |
| REQ-META-002 | 局外成長只擴選項/難度，禁提基礎戰力（§7.3 禁項） | full |
| REQ-META-003 | 進行中 content_snapshot 不因解鎖/熱重載變（§7.3） | partial（快照釘選/lease 機制屬 S1 已驗 AC-078；S5 擁有局外解鎖端行為與 AC-023） |
| REQ-META-004 | MetaRewardTableDef 結算＋run_id receipt exactly once（§7.3） | full |
| REQ-DATA-007 | 局外結算冪等識別＝RuntimeKeyCodec v1 canonical tuple | partial（S1 建 codec；S5 擁有 settlement receipt key 產生與唯一性驗證＝AC-073 的 settlement 子條款） |
| REQ-DATA-006 | ContentSnapshotState 不可變；不相容 run 隔離、保留 ProfileState | downstream（S1 已驗；S5 只沿用，不新增行為） |
| REQ-SAVE-001/003 | 版本化 JSON 原子寫入；schema 變更必附 migration 測試＋fixture | partial（S5 擴充 ProfileState 欄位須帶 migration 測試與保留 fixture；寫入機制沿用） |
| REQ-TECH-002/004/006 | 轉移經 RunController/AppStateMachine；copy-validate-save-swap；具名 error | partial（S5 新 command/交易與 CAMP↔RUN↔RESULTS 流程遵守既有契約） |
| REQ-CONTENT-001 | 驗證器精確驗證內容數量/分布 | partial（S5 擴充：challenge 詞綴內容、claim_scope 放寬後規則、META 禁項檢查） |
| REQ-UX-005 | 玩家可見文字由 localization key 提供 | partial（S5 新內容/灰盒文字給 key；目錄完整性屬 G2） |

## 3. S5 acceptance criteria

### S5-AC-001 — 營地五設施入口與單一狀態源（Covers REQ-META-001；對應 AC-044）
- Given 營地（灰盒）已載入且 ProfileState 存在
- When 依序互動遠征門、指揮官廳、圖鑑館、解鎖工坊、挑戰碑並各自返回
- Then 五設施均可進入、返回；顯示狀態（最近選擇、已解鎖 ID、發現/解鎖、貨幣/購買紀錄、各指揮官最高通關）全部由同一 ProfileState 讀出，無第二資料源

### S5-AC-002 — 指揮官建立遠征與鎖定（Covers REQ-META-001；對應 AC-021）
- Given 基礎 profile 與三位已解鎖指揮官
- When 分別以三位指揮官建立遠征
- Then 指揮官不出現在棋盤/上場區、不佔人口；三者起始包與被動 refs 各自不同；RunState.commander_id 於建立時鎖定，遠征中無任何 command 可更換

### S5-AC-003 — 指揮官被動經作用點實際生效（Covers REQ-META-001/§7.2；使用者裁決）
- Given 指揮官 def 含 passive_effect_refs 與 population_bonus
- When 建立遠征並經過對應作用點（map/shop/settlement/node entry 或 battle_start）
- Then 被動效果與 population_bonus 實際影響 run（效果來源標記為 commander；與遺物同管線）；三名被動非同一效果的數值階級（內容驗證）

### S5-AC-004 — 局外成長禁提基礎戰力（Covers REQ-META-002；對應 AC-022）
- Given 任一局外解鎖（含全部 unlock defs）
- When 解鎖前後以同一 content manifest 比較同一 UnitDef 的 compiled 基礎 stats
- Then 基礎生命/攻防完全一致；內容驗證器拒絕 unlock 內容宣告永久基礎生命/攻防提升、商店免費刷新或固定起始人口（非零退出碼）

### S5-AC-005 — 進行中快照隔離（Covers REQ-META-003；對應 AC-023 局外解鎖端）
- Given 進行中遠征持有 content_snapshot 與 catalog lease
- When 局外解鎖新棋子/內容後續讀該遠征
- Then 進行中遠征內容池完全不變；同 profile 的新遠征才套用新解鎖

### S5-AC-006 — MetaRewardTableDef 結算計算（Covers REQ-META-004）
- Given slice_default 表對齊 §7.3 初值（普通 1/菁英 3/Boss 5/通關 +10；非戰鬥節點 0；failure 加成 0；乘數 bps 10000..15000）
- When 完成或失敗遠征於 Challenge L 結算
- Then 貨幣 = floor(Σ 成功戰鬥計分 ×(10000+1000×L)/10000)＋（通關才加 completion）；戰敗保留該局先前成功戰鬥計分、無失敗額外加成；計算純函式可單元驗證

### S5-AC-007 — settlement receipt exactly once（Covers REQ-META-004；對應 AC-061）
- Given 一個尚無 settlement receipt 的完成或失敗 run
- When 在結算存檔每個故障點終止並重載 RESULTS 三次
- Then 貨幣符合 MetaRewardTableDef；profile、receipt、active run 三者原子一致；同 run_id 永遠只加值一次；receipt key 由 RuntimeKeyCodec canonical tuple 產生且載入/提交時驗唯一

### S5-AC-008 — 端到端結算原子交易與營地回返（對應 AC-042/AC-043）
- Given 新 profile 位於營地
- When 選指揮官完成三幕通關結算；或遠征 HP 歸零/Boss 重戰放棄進入失敗結算
- Then 解鎖、貨幣、里程碑、挑戰紀錄、receipt 與 active run 清除在同一原子存檔交易提交；結算後回到可操作營地（灰盒）；重載 RESULTS 不重複發放

### S5-AC-009 — 挑戰階級進度按指揮官記錄（Covers §7.4）
- Given Challenge 0 基礎與 1..5 逐階
- When 以指揮官 X 於 Challenge N 通關結算
- Then 指揮官 X 的最高通關記為 N、profile 整體最高階同步；Challenge N+1 解鎖條件＝通過前一階（prerequisite 未滿足時遠征門拒選）；其他指揮官紀錄不變

### S5-AC-010 — 挑戰詞綴累積生效＋開局前完整列出（Covers §7.4；使用者裁決全生效）
- Given Challenge N（1..5）遠征與新著作的 challenge 詞綴 effects（涵蓋敵人編成/遭遇規則/經濟壓力/遠征傷害類別）
- When 建立遠征
- Then 詞綴 1..N 累積實際生效（經作用點/run 參數，決定性）；開局前 ViewModel 可完整列出生效詞綴清單；Challenge 0 無詞綴；菁英詞綴與 map node generator 不受重指影響

### S5-AC-011 — 解鎖工坊購買規則（Covers §7.3）
- Given profile 貨幣餘額與可購 unlock 清單（含 prerequisite/currency_cost）
- When 購買某 unlock
- Then 成功路徑：扣款＋寫入 unlocked_content_ids 原子提交；貨幣不足/重複購買/prerequisite 未滿足分別回具名 error 且零變更；購買紀錄可由解鎖工坊讀出

### S5-AC-012 — 圖鑑發現局內即時標記（Covers §7.1；使用者裁決）
- Given 遠征中首次出現的內容（上場/購得棋子、商店出現、遭遇敵人、取得裝備/遺物）
- When 該事件所屬 command 交易提交
- Then discovered_content_ids 於同一 copy-validate-save-swap 交易原子追加（冪等：重載/重放不重複）；圖鑑館按類別讀出發現/解鎖狀態

### S5-AC-013 — claim_scope 真語意防重放（S4 裁決；對應 AC-073 settlement 子條款）
- Given 遺物/效果 claim_scope ∈ {always, once_per_node, on_first_clear}（非 always scope 的支援集合依 design §6.4 收斂為「消費端具 claim-aware 去重」的 (category×kind)，目前即 (rule×heal_expedition_hp)；w3 裁決 2026-07-25）
- When 同節點重入、重載重放、跨節點再觸發、以及戰敗結算
- Then once_per_node 同節點恰一次、on_first_clear 全 run 首次通過恰一次；戰敗不提交也不消耗 claim（w3 裁決 2026-07-25）；validator 與 run_relic_table_builder 同判準同步放寬；claim/settlement keys 全 run 唯一且重複 tuple 拒載

### S5-AC-014 — 正式接線 relic_table 顯式傳入（HANDOFF §4；Covers REQ-TECH-002）
- Given AppRoot 正式 composition root 與 SceneRouter CAMP↔RUN↔RESULTS
- When 由營地開始遠征、進行至任一含遺物作用點的 command
- Then GenerateExpeditionMapCommand/RefreshShopCommand/SettleBattleResultCommand/EnterNodeEvent 均以顯式非 null relic_table 建構（含指揮官被動與挑戰詞綴）；有測試證明正式接線路徑效果生效（防「忘傳靜默跳過」回歸）

## 開放問題

無（failure_reward 歸零、非戰鬥節點計分歸零係依 §7.3 權威初值裁定，列 S5-AC-006；challenge 詞綴具體五條內容屬 design 決定）。
