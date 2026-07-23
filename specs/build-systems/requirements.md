# S4 build-systems 功能需求

> 狀態：已核可（2026-07-22）
> 架構基線：`docs/game-architecture/` v0.2（Approved）；權威需求 §5.4 羈絆、§5.10 裝備鍛造、§5.11 遺物；追溯 §14。
> 範圍：局內構築三系統（羈絆／裝備鍛造／遺物）的 run-layer 邏輯、正式內容實例（.tres）、Build Lab 灰盒與 ViewModel。正式 UI 視覺呈現（Codex 範圍，見 `HANDOFF.md`）不在本片。

## 1. 目標與邊界

- 目標：完成垂直切片的構築深度——羈絆計數與戰鬥快照編譯、6 零件→21 配方鍛造與物品庫管理、遺物 5 槽啟用與替換，並首次建立正式內容實例（S3 完成時全專案 `.tres` 內容為 0，皆為測試 fixture）。
- 已有基礎（S2/S3 已接好、本片不重做）：`BattleSetup` 的 trait/equipment/relic 效果輸入欄位與模擬消費端（`battle_setup_inputs.gd:9-11`、`battle_simulation.gd:36-44`）、`EffectResolver` 的 relic/trait/equipment 效果源類別與 `has_equipment` 條件、`RelicSlotState` 與 `resolve_relic_reward_command.gd`、reward reservation exactly-once（S3）。
- 明確不做：正式構築 UI 視覺（Codex）、營地/局外解鎖（S5）、32 棋子完整美術（橫切 SCOPE-002）。

## 2. Traced requirements 與 clause ownership

| 架構 REQ | 主題 | 本片擁有權 |
|---|---|---|
| REQ-TRAIT-001 | 羈絆計數規則（不同上場 UnitDef.id；排除板凳/同 ID/召喚物；6 陣營＋6 職能；4 隻指定棋子第三標籤） | full |
| REQ-TRAIT-002 | 羈絆戰前快照；死亡不關閉；預覽與實戰同一 TraitDef 資料 | full |
| REQ-ITEM-001 | 6 零件、任兩零件（含相同）恰一配方＝21 件裝備、可查詢；零件僅存物品庫、僅鍛造可合成 | full |
| REQ-ITEM-002 | 每棋 3 件上限、unique_group、裝備綁定/取回、16 格物品庫、overflow tray 不靜默丟棄 | full |
| REQ-RELIC-001 | 遺物 5 槽啟用序、第六件原子替換/放棄、被替換者永久移除、≥15 件內容 | full |
| REQ-CONTENT-001（部分） | 內容驗證器須涵蓋 S4 新內容類型（羈絆/零件/配方/遺物） | partial（驗證器已存在，S4 擴充規則） |
| REQ-UX-002 | 敵情/配裝可視 | downstream（ViewModel 供資料，正式 UI 歸 Codex） |

## 3. S4 acceptance criteria

### S4-AC-001 — 羈絆計數正確性（Covers REQ-TRAIT-001；對應 AC-015）
- Given 上場區含同 ID 重複棋子、板凳有同族棋子、戰鬥中產生召喚物
- When 計算各羈絆的計數
- Then 僅以「不同上場 UnitDef.id」計數；板凳、同 ID 重複、召喚物一律不計

### S4-AC-002 — 標籤結構與門檻啟動（Covers REQ-TRAIT-001）
- Given pinned catalog 含 6 陣營＋6 職能 TraitDef；一般棋子 1 陣營＋1 職能；4 隻指定棋子帶第三標籤
- When 以不同上場組合計數
- Then 各羈絆依 TraitDef.thresholds 正確啟動對應階層；第三標籤棋子同時計入三個羈絆

### S4-AC-003 — 戰前快照與死亡不關閉（Covers REQ-TRAIT-002；對應 AC-015、AC-024）
- Given 戰鬥開始前編譯的 TraitBattleSnapshot
- When 戰鬥中構成羈絆的單位死亡；且以 UI 預覽同一佈局
- Then 已啟動羈絆效果持續到戰鬥結束；預覽顯示的門檻/數值與模擬消費的是同一份 compiled snapshot（同一 TraitDef 資料，逐欄位相等）

