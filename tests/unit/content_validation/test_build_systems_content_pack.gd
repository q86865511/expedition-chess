extends GutTest

# T08(S4 build-systems，免 TDD：內容資料授權)驗收測試。
# 對應 specs/build-systems/design.md §7、tasks.md T08：
#   把 content/packs/build_systems/ 的正式 .tres pack 與「必要的最小 synthetic 補充」
#   (借用 tests/fixtures/content/synthetic_content_fixture.gd 的手法，但把
#   trait/item_component/equipment/relic/consumable 換成本 pack 的正式 id)一起交給
#   ContentRegistryService.install_validated()，斷言 0 issue 且關鍵計數成立。
#
# 本檔不修改 synthetic_content_fixture.gd 共用 fixture；只在本檔內對
# SyntheticContentFixture.build_valid() 回傳的（已 deep-clone 過的）定義做局部替換，
# 不影響 Content suite／其他既有測試共用的原始 fixture 行為。

const PACK_ROOT := "res://content/packs/build_systems"

# 與 content/packs/build_systems 產生時使用的順序一致(見該目錄 README「設計慣例」)。
const FACTION_IDS: Array[StringName] = [
	&"trait.faction_arcane", &"trait.faction_verdant", &"trait.faction_ember",
	&"trait.faction_frost", &"trait.faction_iron", &"trait.faction_shadow",
]
const ROLE_IDS: Array[StringName] = [
	&"trait.role_vanguard", &"trait.role_marksman", &"trait.role_mystic",
	&"trait.role_sentinel", &"trait.role_trickster", &"trait.role_warden",
]

# ================= 頂層驗收 =================

func test_pack_directory_has_expected_definition_counts() -> void:
	var pack := _load_pack()
	assert_eq(_count(pack, &"trait"), 12, "TraitDef 應為 12（6 陣營＋6 職能）")
	assert_eq(_count(pack, &"item_component"), 6, "ItemComponentDef 應為 6")
	assert_eq(_count(pack, &"equipment"), 21, "EquipmentDef 應為 21（6 零件封閉配方）")
	assert_true(_count(pack, &"relic") >= 15, "RelicDef 應 >= 15")
	assert_true(_count(pack, &"consumable") >= 1, "應至少 1 個 ConsumableDef")
	assert_true(_count(pack, &"effect") > 0, "應含引用的 EffectDef")

# G2 difficulty-curve T04（DC-REQ-004）：12 個 TraitDef 的 tier1/2/3 門檻須各自指向
# 互異的 EffectDef，且量值（ModifyStat/GrantMana/Shield 的 amount）嚴格遞增。
func test_trait_thresholds_reference_distinct_effects_with_strictly_increasing_amounts() -> void:
	var pack := _load_pack()
	var effects_by_id: Dictionary = {}
	for definition in pack:
		if definition is EffectDef:
			effects_by_id[definition.id] = definition
	var checked_trait_count := 0
	for definition in pack:
		if not definition is TraitDef: continue
		var trait_def := definition as TraitDef
		assert_eq(trait_def.thresholds.size(), 3, "trait 應有 3 個門檻: %s" % trait_def.id)
		if trait_def.thresholds.size() != 3: continue
		var effect_ids: Array[StringName] = []
		var amounts: Array[int] = []
		for threshold: TraitThresholdDef in trait_def.thresholds:
			assert_eq(threshold.effect_refs.size(), 1, "門檻應恰指向 1 個 effect: %s" % trait_def.id)
			if threshold.effect_refs.is_empty(): continue
			var effect_id: StringName = threshold.effect_refs[0]
			effect_ids.append(effect_id)
			var effect := effects_by_id.get(effect_id) as EffectDef
			assert_not_null(effect, "找不到 trait 門檻引用的 effect: %s (trait=%s)" % [effect_id, trait_def.id])
			if effect == null: continue
			assert_eq(effect.battle_operations.size(), 1, "trait 效果應恰含 1 個 battle_operation: %s" % effect_id)
			if effect.battle_operations.is_empty(): continue
			amounts.append(int(effect.battle_operations[0].get("amount")))
		var unique_ids: Dictionary = {}
		for effect_id: StringName in effect_ids:
			unique_ids[effect_id] = true
		assert_eq(
			unique_ids.size(), 3,
			"三階 effect id 應互異: %s -> %s" % [trait_def.id, effect_ids]
		)
		for index: int in range(1, amounts.size()):
			assert_true(
				amounts[index] > amounts[index - 1],
				"trait %s 的階梯量值應嚴格遞增: %s" % [trait_def.id, amounts]
			)
		checked_trait_count += 1
	assert_eq(checked_trait_count, 12, "應檢查全部 12 個 TraitDef")

