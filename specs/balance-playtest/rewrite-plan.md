# balance-playtest 重寫方案（BP-IR-001～008 閉環）

> 撰於 2026-08-02。目的：關閉 `specs/balance-playtest/implementation-review.md` 記錄的 8 條
> blocking findings（雙審共同判定、程式碼層已第三方逐條驗證屬實），使 Git gate 可重審。
> 本文件自包含：實作者不需要先前對話脈絡，所有引用皆為 repo 內真實 檔案:行號（實查於 2026-08-02）。

---

## 0. 背景與問題總結

現行 `application/balance/balance_production_case_driver.gd` 是一個繞過正式鏈路的自製模擬器：

1. **BP-IR-001（CRITICAL）**：每 case 只跑 3 場「每幕代表戰」（`:72-90` 對每幕取
   `_first_combat_node()`），地圖實際是 3 幕 × 7 層 = 21 節點，其餘 18 節點未走訪。
   整個 `application/balance/` 對 `RunController`／`RunCommand`／settlement 零引用，
   driver 直接 `new MapService/ShopService/BattleSimulation`，違反 spec §8.5 / REQ-TECH-004
   的 copy-validate-save-swap 狀態擁有權。
2. **BP-IR-002（HIGH）**：`run_id = "balance_%s_%08d" % [strategy_id, seed_index]`（`:23`）
   把 strategy 混進 run_id，而 `MapService`（`domain/run/map_generation/map_service.gd:15-16`）
   與 ShopService 都拿 run_id 進 RNG context。同 seed 下三策略的地圖與商店是不同世界，
   跨策略比較不成立。
3. **BP-IR-003 之 bot 部分（HIGH）**：bot 整場只決策一次（`:53-55`），observation 硬編碼
   `(20, 3, 100, 1)`；無任何購買扣款／升級／裝備套用；`ending_gold=20`、`ending_hp=100`
   直接寫死（`:86-94`）。實測 30k artifact：90,000 戰全勝、economy／synergy 策略的 build_id
   100% 走 fallback。報告零平衡資訊。
4. **BP-IR-004（HIGH）**：gate 依賴 caller 自填 failure code，report 未強制負資源、死局、
   重複獎勵等 proof。
5. **BP-IR-005（HIGH）**：candidate_id 硬寫死 `&"balance.g2.rc1"`
   （`domain/balance/balance_tune_inventory.gd:14`），TUNE 改動時 digest 變、ID 不變；
   scanner 白名單漏 `cells`（實證：`content/packs/vertical_slice/effects/slice_challenge_affix_02.tres:12`）；
   失敗候選無 immutable 留存。
6. **BP-IR-006（HIGH）**：session report 收精確 `started_at_utc`（quasi-identifier）；
   `route_ids`/`build_summary` 只驗型別、path-like 值可通過（`playtest_session_report_codec_v1.gd:40-47`）；
   Boss retry 的 abandon 被壓成 failed。
7. **BP-IR-007（HIGH）**：測試只驗 preload，缺 full expedition／action apply／Boss retry／
   save-reload／三 terminal exactly-once 整合測試。
8. **BP-IR-008（HIGH）**：30k／All／soak／RC 四份證據未綁同一 source manifest。
   另 RC smoke 只有 2 行 boot log（`artifacts/rc/rc-smoke.log`；
   `tools/balance/package-rc.ps1:64-78` 只跑 `--headless --quit-after 5`）。

未編號 OPEN 項（一併處理）：export 未排除 `addons/gut/**` 且缺 PCK inventory 禁入清單；
route 聚合以 runtime node digest 產生 90,000 個低資訊 key。

**注意**：既有 `tests/runners/expedition_soak_runner.gd` **不是**全鏈路參考——它同樣沒碰
RunController（只 new 個別 service、用 fixture run 直呼 4 個 command 的 `apply_to`），
不要照抄它。正確的全鏈路參考見下節。

---

## 1. Part A — driver 重寫（關 BP-IR-001/002/003/004，主工作量）

### 1.1 設計原則

driver 改為「headless 驅動正式 RunController command chain 的 bot 玩家」。照抄以下三個
已存在的全鏈路範例的形狀，不要發明新鏈路：

- **步驟順序**：`scripts/dev/run/run_lab_session.gd:96-200`
  （generate_map → enter_node → refresh_shop → commit_board → start_combat →
  settle_battle → resolve_rewards）。
- **自建 composition（無 AppRoot）**：
  `tests/integration/meta_progression/test_run_lab_session_factory_chain.gd:31-113`。
- **headless SceneTree runner 內建 RunController＋FakeSaveStorage**：
  `tests/runners/expedition_runner.gd:86-170`（save 層照 `:128-129` 的
  `FakeSaveStorage` + `SaveRootFixture.create_repository`）。

### 1.2 composition 最小依賴（每 case 一套，彼此隔離）

1. `ContentRegistryService` + `ProjectContentBootstrap.new().run(registry)`
   （`app/content/project_content_bootstrap.gd:80`）→ 取
   `economy_catalog / relic_table / battle_catalog / forge_table / consumable_rules /
   receipt / content_snapshot`（`app/content/project_content_bootstrap_result.gd:9-18`）。
   bootstrap 可全部 case 共用一次載入的 immutable snapshot；per-case 只建 run 層物件。
