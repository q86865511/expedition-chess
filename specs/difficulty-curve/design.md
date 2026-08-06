# G2 difficulty-curve — Design

## 資料與介面

- `CombatConfigDef` 新增三個 per-act 敵方成長基點值（`domain/battle/catalog/
  battle_combat_config_rule.gd` 同步新增欄位並加入其 canonical 欄名清單，
  `battle_combat_config_rule.gd:45` 附近）。三值皆 TUNE：

  | 欄位 | 值 | 說明 |
  |---|---|---|
  | `act1_enemy_stat_bps` | 10000 | 恆等，act1 行為與現況 byte-identical |
  | `act2_enemy_stat_bps` | 13000 | TUNE |
  | `act3_enemy_stat_bps` | 16000 | TUNE |

  乘數只作用於 `health`、`attack`、`armor`、`magic_resist` 四個純量。
  `attack_speed_milli`／`move_speed_milli`／`attack_range_cells`／`start_mana`／
  `max_mana` 是節奏與可達性語意，縮放後會改變 tick 對齊與射程合法性，屬固定規則、
  不受 act 乘數影響——這是規格層的固定規則，只有 bps 值是 TUNE。
- `EncounterCompiler._build_unit_snapshot()`（`domain/battle/encounter/
  encounter_compiler.gd:214-234`）在既有 `_scaled(base, star_bps)` 之後再套一次
  `_scaled(value, act_bps)`；act bps 由 `catalog.try_combat_config_rule(
  &"config.combat_default")` 取得（與 `domain/battle/battle_rules_snapshot_builder.gd:24`
  同一慣例），act index 用 request 已有的 `EncounterCompileRequest.act_index`
  （`domain/battle/encounter/encounter_compile_request.gd:7`），因此 request schema
  不變。既有的 i32／值域守衛（`encounter_compiler.gd:465-473`）改套在最終縮放值上，
  取不到 config 或 act_index 不在 1–3 時回既有具名 `INPUT_INVALID`，不得 fallback。
- Boss encounter 映射在 `domain/run/economy/node_entry_service.gd:50-58`：取得
  `node_rule` 後，若 `node.node_kind == BOSS`，以 `node.act_index` 查固定表
  `{1: &"encounter.slice_boss_0", 2: &"encounter.slice_boss_1", 3: &"encounter.slice_boss_2"}`
  覆寫 `compile_request.encounter_id`；表外的 act 回既有
  `ENCOUNTER_COMPILE_FAILED`。`map_nodes/slice_boss.tres` 的 `generator_ref` 保留為
  act1 值，schema 不動。`slice_boss_1/2` 必須進 pinned 集合：`app/app_root.gd:2207`
  的 `_battle_root_ids()` 已 `append_array(content.encounter_ids)`，涵蓋全部五個
  encounter；balance driver 走 `application/balance/balance_production_case_driver.gd:267`
  的同一條 `RunCompositionSupport.required_battle_ids()`，兩端一致。
- Trait 階梯純內容：12 個 `TraitDef` 的三個 `TraitThresholdDef.effect_refs` 分別改指
  `effect.trait_<name>`／`_t2`／`_t3`。`domain/run/controller/combat/
  battle_setup_source_compiler.gd:164-179` 已取「最高達標階」的 `effect_ids`，
  程式零改動；`stacking` 維持 `replace`。
- 觀測性：`domain/balance/balance_bot_act_snapshot.gd` 增
  `battle_wins`／`battle_losses`／`elimination_node_id: StringName`（未淘汰為空），
  三者進 `is_valid()` 與 `canonical_token()`。
  `application/balance/balance_production_case_driver.gd:595` 附近的
  `reward.kind.%d` 佔位只能在 `content_id` 缺失時使用，且該路徑必須同時遞增既有
  opaque 計數（`domain/balance/balance_bot_report.gd:415`
  `_opaque_selected_id_count()`），不得以佔位字串冒充 stable ID。

## 敵方成長與遭遇編成（TUNE）

現有怪物數值為線性遞增（`monster_00` health 300／attack 20，每號 +10／+1，
`monster_11` 為 410／31）；`00/03/06/09` 為近戰（range 1），其餘為遠程（range 4）。
編成一律落在敵方半場 `logical_y` 4–7（玩家半場為 0–3，§5.1「玩家半場 32 個合法格」），
近戰置前排（y=5）、遠程置後排（y=7）、原有 spawn 保留在 y=6。下表全部為 TUNE：

