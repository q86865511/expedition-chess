# PVE 自走棋 Roguelite 主體架構規格：Stable ID、亂數與存檔

> 文件集入口：[game-architecture-spec.md](../game-architecture-spec.md)  
> 文件狀態：`v0.1 / Approved`
> 本檔範圍：第 9 章

---

<a id="section-9"></a>

## 9. Stable ID、亂數與存檔

### 9.1 Stable ID

格式：

- ASCII 小寫命名空間與 slug：`<category>.<slug>`。
- 合法 regex：`^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`。
- 範例：`unit.ember_squire`、`trait.ashen_oath`、`relic.travelers_lantern`。
- 顯示名稱、翻譯 key、檔名與 ID 彼此獨立。
- 發布後 ID 不得重用；刪除內容保留 tombstone，改名保留 alias migration。
- 執行期棋子／物品實例分別使用單局單調序號 ID（例如 `u_000000000000008e`、`it_0000000000000021`）；`next_unit_serial`／`next_item_serial` 只在建立實例的交易成功時遞增，不得以 Resource ID 代替或在單局內重用。

- **[REQ-DATA-003]** 所有存檔引用必須使用 stable ID；內容刪除或改名必須提供 alias 或 tombstone migration。

內容 stable ID regex 不套用到執行期 key。執行期冪等 key 使用 `RuntimeKeyCodec v1`。每個欄位先形成帶 type tag 的 canonical ASCII token，再依 tuple 順序編成「4-byte unsigned big-endian byte 長度＋token bytes」；第一欄固定為 `k:<kind>`。串接後計算完整 SHA-256，輸出 `<kind>_<64 lowercase hex>`。DTO 必須同時保存具型別可診斷 tuple，載入時重編碼並比對，不得只信任字串。

| Tag | Canonical token |
|---|---|
| `k` | key kind，`^[a-z][a-z0-9_]*$` |
| `e` | enum，`^[a-z][a-z0-9_]*$` |
| `s` | 已經 canonical 的 ASCII stable／runtime ID；非 ASCII 或空字串拒絕 |
| `h` | 固定長度 lowercase hex；`profile_id` 恰 32 字元 |
| `u` | unsigned 64-bit，恰 16 lowercase hex |
| `i` | schema 已限制範圍的非負整數，無正號、無前導零，零只寫 `0` |

type tag、冒號與值都是 token bytes 的一部分；數值不得依 locale、JSON number 或 GDScript 預設 `str()` 隱式轉換。

| Key | Canonical tuple |
|---|---|
| `profile_id` | 建立 profile 時由 OS CSPRNG 產生並保存的 16 bytes，表示為 32 lowercase hex；不進入 gameplay RNG |
| `run_id` | `[h:profile_id, u:next_run_serial]`；建立 run 與遞增 serial 在同一存檔交易 |
| `node_id` | `[s:run_id, i:act_index, e:node_kind, i:layer_index, i:slot_index]`；固定開場／休整／Boss 也使用不同 kind，不得跨幕重用模板 ID |
| `reservation_owner_id` | `[s:run_id, s:node_id, e:source_kind, s:stage_or_refresh_id, i:slot_index]` |
| `transaction_id` | `[s:run_id, s:node_id_or_camp, e:command_kind, u:next_transaction_serial]` |
| `effect_claim_key` | `[s:run_id, s:node_id, e:claim_scope, s:source_instance_or_slot, s:effect_id, i:operation_index]` |
| `settlement_receipt_id` | `[s:run_id]` |

Golden vector：

| Key | Canonical bytes（hex） | SHA-256／輸出 |
|---|---|---|
| run | `000000056b3a72756e00000022683a303031313232333334343535363637373838393961616262636364646565666600000012753a30303030303030303030303030303261` | `run_ec13b8c584b94fc6d1fb15852ee35573bc8e02739b120f218ce91c361e947cbb` |
| node | `000000066b3a6e6f646500000046733a72756e5f6563313362386335383462393466633664316662313538353265653335353733626338653032373339623132306632313863653931633336316539343763626200000003693a3200000006653a626f737300000003693a3500000003693a30` | `node_d94992320541276dfd384a614e280c0e1e0f804931a3ba6ec8e59fd467a033bc` |