2. `RunSession.new(profile, run, lease)`（`domain/run/session/run_session.gd:9`）；
   lease 走 `RunSessionFactory.create`（`:9-66`，需 registry receipt）。
3. `SaveRepository`：headless 用 `FakeSaveStorage`（in-memory，供 save-reload 測試重用）。
4. `RunStateValidator` + `RunSaveRootFactory("0.2.0", FixedRunCommitClock)`。
5. `RunController.new(...)` + `RunCommandFactory.new(economy_catalog, relic_table,
   battle_catalog, challenge_affix_effect_ids, commander_id, commander_population_bonus,
   forge_table, consumable_rules)`（`domain/run/controller/run_command_factory.gd:33-55`；
   `relic_table` 必填無預設）。
6. 戰鬥驅動：沿 `RunPresentationSession`（`presentation/run/run_presentation_session.gd:50-52`
   會自建 `CombatCoordinator`），用 `drive_current_combat_to_commit(step_limit)`（`:551`）；
   或等價地直接驅動 `CombatCoordinator.begin_or_resume/advance`
   （`services/combat/combat_coordinator.gd:38/:108`）到
   `RecordBattleResultCommand` dispatch（`:168-179`）。二擇一，選改動最小者，
   但 BattleSetup 必須經 `BattleSetupSourceCompiler.compile(roster_snapshot, battle_catalog,
   commander_passive_effect_ids)`（`domain/run/controller/combat/battle_setup_source_compiler.gd:10-31`）
   組出——這樣 roster／裝備／羈絆／遺物才會真的進戰鬥。

### 1.3 世界 cohort（關 BP-IR-002）

正式路徑的 run_id 由 `RunBootstrapService` 推導且呼叫端不可指定：
`run_key = build_run(profile_id, next_run_serial)` → `run_id = run_key.digest` →
`run_seed = digest 前 16 hex`（`domain/run/camp/run_bootstrap_service.gd:52-70`），
validator 強制 `run_id == run_key.digest`（`domain/run/run_state_validator.gd:103`）。

因此 cohort 共用的做法是：**per seed_index 固定同一組 `(profile_id, next_run_serial)`，
三策略各自在隔離的 FakeSaveStorage 沙盒裡用同一組輸入開局**——run_id／run_seed／
map／shop stream 完全相同，世界一致；策略差異只體現在 bot 下的 command 序列。
`profile_id` 由 seed_index 決定（例如 `balance_profile_%08d`），serial 固定 1。
**禁止**把 strategy 字串放進 profile_id、run_id、或任何 RNG context。
報告中記錄 cohort key = run_id（三策略同 case 必須相同，作為驗收斷言）。

### 1.4 bot 主迴圈（關 BP-IR-001/003）

每 case 的迴圈（全部經 `RunController.dispatch/transition`，不得直改 RunState）：

```
StartExpeditionCommand（domain/run/camp/start_expedition_command.gd:44-93）開局
generate_expedition_map_command()                    # factory :61
while phase != RESULTS:
    bot 依 map_snapshot() 選下一節點（策略決定路線）→ enter_node_event()   # :101
    if 開出 node choice → commit_node_choice_command / acknowledge_...     # :122/:133
    if 戰鬥節點:
        PREPARE 階段 bot 迴圈（依 economy_snapshot()/roster_snapshot()/shop offers 真實觀測）:
            refresh_shop_command() :64（reroll 就是它，沒有別的 reroll command）
            buy_offer_command(offer_id) :67 / buy_xp_command() :70 / sell_unit_command :73
            forge_equipment_command :76 / equip_item_command :84 / dismantle :90
            resolve_unit_overflow / resolve_item_overflow :181/:186
        commit_board_layout_command(board, bench) :213
        start_combat_event(BattleSetupSourceCompiler 的 sources) :107
        戰鬥驅動到 RecordBattleResultCommand 落地（1.2 第 6 點）
        settle_battle_result_command() :98
        REWARD 鏈：choose_reward :163 → resolve_unit/item/relic_reward :166/:169/:175
                   → advance_reward_command :178
        Boss 敗且 hp>0：策略決定重試（回 PREPARE）或 abandon_boss_retry_command() :202
    else:
        resolve_non_combat_node_command() :110（收入等結算）
terminal：settle_terminal_run_command() :208
```

（行號皆為 `domain/run/controller/run_command_factory.gd`。不存在的操作不要發明：
沒有獨立 unequip、沒有 skip-node。）

**bot observation 必須全部來自 controller 讀取投影**（`view_state`/`roster_snapshot`/
`map_snapshot`/`economy_snapshot`/`pending_reward_snapshot` 等，
`domain/run/controller/run_controller.gd:122-154`），刪除現行硬編碼 observation 與
固定分數候選（`balance_production_case_driver.gd:44-55`）。三種策略（tempo/economy/synergy）
保留 typed bot 介面，但決策函式的輸入輸出改綁真實 snapshot 與真實 command。
bot 決策必須是決定性的：只依 snapshot 內容＋策略規則，不得引入 Godot `rand*`
或時間（架構約定：gameplay entropy 只能來自 RngService 具名 stream）。