func test_pack_equipment_recipes_are_a_closed_set_of_21_unique_pairs() -> void:
	var pack := _load_pack()
	var components: Array[StringName] = []
	for definition in pack:
		if definition is ItemComponentDef: components.append(definition.id)
	components.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var seen: Dictionary = {}
	for definition in pack:
		if not definition is EquipmentDef: continue
		var equipment := definition as EquipmentDef
		var pair: Array[StringName] = equipment.component_pair.duplicate()
		pair.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		var key := "%s+%s" % [pair[0], pair[0] if pair.size() == 1 else pair[1]]
		assert_false(seen.has(key), "配方重複: %s（%s）" % [key, equipment.id])
		seen[key] = true
	var expected := 0
	for left in components.size():
		for right in range(left, components.size()):
			expected += 1
			var key := "%s+%s" % [components[left], components[right]]
			assert_true(seen.has(key), "缺少配方: %s" % key)
	assert_eq(expected, 21)
	assert_eq(seen.size(), 21)

func test_pack_relics_cover_all_four_categories() -> void:
	var pack := _load_pack()
	var by_category: Dictionary = {}
	for definition in pack:
		if not definition is RelicDef: continue
		var relic := definition as RelicDef
		by_category[relic.category] = int(by_category.get(relic.category, 0)) + 1
	for category in [&"battle", &"economy", &"route", &"rule"]:
		assert_true(int(by_category.get(category, 0)) >= 1, "遺物類別缺少: %s" % category)

func test_pack_has_at_least_one_dismantle_consumable_with_no_run_operations() -> void:
	var pack := _load_pack()
	var found := false
	for definition in pack:
		if not definition is ConsumableDef: continue
		var consumable := definition as ConsumableDef
		if consumable.use_timing == &"dismantle":
			found = true
			assert_true(consumable.run_operations.is_empty(), "拆卸道具的 run_operations 須為空: %s" % consumable.id)
	assert_true(found, "應至少有一個 use_timing == dismantle 的 ConsumableDef")

func test_pack_installs_validated_with_zero_issues_via_content_registry() -> void:
	var pack := _load_pack()
	var input := _build_validation_input(pack)

	var report := ContentValidator.new().validate(input)
	assert_true(report.valid, _issue_text(report))

	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var pack_ids: Array[StringName] = [&"pack.build_systems", &"pack.vertical_slice_synthetic"]
	var result := registry.install_validated(input, "0.1.0-build-systems-t08", pack_ids)
	if not result.ok:
		var source := String(result.error.source_id.value) if result.error.source_id != null else "?"
		assert_true(result.ok, "install_validated 失敗: %s field=%s source=%s" % [result.error.code, result.error.field_path, source])
	if result.ok:
		assert_false(result.handle.manifest_digest.is_empty())

# ================= pack 載入 =================

func _load_pack() -> Array[ContentDefinition]:
	var result: Array[ContentDefinition] = []
	_load_dir(PACK_ROOT, result)
	# G2 difficulty-curve T04：trait 門檻階梯化新增 24 個 tier2/tier3 effect（34→58）。
	assert_eq(result.size(), 114, "pack 資源總數應為 114（12+6+21+16+1+58）")
	return result

