class_name CombatLabProxySetupFactory
extends RefCounted

const PROXY_UNIT_IDS: Array[StringName] = [
	&"unit.proxy_vanguard", &"unit.proxy_guardian", &"unit.proxy_duelist",
	&"unit.proxy_ranger", &"unit.proxy_arcanist", &"unit.proxy_mender",
	&"unit.proxy_assassin", &"unit.proxy_summoner",
]

func build(
	boss: bool = false,
	player_cells: Array[Vector2i] = []
) -> BattleSetup:
	var preview := EncounterPreviewSnapshot.new()
	preview.preview_schema_version = 1
	preview.encounter_id = &"encounter.proxy_boss" if boss else &"encounter.proxy_normal"
	preview.manifest_digest = &"0000000000000000000000000000000000000000000000000000000000000000"
	var boss_source := _append_enemy_team(preview, boss)
	if boss:
		_append_boss_phases(preview, boss_source.instance_id)
	var inputs := BattleSetupInputs.new()
	inputs.setup_schema_version = 2
	inputs.content_version = "dev.proxy.1"
	inputs.manifest_digest = preview.manifest_digest
	inputs.encounter_snapshot = preview
	_append_player_team(inputs.player_units, player_cells)
	inputs.battle_rules = BattleRulesSnapshot.new()
	inputs.battle_rules.encounter_kind = &"boss" if boss else &"normal"
	var validation := BattleSetupInputsValidator.new().validate_for_build(inputs)
	if not validation.ok:
		return null
	var built := BattleSetupHashBuilder.new(U64Bits.zero()).build_from_validated(
		inputs, validation.receipt
	)
	return built.battle_setup if built.ok else null

func proxy_unit_ids() -> Array[StringName]:
	return PROXY_UNIT_IDS.duplicate()

func _append_player_team(
	output: Array[UnitBattleSnapshot],
	player_cells: Array[Vector2i]
) -> void:
	var stats: Array = [
		[220, 22, 24, 900, 1], [260, 18, 32, 850, 1],
		[170, 30, 12, 1200, 1], [145, 27, 8, 1050, 3],
		[135, 34, 6, 950, 3], [155, 16, 14, 900, 2],
		[125, 38, 5, 1300, 1], [150, 24, 10, 1000, 2],
	]
	for index: int in range(PROXY_UNIT_IDS.size()):
		var row: Array = stats[index]
		var cell := Vector2i(index % 4 + 2, index / 4)
		if player_cells.size() == PROXY_UNIT_IDS.size():
			cell = player_cells[index]
		output.append(_unit(
			StringName("u_%016x" % (index + 1)), PROXY_UNIT_IDS[index], &"player",
			cell.y, cell.x,
			int(row[0]), int(row[1]), int(row[2]), int(row[3]), int(row[4])
		))

func _append_enemy_team(
	preview: EncounterPreviewSnapshot,
	boss: bool
) -> UnitBattleSnapshot:
	if boss:
		var boss_unit := _unit(
			&"e_0000000000000001", &"monster.proxy_colossus", &"enemy",
			5, 3, 1200, 38, 28, 900, 2
		)
		preview.enemy_units.append(boss_unit)
		return boss_unit
	var enemy_ids: Array[StringName] = [
		&"monster.proxy_raider", &"monster.proxy_archer",
		&"monster.proxy_guard", &"monster.proxy_hexer",
	]
	for index: int in range(enemy_ids.size()):
		preview.enemy_units.append(_unit(
			StringName("e_%016x" % (index + 1)), enemy_ids[index], &"enemy",
			6 + index / 2, 2 + index % 2 * 3,
			240 - index * 20, 25 + index * 2, 14 + index * 3,
			950 + index * 50, 3 if index in [1, 3] else 1
		))
	return preview.enemy_units[0]

func _append_boss_phases(
	preview: EncounterPreviewSnapshot,
	source_instance_id: StringName
) -> void:
	for phase_index: int in range(2):
		var phase := BossPhaseSnapshot.new()
		phase.phase_index = phase_index
		phase.hp_threshold_bps = 7500 if phase_index == 0 else 3500
		phase.source_instance_id = source_instance_id
		preview.boss_phases.append(phase)

func _unit(
	instance_id: StringName,
	unit_id: StringName,
	side: StringName,
	y: int,
	x: int,
	health: int,
	attack: int,
	armor: int,
	speed: int,
	range_cells: int
) -> UnitBattleSnapshot:
	var unit := UnitBattleSnapshot.new()
	unit.instance_id = instance_id
	unit.unit_id = unit_id
	unit.side = side
	unit.logical_y = y
	unit.logical_x = x
	unit.health = health
	unit.attack = attack
	unit.armor = armor
	unit.magic_resist = armor
	unit.attack_speed_milli = speed
	unit.attack_range_cells = range_cells
	unit.move_speed_milli = 1000
	return unit
