extends GutTest

## DC-REQ-001 / REQ-ENEMY-003：per-act 敵方成長乘數。
## 縮放只作用於 health/attack/armor/magic_resist,act1 恆等 10000;
## attack_speed_milli/move_speed_milli/attack_range_cells/start_mana/max_mana 三幕相同。
## 期望值一律硬寫(不在測試裡重算公式),讓乘法被拆掉時必紅。

const BattleSetupFixture = preload("res://tests/fixtures/canonical/battle_setup_fixture.gd")

const DIGEST := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const ACT1_BPS: int = 10000
const ACT2_BPS: int = 14000  # R1 TUNE: act2 淘汰 0 上調(phase2-iteration-log R1)
const ACT3_BPS: int = 16000

var _compiler := EncounterCompiler.new()

## act1 = 星級縮放值本身(★1 100/10/5/5、★2 180/18/9/9);
## act2 = ×1.3 逐步截斷;act3 = ×1.6 逐步截斷。
func test_act_multiplier_scales_only_the_four_combat_stats() -> void:
	var expectations: Array = [
		[1, [100, 10, 5, 5], [180, 18, 9, 9]],
		[2, [130, 13, 6, 6], [234, 23, 11, 11]],
		[3, [160, 16, 8, 8], [288, 28, 14, 14]],
	]
	for row: Array in expectations:
		var act_index: int = row[0]
		var star1: Array = row[1]
		var star2: Array = row[2]
		var result := _compile(act_index)
		assert_true(result.ok, "act %d should compile: %s" % [
			act_index, _error_text(result)
		])
		if not result.ok:
			continue
		var units := result.preview.enemy_units
		assert_eq(units.size(), 2, "act %d spawn count" % act_index)
		_assert_combat_stats(units[0], star1, "act %d star1" % act_index)
		_assert_combat_stats(units[1], star2, "act %d star2" % act_index)

func test_pace_and_reach_stats_are_identical_across_all_three_acts() -> void:
	var first := _compile(1)
	var second := _compile(2)
	var third := _compile(3)
	assert_true(first.ok and second.ok and third.ok, "all acts should compile")
	if not (first.ok and second.ok and third.ok):
		return
	for index: int in range(2):
		var a := first.preview.enemy_units[index]
		var b := second.preview.enemy_units[index]
		var c := third.preview.enemy_units[index]
		for property: StringName in [
			&"attack_speed_milli",
			&"move_speed_milli",
			&"attack_range_cells",
			&"start_mana",
			&"max_mana",
		]:
			assert_eq(b.get(property), a.get(property),
				"act2 must not change %s (unit %d)" % [property, index])
			assert_eq(c.get(property), a.get(property),
				"act3 must not change %s (unit %d)" % [property, index])

## 回歸鎖:act1 bps 恆等 10000,且 act1 輸出與本片之前的星級縮放值逐字相同。
func test_act1_multiplier_is_identity_and_pinned_to_ten_thousand() -> void:
	assert_eq(CombatConfigDef.new().act1_enemy_stat_bps, ACT1_BPS,
		"CombatConfigDef default act1 multiplier must be identity")
	assert_eq(CombatConfigDef.new().act2_enemy_stat_bps, ACT2_BPS)
	assert_eq(CombatConfigDef.new().act3_enemy_stat_bps, ACT3_BPS)
	var authored: CombatConfigDef = load(
		"res://content/packs/vertical_slice/combat_configs/combat_default.tres"
	) as CombatConfigDef
	assert_not_null(authored, "authored combat_default must load")
	if authored == null:
		return
	assert_eq(authored.act1_enemy_stat_bps, ACT1_BPS,
		"authored act1 multiplier must stay identity")
	assert_eq(authored.act2_enemy_stat_bps, ACT2_BPS)
	assert_eq(authored.act3_enemy_stat_bps, ACT3_BPS)
	var result := _compile(1)
	assert_true(result.ok, _error_text(result))
	if not result.ok:
		return
	_assert_combat_stats(result.preview.enemy_units[0], [100, 10, 5, 5], "act1 star1")
	_assert_combat_stats(result.preview.enemy_units[1], [180, 18, 9, 9], "act1 star2")

func test_recompiling_the_same_request_is_byte_identical() -> void:
	var request := _request(3)
	var first := _compiler.compile(request, _catalog())
	var second := _compiler.compile(request, _catalog())
	assert_true(first.ok and second.ok, "act3 should compile twice")
	if not (first.ok and second.ok):
		return
	# 直接比對正式 canonical serializer 的輸出,而不是在測試裡重寫一份序列化。
	var writer := BattleCanonicalWriterV2.new()
	assert_eq(
		writer.call("_write_encounter", first.preview) as String,
		writer.call("_write_encounter", second.preview) as String,
		"same request must produce byte-identical preview"
	)