| encounter | spawn_key | unit | ★ | (y, x) |
|---|---|---|---|---|
| `slice_normal` | `enemy_0` | `unit.slice_monster_00` | 1 | (6, 3) |
| `slice_normal` | `enemy_1` | `unit.slice_monster_01` | 1 | (7, 4) |
| `slice_elite` | `enemy_0` | `unit.slice_monster_01` | 1 | (6, 3) |
| `slice_elite` | `enemy_1` | `unit.slice_monster_06` | 1 | (5, 2) |
| `slice_elite` | `enemy_2` | `unit.slice_monster_07` | 1 | (7, 4) |
| `slice_boss_0` | `boss_0` | `unit.slice_monster_02` | 1 | (6, 3) |
| `slice_boss_0` | `add_0` | `unit.slice_monster_00` | 1 | (5, 2) |
| `slice_boss_0` | `add_1` | `unit.slice_monster_01` | 1 | (7, 4) |
| `slice_boss_1` | `boss_1` | `unit.slice_monster_03` | 2 | (6, 3) |
| `slice_boss_1` | `add_0` | `unit.slice_monster_06` | 1 | (5, 2) |
| `slice_boss_1` | `add_1` | `unit.slice_monster_07` | 1 | (5, 4) |
| `slice_boss_1` | `add_2` | `unit.slice_monster_08` | 1 | (7, 3) |
| `slice_boss_2` | `boss_2` | `unit.slice_monster_04` | 2 | (6, 3) |
| `slice_boss_2` | `add_0` | `unit.slice_monster_09` | 2 | (5, 2) |
| `slice_boss_2` | `add_1` | `unit.slice_monster_10` | 1 | (5, 4) |
| `slice_boss_2` | `add_2` | `unit.slice_monster_11` | 1 | (7, 2) |
| `slice_boss_2` | `add_3` | `unit.slice_monster_05` | 1 | (7, 4) |

- Boss 的 `logical_x` 由現況預設 0（`slice_boss_0`）／1／2 一律顯式改為 3 置中（TUNE）。
- `BossPhaseDef.source_spawn_key` 沿用 `boss_0/1/2`，隨從不參與階段轉換。
- 最大實體數為 5 敵 + 12 玩家 + summon，仍遠低於 `entity_budget = 64`。
- 星級 bps 沿用 `UnitDef` 既有 `star_scalings`（★2 = 18000、★3 = 32000）；
  act 乘數疊乘其上，例如 act3 的 `boss_2` health = `340 × 1.8 × 1.6 = 979`
  （逐步整數截斷：`340×18000/10000 = 612`，`612×16000/10000 = 979`）。
- tier-1 池重標：`content/packs/vertical_slice/units/slice_player_07.tres:49` 的
  `trait.faction_verdant` 改為 `trait.faction_shadow`。改後全庫 verdant 7→6、
  shadow 5→6，兩者皆仍滿足 2／4／6 三階。

## Trait 門檻階梯（TUNE）

tier1 為現值，tier2 = `round(tier1 × 1.75)`、tier3 = `round(tier1 × 2.5)`（四捨五入取整）。
新增 24 個 effect（`effect.trait_<name>_t2`／`_t3`，`content/packs/build_systems/effects/`）
與 48 個 loc key（每個 effect 各一組 `display_name_key`／`description_key`，
`zh_TW`／`en` 皆需）。全部數值為 TUNE：

> `required_count` 門檻是既有內容值，本片只改 `effect_refs`、不改門檻：一／二階皆為
> 2／4；第三階 `faction_shadow`／`role_mystic`／`role_sentinel`／`role_trickster`／
> `role_warden` 五者為 5、其餘七個 trait（`faction_arcane`／`faction_ember`／
> `faction_frost`／`faction_iron`／`faction_verdant`／`role_marksman`／`role_vanguard`）
> 為 6。下表「tier3 (6隻)」欄名沿用多數案例的字面值，實際部署人數以上述門檻為準
>（T11 F7 閉環）。

| trait | operation | tier1 (2隻) | tier2 (4隻) | tier3 (6隻) |
|---|---|---|---|---|
| `trait.faction_arcane` | GrantMana | 15 | 26 | 38 |
| `trait.faction_ember` | ModifyStat `attack` | 8 | 14 | 20 |
| `trait.faction_frost` | ModifyStat `magic_resist` | 8 | 14 | 20 |
| `trait.faction_iron` | ModifyStat `armor` | 8 | 14 | 20 |
| `trait.faction_shadow` | ModifyStat `attack_speed_milli` | 80 | 140 | 200 |
| `trait.faction_verdant` | Shield | 20 | 35 | 50 |
| `trait.role_marksman` | ModifyStat `attack` | 10 | 18 | 25 |
| `trait.role_mystic` | GrantMana | 10 | 18 | 25 |
| `trait.role_sentinel` | Shield | 10 | 18 | 25 |
| `trait.role_trickster` | ModifyStat `attack_speed_milli` | 100 | 175 | 250 |
| `trait.role_vanguard` | ModifyStat `armor` | 10 | 18 | 25 |
| `trait.role_warden` | ModifyStat `magic_resist` | 10 | 18 | 25 |

新 effect 除 `id`／loc key／operation amount 外，其餘欄位（`trigger = battle_start`、
`stacking = replace`、`max_stacks`、`duration_ticks`、`content_role`）逐字沿用同名 tier1
effect，避免 lifecycle 分類意外變動。