`next_transaction_serial` 只在候選交易成功存檔時遞增；同一 pending command 的 retry 必須重用原 tuple。`source_instance_or_slot` 對棋子／裝備使用 run-global instance ID，對遺物使用槽位，對羈絆／指揮官使用 stable source ID，確保兩個外觀相同但不同來源的 operation 不碰撞。`income_claimed_node_ids` 必須保存上述 run-global node ID。內容驗證、存檔載入與 property test 必須拒絕重複 tuple、重複 key、digest 不符、serial 回退或同一 receipt 對應不同 payload；serial 溢位時拒絕建立新交易並顯示錯誤，不 wraparound。

- **[REQ-DATA-007]** 所有收入、reservation、交易、效果 claim 與局外結算的冪等識別必須由 RuntimeKeyCodec v1 的完整 canonical tuple 產生，且在載入與提交時驗證唯一性。

### 9.2 PRNG 契約

`rng_version=1` 固定使用 PCG-XSH-RR 64/32（PCG32）。下列常數、位元語意與派生程序都是版本契約，不得以「相近」的 PRNG 或 Godot `rand*` 取代：

| 名稱 | 十六進位／十進位 |
|---|---|
| `PCG_MULT` | `0x5851f42d4c957f2d` = `6364136223846793005` |
| `FNV_OFFSET` | `0xcbf29ce484222325` |
| `FNV_PRIME` | `0x00000100000001b3` |
| `SPLITMIX_GAMMA` | `0x9e3779b97f4a7c15` |
| `SPLITMIX_MUL1` | `0xbf58476d1ce4e5b9` |
| `SPLITMIX_MUL2` | `0x94d049bb133111eb` |
| `DERIVE_XOR` | `0xda3e39cb94b95bdb` |

所有 `u64` 運算都 modulo `2^64`；`u32` 都 modulo `2^32`；右移是補零的 logical shift。GDScript 實作使用兩個 32-bit limb 或等價的明確 unsigned helper，不得依賴負數算術右移。旋轉量只取低 5 bit。

```text
seed(init_state, init_seq):
  state = 0
  inc = ((init_seq << 1) | 1) mod 2^64
  next_u32()                         # warm-up，不計入公開 counter
  state = (state + init_state) mod 2^64
  next_u32()                         # warm-up，不計入公開 counter
  counter = 0

next_u32():
  old = state
  state = (old * PCG_MULT + inc) mod 2^64
  xorshifted = ((((old >>> 18) XOR old) >>> 27) AND 0xffffffff)
  rot = (old >>> 59) AND 31
  counter = (counter + 1) mod 2^64
  return rotr32(xorshifted, rot)

next_bounded(bound):
  require 1 <= bound <= 2^32
  threshold = (2^32 - bound) mod bound
  loop:
    raw = next_u32()
    if raw >= threshold: return raw mod bound

next_basis_points():
  return next_bounded(10000)
```

`next_bounded` 必須使用上述 rejection sampling；每次遭拒的 raw draw 仍增加 counter。`snapshot()` 回傳 `state`、奇數 `inc` 與 raw-draw `counter`。公開 `RngStream` 介面固定為 `next_u32()`、`next_bounded(bound)`、`next_basis_points()`、`snapshot()`。

命名 stream 的派生不消耗任何父 stream。`encode_tuple(stream_name, context_id)` 依參數順序，把每個 UTF-8 byte string 編成「4-byte unsigned big-endian 長度＋原始 bytes」後串接；不得使用含糊的分隔字元。接著：

```text
name_hash = fnv1a64(encode_tuple(stream_name, context_id))
init_state = splitmix64(run_seed XOR name_hash)
init_seq = splitmix64(init_state XOR DERIVE_XOR)
stream = pcg32.seed(init_state, init_seq)

fnv1a64(bytes):
  hash = FNV_OFFSET
  for byte in bytes:
    hash = ((hash XOR byte) * FNV_PRIME) mod 2^64
  return hash

splitmix64(input):
  z = (input + SPLITMIX_GAMMA) mod 2^64
  z = ((z XOR (z >>> 30)) * SPLITMIX_MUL1) mod 2^64
  z = ((z XOR (z >>> 27)) * SPLITMIX_MUL2) mod 2^64
  return z XOR (z >>> 31)
```

Golden vectors（輸出為 8 字元小寫 hex）：