## i32 守衛必須套在「act 縮放後」的值:star 縮放後仍在 i32 內、act3 縮放後溢位 → RULE_INVALID。
func test_act_scaled_value_outside_i32_is_rejected() -> void:
	var accepted := _compiler.compile(
		_request(1), _catalog(2000000000, true, true)
	)
	assert_true(accepted.ok,
		"act1 identity keeps the value inside i32: %s" % _error_text(accepted))
	var rejected := _compiler.compile(
		_request(3), _catalog(2000000000, true, true)
	)
	assert_false(rejected.ok, "act3 scaling overflows i32 and must fail closed")
	if rejected.ok:
		return
	assert_eq(rejected.error.code, EncounterCompiler.RULE_INVALID)
	assert_eq(rejected.error.source_id, &"unit.enemy")

func test_missing_combat_config_rule_fails_closed() -> void:
	var result := _compiler.compile(_request(2), _catalog(100, false))
	assert_false(result.ok, "compiler must not run without the pinned combat config")
	if result.ok:
		return
	assert_eq(result.error.code, EncounterCompiler.INPUT_INVALID)

func test_act_index_outside_one_to_three_fails_closed() -> void:
	for act_index: int in [0, 4]:
		var result := _compiler.compile(_request(act_index), _catalog())
		assert_false(result.ok, "act_index %d must be rejected" % act_index)
		if result.ok:
			continue
		assert_eq(result.error.code, EncounterCompiler.INPUT_INVALID,
			"act_index %d error code" % act_index)
		assert_eq(result.error.field_path, &"act_index",
			"act_index %d field path" % act_index)

## 新欄位必須進 content payload,且 payload 欄序與 BattleCombatConfigRule 的
## canonical 欄名清單對齊——BattleRuleCatalogBuilder._decode_config 就是靠這個對齊
## 把 children[index + 3] 寫回規則物件的。
func test_combat_config_payload_carries_the_three_act_multipliers() -> void:
	var definition := CombatConfigDef.new()
	definition.id = &"config.combat_default"
	definition.display_name_key = &"loc.config_combat_default"
	var compiled := ContentDefinitionCompilerV2.new().compile(definition)
	assert_true(compiled.ok, "combat config should compile")
	if not compiled.ok:
		return
	var codec := ContentCanonicalCodecV2.new()
	var encoded := codec.encode_entry(compiled.entry)
	assert_true(encoded.ok, "combat config entry should encode")
	if not encoded.ok:
		return
	var decoded := codec.decode_entry(encoded.canonical_bytes)
	assert_true(decoded.ok, "combat config entry should decode")
	if not decoded.ok:
		return
	var children: Array = decoded.entry.payload.children
	var properties := BattleCombatConfigRule._integer_properties()
	assert_eq(children.size(), properties.size() + 3,
		"payload arity must stay in step with the canonical property list")
	for name: StringName in [
		&"act1_enemy_stat_bps", &"act2_enemy_stat_bps", &"act3_enemy_stat_bps"
	]:
		assert_true(properties.has(name),
			"%s must be a canonical combat config property" % name)
	for pair: Array in [
		[&"act1_enemy_stat_bps", ACT1_BPS],
		[&"act2_enemy_stat_bps", ACT2_BPS],
		[&"act3_enemy_stat_bps", ACT3_BPS],
	]:
		var index: int = properties.find(pair[0])
		assert_eq(children[index + 3].int_value, int(pair[1]),
			"payload slot for %s" % pair[0])

