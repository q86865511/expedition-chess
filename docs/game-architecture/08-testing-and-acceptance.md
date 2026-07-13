# PVE 自走棋 Roguelite 主體架構規格：測試策略與驗收條件

> 文件集入口：[game-architecture-spec.md](../game-architecture-spec.md)  
> 文件狀態：`v0.1 / Approved`
> 本檔範圍：第 11 章

---

<a id="section-11"></a>

## 11. 測試策略與驗收條件

### 11.1 測試層級

| 層級 | 內容 | 執行時機 |
|---|---|---|
| 靜態內容驗證 | ID、引用、數量、配方、門檻、權重、資產、翻譯、解鎖循環 | 每次內容變更、匯出前 |
| 純函式單元測試 | 整數數學、經濟、卡池、升星、羈絆、效果、PRNG、migration | 每次提交 |
| Domain 整合測試 | 狀態機、節點、商店、戰鬥、獎勵、存讀 | 每次提交 |
| Canonical 戰鬥 | 固定 seed 的 setup、result、event hash | 每次規則變更 |
| Headless soak | 10,000 seeds、全地圖與多構築 | 每日／release candidate |
| 場景 smoke | UI 綁定、場景切換、資產缺漏 | 每次提交 |
| 視覺與可讀性 | 像素縮放、tooltip、色覺模式、壓力畫面 | 里程碑 |
| 人工 playtest | 時長、構築多樣性、敵情理解 | G0／G1／G2 |

單元 suite 至少逐項涵蓋：利息、連勝、每幕一次連敗補助、各等級商店機率、有限池取還、三合一升星、羈絆計數、裝備綁定／unique_group、遺物替換、效果排序、PRNG golden／bounded vectors 與逐版 migration。整合 suite 至少逐項涵蓋：三幕流程、普通／菁英戰敗、Boss 重戰無重複收入、獎勵多 stage 提交、所有 commit-before-present 故障點、崩潰續局、局外結算 exactly-once，以及局外解鎖不改基礎戰力。

- **[REQ-QA-001]** 匯出前內容驗證器必須以非零退出碼阻止含無效內容的 build。
- **[REQ-QA-002]** Release candidate 必須通過所有單元、整合、canonical、10,000-seed soak、效能與文件追溯檢查。
- **[REQ-QA-003]** 文件 release gate 必須確認每段規範性條款均有明確 owning REQ；無法判定者必須以 TRACE-GAP 阻止 Approved。

### 11.2 內容驗證器

至少驗證：

- Stable ID 符合 regex、全域唯一、alias 無循環。
- 所有 Resource、資產與 localization key 引用存在。
- 32 隻玩家棋子費用分布為 10／8／6／5／3。
- 恰有 6 陣營、6 職能及 4 隻三標籤棋子。
- 每條羈絆門檻可由已解鎖內容合法達成。
- 6 種零件形成 21 個無重複、無缺口的無序配方。
- 至少 15 件遺物、3 名指揮官、12 怪物、6 菁英詞綴、3 Boss、12 事件。
- 節點 registry 恰好涵蓋普通、菁英、商人、事件、休整、寶藏、Boss 七種類型；固定 Boss 前整備引用休整型別，不建立第八類。
- Challenge 0 基礎難度及 Challenge 1–5 都有可解析、逐階無斷鏈的 UnlockDef／modifier；缺任一階或跳階解鎖均失敗。
- 商店每等級機率和為 100%，卡池副本不低於三星所需上限。
- RewardTable 權重非負且至少一個候選可用。
- 解鎖圖無循環、基礎 profile 至少有一條合法構築。
- 當前內容最大可達人口及最大可能同時實體數。
- 所有公開效果的 trigger、condition、operation 與參數範圍合法。
- 所有 runtime key tuple／digest 全域一致且唯一，serial 不回退；戰鬥來源 RunMutationProposal 僅使用第 8.10 節 scalar 白名單。

### 11.3 Canonical fixture

至少保存：

- `fixture.economy_basic`：利息、連勝、一次性連敗補助。
- `fixture.merge_and_pool`：一星到三星、出售歸池、裝備溢出。
- `fixture.trait_snapshot`：重複、板凳、召喚物與死亡後快照。
- `fixture.item_binding`：鍛造、綁定、拆卸、出售。
- `fixture.boss_retry`：扣血、無收入重戰、崩潰恢復。
- `fixture.simultaneous_death`：同 tick 全滅裁決。
- `fixture.path_tie`：尋路與鎖敵 tie-break。
- `fixture.rng_stream_isolation`：某 stream 多抽不影響其他 stream。