| Fixture | 輸入 | 前六次 `next_u32()` |
|---|---|---|
| PCG reference | `init_state=000000000000002a`、`init_seq=0000000000000036` | `a15c02b7 7b47f409 ba1d3330 83d2f293 bfa4784b cbed606e` |
| Derived shop | `run_seed=000000000000002a`、`shop`、`act1.node3.refresh0` | `535f5c38 2cb08b6d 0319e6b0 845361ca a6219ffd ada38359` |

Derived shop fixture 的 tuple bytes 為 `0000000473686f7000000013616374312e6e6f6465332e7265667265736830`、`name_hash=83fb29e4f4dc9cff`、`init_state=00d680f2ffcc2419`、`init_seq=0a2c20ee2cf89fc5`，seed 後的 odd `inc=145841dc59f13f8b`；PCG reference 的 `inc=000000000000006d`。PCG reference 另依序呼叫 `next_bounded(10, 100, 10000, 7, 2^32)` 時，輸出必須是 `3, 97, 5824, 0, 3215226955`，raw-draw counter 為 `5`。

JSON 不得把任何持久 unsigned 64-bit 值存成 number。`run_seed`、每個 stream 的 `state`／`inc`／`counter`、Profile 的 `next_run_serial`，以及 RunState 的 `next_transaction_serial`／`next_unit_serial`／`next_item_serial` 都存成恰好 16 字元的小寫 hex string；解析時拒絕前綴、正負號、非 hex、大小寫不符或長度不符。執行期 `U64Bits` 以兩個 32-bit limb 表示，確保每一種欄位的 `0`、`2^53-1`、`2^53`、`2^53+1`、`2^63`、`2^64-1` 都能無損 round-trip。

不允許使用全域 `rand*`、時間、Object ID 或容器順序做遊戲亂數。

命名 stream：

| Stream | Context | 允許消費者 |
|---|---|---|
| map | act_id | MapService |
| shop | node_id＋refresh_index | ShopService |
| reward | node_id＋reward_stage | RewardService |
| combat | encounter_id＋battle_setup_hash | BattleSimulation |

不同 stream 不共用 counter；一個系統增加抽樣不得改變其他系統結果。Boss 重戰若戰鬥相關的 `BattleSetup` 未改變，使用同一 combat seed。只有棋盤、裝備、啟用羈絆、遺物、指揮官效果或遭遇修正改變時才建立新的 setup hash；單純刷新商店、買賣板凳棋子或開關 UI 不得改變戰鬥 seed。任何重戰都不得重抽遭遇或節點獎勵。

- **[REQ-RNG-001]** 地圖、商店、獎勵與戰鬥必須使用獨立命名亂數流，並保存足以重現結果的版本、seed 與 counter。
- **[REQ-RNG-002]** rng_version=1 必須逐位實作本節 PCG32、派生、bounded sampling 與 64-bit hex 持久化契約，並通過全部 golden／邊界 vectors。

### 9.3 BattleSetup 建立與 canonical hash

進入戰鬥節點時只建立並保存 `EncounterPreviewSnapshot`，其內容為 `encounter_id`、敵方單位與站位、有效 stats／技能／羈絆／詞綴／Boss 階段、`content_snapshot.manifest_digest` 與 preview schema version。UI 和之後的 BattleSetup 必須消費同一份 snapshot；不得在玩家按下開戰時重新生成敵人。

玩家按下「開戰」時固定依序處理：

1. 從 `RosterState`、等級、指揮官、羈絆、遺物及事件 modifier 推導當前人口。
2. 驗證人口、位置、重疊、裝備、instance reference、overflow 與其他 roster invariant；失敗即回傳完整錯誤並停留 PREPARE。
3. 從當下玩家狀態和既存 `EncounterPreviewSnapshot` 建立 `BattleSetupInputs`。
4. 以 `CanonicalBattleCodec v1` 序列化 inputs，計算 SHA-256 `battle_setup_hash`。
5. 以 `combat` stream 與 `context_id = encounter_id + \":\" + battle_setup_hash` 派生初始 combat RNG。
6. 組成 `BattleSetup(inputs, hash_version, battle_setup_hash, rng_version, combat_rng_snapshot)`，與 `ResolutionState.combat_pending` 原子存檔；成功後才進 COMBAT。