## 新欄位必須進 battle setup 的 canonical bytes(不得為了保住舊 hash 排除在外)。
func test_act_multipliers_are_part_of_the_canonical_battle_setup() -> void:
	var inputs: BattleSetupInputs = BattleSetupFixture.create_inputs()
	inputs.setup_schema_version = 2
	# v2 要求 effect source 帶完整歸屬欄位（沿用 test_battle_codec_v2 的最小補齊）。
	inputs.player_equipment_effects[0].source_category = &"equipment"
	inputs.player_equipment_effects[0].source_side = &"player"
	inputs.player_equipment_effects[0].source_instance_id = \
		OptionalStringNameValue.of(&"u_0000000000000001")
	inputs.player_equipment_effects[0].source_slot = 0
	# 玩家棋子引用 ability.test／effect.test，pinned rules 必須同時帶上這兩條規則。
	var ability := BattleAbilityRuleSnapshot.new()
	ability.ability_id = &"ability.test"
	ability.target_rule = &"self"
	ability.cast_ticks = 1
	ability.effect_ids = [&"effect.test"]
	inputs.battle_rules.ability_rules.append(ability)
	var effect := BattleEffectRuleSnapshot.new()
	effect.effect_id = &"effect.test"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	inputs.battle_rules.effect_rules.append(effect)
	var codec := CanonicalBattleCodecV2.new()
	var baseline := codec.encode(inputs)
	assert_true(baseline.ok, "baseline setup should encode: %s" % (
		"" if baseline.ok else "%s:%s" % [
			String(baseline.error.code), String(baseline.error.field_path)
		]
	))
	if not baseline.ok:
		return
	var text := baseline.canonical_bytes.get_string_from_utf8()
	for name: String in [
		"act1_enemy_stat_bps", "act2_enemy_stat_bps", "act3_enemy_stat_bps"
	]:
		assert_true(text.contains("\"%s\":" % name),
			"%s must appear in canonical battle bytes" % name)
	inputs.battle_rules.act2_enemy_stat_bps = ACT2_BPS + 1
	var mutated := codec.encode(inputs)
	assert_true(mutated.ok, "mutated setup should still encode")
	if not mutated.ok:
		return
	assert_ne(mutated.canonical_bytes, baseline.canonical_bytes,
		"changing an act multiplier must change the canonical bytes")

func _assert_combat_stats(
	unit: UnitBattleSnapshot, expected: Array, label: String
) -> void:
	assert_eq(unit.health, int(expected[0]), "%s health" % label)
	assert_eq(unit.attack, int(expected[1]), "%s attack" % label)
	assert_eq(unit.armor, int(expected[2]), "%s armor" % label)
	assert_eq(unit.magic_resist, int(expected[3]), "%s magic_resist" % label)

func _compile(act_index: int) -> EncounterCompileResult:
	return _compiler.compile(_request(act_index), _catalog())

func _request(act_index: int) -> EncounterCompileRequest:
	var request := EncounterCompileRequest.new()
	request.manifest_digest = DIGEST
	request.encounter_id = &"encounter.act_scaling"
	request.node_id = &"node_d94992320541276dfd384a614e280c0e1e0f804931a3ba6ec8e59fd467a033bc"
	request.act_index = act_index
	request.depth = 5
	request.challenge_level = 0
	return request

func _catalog(
	base_health: int = 100,
	with_config: bool = true,
	star1_only: bool = false
) -> BattleRuleCatalog:
	var unit := BattleUnitRule.new()
	unit.unit_id = &"unit.enemy"
	unit.base_stats = BattleUnitStatsRule.new()
	unit.base_stats.health = base_health
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
		scaling.attack_speed_bps = 10000
		scaling.attack_range_bps = 10000
		scaling.start_mana_bps = 10000
		scaling.max_mana_bps = 10000
		scaling.move_speed_bps = 10000
		unit.star_scalings.append(scaling)
	var units: Array[BattleUnitRule] = [unit]
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = [_encounter(star1_only)]
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	if with_config:
		configs.append(_config())
	return BattleRuleCatalog.new(
		DIGEST, units, traits, abilities, effects, encounters, equipment, configs
	)

func _config() -> BattleCombatConfigRule:
	var config := BattleCombatConfigRule.new()
	config.config_id = &"config.combat_default"
	var defaults := CombatConfigDef.new()
	for property: StringName in BattleCombatConfigRule._integer_properties():
		config.set(property, defaults.get(property))
	return config

func _encounter(star1_only: bool = false) -> BattleEncounterRule:
	var frontline := BattleEnemySpawnRule.new()
	frontline.side = &"enemy"
	frontline.logical_y = 4
	frontline.logical_x = 1
	frontline.spawn_key = "frontline_0"
	frontline.unit_id = &"unit.enemy"
	frontline.star = 1
	var elite := BattleEnemySpawnRule.new()
	elite.side = &"enemy"
	elite.logical_y = 6
	elite.logical_x = 3
	elite.spawn_key = "elite_0"
	elite.unit_id = &"unit.enemy"
	elite.star = 2
	var encounter := BattleEncounterRule.new()
	encounter.encounter_id = &"encounter.act_scaling"
	encounter.encounter_kind = &"normal"
	encounter.preview_schema_version = 1
	var spawns: Array[BattleEnemySpawnRule] = [frontline]
	if not star1_only:
		spawns.append(elite)
	encounter.enemy_spawns = spawns
	return encounter

func _error_text(result: EncounterCompileResult) -> String:
	if result.ok or result.error == null:
		return ""
	return "%s:%s:%s" % [
		String(result.error.code),
		String(result.error.field_path),
		String(result.error.source_id),
	]