### 1.5 report proof（關 BP-IR-004）

報告欄位一律取自 settlement 後的真實狀態，禁止 caller 自填：

- `ending_gold`/`ending_hp`：`economy_snapshot()` 讀出（settlement 行為見
  `domain/run/economy/battle_settlement_service.gd:79-99/:134-180`）。
- per-case proof 欄位（進 report DTO 與 codec）：settlement receipt 數、
  reward exactly-once 證明（receipt digest 序列）、final phase、走訪節點數
  （必須 = 該 run 實際 route 長度，正常完整局為 21 或依 route 定義）、
  失敗時的 failure code 由 driver 依 controller 拒絕原因／終局狀態推導。
- gate 檢查（`domain/balance/balance_bot_report.gd:181-193` 的 `DOMINANCE_BPS` 等）
  改為從上述 proof 欄位重算，不信任輸入側統計。
- 負資源／死局是 domain validator 的職責；driver 對每次 dispatch 的失敗必須記錄
  （command、拒絕碼），不得吞掉。

### 1.6 效能與規模（明示決策點，不許無聲縮水）

完整 21-node × 真實戰鬥 × 30k case × 3 策略 = 90k 場完整遠征，成本遠高於現行 3 戰版。
實作順序：先讓 3k screening 跑通並量測單 case 平均耗時，把實測數字回報在
evidence-index；30k 是否維持原規模由使用者依耗時裁決。**不得自行降規模或抽樣後
仍宣稱 30k**（no silent caps）。

**已裁決（2026-08-02，使用者核可）**：canonical replay 改為 **5% 抽樣驗證**
（抽樣以決定性規則選 case——例如 seed_index % 20 == 0——不得用非決定性亂數；
報告明載「replay 驗證為 5% 抽樣」與抽中清單）。並行分片與最終 seed 規模
待正式量測數字回報後由使用者裁決，量測回報須含：單 case 平均耗時（含/不含 replay 分列）、
建議分片方案與預估總時長。

**已裁決（2026-08-02，預量測後）**：採 **8 分片**（本機 i5-13600K，14 實體核心／32GB，
資源充足），先跑 **24-case 並行校準**再啟動完整 3k。執行判準：
- 校準的單 case 平均耗時對比單程序基準 56.4 秒：**slowdown >30% → 降 4 分片**；
  **<10% 且有意願 → 可試 12 分片**（6P+8E 異質核心，實測為準）；其間維持 8。
- 分片切割必須是決定性的 seed_index 區間（例如 shard k 取 index % 8 == k），
  分片對照表與各分片 artifact 一併記入 evidence；全部分片必須綁同一 source freeze
  與 candidate digest。
- 3k 完成後，30k 是否維持原規模另行裁決（8 分片粗估約 62 小時，屆時附實測外推）。

---

## 2. Part B — candidate 版本化與 TUNE inventory（關 BP-IR-005）

1. `domain/balance/balance_tune_inventory.gd:14` 的 candidate_id 改為由 tune_digest 衍生：
   格式 `balance.g2.<tune_digest 前 12 hex>`（descriptor 已有 canonical tune_digest：
   `domain/balance/balance_candidate_descriptor.gd:70-85`）。任何 TUNE 值變動 → digest 變
   → ID 變，滿足 BP-REQ-001（`specs/balance-playtest/requirements.md:15-17`）。
2. 失敗候選 immutable 留存：每次產出 candidate descriptor 時，把 canonical JSON 落到
   `specs/balance-playtest/candidates/<candidate_id>.json`（append-only；已存在同名檔時
   必須逐 byte 相同，否則 fail）。若同一 tune candidate 在不同 pinned manifest 上重建
   （例如 fail-closed parser 修復使正式 content manifest 改變、但 TUNE entries 不變），
   flat archive 保持 immutable，後續 descriptor 只可追加至
   `candidates/revisions/<candidate_id>/<manifest_digest>.json`；既有 flat descriptor 必須可
   decode、candidate_id 與完整 tune_digest 相同且 manifest 不同才可分流。同 manifest 或
   無法 decode 的 byte conflict 仍 fail-closed，不得覆寫或刪除舊證據。
3. scanner 修正（`application/balance/balance_tune_source_scanner.gd`）：
   - `TUNE_FIELDS`（`:8-26`）補 `cells`。
   - `FIXED_FIELDS`（`:27-30`）與 descriptor 的 `FIXED_RULE_FIELDS`
     （`balance_candidate_descriptor.gd:6-10`）對齊為同一組（現況：scanner 有
     `overtime_interval_ticks` 缺 `basis_points`，descriptor 相反）——抽成單一共用常數表。
   - 新增 fail-closed 對帳：掃描範圍內 `.tres` 出現的任何數值欄位，必須屬於
     `TUNE_FIELDS ∪ FIXED_FIELDS ∪ 明示忽略清單`，否則 scanner 直接 fail
     （防止新增欄位靜默不入 digest）。忽略清單逐欄附一行理由。

