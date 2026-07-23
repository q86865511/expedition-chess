# build-systems 內容 pack

> 對應 `specs/build-systems/design.md` §7、任務 T08。這是全專案第一批正式 `.tres` 內容
> 授權（S3 完成時全專案 `.tres` 內容為 0，皆為測試 fixture——見 `specs/build-systems/requirements.md` §1）。

## 佈局慣例

```
content/packs/<pack_name>/<category>/<short_id>.tres
```

- `<pack_name>` 對應規格片名（本 pack 為 `build_systems`，對應 S4 build-systems 切片）。
- `<category>` 對應 `ContentDefinition.category_name()`（`traits`／`item_components`／
  `equipment`／`relics`／`consumables`／`effects`，複數形式，與 `content/definitions/*_def.gd`
  的單數 class 名稱區分)。
- `<short_id>` 是 stable id 去掉 category 前綴後的尾段（例如 `trait.faction_arcane` →
  `traits/faction_arcane.tres`），檔名與 stable id 一一對應，方便用 id 反查檔案。
- 之後新增 pack（例如 T09 的垂直切片伴生 catalog）比照建立 `content/packs/<pack_name>/`，
  不與本目錄混放，讓每個 pack 的授權範圍在檔案系統層級可見。

## 內容清單

| Category | 數量 | 說明 |
|---|---:|---|
| `traits/` | 12 | 6 陣營（`trait.faction_*`）+ 6 職能（`trait.role_*`），各 3 階遞增門檻 |
| `item_components/` | 6 | 封閉配方的原料零件 |
| `equipment/` | 21 | 6 零件的全部無序配對（含自配）＝ C(6,2)+6 = 21，封閉枚舉 |
| `relics/` | 16 | `battle`／`economy`／`route`／`rule` 四類各 4 件（≥15 要求已滿足） |
| `consumables/` | 1 | `consumable.dismantle_kit`（`use_timing = &"dismantle"`，拆卸道具） |
| `effects/` | 34 | 上列內容引用的全部 `EffectDef`（12 trait tier 效果 + 6 裝備零件效果 + 16 遺物效果） |

## 設計慣例（供後續擴充參考）

- **零件與裝備**：6 個零件依 stable id 字母序 `arcane < ember < frost < iron < shadow < verdant`
  排列；`equipment/<a>_<b>.tres` 的檔名／id 恆以此字母序命名（`a <= b`），與
  `ContentValidator._validate_recipes()` 內部用同一字母序做封閉性核對一致，避免重複配方。
  自配（`a == b`）僅 1 個零件、視為零件的「精煉」版本，數值與效果為對應單一零件的加強版；
  異配（`a < b`）取兩零件各自的加成（`stat_modifiers` 各 1 條、`effect_refs` 各 1 個）。
- **unique_group 樣本**：`equipment.arcane_arcane` 與 `equipment.shadow_shadow` 共用
  `unique_group.mythic_core`，示範同組互斥；其餘裝備 `has_unique_group = false` 且
  `unique_group` 維持空字串（與驗證器規則 (a) 一致：旗標與值必須一致，見
  `content/validation/content_validator.gd` `_validate_operations()` 內 `EquipmentDef` 分支）。
- **遺物四類**：每類各 4 件。`battle` 類 `effect_refs` 指向的 `EffectDef` 帶非空
  `battle_operations`（`ModifyStatOperationDef` 或 `DamageOperationDef`）；`economy`／
  `route`／`rule` 三類指向的 `EffectDef` 帶非空 `run_operations`（僅使用 `AddGoldOperationDef`／
  `AddXpOperationDef`／`HealExpeditionHpOperationDef`——`EffectDef.run_operations` 的驗證規則
  不允許 `ModifyUnitPoolOperationDef`／`GrantItemOperationDef`／`GrantRelicOperationDef`／
  `PopulationSourceOperationDef` 等「容量類」操作，見 `_validate_run_operations(..., allow_capacity=false)`）。
- **拆卸道具**：`use_timing = &"dismantle"` 時 `run_operations` 必須為空陣列——拆卸的實際效果
  由專屬 `DismantleEquipmentCommand`（T04 已實作）表達，不透過通用 run_operations。
- **TUNE 佔位**：本 pack 全部數值（門檻遞增計數、`stat_modifiers`／`ModifyStatOperationDef`
  的 amount、遺物 `activation_limit`、run 效果的 amount/claim_scope）皆為 TUNE 佔位，非最終平衡；
  用整數慣例（多為 5 的倍數、門檻取 2/4/6 或 2/4/5 三階）標示「尚待調校」，不代表最終數值。
  最終平衡屬下游 content-completion 橫切（SCOPE-002），不在本片範圍。
- **戰鬥觸發慣例**：被動類效果（trait tier／equipment aura／battle 遺物中的 stat 型）一律
  `trigger = &"battle_start"`、`stacking = &"replace"`、`duration_ticks = 1800`（視為持續整場戰鬥）；
  唯一例外 `effect.relic_frost_edge` 用 `trigger = &"hit"` 示範 on-hit proc 型戰鬥效果。

## 重新產生方式

本目錄的 `.tres` 由一次性 GDScript 工具產生（該工具未隨專案提交，僅在授權 session 內
於 scratchpad 執行 `ResourceSaver.save()`）。若要調整數值或新增內容，直接編輯對應 `.tres`
即可（Godot 編輯器可正常開啟／編輯這些資源），不必依賴產生工具；若需批次重新產生，
比照本 README「設計慣例」一節重建對應的 GDScript 建構邏輯即可，內容結構已在此文件與
`content/validation/content_validator.gd` 中完整定義。

## 驗收

`tests/unit/content_validation/test_build_systems_content_pack.gd`（GUT，跑在 `-Suite Gut`／
`-Suite All`）載入本目錄全部 `.tres`，與最小 synthetic 補充內容（32 棋子／怪物／遭遇／
經濟／獎勵／unlock／combat config 等，借用 `tests/fixtures/content/synthetic_content_fixture.gd`
的手法但改指向本 pack 的 trait/equipment/relic/consumable id）一起交給
`ContentRegistryService.install_validated()`，斷言 0 issue 且關鍵計數
（12 traits／6 components／21 equipment／16 relics）成立。
