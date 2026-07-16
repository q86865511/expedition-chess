extends SceneTree

const Support = preload("res://tests/runners/runner_support.gd")
const ARTIFACT_PATH := "res://artifacts/test/combat-runner.json"

var _started_at_utc := ""

func _init() -> void:
	_started_at_utc = Support.utc_now()
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	var assertions := 0
	var setup := _fast_setup(U64Bits.zero())
	assertions += 1
	if setup == null:
		failures.append("fast BattleSetup build failed")
	else:
		var first := _simulate(setup)
		var second := _simulate(setup)
		assertions += 4
		if first == null or second == null:
			failures.append("canonical combat did not finish")
		elif first.result_hash != second.result_hash \
			or first.summary_hash != second.summary_hash:
			failures.append("same setup produced different result/event summary")
		elif first.final_tick > 1800 or first.validate() != null:
			failures.append("canonical result invariant failed")
	var stress_setup := _stress_setup()
	assertions += 1
	if stress_setup == null:
		failures.append("32v32/64-entity stress setup build failed")
	else:
		var stress := _simulate(stress_setup)
		assertions += 3
		if stress == null:
			failures.append("32v32/64-entity stress did not finish")
		elif stress.final_tick > 1800:
			failures.append("32v32/64-entity stress exceeded hard limit")
	var completed: Array[String] = [
		"battle_simulation_quick_regression",
		"battle_result_event_canonical",
		"battle_32v32_64_entity_stress",
	]
	var deferred: Array[String] = ["battle_10000_seed_soak"]
	var report := Support.base_report("combat", _started_at_utc, completed, deferred)
	report["case_count"] = 2
	report["assertion_count"] = assertions
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	report["acceptance"] = {
		"AC-COMBAT-CANONICAL": failures.is_empty(),
		"AC-COMBAT-64-ENTITY": stress_setup != null,
	}
	var written := Support.write_json_artifact(ARTIFACT_PATH, report)
	quit(3 if written != OK else (0 if failures.is_empty() else 2))

func _simulate(setup: BattleSetup) -> BattleResult:
	var simulation := BattleSimulation.new()
	if not simulation.initialize(setup).ok:
		return null
	for _index: int in range(1801):
		var stepped := simulation.step()
		if not stepped.ok:
			return null
		for event: BattleEvent in stepped.events:
			if not BattleEventCodecV1.new().encode(event).ok:
				return null
		if stepped.finished:
			var queried := simulation.result()
			return queried.result if queried.ok else null
	return null

func _fast_setup(seed: U64Bits) -> BattleSetup:
	var inputs := _inputs()
	inputs.player_units.append(_unit(&"u_0000000000000001", &"unit.proxy_a", &"player", 3, 3))
	inputs.encounter_snapshot.enemy_units.append(
		_unit(&"e_0000000000000001", &"unit.proxy_b", &"enemy", 4, 3)
	)
	inputs.player_units[0].attack = 1000
	return _build(inputs, seed)

func _stress_setup() -> BattleSetup:
	var inputs := _inputs()
	for index: int in range(32):
		var py := index / 8
		var px := index % 8
		var ey := index / 8 + 4
		var ex := index % 8
		var player_id := StringName("u_%016x" % (index + 1))
		var enemy_id := StringName("e_%016x" % (index + 1))
		var player := _unit(player_id, &"unit.proxy_a", &"player", py, px)
		var enemy := _unit(enemy_id, &"unit.proxy_b", &"enemy", ey, ex)
		player.attack_range_cells = 7
		enemy.attack_range_cells = 7
		inputs.player_units.append(player)
		inputs.encounter_snapshot.enemy_units.append(enemy)
	return _build(inputs, U64Bits.one())

func _inputs() -> BattleSetupInputs:
	var preview := EncounterPreviewSnapshot.new()
	preview.preview_schema_version = 1
	preview.encounter_id = &"encounter.runner"
	preview.manifest_digest = &"0000000000000000000000000000000000000000000000000000000000000000"
	var inputs := BattleSetupInputs.new()
	inputs.setup_schema_version = 2
	inputs.content_version = "runner.1"
	inputs.manifest_digest = preview.manifest_digest
	inputs.encounter_snapshot = preview
	inputs.battle_rules = BattleRulesSnapshot.new()
	return inputs

func _unit(
	instance_id: StringName,
	unit_id: StringName,
	side: StringName,
	y: int,
	x: int
) -> UnitBattleSnapshot:
	var unit := UnitBattleSnapshot.new()
	unit.instance_id = instance_id
	unit.unit_id = unit_id
	unit.side = side
	unit.logical_y = y
	unit.logical_x = x
	unit.health = 100
	unit.attack = 100
	unit.attack_speed_milli = 1000
	unit.attack_range_cells = 1
	unit.move_speed_milli = 1000
	return unit

func _build(inputs: BattleSetupInputs, seed: U64Bits) -> BattleSetup:
	var validated := BattleSetupInputsValidator.new().validate_for_build(inputs)
	if not validated.ok:
		return null
	var built := BattleSetupHashBuilder.new(seed).build_from_validated(
		inputs, validated.receipt
	)
	return built.battle_setup if built.ok else null
