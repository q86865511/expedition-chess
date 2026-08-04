extends GutTest

const DIGEST_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const DIGEST_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

var _compiler := EncounterCompiler.new()

func test_compile_is_deterministic_and_persists_boss_source_id() -> void:
	var request := _request(DIGEST_A)
	var first := _compiler.compile(request, _catalog(DIGEST_A, _encounter()))
	var second := _compiler.compile(request, _catalog(DIGEST_A, _encounter()))
	assert_true(first.ok, _error_text(first))
	assert_true(second.ok, _error_text(second))
	assert_eq(first.preview.manifest_digest, StringName(DIGEST_A))
	assert_eq(first.preview.enemy_units.size(), 2)
	assert_eq(first.preview.enemy_units[0].logical_y, 4)
	assert_eq(first.preview.enemy_units[1].logical_y, 6)
	# DC-REQ-001 重算：request.act_index = 2，星級縮放後再套 act2 乘數 13000 bps
	# （180 → 234、18 → 23；★1 的 100 → 130）。
	assert_eq(first.preview.enemy_units[1].health, 234)
	assert_eq(first.preview.enemy_units[1].attack, 23)
	assert_eq(first.preview.active_traits.size(), 1)
	assert_eq(first.preview.active_traits[0].tier, 2)
	assert_eq(first.preview.enemy_units[0].effect_assignments.size(), 1)
	assert_eq(
		first.preview.enemy_units[0].effect_assignments[0].source_category,
		&"unit"
	)
	assert_eq(
		first.preview.enemy_units[0].effect_assignments[0].source_side,
		&"enemy"
	)
	assert_eq(
		first.preview.enemy_units[0].effect_assignments[0].source_instance_id.value,
		first.preview.enemy_units[0].instance_id
	)
	assert_eq(first.preview.active_traits[0].effect_assignments.size(), 1)
	assert_eq(
		first.preview.active_traits[0].effect_assignments[0].effect_id,
		&"effect.trait_2"
	)
	assert_eq(
		first.preview.active_traits[0].effect_assignments[0].source_category,
		&"trait"
	)
	assert_eq(first.preview.affix_effects[0].effect_id, &"effect.affix")
	assert_eq(
		first.preview.affix_effects[0].source_category,
		&"encounter_affix"
	)
	var expected_source := BattleEntityIdCodecV1.new().encode_enemy(
		request.node_id, "boss_0"
	)
	assert_true(expected_source.ok)
	assert_eq(
		first.preview.boss_phases[0].source_instance_id,
		expected_source.entity_id
	)
	assert_eq(
		first.preview.boss_phases[0].source_instance_id,
		second.preview.boss_phases[0].source_instance_id
	)
	first.preview.enemy_units[0].health = 1
	assert_eq(second.preview.enemy_units[0].health, 130)

func test_wrong_pinned_generation_is_rejected_without_latest_fallback() -> void:
	var result := _compiler.compile(
		_request(DIGEST_A),
		_catalog(DIGEST_B, _encounter())
	)
	assert_false(result.ok)
	assert_eq(result.error.code, EncounterCompiler.GENERATION_MISMATCH)
	assert_eq(result.error.field_path, &"manifest_digest")

func test_duplicate_spawn_key_is_rejected_before_preview_publication() -> void:
	var encounter := _encounter()
	encounter.enemy_spawns[1].spawn_key = encounter.enemy_spawns[0].spawn_key
	var result := _compiler.compile(
		_request(DIGEST_A),
		_catalog(DIGEST_A, encounter)
	)
	assert_false(result.ok)
	assert_eq(result.error.code, EncounterCompiler.SPAWN_KEY_DUPLICATE)

func test_boss_phase_requires_explicit_spawn_key_in_same_encounter() -> void:
	var encounter := _encounter()
	encounter.boss_phases[0].source_spawn_key = "missing"
	var result := _compiler.compile(
		_request(DIGEST_A),
		_catalog(DIGEST_A, encounter)
	)
	assert_false(result.ok)
	assert_eq(result.error.code, EncounterCompiler.BOSS_SOURCE_MISSING)
	assert_eq(
		result.error.field_path,
		&"encounter.boss_phases.0.source_spawn_key"
	)

func test_missing_compiled_unit_rule_is_fatal() -> void:
	var encounter := _encounter()
	encounter.enemy_spawns[0].unit_id = &"unit.missing"
	var result := _compiler.compile(
		_request(DIGEST_A),
		_catalog(DIGEST_A, encounter)
	)
	assert_false(result.ok)
	assert_eq(result.error.code, EncounterCompiler.RULE_MISSING)
	assert_eq(result.error.source_id, &"unit.missing")

