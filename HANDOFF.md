# HANDOFF — Claude／Codex 分工與交接指引

> 建立於 2026-07-22（使用者裁決）。本檔是兩個 AI 協作者之間的分工契約與接手入口；專案進度見 `PROGRESS.md`，規格單一事實來源見 `docs/game-architecture/`。

## 1. 分工邊界

| 負責方 | 範圍 |
|---|---|
| **Claude** | 程式邏輯與架構：`domain/`、`services/`、`content/`（定義、註冊表、驗證器、內容邏輯）、`app/`、全部測試與 runner、**ViewModel／介面層**（UI 可消費的資料介面與快照、場景骨架、`SceneRouter` 路由、事件訂閱）、開發用灰盒 Lab（`scenes/dev/`）。 |
| **Codex** | 表現與體驗：正式畫面的視覺呈現、佈局、動畫、美術素材（像素圖、圖示、字型）、音效／音樂、UX 打磨與易用性調整。 |

- 灰盒 Lab（Combat Lab／Expedition Lab／Build Lab）是開發驗證工具，**不是**正式 UI；Codex 建正式畫面時以 Lab 展示的操作流與 ViewModel 為參照，不必沿用其外觀。
- 內容數值（TUNE 標記者）屬遊戲設計，目前由 Claude 隨切片授權佔位值；最終平衡屬下游調整，任一方發現數值問題記入 PROGRESS.md 待辦而非默改。

## 2. Presentation 消費契約（Codex 建 UI 時必守）

依 spec §8.5 與 REQ-TECH-004（違反即審查退回）：

1. **只持 clone／snapshot**：presentation 一律經 ViewModel 或 RunController 提供的 read-only snapshot 讀狀態，不得保留任何 domain 可變引用、不得跨操作快取 domain 物件。
2. **寫操作一律經 RunController command**：所有玩家操作（買賣、鍛造、換裝、遺物選擇…）呼叫既有 command，由 copy-validate-save-swap 交易提交；UI 不得直接改 `RunState` 或任何 domain 狀態。
3. **不得使用 Godot `rand*`／時間／Object ID 產生 gameplay entropy**：純視覺抖動可用本地亂數但不得回寫 domain；一切 gameplay 決定性亂數走 `RngService` 具名 stream。
4. **不得讀 latest catalog**：內容一律經 pinned canonical snapshot（`ContentRegistry` generation pin）；UI 顯示的門檻／數值必須與模擬消費同一份 compiled snapshot（例：羈絆預覽用 `BattleSetupSourceCompiler` 的產物）。
5. **Autoload 維持既有五個**（`ContentRegistry`、`SaveService`、`SettingsService`、`AudioService`、`SceneRouter`），不新增。
6. 驗證失敗 command 會回具名 error——UI 負責呈現，不得吞掉或繞過（例如 overflow tray 未清空時開戰被拒是設計行為）。
   - **具名原因的讀法**：頂層 `CommandError.code` 對所有拒絕一律是 `APPLY_FAILED`；具體原因（如 `EQUIP_ITEM_SLOTS_FULL`、`RESOLVE_OVERFLOW_ITEM_NOT_IN_TRAY`）在 `error.diagnostic_values` 中 key 為 `source_code` 的診斷字串——UI 分流訊息請讀這裡。
7. **讀取節奏**：ViewModel 每次讀取都回完整 deep-clone snapshot——請「操作後刷新」，不要逐幀輪詢（避免高頻深拷貝的效能壓力）。ViewModel 建構時持有 pinned catalog/規則表的私有 clone；catalog 世代更換（新 run／熱重載）時請重建 ViewModel 實例，勿沿用舊物件。

**ViewModel 入口清單**（S4 起提供，Codex 換皮起點）：
- `TraitPreviewViewModel`（`presentation/viewmodels/trait_preview_view_model.gd`） — 羈絆面板（當前計數／下一門檻／效果，與實戰同源）
- `ForgeViewModel`（`presentation/viewmodels/forge_view_model.gd`） — 鍛造介面（零件清單、配方預覽）
- `InventoryViewModel`（`presentation/viewmodels/inventory_view_model.gd`） — 物品庫／棋子裝備／overflow tray
- `RelicSlotViewModel`（`presentation/viewmodels/relic_slot_view_model.gd`） — 遺物槽序與第六件替換
- `CampViewModel`（`presentation/viewmodels/camp_view_model.gd`） — 營地五設施的單一 ProfileState 投影
- `ExpeditionGateViewModel`／`CommanderHallViewModel`／`CollectionViewModel`／`UnlockWorkshopViewModel`／`ChallengeMonumentViewModel` — S5 局外成長各設施讀取介面
- （S2/S3 既有）戰鬥 event/result clone、商店 offer 表、地圖節點狀態——見各 Lab 的 session/presentation 腳本示範消費方式

## 3. 進度地圖（接手時從這裡看）

