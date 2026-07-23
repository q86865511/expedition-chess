# vertical_slice 內容 pack

> 對應 `specs/build-systems/design.md` §7、任務 T09。與 `content/packs/build_systems/`
> 合併後構成 `ContentValidator.validate()` 要求的完整 manifest（32 棋子/敵人/指揮官/節點/
> 經濟/獎勵/戰鬥 config），讓 manifest 可通過驗證、可 pin digest 進 canonical snapshot、
> Build Lab（T11）可實跑。**本 pack 全部數值皆為 TUNE 佔位，非最終平衡**——最終棋子/敵人
> 授權屬下游 content-completion 橫切（SCOPE-002），不在本片範圍。

## 佈局慣例

沿用 `content/packs/build_systems/README.md` 的慣例：
`content/packs/<pack_name>/<category>/<short_id>.tres`，`<category>` 對應
`ContentDefinition.category_name()` 的複數形式。本 pack 的 stable id 一律加
`slice_` 前綴（`config.combat_default` 除外——該 id 由驗證器硬性要求固定值），
避免與 `build_systems` 或任何測試 fixture 的 id 撞名。

## 內容清單

| Category | 數量 | 說明 |
|---|---:|---|
| `units/` | 44 | 32 位玩家棋（`unit.slice_player_*`，cost_tier 分布 10/8/6/5/3，恰 4 隻三標籤）＋12 隻 monster（`unit.slice_monster_*`） |
| `commanders/` | 3 | `commander.slice_c0/c1/c2`，各帶 1 張起始棋、`passive_effect_refs` 指向共用被動效果 |
| `encounters/` | 5 | `encounter.slice_normal`／`slice_elite`／`slice_boss_0..2`（3 Boss，各 1 phase） |
| `map_nodes/` | 18 | 6 種固定節點（normal/elite/merchant/rest/treasure/boss 各 1）＋12 個 event 節點，`generator_ref` 各不相同；normal／elite 節點數相等（W2-F6 規則） |
| `unlocks/` | 7 | `unlock.slice_base_profile`（3 位起始棋，共享 `trait.faction_arcane`／`trait.role_vanguard`，滿足門檻可達性）＋6 級 challenge 鏈 |
| `economy_configs/` | 1 | `economy.slice_default`：shop_odds_by_level（level 1-9）、pool_copies_by_tier（tier 1-5 皆 >=9） |
| `combat_configs/` | 1 | `config.combat_default`：全部欄位採用 `CombatConfigDef` 預設值（固定規則與驗證器要求的精確值一致） |
| `reward_tables/` | 2 | `reward_table.slice_standard`（gold/heal，涵蓋 standard／event 兩種 fallback）、`reward_table.slice_relic`（指向 `build_systems` 的 `relic.ember_ward`） |
| `effects/` | 19 | 6 個 elite_affix（`effect.slice_affix_*`）＋12 個 event generator 佔位（`effect.slice_event_gen_*`）＋1 個指揮官被動（`effect.slice_commander_passive`） |

## 設計慣例（供後續擴充參考）

- **與 build_systems 的耦合點**：event 節點之一（`map_node.slice_event_00`）示範完整
  的容量類 run_operations（`ModifyUnitPoolOperationDef`／`GrantItemOperationDef`
  指向 `build_systems` 的 `consumable.dismantle_kit`／`GrantRelicOperationDef` 指向
  `relic.ember_ward`／`PopulationSourceOperationDef`），且 `reward_table.slice_relic`
  同樣引用 `relic.ember_ward`——示範兩個 pack 合併驗證時的跨 pack 參照。
- **base_profile 門檻可達性**：`unlock.slice_base_profile` 選了 index 0/6/12 三隻棋，
  三者的 `index % 6` 相同（皆為 0），共享 `trait.faction_arcane`／`trait.role_vanguard`，
  滿足 `build_systems` 該 trait 門檻表第一階 `required_count = 2`。
- **NORMAL/ELITE 節點規則筆數對等**：固定節點各 1 個 normal／1 個 elite，滿足
  `ContentValidator._validate_minimum_counts_and_nodes()` 的 `CONTENT_MAP_NODE_RULE_COUNT_PARITY`
  規則（MapService 覆寫 kind 時 RNG 消耗量須一致）。
- **人口/entity 壓力**：本 pack 不含任何 `AbilityDef`／召喚技能，`summon` 相關數值皆為 0；
  `base_population_cap` 由呼叫端的 `ContentValidationInput` 傳入（測試取 9），
  加上 event 節點的 `PopulationSourceOperationDef`（+1）後 `version_maximum_population = 10`，
  `entity_stress_minimum` 落在 `CombatConfigDef` 預設 `entity_budget = 64` 之內。
- **TUNE 佔位**：全部數值（stat/star_scalings bps、economy 賠率與 pool 數、reward 權重、
  affix 加成等）皆為 TUNE 佔位，非最終平衡，僅供驗證器與 Build Lab 灰盒可跑。

## 重新產生方式

本目錄的 `.tres` 由一次性 GDScript 工具產生（比照 `build_systems` pack 慣例，該工具未隨
專案提交，僅在授權 session 內於 scratchpad／`tools/` 暫存執行 `ResourceSaver.save()` 後刪除）。
若要調整數值，直接編輯對應 `.tres` 即可；若需批次重新產生，比照本文件「內容清單」與
「設計慣例」重建對應的 GDScript 建構邏輯，內容結構已在此文件與
`content/validation/content_validator.gd` 中完整定義。

## 驗收

`tests/unit/content_validation/test_vertical_slice_content_pack.gd`（GUT，跑在 `-Suite Gut`／
`-Suite All`）載入本目錄與 `build_systems` pack 全部 `.tres`（無 synthetic 補充），合併後交給
`ContentValidator.validate()` 斷言 0 issue，並經 `ContentRegistryService.install_validated()`
確認 manifest digest 非空、`latest_catalog_handle()`／`resolve()` 可查回同一份 pin 的內容。