`BattleSetupInputs` 不得包含 combat seed、RNG state、setup hash、動畫、語系、音量、UI 狀態或時間。必備欄位依固定順序為：`setup_schema_version`、`content_version`、`manifest_digest`、`encounter_snapshot`、`player_units`、`player_active_traits`、`player_equipment_effects`、`player_relic_effects`、`commander_effects`、`challenge_modifiers`、`battle_rules`。敵方單位、站位、羈絆、詞綴與階段只存在 `encounter_snapshot`，不得再複製成第二權威欄位。雙方 snapshot 內的單位陣列各依 `side → logical_y → logical_x → instance_id` 排序；效果與 modifier 依 `priority → source_stable_id → effect_index` 排序；target ID 集合排序且去重。所有內容先解析成戰鬥所需的不可變數值快照，重播不再讀取可變 Resource。

`CanonicalBattleCodec v1` 使用無 BOM UTF-8、無多餘空白、上述固定欄位順序；整數採無前導零十進位（零只寫 `0`）、boolean 為 `true/false`、字串採 JSON escape、缺少的 optional 以規定的 `null` 或空 typed array 表示。禁止浮點數、NaN、Infinity、Dictionary 迭代順序與未定義欄位。SHA-256 輸出為 64 字元小寫 hex。任何 codec 或欄位語意改變都必須提高 `setup_schema_version` 或 `hash_version` 並更新 canonical fixture。

- **[REQ-DATA-005]** BattleSetup 必須在最終備戰狀態驗證後，依本節唯一 canonical codec 建立；setup hash 不得包含由自身派生的 seed，敵方資料不得偏離已提交 preview。

### 9.4 存檔根結構

主要存檔位於 `user://saves/save.json`，備份為 `save.backup.json`。

```json
{
  "schema_version": 1,
  "content_version": "slice-0.1",
  "app_version": "0.1.0",
  "rng_version": 1,
  "hash_version": 1,
  "saved_at_utc": "2026-07-13T00:00:00Z",
  "profile": {},
  "run": null
}
```

`run` 為 null 表示沒有進行中遠征。時間只供診斷，不得影響遊戲亂數或獎勵。

### 9.5 必要 RunState 欄位

- `run_id`、16-hex `run_seed`、`content_snapshot`、`next_transaction_serial`、`next_unit_serial`、`next_item_serial`。
- `commander_id`、`challenge_level`。
- `act_index`、`map_state`、`current_node_id`、`run_phase`。
- `expedition_hp`、`economy_state`、`unit_pool_state`、`roster_state`。
- `roster_state` 是棋盤、板凳、物品庫、`pending_item_overflow` 與五個遺物槽的唯一序列化權威；其他模組只能取得衍生唯讀 view。
- `cleared_normal_count`、`cleared_elite_count`、`defeated_boss_count`。
- `rng_stream_states`。
- `income_claimed_node_ids`、`loss_stipend_claimed_act_ids`。
- `reservation_owners` 與已提交 transaction／claim receipts。
- 唯一 `resolution_state` tagged union；不得另存互相獨立的 pending boolean 或重複 payload。

`ContentSnapshotState` 是純 DTO，不是 Resource，固定包含 `content_version`、排序且去重的 `enabled_content_ids`、`economy_config_id`、`reward_table_ids`、`map_node_def_ids`、`challenge_unlock_def_ids`、`meta_reward_table_id` 與 SHA-256 `manifest_digest`。manifest digest 由這些 ID 及其版本化內容摘要依 stable ID 排序後計算。遠征建立後 snapshot 不可變；熱重載、局外解鎖或目前 registry 的不同版本都不得改寫它。

`ResolutionState` 的 `kind` 只能是：

| kind | 唯一 payload | 合法來源／去向 |
|---|---|---|
| `idle` | 無 | MAP／PREPARE 或完成所有獎勵後 |
| `combat_pending` | `BattleSetup` | 開戰提交後；重播至 battle_result_pending |
| `battle_result_pending` | setup hash、`BattleResult` | 模擬完成後；原子套用戰果並轉 loss destination 或 reward_pending |
| `reward_pending` | `PendingRewardState` | 勝利候選或事件給予已提交；解決後轉下一 stage 或 idle |

`PendingRewardState` 固定具有 `node_id`、`stage_id`（`standard`、`relic` 或 `event_grant`）、`phase`（`choosing`、`unit_resolution`、`item_resolution`、`relic_resolution`、`ready_to_advance`）、`offers`、`reserved_copies`、nullable `selected_choice_id`、nullable `selected_unit_reservation` 與 `transaction_id`。同一時間只能有一個 active stage；菁英的 standard stage 完成且所有 subphase 解決後才原子建立 relic stage，Boss 直接建立 relic stage。事件的棋子／物品給予在選項本身先提交後建立單一 `event_grant` stage，沿用同一 overflow 與 reservation 規則。`RosterState.pending_item_overflow` 與這個 phase 一起驗證：只要 unit／item／relic 尚未解決，就不得建立下一 stage 或離場。不存在「兩組候選各自 pending」的表示法。