## 決定性與失敗政策

- act 乘數與 Boss 映射都是「查表 + 整數乘除」，不新增 RNG stream、不消耗任何既有
  stream 的 counter；`map`／`shop`／`reward`／`combat` 四流的 draw 次數與順序不變。
  同一 (manifest digest, encounter ID, node ID, act, depth, challenge) 仍唯一決定編譯結果，
  AC-050「只換玩家 build 不改遭遇」因此保持成立。
- 多敵編成的排序沿用 `encounter_compiler._unit_before()`（`logical_y → logical_x →
  instance ID`），格位不重疊即排序唯一；spawn_key 重複、格位碰撞、越界或
  `logical_y < 4` 一律由內容驗證與既有 setup 驗證器以具名錯誤 fail-closed。
- 新增 `CombatConfigDef` 欄位會改變 `BattleRulesSnapshot` 的 canonical bytes 與
  battle setup hash：這是一次性遷移，既有 battle golden 必須在 T01 同批重算並在
  commit 訊息中揭露；不得為了保住舊 golden 而把新欄位排除在 hash 之外。
- challenge 回鏈回復內容編排與 `content/validation/content_validator.gd:506-508`／
  `:541-551` 的三桶覆蓋 gate：run-layer 詞綴仍由 `RunModifierTable` 軌 B 的
  always-active 規則消費（meta-progression design §6.1／§6.3）。global source lifecycle
  的 RunOperation 禁令額外於 `content_validator.gd:1097-1101`（`_global_effect_lifecycle_valid`）
  收斂為 scoped 判準，與 `specs/combat-core/design.md:117／:236` 的作用域限定同步：
  challenge 來源僅在效果同時攜帶 `battle_operations`（因此會被 pin 進 `BattleSetup` 的
  `EffectSourceState`，即「雙軌」）時才拒絕再帶 `run_operations`；純 `run_operations`
  的 challenge 詞綴（ShopSurcharge／DrainExpeditionHp）不進 `BattleSetup`，不受此條
  限制，這是 `slice_challenge_affix_01/03` 能回鏈的前提。encounter_affix／enemy-side
  source（`source_side == &"enemy"`）的 RunOperation 禁令不受此範圍限縮，維持全面禁止
  ——目前 `encounter_affix` 的唯一呼叫點（`content_validator.gd:1039-1044`）固定傳
  `source_side = &"enemy"`，故落入 enemy-side 全面禁止分支；若未來新增非 enemy-side
  的 `encounter_affix` 呼叫點，需重新檢視此判準是否仍成立。既有兩處針對「純 run_operations challenge global source」的 `CONTENT_EFFECT_SOURCE_LIFECYCLE`
  負向斷言被反轉為 `assert_false`（此規則收斂後的有意結果，T11 F2 閉環，不是繞過）：
  `test_global_effect_source_lifecycle_validation.gd` 舊版 `test_global_hit_trigger_and_
  challenge_run_operation_are_rejected` 對純 run_operations 案例的 `assert_true` 由新增的
  `test_challenge_pure_run_operation_without_battle_operations_is_accepted`（:99-114）
  以 `assert_false` 取代，原函式改名為 `test_global_hit_trigger_and_challenge_dual_track_
  run_operation_are_rejected`（:63-93）並把其 run 案例改為雙軌效果，`assert_true` 對雙軌
  案例維持成立；`test_challenge_affix_operation_validation.gd:249-256`
  （`test_challenge_chain_modifier_with_non_always_claim_scope_is_rejected`）的純
  run_operations 案例同樣由 `assert_true` 改為 `assert_false`。
- 既有 3k screening #2 快照（`specs/balance-playtest/evidence-lock.md`）在本片之後
  一律不得作為回歸對照組；本片只證機制，不宣稱平衡結論。

## 觀測性與 per-act gate（收尾）

- `BALANCE_ACT_ELIMINATION_FLAT` 判準：統計全部 terminal 敗局的
  `elimination_node_id` 所屬 act；當 `cohort_seed_count >= 1000` 且敗局總數 > 0 且
  全部敗局落在同一 act 時輸出該 reason。`seed_count < 1000` 時不評估（screening
  以下樣本量的集中是統計噪音）。門檻 1000 為 TUNE。
- 兩份實作：`domain/balance/balance_bot_report.gd`（`gate_reasons()`，
  `:65-99` 區段）與 `tools/balance/run-sharded-cohort.ps1:397-454` 的鏡射區塊。
  一致性由 golden fixture 測試釘死：同一份 case JSON 分別餵兩側，比較 gate reason
  的**有序集合**逐字相同；任一側漏實作即紅。
- `BalanceBotActSnapshot` 的新欄位進 `canonical_token()`，因此 replay digest 會因
  本片改變——這是預期的一次性遷移，不是 drift；replay 一致性仍以「同一 candidate／
  strategy／seed 在本片後重跑 digest 相同」為判準。
