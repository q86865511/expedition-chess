class_name BattleSetupSourceCompiler
extends RefCounted

## 把「已提交 roster ＋ pinned BattleRuleCatalog」編譯成 BattleSetupSourceBundle 的唯一 producer
## （design.md §4）。純函式式：只讀 clone 與 pinned catalog、不修改輸入、無拒絕路徑
## （世代拒絕由 StartCombatEvent 把關）。PREPARE 期預覽與 combat entry 共用同一份編譯結果。

const BASIS_POINTS: int = 10000

func compile(
	committed_roster: RosterState,
	catalog: BattleRuleCatalog,
	commander_passive_effect_ids: Array[StringName] = []
) -> BattleSetupSourceBundle:
	var on_field := _collect_on_field(committed_roster, catalog)
	var player_units := _compile_player_units(on_field, catalog)
	var active_traits := _compile_traits(on_field, catalog)
	var equipment_effects := _compile_equipment_effects(on_field, committed_roster, catalog)
	var relic_effects := _compile_relic_effects(committed_roster, catalog)
	var commander_effects := _compile_commander_effects(commander_passive_effect_ids)
	var empty_effects: Array[BattleEffectSnapshot] = []
	return BattleSetupSourceBundle.new(
		catalog.manifest_digest_value(),
		player_units,
		active_traits,
		equipment_effects,
		relic_effects,
		commander_effects,
		empty_effects,
		true, true, true, true, true, true
	)

## 單一單位的星級縮放屬性預覽（IRH-REQ-016）。與 compile() 共用 _apply_stats／
## _find_scaling，因此逐欄位等同 compile() 產出的 UnitBattleSnapshot，也就是
## BattleSimulation 初始化寫進 BattleEntityState 的 base 值。不需要
## BoardPlacementState，板凳單位同樣適用；rule 或 catalog 缺失時屬性維持零值。
## 依 try_ 慣例：instance 為 null 時回 null，呼叫端必須處理。
func try_compile_unit_stats(
	instance: UnitInstance,
	catalog: BattleRuleCatalog
) -> UnitStatsPreviewSnapshot:
	if instance == null:
		return null
	var carrier := UnitBattleSnapshot.new()
	carrier.instance_id = StringName(instance.instance_id)
	carrier.unit_id = instance.def_id
	carrier.star = instance.star
	var rule: BattleUnitRule = (
		catalog.try_unit_rule(instance.def_id) if catalog != null else null
	)
	if rule != null:
		carrier.unit_id = rule.unit_id
		carrier.basic_attack_profile = rule.basic_attack_profile
		if rule.base_stats != null:
			_apply_stats(
				carrier, rule.base_stats, _find_scaling(rule.star_scalings, instance.star)
			)
	var preview := UnitStatsPreviewSnapshot.new()
	preview.instance_id = carrier.instance_id
	preview.unit_id = carrier.unit_id
	preview.star = carrier.star
	preview.health = carrier.health
	preview.attack = carrier.attack
	preview.armor = carrier.armor
	preview.magic_resist = carrier.magic_resist
	preview.attack_speed_milli = carrier.attack_speed_milli
	preview.attack_range_cells = carrier.attack_range_cells
	preview.start_mana = carrier.start_mana
	preview.max_mana = carrier.max_mana
	preview.move_speed_milli = carrier.move_speed_milli
	preview.basic_attack_profile = carrier.basic_attack_profile
	preview.equipment_instance_ids = instance.equipment_instance_ids.duplicate()
	return preview

# ---------------------------------------------------------------------------
# 上場棋收集（排除板凳；召喚物結構上不存在於 RosterState）
# ---------------------------------------------------------------------------

func _collect_on_field(roster: RosterState, catalog: BattleRuleCatalog) -> Array:
	var result: Array = []
	for placement: BoardPlacementState in roster.board.placements:
		if placement == null:
			continue
		var instance := _find_unit_instance(
			roster.unit_instances, placement.unit_instance_id
		)
		if instance == null:
			continue
		result.append({
			"placement": placement,
			"instance": instance,
			"rule": catalog.try_unit_rule(instance.def_id),
		})
	result.sort_custom(_on_field_before)
	return result