func _request(digest: String) -> EncounterCompileRequest:
	var request := EncounterCompileRequest.new()
	request.manifest_digest = digest
	request.encounter_id = &"encounter.boss"
	request.node_id = &"node_d94992320541276dfd384a614e280c0e1e0f804931a3ba6ec8e59fd467a033bc"
	request.act_index = 2
	request.depth = 5
	request.challenge_level = 3
	return request

func _catalog(
	digest: String,
	encounter: BattleEncounterRule
) -> BattleRuleCatalog:
	var unit := BattleUnitRule.new()
	unit.unit_id = &"unit.enemy"
	unit.trait_ids = [&"trait.enemy"]
	unit.base_stats = BattleUnitStatsRule.new()
	unit.base_stats.health = 100
	unit.base_stats.attack = 10
	unit.base_stats.armor = 5
	unit.base_stats.magic_resist = 5
	unit.base_stats.attack_speed_milli = 1000
	unit.base_stats.attack_range_cells = 1
	unit.base_stats.start_mana = 0
	unit.base_stats.max_mana = 100
	unit.base_stats.move_speed_milli = 1000
	for pair: Array in [[1, 10000], [2, 18000], [3, 32000]]:
		var scaling := BattleStarScalingRule.new()
		scaling.star = int(pair[0])
		scaling.health_bps = int(pair[1])
		scaling.attack_bps = int(pair[1])
		scaling.armor_bps = int(pair[1])
		scaling.magic_resist_bps = int(pair[1])
		scaling.attack_speed_bps = int(pair[1])
		scaling.attack_range_bps = 10000
		scaling.start_mana_bps = 10000
		scaling.max_mana_bps = 10000
		scaling.move_speed_bps = 10000
		unit.star_scalings.append(scaling)
	var trait_rule := BattleTraitRule.new()
	trait_rule.trait_id = &"trait.enemy"
	trait_rule.member_rule = &"instances"
	for required_count: int in [1, 2]:
		var threshold := BattleTraitThresholdRule.new()
		threshold.required_count = required_count
		threshold.effect_ids = [
			StringName("effect.trait_%d" % required_count)
		]
		trait_rule.thresholds.append(threshold)
	var effects: Array[BattleEffectRule] = []
	for effect_id: StringName in [
		&"effect.affix",
		&"effect.phase",
		&"effect.spawn",
		&"effect.trait_1",
		&"effect.trait_2",
	]:
		var effect := BattleEffectRule.new()
		effect.effect_id = effect_id
		effects.append(effect)
	var units: Array[BattleUnitRule] = [unit]
	var traits: Array[BattleTraitRule] = [trait_rule]
	var abilities: Array[BattleAbilityRule] = []
	var encounters: Array[BattleEncounterRule] = [encounter]
	var equipment: Array[BattleEquipmentRule] = []
	# DC-REQ-001：EncounterCompiler 現在必須拿到 pinned combat config 才能取幕乘數。
	var configs: Array[BattleCombatConfigRule] = [_combat_config()]
	return BattleRuleCatalog.new(
		digest,
		units,
		traits,
		abilities,
		effects,
		encounters,
		equipment,
		configs
	)

func _combat_config() -> BattleCombatConfigRule:
	var config := BattleCombatConfigRule.new()
	config.config_id = &"config.combat_default"
	var defaults := CombatConfigDef.new()
	for property: StringName in BattleCombatConfigRule._integer_properties():
		config.set(property, defaults.get(property))
	return config

func _encounter() -> BattleEncounterRule:
	var frontline := BattleEnemySpawnRule.new()
	frontline.side = &"enemy"
	frontline.logical_y = 4
	frontline.logical_x = 1
	frontline.spawn_key = "frontline_0"
	frontline.unit_id = &"unit.enemy"
	frontline.star = 1
	frontline.effect_ids = [&"effect.spawn"]
	var boss := BattleEnemySpawnRule.new()
	boss.side = &"enemy"
	boss.logical_y = 6
	boss.logical_x = 3
	boss.spawn_key = "boss_0"
	boss.unit_id = &"unit.enemy"
	boss.star = 2
	boss.effect_ids = [&"effect.spawn"]
	var phase := BattleBossPhaseRule.new()
	phase.phase_index = 0
	phase.hp_threshold_bps = 5000
	phase.source_spawn_key = "boss_0"
	phase.effect_ids = [&"effect.phase"]
	var encounter := BattleEncounterRule.new()
	encounter.encounter_id = &"encounter.boss"
	encounter.encounter_kind = &"boss"
	encounter.preview_schema_version = 1
	encounter.enemy_spawns = [boss, frontline]
	encounter.affix_ids = [&"effect.affix"]
	encounter.boss_phases = [phase]
	return encounter

func _error_text(result: EncounterCompileResult) -> String:
	if result.ok or result.error == null:
		return ""
	return "%s:%s:%s" % [
		String(result.error.code),
		String(result.error.field_path),
		String(result.error.source_id),
	]