### 9.6 存檔時點

必須在下列狀態改變後存檔：

1. 建立或結束遠征。
2. 選擇節點並提交 `current_node_id` 與已生成的節點資料／`EncounterPreviewSnapshot`。
3. 結算節點收入。
4. 商店購買、出售、刷新、購買 XP。
5. 棋子升星、佈陣確認、鍛造、裝備、拆卸、遺物替換。
6. 事件、休整、寶藏或商人選擇提交。
7. `BattleSetup` 與 `resolution_state=combat_pending` 提交。
8. `BattleResult` 先以 `battle_result_pending` 提交，再以獨立交易扣除 HP、提交合法 run intents 並建立下一個 resolution。
9. 選擇獎勵與進入下一節點。
10. 局外解鎖或挑戰紀錄改變。

純視覺動作、tooltip、動畫進度與戰鬥中間 tick 不存檔。

- **[REQ-SAVE-004]** 所有資源消耗、不可逆選擇及隨機候選都必須依第 9.6 節時點先提交可恢復狀態，再顯示不可逆結果。

### 9.7 原子寫入

`SaveRepository.save()` 以 process-local mutex 序列化整個流程；同時來的請求只能排隊或回傳 `SaveBusy`，不得交錯寫檔。`save.tmp.json`、主檔、backup 與 rotation 檔都在同一目錄／filesystem。固定流程：

1. 在鎖內取得候選 `SaveRoot`，轉成 JSON 基本型別，執行 schema、範圍、union、stable ID、內容 snapshot 與 cross-ledger 驗證，計算診斷摘要。
2. 以 truncate 模式呼叫 `FileAccess.open()` 建立 `save.tmp.json`，要求回傳非 null 且 `FileAccess.get_open_error()==OK`；Godot 4.7 的 `store_buffer()` 必須回傳 `true`，並再檢查實例 `get_error()==OK`。`flush()`／`close()` 回傳 `void`：flush 後檢查 `get_error()==OK`，close 是否完整落盤則由下一步的長度、bytes、parse 與摘要讀回驗證，不得虛構 void API 的 Error 回傳值。
3. 重新開啟 tmp，讀到 EOF、解析、重建 DTO，再比較 schema、run ID、resolution kind、ledger 與摘要；任一差異立即失敗，尚未接觸主檔。
4. 先判定 committed copies。若有效 main 存在：把任何既有 backup 原子 rename 成 old（old 先 quarantine），再把 main 原子 rename 成 backup。若 main 缺失／無效但有效 backup 存在：先 quarantine 無效 main，**不得移動唯一 backup**。只有 main／backup 路徑都不存在時才視為首次存檔；只要任一路徑存在但有效 committed copy 為零（invalid-main-only、invalid-backup-only 或兩者皆 invalid），一律拒絕 save 並保留／隔離診斷證據。只有玩家明確確認建立新 profile，先封存這些檔後，才可另走首次存檔流程。
5. 將已驗證 tmp atomic rename 成 main。每次 rename 都檢查 `DirAccess` 回傳的 `Error`，失敗即停止；除首次存檔外，每次 mutation 後都重新確認 main 或 backup 至少有一份有效 committed copy。
6. 重新開啟主檔做完整驗證。成功後才可嘗試刪除 old rotation；刪除 Error 必須記錄但不使已驗證 main 失效。主檔驗證失敗時先把壞主檔 quarantine，再嘗試將有效 backup 原子復原為主檔；復原失敗仍保留原位 backup，回傳可見錯誤。
7. 釋放 mutex。只有 SaveResult 成功時，RunController 才可 swap canonical state。

除沒有舊進度的首次存檔外，在第 4–5 步的任何 crash 點，`save.json` 或 `save.backup.json` 至少有一份已提交有效檔；backup-only recovery 分支永遠不先移走 backup。不得直接覆寫唯一主檔。所有 quarantine 名稱可使用 UTC 時間與遞增序號，但該值只供診斷。