### 11.4 固定 Headless 入口

下列是 G1 起必須存在的 repository-owned runner 契約；本文件集階段不建立腳本。CI 與本機只能呼叫這些穩定入口，不得以人工勾選編輯器結果取代：

| 用途 | 固定指令（從專案根目錄） | Timeout | 必要 artifact |
|---|---|---:|---|
| 內容驗證 | `godot --headless --path . --script res://tests/runners/content_validation_runner.gd -- --report=res://artifacts/test/content-validation.json` | 2 分鐘 | JSON：錯誤 ID、Resource path、invariant |
| GUT 單元／整合 | `godot --headless --path . --script res://tests/runners/gut_runner.gd -- --report=res://artifacts/test/gut.xml` | 10 分鐘 | JUnit XML |
| Canonical／golden | `godot --headless --path . --script res://tests/runners/canonical_runner.gd -- --report=res://artifacts/test/canonical.json` | 5 分鐘 | setup／result／event hashes 與 diff |
| 10,000-seed soak | `godot --headless --path . --script res://tests/runners/soak_runner.gd -- --seed-count=10000 --report=res://artifacts/test/soak.json` | 45 分鐘 | seed 範圍、失敗 seed、統計與效能摘要 |
| 文件追溯／API | `godot --headless --path . --script res://tests/runners/spec_contract_runner.gd -- --manifest=res://docs/game-architecture-spec.md --report=res://artifacts/test/spec-contract.json` | 2 分鐘 | ID、TRACE-GAP、公開 API／Autoload 碰撞報告 |

`spec_contract_runner.gd` 必須讀取 `--manifest` 指向索引中的 `spec-manifest` JSON 區塊，依陣列順序解析全部規範檔；缺檔、重複路徑、清單外規範檔、非法相對路徑或失效跨檔連結皆以退出碼 `2` 回報。

runner 腳本以 `SceneTree` 作入口，從 `_init()` 啟動明確的 main coroutine；GUT 與場景測試可以 `await process_frame`、signal 或受控測試完成事件，但不得進入無退出條件的 idle loop。成功、失敗與基礎設施例外都必須在 artifact flush 後主動 `quit(code)`；`0` 表示通過、`2` 表示可重現的測試／驗證失敗、`3` 表示 runner／fixture／參數基礎設施錯誤，外部 timeout 記為 `124`。CI 必須保存 `res://artifacts/test/`。Godot 執行檔由 toolchain lock 解析為 4.7 stable，runner 必須在報告中寫出 engine、app、schema、content、rng 與 hash version。

- **[REQ-QA-004]** G1 起自動驗證必須使用第 11.4 節固定 headless runner、退出碼、timeout 與 artifact 契約，確保本機與 CI 可重現。

### 11.5 Given／When／Then 驗收