| 切片 | 狀態 | 規格 | 完成證據 |
|---|---|---|---|
| S1 `foundation-core` | ✅ 完成 | `specs/foundation-core/` | PROGRESS 2026-07-13 條目；`foundation-acceptance.json`（無獨立 final-review，複檢結論僅載於 PROGRESS——歷史事實，如實記載） |
| S2 `combat-core` | ✅ 完成，複檢 PASS | `specs/combat-core/`（含 final-review.md） | `artifacts/test/`、10,000-seed soak |
| S3 `economy-expedition` | ✅ 完成，複檢 PASS | `specs/economy-expedition/`（final-review.md＋implementation-review.md） | 11/11 S4-AC evidence、10,000-seed ExpeditionSoak |
| S4 `build-systems` | ✅ 完成（2026-07-24） | `specs/build-systems/`（三件套＋implementation-review.md） | 12/12 任務、13/13 S4-AC、Gut 399/399、10,000-seed 構築 soak、8 份雙審紀錄（`.pipeline/reviews/` 本機） |
| S5 `meta-progression` | ✅ 實作完成（2026-07-26） | `specs/meta-progression/`（三件套＋implementation-review.md） | T01～T12、S5-AC 14/14、Gut 737/737、10k ExpeditionSoak、All exit 0、W5 R4 雙審零未決 |
| 橫切 UX/QA 15 REQ | 📋 未動工 | `docs/implementation-slices.md` | 正式 UI／美術（Codex）＋效能／QA gate |

- 測試 gate：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite All`（其餘 suite 見專案 `CLAUDE.md`）。`artifacts/test/` 為本機驗證輸出。
- 表現層現況：全專案 `.tscn` 僅 `app/main.tscn`＋dev Lab；美術／音效資源為 0——正式視覺全部待 Codex 建立。
- **T11 內容缺口修復記錄**（S4 wave4 收尾，2026-07-23）：Build Lab（T11）首次把 `content/packs/vertical_slice/` 餵進 production `EconomyExpeditionCatalogBuilder`／`ContentRegistryReceiptAdapter` 後，暴露兩個此前從未被真正觸發過的內容缺口，已一併修復：(1) `economy_configs/slice_default.tres` 原缺 `layer_income`／`xp_thresholds`，被 builder 判定不合法而驗證器當時未攔——`content/validation/content_validator.gd:298` 已補上與 builder 一致的必填欄位檢查（新增 `CONTENT_ECONOMY_CONFIG_INCOMPLETE`）；(2) 雙 pack 合併後完全沒有 `meta_reward_table` 分類內容，導致 `ContentRegistryReceiptAdapter` 的 save/load 在 receipt 重建階段必定失敗（`PINNED_CATALOG_REFERENCE_MISSING`）——已新增 `meta_reward_tables/slice_default.tres` 佔位內容＋驗證器 `CONTENT_META_REWARD_TABLE_MISSING` 規則。細節見 `content/packs/vertical_slice/README.md`「T11 wave4 內容缺口修復」與 `scripts/dev/build_lab/build_lab_content_bootstrap.gd:14` 註解。

## 4. 雙方工作流

- **Claude**：功能片走 `specs/<切片>/` 三件套（逐段核可）→ 依 tasks 波次實作（TDD 分代理：測試先行→紅證據→實作轉綠→fresh 重驗）→ 雙審（Sonnet 5 一審＋Opus 4.8 二審，兩獨立 session；使用者裁決不用 Codex review）→ 更新 PROGRESS.md 與本檔。
- **Codex**：接手 UI 時（1）讀本檔 §2 契約與 §3 進度地圖；（2）從對應 Lab 的 session 腳本看 ViewModel 消費示範；（3）正式場景放 `scenes/`（非 `scenes/dev/`），經 `SceneRouter` 掛入；（4）改動不得觸碰 `domain/`／`services/` 邏輯——需要新資料介面時，在 PROGRESS.md 待辦記需求由 Claude 補 ViewModel；（5）改動後跑 `-Suite All` 確認灰盒與邏輯測試不受影響。
- 規格／數值變更：先改 `docs/game-architecture/` 對應章節＋§14 追溯矩陣，再改程式（見專案 `CLAUDE.md`）。
- **S5 接線完成記錄**：`RunCommandFactory` 已成為 `GenerateExpeditionMapCommand`／`RefreshShopCommand`／`SettleBattleResultCommand`／`EnterNodeEvent` 的唯一正式建構點，顯式注入非 null `relic_table` 與 pinned generation；`test_run_command_factory*.gd`、Run 灰盒與 10k soak 已鎖定此契約。
- **Retained run 契約**：一般 Camp writer 僅在 fresh load 明確 `RunStatus.NONE` 時可寫；decoded composition failure 以 expected run-id 明示棄置，`INCOMPATIBLE_PRESERVED` 則 boot failure 保留原始資料。正式 UI 不得提供繞過此流程的「直接重開」或刪檔按鈕。