func _compile_player_units(
	on_field: Array,
	catalog: BattleRuleCatalog
) -> Array[UnitBattleSnapshot]:
	var result: Array[UnitBattleSnapshot] = []
	for entry: Dictionary in on_field:
		result.append(_build_player_unit(
			entry["placement"], entry["instance"], entry["rule"], catalog
		))
	return result

func _build_player_unit(
	placement: BoardPlacementState,
	instance: UnitInstance,
	rule: BattleUnitRule,
	catalog: BattleRuleCatalog
) -> UnitBattleSnapshot:
	var unit := UnitBattleSnapshot.new()
	unit.instance_id = StringName(instance.instance_id)
	unit.unit_id = instance.def_id
	unit.side = &"player"
	unit.logical_y = placement.logical_y
	unit.logical_x = placement.logical_x
	unit.star = instance.star
	if rule == null:
		return unit
	unit.unit_id = rule.unit_id
	unit.basic_attack_profile = rule.basic_attack_profile
	unit.ability_id = rule.ability_id.deep_clone() if rule.ability_id != null else null
	if rule.base_stats != null:
		_apply_stats(unit, rule.base_stats, _find_scaling(rule.star_scalings, instance.star))
	unit.effect_ids = rule.effect_ids.duplicate()
	# ability primary effect 依 wave3 契約不得寫進 UnitDef 的 innate effect_refs,
	# 施法解算的 effect source 在此併入(去重,fixture 內容兩處同值時不變)
	if unit.ability_id != null:
		var ability_rule := catalog.try_ability_rule(unit.ability_id.value)
		if ability_rule != null:
			for ability_effect_id: StringName in ability_rule.effect_ids:
				if not unit.effect_ids.has(ability_effect_id):
					unit.effect_ids.append(ability_effect_id)
	unit.effect_ids.sort_custom(_string_name_before)
	for effect_index: int in range(unit.effect_ids.size()):
		unit.effect_assignments.append(_build_effect(
			&"unit",
			&"player",
			unit.unit_id,
			OptionalStringNameValue.of(unit.instance_id),
			0,
			effect_index,
			unit.effect_ids[effect_index],
			[] as Array[StringName]
		))
	return unit

func _apply_stats(
	unit: UnitBattleSnapshot,
	base: BattleUnitStatsRule,
	scaling: BattleStarScalingRule
) -> void:
	if scaling == null:
		unit.health = base.health
		unit.attack = base.attack
		unit.armor = base.armor
		unit.magic_resist = base.magic_resist
		unit.attack_speed_milli = base.attack_speed_milli
		unit.attack_range_cells = base.attack_range_cells
		unit.start_mana = base.start_mana
		unit.max_mana = base.max_mana
		unit.move_speed_milli = base.move_speed_milli
		return
	unit.health = _scaled(base.health, scaling.health_bps)
	unit.attack = _scaled(base.attack, scaling.attack_bps)
	unit.armor = _scaled(base.armor, scaling.armor_bps)
	unit.magic_resist = _scaled(base.magic_resist, scaling.magic_resist_bps)
	unit.attack_speed_milli = _scaled(base.attack_speed_milli, scaling.attack_speed_bps)
	unit.attack_range_cells = _scaled(base.attack_range_cells, scaling.attack_range_bps)
	unit.start_mana = _scaled(base.start_mana, scaling.start_mana_bps)
	unit.max_mana = _scaled(base.max_mana, scaling.max_mana_bps)
	unit.move_speed_milli = _scaled(base.move_speed_milli, scaling.move_speed_bps)

# ---------------------------------------------------------------------------
# 羈絆計數（不同 def_id set 決定 tier；成員以 instance id 列示）
# ---------------------------------------------------------------------------