---

## 3. Part C — session report 隱私與語意（關 BP-IR-006）

report DTO／codec：`application/balance/playtest_session_report.gd:7-17`、
`playtest_session_report_codec_v1.gd:4-8`（ALLOWED_KEYS 封閉集合維持不變，以下為欄位內修正）：

1. `started_at_utc`（`report.gd:12`；寫入點 `app/app_root.gd:2047`）降精度到**日期＋小時**
   （`YYYY-MM-DDTHH:00:00Z`），去除可關聯性；`duration_seconds` 保留。
2. `route_ids`/`build_summary` fail-closed 驗證（`codec_v1.gd:40-47`）：每個元素必須符合
   `^[a-z0-9_.]+$` 且以已知 prefix 開頭（依現有 stable-ID 慣例列舉）；含 `/`、`\`、`:`
   或超長（>128）一律拒收整份報告（拒收＝不落檔＋記 error code，不是靜默剔除欄位）。
3. outcome 語意：Boss retry 後放棄必須是獨立 outcome（如 `abandoned`），不得壓成
   `failed`；三 terminal（victory/failed/abandoned）在 codec 列舉驗證。
4. schema 有欄位語意變更 → `schema_version` 遞增，舊版報告讀取行為明確（拒讀或升級）。

---

## 4. Part D — 證據鏈重建（關 BP-IR-003 RC smoke／BP-IR-008，程式修完後才做）

1. **source manifest**：`tools/balance/package-rc.ps1` 增產 `source-manifest.json`：
   git commit SHA（工作樹必須 clean，dirty 直接 fail）、content_version、tune_digest、
   candidate_id、Godot 版本、產出時間。30k report、All/soak 證據、RC zip 的 `.sha256`
   旁都要放同一份（或內嵌同一 manifest digest），四份證據可互相對帳。
2. **RC 全鏈路 smoke**：新增腳本化 headless smoke（可仿 `tests/runners/` 慣例）：
   start → 存檔 → 重啟 load → 打到一種 terminal → abandon 路徑 → 驗證
   `user://playtest_reports` 產出的報告可 read-back 且欄位通過 codec 驗證。
   log 與報告樣本落 `artifacts/rc/`，取代現行 2 行 boot log。
3. **export 排除**：export preset 排除 `addons/gut/**`；產 PCK inventory 並比對禁入清單
   （gut、tests、specs、tools 不得入包），結果落 `artifacts/rc/`。
4. **重跑順序**：Part A~C 全綠 → commit 凍結 source → 3k screening（量測耗時、回報）→
   使用者裁決 30k 規模 → 30k → All（`tools/run-tests.ps1 -Suite All`）→
   ExpeditionSoak 10k → 重打 RC + 全鏈路 smoke → 更新 evidence-index.md →
   兩位 fresh reviewer 重審（gate 裁決要求，`implementation-review.md:45-48`）。

---

## 5. 測試要求（關 BP-IR-007）

新增整合測試（GUT，位置沿 `tests/unit/balance_playtest/` 與 `tests/integration/` 慣例）：

1. **full expedition smoke**：單 seed 三策略各跑完整局到 terminal，斷言：
   三策略 run_id 相同（cohort）；走訪節點數 = route 長度；final phase = RESULTS。
2. **action apply**：bot 每類 command（buy/buy_xp/sell/equip/forge/refresh）後，
   對應 snapshot 確實變化（gold 減少、roster 增減、equipment 綁定）。
3. **Boss retry**：敗於 Boss 且 hp>0 → 回 PREPARE 可重戰；abandon → outcome=abandoned。
4. **save-reload 等價**：局中任一點以 FakeSaveStorage 存檔重載，續跑結果與不中斷跑一致。
5. **三 terminal exactly-once**：victory/failed/abandoned 各一案例，settlement receipt
   恰好一次、無重複獎勵。
6. **回歸判準（防呆）**：3k screening 產出中，win rate 不得三策略皆 100%、
   build_id 不得 100% fallback、ending_gold 不得全數相同——任一成立即 gate fail
   （這三個正是舊 30k artifact 的病徵）。
7. 新測試依專案已知風險（GUT parse error 時靜默跳過、suite 仍綠）需做一次變異驗證
   確認測試真的有執行。

---

## 6. 約束與紅線

- 不得為遷就 driver 修改 `domain/run/` 正式鏈路的行為；若發現正式鏈路真 bug，
  停下回報，不自行改。
- 全部決定性亂數走 `RngService` 具名 stream；禁 Godot `rand*`／時間／Object ID。
- JSON `Dictionary` 只能存在於 codec 邊界；domain API 用具名型別。
- 不 commit／push；驗證暫存檔寫 session scratchpad，不落專案目錄
  （evidence 產物除外，落 `artifacts/` 與 `specs/balance-playtest/`）。
- 驗證指令：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run-tests.ps1 -Suite All`
  （快速 gate）；balance 相關可先 `-Suite Gut -TestPath res://tests/unit/balance_playtest`。