| ID | Given | When | Then |
|---|---|---|---|
| **[AC-001]** | 一個有效 run seed | 產生並走完三幕任一合法路徑 | 每幕正好經過七節點，全局正好三個 Boss |
| **[AC-002]** | 任一批 10,000 個 map seeds | 執行地圖驗證 | 無斷路；每路含開場戰、兩個分岔戰、整備與 Boss |
| **[AC-003]** | 玩家首次進入節點且收入未領 | 儲存、重載、切換畫面或 Boss 重戰 | 基礎收入、利息與連勝金總共只結算一次 |
| **[AC-004]** | 8×8 棋盤與合法部署 | 嘗試重疊、敵方半場或超員開戰 | 開戰被阻止並指出所有非法原因 |
| **[AC-005]** | 等級 9 且同時取得三個 +1 來源 | 形成合法陣容 | 可部署 12；移除來源後顯示超員且不能開戰 |
| **[AC-006]** | 一個戰鬥節點 | 玩家進入備戰 | 可見敵方站位、羈絆、技能、目標與 Boss 階段；戰中無主動規則操作 |
| **[AC-007]** | 相同內容版本、setup、seed、rng_version | 分別以 1×、4×及重載後執行 | BattleResult 與事件摘要完全一致 |
| **[AC-008]** | 雙方在 1,200 tick 仍存活 | 繼續模擬至 1,800 tick | 決勝傷害生效且最晚 1,800 tick 產生唯一結果 |
| **[AC-009]** | 第一幕普通戰敗且 3 名敵人存活 | 結算戰果 | 扣 12 HP、無獎勵並前進 |
| **[AC-010]** | 第二幕 Boss 戰敗且 2 名敵人存活 | 結算並重載 | 扣 24 HP、回同節點備戰且沒有新收入 |
| **[AC-011]** | 金幣 47、5 連勝、首次進入節點 | 結算收入 | 得 5 基礎＋4 利息＋2 連勝，結果不超過 99 |
| **[AC-012]** | 本幕尚未領補助 | 第二次連續戰敗後再持續戰敗 | 第 2 敗只領一次 3 金，本幕後續不再領 |
| **[AC-013]** | 有限卡池、五格商店與棋子獎勵 | 反覆刷新、產生候選、購買、選取、出售與重載 | 每個 UnitDef 的「池中＋所有候選保留＋持有」副本總數守恆 |
| **[AC-014]** | 9 個同名一星棋子 | 完成自動合成 | 產生一個三星、消耗 9 副本，裝備無遺失或複製 |
| **[AC-015]** | 棋盤有同 ID 重複、板凳與召喚物 | 計算羈絆並有單位死亡 | 只計不同上場 ID，快照在整場不因死亡變動 |
| **[AC-016]** | 6 種零件 | 枚舉含同種的所有無序配對 | 正好得到 21 個唯一成裝 |
| **[AC-017]** | 棋子已裝三件綁定裝備且物品庫已滿 | 嘗試換裝、出售與使用拆卸道具 | 直接換裝被拒；出售／拆卸物進 overflow tray，解決後完整取回且不造成軟鎖 |
| **[AC-018]** | 已啟用五件遺物 | 取得第六件 | 必須替換或放棄；重載後選擇及槽位順序不變 |
| **[AC-019]** | 普通、菁英或 Boss 戰敗 | 結算、重載、重戰 | 無任何戰後獎勵，已知候選不可藉此生成 |
| **[AC-020]** | 一個未顯示的勝利獎勵 | 生成後強制關閉再載入 | 三個候選完全相同且只能領一次 |
| **[AC-021]** | 基礎 profile 與三位指揮官 | 分別建立遠征 | 指揮官不上場、不佔人口，起始包與被動各自不同 |
| **[AC-022]** | 任一局外解鎖 | 比較解鎖前後相同 UnitDef 的基礎 stats | 基礎生命與攻防完全一致，只增加選項或難度 |
| **[AC-023]** | 正在進行的 content_snapshot | 局外解鎖新棋子後續讀 | 進行中遠征內容池不變，新遠征才套用 |
| **[AC-024]** | UI 與模擬引用同一 stable ID、content version 與 catalog generation | 顯示 tooltip 並開戰 | 顯示門檻與模擬值源自同一 compiled snapshot；兩者不持有或共享 authoring Resource |
| **[AC-025]** | 一份舊 schema fixture | 執行逐版 migration 兩次 | 第一次成功升級，第二次資料不再改變 |
| **[AC-026]** | 寫檔中斷或主檔損毀 | 下次啟動載入 | 自動使用有效 backup，保留損毀檔供診斷並顯示訊息 |
| **[AC-027]** | map stream 的抽樣次數增加 | 用相同 run seed 產生商店、獎勵與戰鬥 | shop／reward／combat 的結果保持不變 |
| **[AC-028]** | 720p、1080p 與 1440p | 顯示世界與繁中 UI | 世界像素無模糊，必要文字與操作不被裁切 |
| **[AC-029]** | 任一色覺模式與 150% UI | 檢視羈絆、稀有度與傷害類型 | 不靠顏色仍能區分，焦點與按鈕皆可操作 |
| **[AC-030]** | 10,000 個合法 run seeds | 完成 headless soak | 無死局、非法地圖、負資源、遺失實體或重複獎勵 |
| **[AC-031]** | 參考最低 PC | 執行 12v12 與 64 實體壓力戰至少 5 分鐘 | 正常 60 FPS；壓力至少 55 FPS；tick p99 ≤ 8 ms；不漏 tick；presentation 待處理佇列不持續成長且不超過 4,096 |
| **[AC-032]** | 至少 30 名熟悉規則的測試者 | 各完成至少 3 局基礎難度 | 完成局中位數 45–60 分鐘，至少三種構築有通關紀錄 |
| **[AC-033]** | 全部候選角色、美術、名稱及 UI | 執行原創性審查 | 無直接使用或近似重製 Riot 的受保護內容 |
| **[AC-034]** | 新增一個 +1 人口來源 | 執行內容驗證與壓測選擇 | 最大人口重新計算，壓測下限同步提高 |
| **[AC-035]** | `ResolutionState` 為 combat_pending 或 battle_result_pending | 在各提交點強制終止並載入 | 重播／結果一致，Boss 收入與獎勵皆不重複 |
| **[AC-036]** | 專案依賴與匯出環境 | 執行版本檢查與 headless build | Godot 為 4.7 stable、GUT 為 9.7.1，且不存在浮動版本依賴 |
| **[AC-037]** | PC 完全離線、沒有帳號與既有存檔 | 從啟動完成一場遠征並回到營地 | 所有核心流程可用，且不發出必要網路請求 |
| **[AC-038]** | 內容完整 G2 候選 | 執行資產清單驗證 | 32 隻玩家棋子各自具備第 6.3 節全部資產，無色票替代角色 |
| **[AC-039]** | 任一 App／Run 狀態 | UI 嘗試合法及非法轉移並修改 DTO | 合法轉移只經狀態機；非法轉移與 UI 直接寫狀態均被拒絕 |
| **[AC-040]** | 所有需存檔或跨畫面的 DTO | 執行序列化與靜態依賴檢查 | DTO 可轉為 JSON 基本型別，且不含 Node、Resource、Callable 或 SceneTree 路徑 |
| **[AC-041]** | 同一 Boss、相同最終 BattleSetup | 只刷新商店或買賣板凳後重戰 | battle_setup_hash、combat seed、BattleResult 與事件摘要保持不變 |
| **[AC-042]** | 新 profile 位於營地 | 選指揮官、完成三幕、結算通關並確認 | 解鎖／貨幣依結果套用、active run 清除、回到可操作營地 |
| **[AC-043]** | 進行中遠征 | 遠征 HP 歸零或在 Boss 重戰選擇放棄 | 進入失敗結算、套用合法里程碑／貨幣、清除 active run、回到營地 |
| **[AC-044]** | 營地已載入 | 依序互動遠征門、指揮官廳、圖鑑館、解鎖工坊、挑戰碑 | 五類功能均可進入、返回，且狀態由同一 ProfileState 讀取 |
| **[AC-045]** | 大量 map seeds 與每個生成節點圖 | 枚舉所有起點到 Boss 的路徑 | 無斷路、無連續三個相同非戰鬥節點，且四個分岔層各有 2–3 個候選 |
| **[AC-046]** | 事件、商人、休整、寶藏、鍛造、裝備、遺物替換各一個待提交選擇 | 在提交前後每個故障注入點終止並載入 | 不會半消耗或重領；已顯示不可逆結果必有相符的已提交狀態 |
| **[AC-047]** | 一份有效內容集 | 逐次破壞每項第 11.2 節 invariant 並執行驗證器 | 每一種破壞都產生具體錯誤及非零退出碼；有效集回傳 0 |
| **[AC-048]** | 已知金幣、卡池與 roster ledger | 依序購買、刷新、買 XP、升星、出售 | 每步金幣差額符合 EconomyConfigDef，卡池副本守恆，無免費交易 |
| **[AC-049]** | UI、ShopService 與 EconomyConfigDef | 執行靜態掃描並變更一個 TUNE 值 | UI／domain 無重複經濟常數，變更後兩者顯示與行為同步 |
| **[AC-050]** | 固定 run seed、act、node、難度與解鎖池 | 只替換玩家 roster、羈絆及裝備後重新產生遭遇 | EncounterDef、敵隊與詞綴完全不變 |
| **[AC-051]** | 含舊 stable ID 的已發布存檔 fixture | 內容 ID 改名並提供 alias 後載入 | 舊引用遷移至新 ID、資料守恆、再次 migration 不改變結果 |
| **[AC-052]** | 含已刪除內容的兩份 fixture | 分別刪除非必要圖鑑內容與當前棋子／遺物 | 前者由 tombstone 安全載入；後者拒載、保留 backup 且不猜測替代 |
| **[AC-053]** | 候選 Approved 文件 | 掃描所有「必須／不得／禁止／MUST」規範句並人工核對 | 每句都有明確 owning REQ；任何歧義輸出 TRACE-GAP 並阻止 Approved |
| **[AC-054]** | 所有跨模組公開方法與訊號 | 執行 GDScript static analysis 與 API 掃描 | 參數、回傳與集合元素皆具名型別，domain API 不暴露未型別化 Dictionary |
| **[AC-055]** | 含棋盤、板凳、物品、overflow 與五遺物槽的 RunState | 序列化、重載並建立所有 UI view | 只有 RosterState 保存這些資料；view 值一致但沒有共享可變集合或重複權威欄位 |
| **[AC-056]** | 等級 9、三個 +1 來源與 12 隻部署棋子 | 依序計算羈絆、人口與合法性，再於戰中觸發效果 | derived capacity 為 12 且可開戰；戰中效果不改人口；少一來源時在建立 setup 前拒絕超員 |
| **[AC-057]** | 棋盤、板凳與物品庫皆滿的合法玩家 | 產生普通、事件與棋子獎勵並嘗試提交 | 每組至少有可領非棋子選項；棋子可經 unit_overflow 出售／替換／放棄完成，無軟鎖或靜默遺失 |
| **[AC-058]** | 五個 shop offer 與三個 reward candidate 都有 reservation_owner_id | 關閉 UI、重載、Boss 戰敗、刷新、選取及節點離場 | 關閉／Boss 重戰保留；刷新只釋放舊 shop owner；提交／離場各 owner 恰釋放一次，池總量守恆 |
| **[AC-059]** | 三個戰鬥效果分別提出 `add_gold`、`add_xp`、`heal_expedition_hp` RunMutationProposal | 在同一 Boss 反覆戰敗、重播，最後勝利 | 每次戰敗都丟棄 proposal，首次合法勝利只依各 claim key 提交一次並依資源上限 clamp |
| **[AC-060]** | 三個待合成同名棋子含超過三件裝備及相同 unique_group | 依固定主體與槽序完成合成、存檔並重載 | 主體合法裝備保持；衝突／超量裝備依序進 inventory／overflow，沒有取代、銷毀或複製 |
| **[AC-061]** | 一個尚無 settlement receipt 的完成或失敗 run | 在結算存檔每個故障點終止並重載 RESULTS 三次 | 貨幣符合 MetaRewardTableDef 且 profile、receipt、active run 原子一致；同 run_id 永遠只加值一次 |
| **[AC-062]** | 玩家 3 級 0 XP 且有足夠金幣 | 累積 164 XP、在跨級時製造溢出並於 9 級再買 XP | 正好到 9 級、各級扣門檻且保留跨級溢出；9 級購買停用不扣金，事件溢出歸零 |
| **[AC-063]** | rng_version=1 參考實作與每個持久 u64 欄位的邊界 fixture | 執行本節 PCG／derive／bounded vectors，並讓 run_seed、RNG state／inc／counter 及四個 next_*_serial 各自 JSON round-trip 0、2^53±1、2^63、2^64-1 | 每個 raw output、counter 與 derived seed 完全相同；每欄 u64 恰為小寫 16-hex 且無精度遺失 |
| **[AC-064]** | 已提交 EncounterPreviewSnapshot 與一份合法備戰狀態 | 修改上場站位後開戰，再只刷新商店重建 setup | 敵方永遠等同 preview；站位改變會改 hash，純商店變更不改 hash；hash inputs 不含 seed／hash，combat seed 在 hash 後派生 |
| **[AC-065]** | 一個可扣金購買 command 與可注入失敗的 SaveRepository | 分別讓驗證、tmp 寫入及 final read-back 失敗，並嘗試由 UI 修改 view | canonical 金幣／卡池完全不變、無成功事件；UI 修改不影響 state；只在 save 成功後一次 swap |
| **[AC-066]** | 一場菁英勝利，依序有 standard 與 relic 獎勵 | 在 combat、result、standard submit、relic submit 前後各 crash／load | 每次只有一個合法 ResolutionState；候選不重抽、reservation 不重複釋放，兩 stage 各只能領一次 |
| **[AC-067]** | 每一種 EffectDef operation 與 BattleEvent type | 執行型別掃描、codec round-trip 與戰敗／勝利結算 | battle operation 只改 local state；run intent 只在合法勝利提交；payload 無任意 Dictionary，event hash 穩定 |
| **[AC-068]** | project.godot Autoload 與全部 class_name | 執行 spec_contract_runner 靜態掃描 | ContentRegistry／SaveService 只作實例名，實作型別分別為 ContentRegistryService／SaveRepository，無全域符號碰撞 |
| **[AC-069]** | 兩個同時 save 請求，以及 main／backup 的有效、backup-only、invalid-main-only、invalid-backup-only、全無與殘留 tmp 組合 | 對 open 至 restore 每一步做 fault injection 並模擬 crash | 寫入不交錯；有效 main 優先、backup-only 不被移走；任一路徑存在但零有效副本時拒絕覆寫；tmp／corrupt 被 quarantine，既有進度至少一份 committed copy 可用且所有 Error 可觀察 |
| **[AC-070]** | profile 有效但 active run 的 manifest digest 無法解析 | 載入、取消放棄，再明確確認放棄 run | profile 全部資料保持可用；取消時原檔不變；確認時先封存原檔，只清 run 且不重置貨幣／解鎖／receipt |
| **[AC-071]** | G1 或 G2 candidate 與固定 Godot 4.7 環境 | 逐一執行第 11.4 節五個命令並製造 pass、test fail、infra fail、timeout | 分別得到 0／2／3／124，artifact 含版本與診斷，受控 await 可完成且沒有無界 SceneTree 等待 |
| **[AC-072]** | 菁英勝利、shop offer 尚保留、roster／inventory 皆滿，所選棋子需靠出售帶裝棋子騰位 | 在 standard choice、unit resolution、出售造成 item overflow、建立 relic stage 與 final exit 前後逐點 crash／load | 每次恢復同一 subphase；放棄所選棋子會歸池、接受則轉持有；shop 直到 relic 與所有 overflow 完成才釋放，兩 stage 各一次且最終才離場 |
| **[AC-073]** | 三幕都引用同一 encounter template，且同一單位的兩個裝備各提供相同 effect | 產生 node／reservation／transaction／claim／settlement keys，重載並故意注入一個重複 tuple 與一個 digest 不符 key | 各幕收入與各來源效果各自恰提交一次、所有合法 key 唯一；兩個損壞 fixture 均拒載且不猜測修復 |
| **[AC-074]** | 一組戰鬥效果分別提出三種合法 scalar intent 與棋子、物品、遺物、人口等容量型 intent | 執行內容驗證並讓合法效果在 Boss 先敗後勝 | 容量型內容以非零碼拒絕；戰敗不提交 scalar，首次勝利依 claim key 提交一次並按金幣／XP／HP 上限決定性 clamp |
| **[AC-075]** | registry 已從含 nested Array／subresource 的 `.tres` 編譯 catalog，UI 取得一份 definition view | UI 修改 view 的 scalar／Array，並對原 `.tres` 觸發熱重載 | 目前 domain 值、active run、manifest digest 與 canonical 戰果不變；新內容先形成不同 generation／digest，原始 Resource 從未暴露給 consumer |
| **[AC-076]** | 每個第 8.7 節公開服務各有一個合法 request 與一個失敗 fixture | 依序觸發缺 ID、非法 transition、stale offer、壞 setup、未知 operation、I/O failure、壞 RNG context，並在錯誤 lifecycle 呼叫 step／result | 每次回傳對應具名 error；canonical state、serial、RNG counter、事件與 committed save 均不變，沒有 silent null、assert crash 或部分套用 |
| **[AC-077]** | G2 全部場景、ContentDefinition 與 `zh_TW`／`en` 目錄 | 靜態掃描玩家可見字串並比較 key 集合 | 場景／domain 無硬編碼玩家文字，繁中無缺值，英文目錄具有完全相同 key；刪任一必要 key 會使驗證非零退出 |
| **[AC-078]** | registry 同時保留 manifest A／B，兩者有同 stable ID 但數值不同，active run pinned A 而 CAMP 使用 B | 兩端各自 resolve、重載 active run，並執行公開 API 掃描 | run 永遠取得 A、CAMP／新 run 取得 B；缺 digest 的呼叫不存在，移除 A 後只將 run 標為 incompatible 而不退回 B |

---

[← 像素呈現、UI 與無障礙](07-pixel-presentation-and-ui.md) · [返回文件集入口](../game-architecture-spec.md) · [風險、決策與假設 →](09-risks-decisions-and-assumptions.md)