func _compile_traits(on_field: Array, catalog: BattleRuleCatalog) -> Array[TraitBattleSnapshot]:
	var trait_ids: Array[StringName] = []
	var def_sets: Dictionary = {}
	var members: Dictionary = {}
	for entry: Dictionary in on_field:
		var rule: BattleUnitRule = entry["rule"]
		if rule == null:
			continue
		var instance: UnitInstance = entry["instance"]
		for trait_id: StringName in rule.trait_ids:
			if not trait_ids.has(trait_id):
				trait_ids.append(trait_id)
				def_sets[trait_id] = {}
				members[trait_id] = [] as Array[StringName]
			(def_sets[trait_id] as Dictionary)[instance.def_id] = true
			var member_list: Array[StringName] = members[trait_id]
			var member_id := StringName(instance.instance_id)
			if not member_list.has(member_id):
				member_list.append(member_id)
	trait_ids.sort_custom(_string_name_before)
	var result: Array[TraitBattleSnapshot] = []
	for trait_id: StringName in trait_ids:
		var trait_rule := catalog.try_trait_rule(trait_id)
		if trait_rule == null:
			continue
		var distinct_count := (def_sets[trait_id] as Dictionary).size()
		var active_tier := 0
		for index: int in range(trait_rule.thresholds.size()):
			var threshold := trait_rule.thresholds[index]
			if threshold != null and distinct_count >= threshold.required_count:
				active_tier = index + 1
		if active_tier == 0:
			continue
		var snapshot := TraitBattleSnapshot.new()
		snapshot.trait_id = trait_id
		snapshot.tier = active_tier
		var member_list: Array[StringName] = members[trait_id]
		member_list.sort_custom(_string_name_before)
		snapshot.member_instance_ids = member_list
		var effect_ids: Array[StringName] = \
			trait_rule.thresholds[active_tier - 1].effect_ids.duplicate()
		effect_ids.sort_custom(_string_name_before)
		var effect_index := 0
		for effect_id: StringName in effect_ids:
			if catalog.try_effect_rule(effect_id) == null:
				continue
			snapshot.effect_assignments.append(_build_effect(
				&"trait", &"player", trait_id, null, 0, effect_index, effect_id,
				[] as Array[StringName]
			))
			effect_index += 1
		result.append(snapshot)
	return result

# ---------------------------------------------------------------------------
# 裝備效果（逐上場棋 equipment_instance_ids → def_id → try_equipment_rule）
# ---------------------------------------------------------------------------

func _compile_equipment_effects(
	on_field: Array,
	roster: RosterState,
	catalog: BattleRuleCatalog
) -> Array[BattleEffectSnapshot]:
	var result: Array[BattleEffectSnapshot] = []
	for entry: Dictionary in on_field:
		var instance: UnitInstance = entry["instance"]
		var targets: Array[StringName] = [StringName(instance.instance_id)]
		for slot_index: int in range(instance.equipment_instance_ids.size()):
			var item := _find_item(
				roster.item_instances, instance.equipment_instance_ids[slot_index]
			)
			if item == null:
				continue
			var rule := catalog.try_equipment_rule(item.def_id)
			if rule == null:
				continue
			var effect_index := 0
			for effect_id: StringName in rule.effect_ids:
				result.append(_build_effect(
					&"equipment",
					&"player",
					item.def_id,
					OptionalStringNameValue.of(StringName(item.instance_id)),
					slot_index,
					effect_index,
					effect_id,
					targets
				))
				effect_index += 1
	return result

# ---------------------------------------------------------------------------
# 戰鬥遺物效果（依 active_relic_slots slot_index 升序；非 battle 類 catalog 查無即跳過）
# ---------------------------------------------------------------------------