### S4-AC-004 — 21 配方封閉枚舉（Covers REQ-ITEM-001；對應 AC-016）
- Given 6 種零件的完整配方表
- When 枚舉所有無序零件配對（含自身配對）
- Then 恰得 21 個唯一完整裝備，且每一配對恰有一個配方；配方可由任一零件反查

### S4-AC-005 — 鍛造原子交易與零件約束（Covers REQ-ITEM-001）
- Given 物品庫含兩個零件
- When 執行鍛造（copy-validate-save-swap 交易）
- Then 兩零件消耗、產出恰一件完整裝備入庫；零件不可直接裝備到棋子；交易失敗時物品庫不變

### S4-AC-006 — 裝備上限與 unique_group（Covers REQ-ITEM-002）
- Given 棋子已裝 3 件裝備、或已裝 unique_group=X 的唯一裝備
- When 嘗試再裝第 4 件、或再裝同 unique_group 裝備
- Then 操作被拒且狀態不變，回傳明確錯誤原因

### S4-AC-007 — 綁定、取回與搬移不複製（Covers REQ-ITEM-002；對應 AC-060）
- Given 裝備已綁定到棋子
- When 出售該棋子、或使用稀有拆卸道具（ConsumableDef）
- Then 裝備回到物品庫且全程恰一實例（無複製、無消失）；除此二途徑外裝備不可取回

### S4-AC-008 — 16 格物品庫與 overflow tray（Covers REQ-ITEM-002；對應 AC-017）
- Given 物品庫 16 格已滿
- When 升星/出售/獎勵產生新物品
- Then 溢出物進一次性 overflow tray、玩家必須明確處置、不得靜默丟棄；任何換裝/出售/拆卸序列不造成軟鎖

### S4-AC-009 — 出售帶裝棋子的 crash/load 恢復（Covers REQ-ITEM-002；對應 AC-072）
- Given 出售帶 3 件裝備的棋子的交易進行中發生 crash
- When 重新載入存檔
- Then 狀態恢復為交易前或交易後之一（原子性）；裝備與貨幣皆 exactly-once、無複製或遺失

### S4-AC-010 — 遺物 5 槽與第六件原子替換（Covers REQ-RELIC-001；對應 AC-018）
- Given 已啟用 5 件遺物（槽 1–5 決定觸發序）
- When 取得第六件並選擇替換或放棄，隨後存檔重載
- Then 選擇為明確可存檔的原子操作；被替換者該局永久移除、不轉貨幣；重載後選擇結果與槽序不變

### S4-AC-011 — 遺物效果作用域（Covers REQ-RELIC-001）
- Given ≥15 件遺物涵蓋戰鬥/經濟/路線/規則四類
- When 戰鬥型經 BattleSetup.player_relic_effects 進入模擬；經濟/路線/規則型在對應 run-layer 決策點套用
- Then 各類效果在正確作用點生效、依槽序觸發；不佔裝備格

### S4-AC-012 — 正式內容實例與驗證器（Covers REQ-ITEM-001、REQ-RELIC-001、REQ-TRAIT-001、REQ-CONTENT-001 部分）
- Given 正式 `.tres` 內容：12 個 TraitDef（6+6）、6 零件、21 配方裝備、≥15 RelicDef、≥1 拆卸 ConsumableDef
- When 執行內容驗證器與 manifest digest pin
- Then 全數通過驗證（配方封閉性、門檻遞增、unique_group 一致性、效果引用存在）；digest 進 canonical snapshot

### S4-AC-013 — Build Lab 灰盒與 ViewModel 契約（Covers REQ-UX-002 downstream；REQ-TECH-004）
- Given Build Lab 灰盒場景與構築 ViewModel（羈絆面板/鍛造/物品庫/遺物槽）
- When 經 ViewModel 執行鍛造、換裝、遺物替換並讀取羈絆預覽
- Then 操作皆經 RunController 交易完成；ViewModel 只持有 clone/snapshot，不保留 domain 可變引用

## 開放問題

（無——內容量、Lab/ViewModel 範圍、伴生 catalog 方案、實作啟動方式均已由使用者裁決，見 `~/.claude/plans/codex-async-orbit.md` 裁決紀錄。）