- Godot 執行檔由 `GODOT_BIN` 環境變數傳入，不得把本機絕對路徑寫進 repo。

## 附錄 A — 已裁決阻擋案：production content `mode="flat"` 修正（2026-08-02 授權）

**背景**：driver 走正式鏈路打 Act 1 Boss 時被 `StartCombatEvent` 拒：
`BATTLE_INPUT_INVALID field=battle_rules.effect_rules.payload`（`effect.slice_affix_00/01`）。
診斷結論：production content 真 bug，非 driver 誤用；AppRoot 正式遊戲打 Boss/Elite 同炸。

**病因**：`ModifyStatOperationDef.mode` 寫成 `&"flat"`，但 canonical 枚舉只接受
`add`/`multiply_bps`（`domain/battle/battle_setup_inputs_validator.gd:501-505`、
`domain/battle/effects/effect_resolver.gd:217`、spec `specs/combat-core/design.md:264`）。
`"flat"` 是 damage/heal 的 `scaling` 欄位合法值（validator `:489/:494`），作者混用了欄位。
中間無任何 flat→add 轉譯（`content/registry/content_definition_compiler.gd:259` 原樣寫入、
`domain/battle/catalog/battle_rule_catalog_builder.gd:357-364` 原樣讀出）。
守門員缺席：`content/validation/content_validator.gd:955-957` 對 mode 只驗非空、不驗枚舉。

**授權修正範圍（僅此四項，不得擴大）**：

1. **content 批次修正**：全 repo 50 個 .tres 的 `ModifyStatOperationDef` 之
   `mode = &"flat"` → `&"add"`（build_systems 21 effects + 21 equipment；vertical_slice
   `slice_affix_00..05`、`slice_challenge_affix_00/04`、`slice_commander_passive_02`）。
   先以精確 grep 產出完整目標清單再逐一改；**只改 modify_stat operation 的 `mode` 欄位，
   damage/heal 的 `scaling = &"flat"` 是合法值，不得誤改**。語意不變（flat 加值＝add），
   不需改 spec 與 §14 矩陣。
2. **validator 補枚舉**：`content_validator.gd:955-957` 對 `ModifyStatOperationDef.mode`
   加白名單 `[&"add", &"multiply_bps"]`（`multiply_bps` 依 battle 層既有界限同步驗 0..100000，
   以 `battle_setup_inputs_validator.gd:501-505` 附近的規則為準）。
3. **fixture 對齊**：`tests/fixtures/content/synthetic_content_fixture.gd` 與
   `tests/integration/meta_progression/test_challenge_affix_operation_validation.gd:295` 等
   使用 `mode = &"flat"` 的測試素材改為合法值；若該處是刻意的負面案例，改為斷言
   「flat 被 validator 拒絕」。
4. **守門測試**：新增一條整合測試——用真實 pack 的 boss/elite encounter
   （如 `encounter.slice_boss_0`）組 BattleSetup 並通過 `BattleSetupInputsValidator`，
   確保 content 與 battle 兩層枚舉不再各說各話。

**連帶影響（預期，不是錯誤）**：content 變更會改變 content_version／manifest／tune 相關
digest 與（Part B 完成後的）candidate_id；30k 等證據本就要在修完後全部重跑，順序不變。
修正完成後 driver 應能通過 Act 1 Boss，繼續完整 21-node 驗證。

**紅線**：仍不得修改 `domain/run/`、`domain/battle/` 的行為邏輯；本附錄只授權
content .tres 值域修正、content validator 補枚舉、fixture 對齊與新增測試。

## 附錄 B — 已裁決阻擋案二：global source effect lifecycle 違規修正（2026-08-02 授權，含使用者四項設計裁決）

**背景**：附錄 A 完成後，driver 於 Boss 第 1 tick 穩定失敗
`BATTLE_EFFECT_FAILED → EFFECT_OPERATION_INVALID`。診斷：28 個 effect 違反 global source
lifecycle 規則（`domain/battle/effects/effect_resolver.gd:106-142`、spec
`specs/combat-core/design.md:236`）。附錄 A 的計數以 Codex 實測為準（51 檔/66 處），
文件先前寫 50 為計數誤差。

**關鍵事實（實作時以此為準）**：
- global source categories＝`challenge/commander/relic/trait/encounter_affix`
  （`effect_resolver.gd:18-20`）；`unit/equipment` 為 unit-scoped，其 `target=self` 合法，不改。
- global 允許矩陣：trigger 僅 `battle_start/periodic/battle_end`（:125）；battle_operations
  禁 `move/summon`、禁 `scaling=attack`、禁 `target∈[self,target]`（:139-142）；conditions
  僅 `max_uses_per_battle`（:136-138）；`challenge|encounter_affix|enemy-side` 連
  run_operations 也禁（:129-132）。
- **陣營語意**：`all_allies/all_enemies` 相對 **source_side**（:395）。encounter affix 的
  source_side＝enemy（`domain/battle/encounter/encounter_compiler.gd:359-360`），故
  affix 的 `self→all_allies` ＝加成敵方全體；relic/trait/commander source_side＝player，
  `self→all_allies` ＝加成玩家全隊。