載入優先序固定為「有效 main > 有效 backup」。`save.tmp.json`、`save.backup.old.json` 與損毀檔一律先移入 quarantine 並保留，不得自動當作已提交進度；若 main 損毀但 backup 有效，載入 backup、顯示恢復訊息，並在保留原始損毀檔後才可重建 main。open、partial write、flush、close、tmp read-back、每次 rename、final read-back 與 restore 都必須有 fault-injection 測試。

### 9.8 Migration

- schema migration 必須逐版執行，例如 1→2→3，不得只支援最舊版直接跳最新版。
- content alias 在 schema migration 後、DTO 建立前處理。
- 無法解析的非必要已刪除內容使用 tombstone 的安全替代；影響當前棋子、遺物、指揮官或遭遇時，載入失敗並保留備份，不得猜測替代。
- migration 必須冪等：對已是最新版的存檔再執行不改變結果。
- `LoadResult` 分開回報 `profile_status` 與 `run_status`。若 profile 可 migration、但 active run 的 `ContentSnapshotState` 無法由已安裝內容版本完整解析，必須載入並保留 profile，將 run 標為 `incompatible_preserved`，保留原始檔且不得自動覆寫。
- 玩家可明確選擇放棄不相容 run；確認後先封存原始檔，再以相同 profile 與 `run=null` 寫入新主檔。不得因 run 損壞而重置局外貨幣、解鎖、圖鑑或 settlement receipts。

### 9.9 戰鬥與獎勵恢復

- 進戰前先保存 `ResolutionState.combat_pending`、完整 `BattleSetup`、combat stream state 與 setup hash。
- 崩潰或離開後載入時，以保存 setup 重播；不恢復至可重抽敵人或 seed 的狀態。
- 戰果先寫入 `ResolutionState.battle_result_pending`，再顯示勝負動畫。載入此狀態只可繼續同一戰果交易，不重跑戰鬥。
- 勝利時，戰果交易只套用第 8.10 節白名單內的 scalar `RunMutationProposal`，再建立第一個 `reward_pending`；候選先存檔再顯示。每個 stage 的 choice 先轉入需要的 unit／item／relic resolution subphase；全部解決後，菁英 standard 原子轉成 relic stage但保留 shop，普通戰才執行 final node-exit，Boss 的 relic stage 解決後才做 final node-exit 與幕結算。每次轉移都沿用 node ID 與唯一 transaction／claim receipt。
- 戰敗時丟棄 run effect intents；普通／菁英扣血後轉 idle 並前進，Boss 則確保當前 node ID 仍在 `income_claimed_node_ids`、轉 idle 且回到無收入 PREPARE。
- 遠征結算先以 `run_id` 查詢 Profile receipt；若不存在，計算 MetaRewardTableDef、更新貨幣／里程碑／挑戰、寫入 receipt 並清除 active run，全部在同一原子存檔。若 receipt 已存在，只顯示既有結算，不再次加值。
- 本作為離線單機，不承諾阻止玩家手動複製或修改存檔；但所有載入資料仍需範圍與引用驗證，避免崩潰或任意程式執行。

- **[REQ-SAVE-001]** 存檔必須是版本化 JSON，透過 tmp、讀回、原子替換與 backup 寫入。
- **[REQ-SAVE-002]** 戰鬥、獎勵、事件與 Boss 重戰恢復不得提供重抽、重領或重複收入窗口。
- **[REQ-SAVE-003]** 每個已發布 schema 與內容 ID 變更必須有自動 migration 測試及保留 fixture。
- **[REQ-DATA-004]** RosterState 必須是物品庫、overflow 與啟用遺物槽的唯一可變權威；任何頂層便利欄位只能是不可序列化的唯讀衍生值。
- **[REQ-SAVE-005]** 戰鬥與獎勵恢復狀態必須使用唯一 ResolutionState tagged union，並以單一 PendingRewardState 串行處理多階段獎勵。
- **[REQ-SAVE-006]** SaveRepository 必須序列化並驗證每次寫入、檢查所有檔案錯誤、按 main 優先規則恢復，且不得把 tmp 或損毀資料視為已提交進度。
- **[REQ-DATA-006]** ContentSnapshotState 必須是不可變純 DTO；active run 不相容時必須隔離 run 失敗並保留可用 ProfileState 與原始檔。

---

[← 技術架構](05-technical-architecture.md) · [返回文件集入口](../game-architecture-spec.md) · [像素呈現、UI 與無障礙 →](07-pixel-presentation-and-ui.md)