func _load_dir(path: String, result: Array[ContentDefinition]) -> void:
	var dir := DirAccess.open(path)
	assert_not_null(dir, "無法開啟目錄: %s" % path)
	if dir == null: return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full_path := "%s/%s" % [path, entry]
			if dir.current_is_dir():
				_load_dir(full_path, result)
			elif entry.ends_with(".tres"):
				var resource := load(full_path)
				assert_true(resource is ContentDefinition, "非預期的資源型別: %s" % full_path)
				if resource is ContentDefinition:
					result.append(resource)
		entry = dir.get_next()
	dir.list_dir_end()

func _count(definitions: Array[ContentDefinition], category: StringName) -> int:
	var total := 0
	for definition in definitions:
		if definition.category_name() == category: total += 1
	return total

# ================= 最小 synthetic 補充(借用 SyntheticContentFixture 手法，換上正式 id) =================

func _build_validation_input(pack: Array[ContentDefinition]) -> ContentValidationInput:
	var baseline := SyntheticContentFixture.build_valid()
	var supplement := _strip_build_systems_placeholders(baseline.definitions)
	_rewire_player_traits(supplement)
	_rewire_dangling_content_refs(supplement)
	var combined: Array[ContentDefinition] = []
	combined.append_array(supplement)
	combined.append_array(pack)
	return ContentValidationInput.new(combined, [], [], baseline.dependency_port, baseline.base_population_cap)

func _strip_build_systems_placeholders(definitions: Array[ContentDefinition]) -> Array[ContentDefinition]:
	var result: Array[ContentDefinition] = []
	for definition in definitions:
		if definition is TraitDef: continue
		if definition is ItemComponentDef: continue
		if definition is EquipmentDef: continue
		if definition is RelicDef: continue
		if definition is ConsumableDef: continue
		# effect.operation_matrix 僅被舊 synthetic 遺物引用（皆已移除）；其內部
		# ConditionDef 指向舊 trait.faction_0，若保留會變成懸空參照，故一併移除。
		if definition.id == &"effect.operation_matrix": continue
		result.append(definition)
	return result

func _rewire_player_traits(definitions: Array[ContentDefinition]) -> void:
	for definition in definitions:
		if not definition is UnitDef: continue
		var unit := definition as UnitDef
		if unit.availability != &"player": continue
		var index := int(String(unit.id).get_slice("_", 1))
		var refs: Array[StringName] = [FACTION_IDS[index % 6], ROLE_IDS[index % 6]]
		if index < 4:
			refs.append(FACTION_IDS[(index + 1) % 6])
		unit.trait_refs = refs

func _rewire_dangling_content_refs(definitions: Array[ContentDefinition]) -> void:
	var event0 := _find(definitions, &"map_node.event_0") as MapNodeDef
	assert_not_null(event0, "fixture 佈局已變動: map_node.event_0 不存在")
	if event0 != null:
		var grant_item := event0.enter_operations[1] as GrantItemOperationDef
		assert_not_null(grant_item, "fixture 佈局已變動: map_node.event_0.enter_operations[1] 不是 GrantItemOperationDef")
		if grant_item != null: grant_item.content_ref = &"consumable.dismantle_kit"
		var grant_relic := event0.enter_operations[2] as GrantRelicOperationDef
		assert_not_null(grant_relic, "fixture 佈局已變動: map_node.event_0.enter_operations[2] 不是 GrantRelicOperationDef")
		if grant_relic != null: grant_relic.relic_ref = &"relic.ember_ward"
	var relic_table := _find(definitions, &"reward_table.relic") as RewardTableDef
	assert_not_null(relic_table, "fixture 佈局已變動: reward_table.relic 不存在")
	if relic_table != null and not relic_table.reward_candidates.is_empty():
		relic_table.reward_candidates[0].content_ref = &"relic.ember_ward"

func _find(definitions: Array[ContentDefinition], content_id: StringName) -> ContentDefinition:
	for definition in definitions:
		if definition.id == content_id: return definition
	return null

func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)