- modify_stat 合法 stat 全集：`attack/armor/magic_resist/attack_speed_milli/move_speed_milli`
  （:216）；damage 合法 damage_type：`physical/magical/true`（:206）。

**授權修正範圍**：

1. **`self→all_allies` 批次修正**（語意見上述陣營規則）：
   `slice_affix_00..05`（6）、`slice_challenge_affix_00/04`（2）、`relic_ember_ward`、
   `slice_commander_passive_02`、以及【使用者裁決：全隊 all_allies】12 個 trait
   （`trait_faction_{arcane,ember,frost,iron,shadow,verdant}`、
   `trait_role_{marksman,mystic,sentinel,trickster,vanguard,warden}`）。
2. **非法 stat 映射**【使用者裁決：依映射表】，全部數值維持原量級並確保標 TUNE：
   - `health` → `shield` 操作（battle_start、等值護盾）：`relic_iron_will`(+40)、
     `trait_faction_verdant`、`trait_role_sentinel`。
   - `max_mana` → `grant_mana` 操作（battle_start）：`trait_faction_arcane`、`trait_role_mystic`。
   - `attack_speed` → `attack_speed_milli`（數值×10 為暫定換算）：`trait_faction_shadow`、
     `trait_role_trickster`、`relic_shadow_veil`(12→120)。
   - **延伸（2026-08-02 追加授權）**：三個漏列的 unit-scoped equipment effect 適用同一
     映射表，`target=self` 維持不變（unit-scoped 合法）、trigger 維持 `battle_start`、標 TUNE：
     `effect.equip_arcane`（max_mana+10 → grant_mana 10）、
     `effect.equip_shadow`（attack_speed+5 → attack_speed_milli 50）、
     `effect.equip_verdant`（health+20 → shield 20）。
3. **`relic_frost_edge` 改寫**【使用者裁決：改寫】：改為 `battle_start` + `all_allies` +
   `modify_stat attack`（數值取與原 proc 期望值相近的保守值，標 TUNE）；原 hit trigger／
   attack scaling／target=target／`magic` damage_type 全部移除。同步更新
   `content/packs/build_systems/README.md:57`（原文稱其為 on-hit proc 示範——該示範
   從未合法執行過）。
4. **`slice_challenge_affix_01/02/03` 移出 challenge 鏈**【使用者裁決：移出＋立 spec issue】：
   自 challenge unlock 的 modifier_refs 移除（balance 跑 challenge level 0 不受影響）。
   若 `content/validation/content_validator.gd:500-501` 的「challenge 鏈須覆蓋
   ShopSurcharge/DrainExpeditionHp 桶」檢查因此失敗——該檢查正是矛盾對的一半——授權將其
   調整為引用 spec issue 的暫緩檢查（附註釋指向 spec-issues.md），不得靜默刪除。
5. **spec issue 落檔**：新建 `specs/balance-playtest/spec-issues.md`，記錄
   (a) challenge run-op 矛盾（content_validator.gd:500-501 要求 vs combat-core §236 禁
   enemy-side run intent；正解方向為 run 層分流，`domain/run/economy/node_entry_service.gd:65`
   未分流）；(b) move 型詞綴（slice_challenge_affix_02）在現行 global 規則下不可表達；
   (c) `reachable_nodes()` 語意為拓撲可達而非當前可進入（driver 已以 frontier 選擇繞過）。
   這些屬未來規格修訂議題，本輪不實作。
6. **ContentValidator source-lifecycle fail-closed**：以反向引用圖判定 source kind
   （`RelicDef.effect_refs`(battle)、`TraitDef.thresholds[].effect_refs`、
   `CommanderDef.passive_effect_refs`、`EncounterDef.affix_refs`、
   `ChallengeUnlock.modifier_refs`；同型走訪已存在於 `content_validator.gd:401-435,465-470,
   510-524,1121-1124`），套上述允許矩陣；並補 `stat`（:216 全集）、`damage_type`（:206）、
   `target` 的枚舉白名單。spec §236 本要求 validator 拒絕非法組合，此為機械對齊。
7. **production guard 升級**：由「只驗 setup schema」升級為至少實際執行首個 battle tick
   （驅動 CombatCoordinator 走到第一次 EffectResolver 生效），用真實 pack 的 boss encounter。

**連帶影響（預期）**：content_version／manifest／tune digest／candidate_id 再變一輪；
證據重跑順序不變（Part D）。修正完成後 driver 應能打穿 Boss 續走完整 21-node。

**紅線**：`domain/run/`、`domain/battle/` 行為邏輯仍不得動（第 4 點的 validator 調整屬
content 層檢查、第 6/7 點屬 validator/測試側，均不在紅線內）。NUL 警告
（`domain/run/run_state_validator.gd:848/:868` 的 `String.chr(0)` 分隔符）已另立獨立任務，
本輪不處理、不繞過。

## 附錄 C — 3k screening #1 FAIL 的修正方案（2026-08-03，依報告分析裁定）

