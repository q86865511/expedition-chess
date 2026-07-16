extends GutTest

var _validator := EncounterPreviewValidator.new()

func test_valid_preview_keeps_explicit_boss_source_through_clone() -> void:
	var preview := _preview()
	var result := _validator.validate(preview, [&"u_0000000000000001"])
	assert_true(result.ok)
	var copied := preview.deep_clone()
	preview.boss_phases[0].source_instance_id = &"e_ffffffffffffffff"
	assert_eq(copied.boss_phases[0].source_instance_id, &"e_00be5709edb0379b")

func test_player_enemy_id_collision_is_fatal_without_retry() -> void:
	var result := _validator.validate(
		_preview(),
		[&"e_00be5709edb0379b"]
	)
	assert_false(result.ok)
	assert_eq(result.error.code, EncounterPreviewValidator.ENTITY_ID_COLLISION)
	assert_eq(result.error.source_id, &"e_00be5709edb0379b")

func test_duplicate_enemy_id_is_fatal() -> void:
	var preview := _preview()
	var duplicate := preview.enemy_units[0].deep_clone()
	duplicate.logical_x = 5
	preview.enemy_units.append(duplicate)
	var result := _validator.validate(preview)
	assert_false(result.ok)
	assert_eq(result.error.code, EncounterPreviewValidator.ENTITY_ID_COLLISION)

func test_phase_source_must_resolve_to_enemy_in_same_preview() -> void:
	var preview := _preview()
	preview.boss_phases[0].source_instance_id = &"e_ffffffffffffffff"
	var result := _validator.validate(preview)
	assert_false(result.ok)
	assert_eq(result.error.code, EncounterPreviewValidator.INVALID)
	assert_eq(
		result.error.field_path,
		&"preview.boss_phases.0.source_instance_id"
	)

func _preview() -> EncounterPreviewSnapshot:
	var unit := UnitBattleSnapshot.new()
	unit.instance_id = &"e_00be5709edb0379b"
	unit.unit_id = &"unit.boss"
	unit.side = &"enemy"
	unit.logical_y = 6
	unit.logical_x = 3
	unit.star = 2
	unit.health = 1000
	unit.attack = 50
	unit.attack_speed_milli = 1000
	unit.attack_range_cells = 1
	unit.max_mana = 100
	unit.move_speed_milli = 1000
	var trait_snapshot := TraitBattleSnapshot.new()
	trait_snapshot.trait_id = &"trait.boss"
	trait_snapshot.tier = 1
	trait_snapshot.member_instance_ids = [unit.instance_id]
	var phase := BossPhaseSnapshot.new()
	phase.phase_index = 0
	phase.hp_threshold_bps = 5000
	phase.source_instance_id = unit.instance_id
	phase.effect_ids = [&"effect.phase"]
	var preview := EncounterPreviewSnapshot.new()
	preview.encounter_id = &"encounter.boss"
	preview.manifest_digest = StringName("a".repeat(64))
	preview.enemy_units = [unit]
	preview.active_traits = [trait_snapshot]
	preview.boss_phases = [phase]
	return preview