func _compile_relic_effects(
	roster: RosterState,
	catalog: BattleRuleCatalog
) -> Array[BattleEffectSnapshot]:
	var slots: Array[RelicSlotState] = roster.active_relic_slots.duplicate()
	slots.sort_custom(_relic_slot_before)
	var result: Array[BattleEffectSnapshot] = []
	for slot: RelicSlotState in slots:
		if slot == null or slot.relic_id == null:
			continue
		var rule := catalog.try_relic_rule(slot.relic_id.value)
		if rule == null:
			continue
		var effect_index := 0
		for effect_id: StringName in rule.battle_effect_ids:
			result.append(_build_effect(
				&"relic",
				&"player",
				slot.relic_id.value,
				null,
				slot.slot_index,
				effect_index,
				effect_id,
				[] as Array[StringName]
			))
			effect_index += 1
	return result

# ---------------------------------------------------------------------------
# 指揮官 player 被動效果（design §6.2、S5-AC-003）
# ---------------------------------------------------------------------------

## 呼叫端已把 CommanderDef.passive_effect_refs 解析成 effect id 清單傳入（本編譯器只消費、不
## 解析 CommanderDef，比照 relic 消費 battle_effect_ids 的方式）。比照戰鬥遺物效果
## （_compile_relic_effects）產出 source_category=commander、source_side=player 的 snapshot：
## commander 效果無槽位/instance 概念（source_slot=0、source_instance_id=null、target_ids 空）。
## 依 effect_id 字典序穩定排序，對齊 BattleSetupInputsValidator 對 commander 類的
## source_stable_id 排序要求；隨 BattleSetup hash 凍結進模擬。
func _compile_commander_effects(
	commander_passive_effect_ids: Array[StringName]
) -> Array[BattleEffectSnapshot]:
	var sorted_ids: Array[StringName] = commander_passive_effect_ids.duplicate()
	sorted_ids.sort_custom(_string_name_before)
	var result: Array[BattleEffectSnapshot] = []
	for effect_id: StringName in sorted_ids:
		result.append(_build_effect(
			&"commander",
			&"player",
			effect_id,
			null,
			0,
			0,
			effect_id,
			[] as Array[StringName]
		))
	return result

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _build_effect(
	category: StringName,
	side: StringName,
	stable_id: StringName,
	source_instance_id: OptionalStringNameValue,
	slot: int,
	effect_index: int,
	effect_id: StringName,
	target_ids: Array[StringName]
) -> BattleEffectSnapshot:
	var effect := BattleEffectSnapshot.new()
	effect.priority = 0
	effect.source_category = category
	effect.source_side = side
	effect.source_stable_id = stable_id
	effect.source_instance_id = source_instance_id
	effect.source_slot = slot
	effect.effect_index = effect_index
	effect.effect_id = effect_id
	effect.target_ids = target_ids.duplicate()
	return effect

func _find_unit_instance(units: Array[UnitInstance], instance_id: String) -> UnitInstance:
	for unit: UnitInstance in units:
		if unit != null and unit.instance_id == instance_id:
			return unit
	return null

func _find_item(items: Array[ItemInstanceState], instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in items:
		if item != null and item.instance_id == instance_id:
			return item
	return null

func _find_scaling(values: Array[BattleStarScalingRule], star: int) -> BattleStarScalingRule:
	for value: BattleStarScalingRule in values:
		if value != null and value.star == star:
			return value
	return null

func _scaled(base_value: int, multiplier_bps: int) -> int:
	@warning_ignore("integer_division")
	var result: int = (base_value * multiplier_bps) / BASIS_POINTS
	return result

func _on_field_before(left: Dictionary, right: Dictionary) -> bool:
	var left_placement: BoardPlacementState = left["placement"]
	var right_placement: BoardPlacementState = right["placement"]
	if left_placement.logical_y != right_placement.logical_y:
		return left_placement.logical_y < right_placement.logical_y
	if left_placement.logical_x != right_placement.logical_x:
		return left_placement.logical_x < right_placement.logical_x
	return left_placement.unit_instance_id < right_placement.unit_instance_id

func _relic_slot_before(left: RelicSlotState, right: RelicSlotState) -> bool:
	return left.slot_index < right.slot_index

func _string_name_before(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