**背景**：首輪 3k（candidate `balance.g2.5e5e8c4e9b70`、freeze `fc99389f…`）結果
3000/3000 terminal、0 failure、150/150 replay 零 drift——儀器有效；gate FAIL 兩條：
`BALANCE_ECONOMY_WIN_SAMPLE_LOW`（economy 0/1000 勝）與
`BALANCE_BUILD_SELECTION_DOMINANCE`（arcane 42.83% 超次名 23.97pp）。
報告分析確認兩條 FAIL 的根因都在 driver/bot 儀器層，另有三項真平衡發現。

### C1 — P0：driver/bot 修正（gate FAIL 的直接原因，非 TUNE）

1. **economy bot 評分退化修正**（`application/balance/balance_production_case_driver.gd:370-401`；
   評分機制 `domain/balance/balance_bot_strategy.gd:34-42` 不動）：現況 HOLD 的 economy
   總分 630 恆高於任何 BUY_UNIT（≤285），1000 局購買次數全為 0、空板打全程。
   修正原則：**場上單位數 < economy.level 時 HOLD 候選不得勝出**（例如該情況下
   HOLD 的 E 分降為 0，或 BUY_UNIT 加「空位補償」分），使 economy bot 至少鋪滿
   可上場數，其「經濟性」體現在偏好 BUY_XP／少 reroll／利息斷點持幣，而非不玩。
   修正後跑 24-case 冒煙確認 economy 購買次數 > 0 且有非零勝場再進全量。
2. **Boss retry 政策修正**（`:155-161`）：現況無條件 `ABANDON_BOSS_RETRY`，但正式規則
   是 Boss 敗且 HP>0 → 回 PREPARE 可重打（`battle_settlement_service.gd:170-172`）。
   改為**HP>0 即重打**（重打前允許再走一輪 shop 動作），直到勝或 HP 耗盡——
   與真實玩家行為對齊，消除系統性低估。
3. **build_id 歸因修正**（`:643-665`）：現況「roster 最多 trait、平手取字典序最小」
   → arcane（字典序最小）吸走全部平手與空板 fallback。改為：僅計「達到啟動門檻
   （≥2 隻同 faction）」的 faction trait；無任何達標者記 `build.none`；平手以
   單位數多者優先、再平手以 run_id 決定性擾動選取（不得引入非決定性亂數）。

### C2 — P1：TUNE 調整（真平衡訊號，本輪一併改）

4. **verdant trait 效果下修**：`content/packs/build_systems/effects/trait_faction_verdant.tres:12`
   shield 30 → **20**。依據：verdant 勝率 60.6%（tempo/synergy 各 61.0/60.1），
   其餘陣營 43–49%；shield 30 ≈ tier1 單位 500 HP 的 6% 全隊直接生存值，
   而 ember/frost/iron 的 +8 單項屬性約 2–4% 戰力。目標把 verdant 壓回 ~50–53%。
5. **商店掉率表啟用高階單位**：`content/packs/vertical_slice/economy_configs/slice_default.tres:32-75`
   現況 9 級全 `[10000,0,0,0,0]`（tier 2–5 的 22 隻單位從未入池）。改為階梯：
   lv1–2 `[10000,0,0,0,0]`、lv3–4 `[7500,2500,0,0,0]`、lv5–6 `[5500,3000,1500,0,0]`、
   lv7–8 `[3500,3500,2000,1000,0]`、lv9 `[2500,3000,2500,1500,500]`（暫定值，標 TUNE）。
   同時解三件事：22 隻單位進入平衡樣本、金幣有天然去向（勝者現況 med 99 觸頂）、
   買 XP 策略產生差異化。並在該區段補 TUNE 註記。

### C3 — P2：記錄為 spec issue，本輪不實作

追加至 `specs/balance-playtest/spec-issues.md`：
- **難度曲線癱瘓（機制缺失）**：三幕共用同一 boss/normal/elite encounter
  （`slice_boss_1/2` 已存在但全庫零引用；`map_nodes/slice_boss.tres:8-9` 只指
  `encounter.slice_boss_0`）；敵方數值不隨 act 縮放（`encounter_compiler.gd:214-233`
  僅 star_scaling）；每 encounter 僅 1 隻敵人。後果：敗局 100% 集中於
  `route.act1.layer6.boss`，過 Act1 後條件勝率 100%（synergy 勝者全數滿血通關）。
  修復需 map/encounter 機制與內容擴充，屬後續切片。
- **trait 門檻無階梯**：門檻 2/4/6 三段指向同一 effect 且 `stacking=replace`，
  2 隻與 6 隻效果相同；階梯化需新增分段 effect 內容。
- **runner 可觀測性缺口**：per-case 無逐幕 gold/HP/roster 規模、單位 ID 皆為不透明
  雜湊（`content_selection_counts` 99.7% 為 `reservation_owner_<hash>`），
  下輪分析前建議 driver 增補 per-act 快照與 stable_id 對照表（driver 端小改，可隨 C1 做）。

### C4a — smoke 後裁決（2026-08-03 補充）

- C1/C2 五項核驗全數落地（含 build_id 平手的 run_id 決定性選取、Boss retry 的
  限次＋扣血雙重終止防護），smoke 24/24 terminal、economy 恢復購買與勝場。核可。
- **build.none 未出現於自然樣本＝通過**：bot 每局購買 10+ 隻，湊不到任一 faction
  2 隻的情況在自然樣本中本就近乎不可能；該分支已有決定性單元測試覆蓋即可。
- `domain/run/controller/run_commit_clock.gd` 新增 `now_unix()`（+3 行）：附錄 C 未列名，
  裁定為**可接受的加法式儀器支援**（無行為變更，配合 balance 的 fixed clock）；
  最終雙審時須在變更說明中列明。
- **分片數改用吞吐量比較決定，取代 slowdown% 判準**【使用者裁決：測 4／8／12 三組】：
  修正後單 case 工作量已變（Boss 重打、更多購買），對舊 56.4 秒基準算 slowdown 無意義；
  目標本來就是總 wall time 最小。做法：4、8、12 分片各跑一輪 24-case（同一組 seed、
  同一 source freeze），比較「每小時完成 case 數」（總 case ÷ 總 wall time），
  三輪皆記入 artifact（含各分片 per-case 耗時，供觀察 E-core 異質性）。
  不需要重測單程序基準。若 12 分片勝出但領先 8 分片不足 5%，取 8
  （留 CPU 餘裕給系統與 coordinator）。
  **硬停點（使用者裁決）**：吞吐量測試完成後停下回報三組數字與建議，
  **不得自行啟動 3k #2**；由使用者確認分片數後才啟動。
  **已裁決（2026-08-03）**：實測 4/8/12/16/24 五組，24 最快（308.6 cases/h）但需改
  runner 分片上限；使用者裁決 **3k #2 用 12 分片**（工具零改動、隔夜可完成），
  24 分片留待 30k 階段連同 runner 上限修改一併啟用（屆時以 3k #2 的 12 分片
  實測為對照組，驗證 24 分片長時間熱節流表現）。

### C4 — 重跑與驗收

- C1+C2 完成 → 全套 targeted GUT 綠 → 重新 source freeze → 24-case 冒煙
  （驗 economy 購買>0、有勝場、build.none 歸因出現）→ 3k screening #2（同 1000 seeds、
  8 分片、5% replay）。
- screening #2 的 gate 判準不變；此外人工檢核：economy 勝場 ≥50、dominance ≤20pp、
  verdant 勝率回落、tier2+ 單位出現於選取樣本。
- 通過後才進入 30k 規模裁決。TUNE 變更 → tune_digest／candidate_id 更新為新值，
  舊 candidate JSON 依 Part B 規則 immutable 留存。

## 附錄 D — Phase 0 收尾裁決（2026-08-04，使用者裁決）

**背景**：3k screening #2（candidate `balance.g2.7d47fada8091`、12 分片、10.1 小時）
gate PASS：3,000/3,000 terminal、0 failure、150/150 replay 零 drift、economy 1,000 勝、
dominance 15.8pp。使用者裁決改走「先修機制、再平衡輪迴」路線（`specs/g2-roadmap.md` §9）。

**裁決內容**：

1. **大樣本統計（10k/30k）延後至 Phase 2** 平衡收斂後執行，規模與 runner 分片上限
   16→24 屆時裁決。本切片以 3k #2 作 screening 證據收尾；roadmap §6.3 已同步修訂
   （大樣本與「三條決策路線穩定通關」移入 §6.3b）。
2. **C4 流程終點修訂**：原「通過後進入 30k 規模裁決」改為「收尾證據完備後交兩位
   fresh reviewer 重審」；tasks.md T08 的大樣本 final 項按本裁決記為「延後至 Phase 2」，
   不視為未完成。
3. **Phase 0 收尾 checklist**（執行順序）：
   - tier2+ 單位入樣補證（3k #2 報告無直接欄位，自 per-case 資料補確認）。
   - Part D 證據鏈：RC 重打包、全鏈路 smoke、source manifest、export 排除與
     PCK inventory（依第 4 節）。
   - NUL 修正合入（獨立任務，log 體積 GB→MB 級）。
   - 文件回寫（PROGRESS、HANDOFF、evidence-index、implementation-slices）。
   - 兩位獨立 fresh reviewer 重審 → 使用者確認 → commit／PR／merge。

**留檔訊號（Phase 2 迭代起點，非本切片 blocker）**：economy 100% 全勝
（XP 性價比壓倒性）、tempo/synergy `buy_xp_count=0`（bot 評分表不選 XP）、
verdant 77% 居首、「過 Act 1 即必勝」依舊（BP-SI-004）、shadow build 0.16%（池構成）。

## 7. 完成定義（對照 gate 重審）

- BP-IR-001～008 逐條有對應變更與證據；`evidence-index.md` 逐 AC 更新。
- 第 5 節測試全綠、fresh All 全綠、10k ExpeditionSoak 0 failures（重跑後數字）。
- 30k（或使用者裁決後的規模）artifact 的統計不再呈現「全勝／全 fallback／恆定資源」病徵。
- 四份證據綁同一 source manifest；RC 全鏈路 smoke 證據存在。
- 交由兩位 fresh implementation reviewer 重審後，才可宣稱切片完成。
