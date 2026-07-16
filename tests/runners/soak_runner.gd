extends SceneTree

const Support = preload("res://tests/runners/runner_support.gd")
const ARTIFACT_PATH := "res://artifacts/test/soak.json"

var _started_at_utc := ""

func _init() -> void:
	_started_at_utc = Support.utc_now()
	call_deferred("_run")

func _run() -> void:
	var seed_count := _seed_count()
	if seed_count < 1:
		_finish(seed_count, ["invalid --seed-count"], 3)
		return
	var failures: Array[String] = []
	var maximum_tick := 0
	var result_hashes: Dictionary = {}
	var replay_count := 0
	for seed_index: int in range(seed_count):
		var seed_result := U64Bits.from_u32(0, seed_index)
		if not seed_result.ok:
			failures.append("seed conversion failed at %d" % seed_index)
			break
		var setup := _setup(seed_result.value)
		if setup == null:
			failures.append("setup build failed at %d" % seed_index)
			break
		var simulation := BattleSimulation.new()
		if not simulation.initialize(setup).ok:
			failures.append("initialize failed at %d" % seed_index)
			break
		var finished := false
		var previous_sequence := -1
		for _tick: int in range(1801):
			var stepped := simulation.step()
			if not stepped.ok:
				failures.append("step failed at seed %d" % seed_index)
				break
			for event: BattleEvent in stepped.events:
				if event.sequence <= previous_sequence \
					or not BattleEventCodecV1.new().encode(event).ok:
					failures.append("event order/codec failed at seed %d" % seed_index)
					break
				previous_sequence = event.sequence
			if not failures.is_empty():
				break
			if not _state_is_valid(simulation.state_snapshot(), 4):
				failures.append("entity/resource invariant failed at seed %d" % seed_index)
				break
			if stepped.finished:
				var queried := simulation.result()
				if not queried.ok or queried.result.final_tick > 1800 \
					or queried.result.validate() != null:
					failures.append("result invariant failed at seed %d" % seed_index)
				else:
					maximum_tick = maxi(maximum_tick, queried.result.final_tick)
					result_hashes[String(queried.result.result_hash)] = true
					if seed_index < mini(seed_count, 64):
						var replay := _simulate(setup)
						if replay == null \
							or replay.result_hash != queried.result.result_hash \
							or replay.summary_hash != queried.result.summary_hash:
							failures.append("RNG replay drift at seed %d" % seed_index)
						else:
							replay_count += 1
				finished = true
				break
		if not failures.is_empty() or not finished:
			if failures.is_empty():
				failures.append("battle did not finish at seed %d" % seed_index)
			break
	if failures.is_empty() and seed_count > 1 and result_hashes.size() < 2:
		failures.append("random target stream produced no observable variation")
	_finish(
		seed_count, failures, 0 if failures.is_empty() else 2,
		maximum_tick, result_hashes.size(), replay_count
	)

func _setup(seed: U64Bits) -> BattleSetup:
	var preview := EncounterPreviewSnapshot.new()
	preview.preview_schema_version = 1
	preview.encounter_id = &"encounter.soak"
	preview.manifest_digest = &"0000000000000000000000000000000000000000000000000000000000000000"
	for index: int in range(3):
		var enemy := _unit(
			StringName("e_%016x" % (index + 1)), &"unit.soak_enemy",
			&"enemy", 4
		)
		enemy.logical_x = 2 + index
		preview.enemy_units.append(enemy)
	var inputs := BattleSetupInputs.new()
	inputs.setup_schema_version = 2
	inputs.content_version = "soak.1"
	inputs.manifest_digest = preview.manifest_digest
	inputs.encounter_snapshot = preview
	inputs.player_units.append(_unit(&"u_0000000000000001", &"unit.soak_player", &"player", 3))
	inputs.player_units[0].health = 500
	inputs.player_units[0].attack = 1000
	inputs.player_units[0].start_mana = 50
	inputs.player_units[0].max_mana = 50
	inputs.player_units[0].ability_id = OptionalStringNameValue.of(&"ability.soak_random")
	inputs.player_units[0].effect_ids = [&"effect.soak_damage"]
	var assignment := BattleEffectSnapshot.new()
	assignment.source_category = &"unit"
	assignment.source_side = &"player"
	assignment.source_stable_id = &"unit.soak_player"
	assignment.source_instance_id = OptionalStringNameValue.of(&"u_0000000000000001")
	assignment.effect_id = &"effect.soak_damage"
	inputs.player_units[0].effect_assignments.append(assignment)
	inputs.battle_rules = BattleRulesSnapshot.new()
	var ability := BattleAbilityRuleSnapshot.new()
	ability.ability_id = &"ability.soak_random"
	ability.target_rule = &"random_enemy"
	ability.cast_ticks = 1
	ability.effect_ids = [&"effect.soak_damage"]
	inputs.battle_rules.ability_rules.append(ability)
	var effect := BattleEffectRuleSnapshot.new()
	effect.effect_id = &"effect.soak_damage"
	effect.trigger = &"cast"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	var damage := BattleOperationRule.new()
	damage.operation_index = 0
	damage.kind = &"damage"
	damage.base_amount = 1000
	damage.scaling = &"flat"
	damage.damage_type = &"magical"
	damage.target = &"target"
	effect.battle_operations.append(damage)
	inputs.battle_rules.effect_rules.append(effect)
	var validated := BattleSetupInputsValidator.new().validate_for_build(inputs)
	if not validated.ok:
		return null
	var built := BattleSetupHashBuilder.new(seed).build_from_validated(
		inputs, validated.receipt
	)
	return built.battle_setup if built.ok else null

func _simulate(setup: BattleSetup) -> BattleResult:
	var simulation := BattleSimulation.new()
	if not simulation.initialize(setup).ok:
		return null
	for _tick: int in range(1801):
		var stepped := simulation.step()
		if not stepped.ok:
			return null
		if stepped.finished:
			var queried := simulation.result()
			return queried.result if queried.ok else null
	return null

func _state_is_valid(state: BattleState, expected_entities: int) -> bool:
	if state == null or state.entities.size() != expected_entities:
		return false
	var ids: Dictionary = {}
	var occupied: Dictionary = {}
	for entity: BattleEntityState in state.entities:
		if entity == null or ids.has(String(entity.instance_id)) \
			or entity.health < 0 or entity.health > entity.max_health \
			or entity.mana < 0 or entity.mana > entity.max_mana:
			return false
		ids[String(entity.instance_id)] = true
		if entity.alive or entity.death_pending:
			var cell := "%d:%d" % [entity.logical_y, entity.logical_x]
			if occupied.has(cell):
				return false
			occupied[cell] = true
	return true

func _unit(
	instance_id: StringName,
	unit_id: StringName,
	side: StringName,
	y: int
) -> UnitBattleSnapshot:
	var value := UnitBattleSnapshot.new()
	value.instance_id = instance_id
	value.unit_id = unit_id
	value.side = side
	value.logical_y = y
	value.logical_x = 3
	value.health = 100
	value.attack = 10
	value.attack_speed_milli = 1000
	value.attack_range_cells = 1
	value.move_speed_milli = 1000
	return value

func _seed_count() -> int:
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == "--seed-count":
			return int(arguments[index + 1])
	return 10000

func _finish(
	seed_count: int,
	failures: Array[String],
	exit_code: int,
	maximum_tick: int = 0,
	unique_result_hashes: int = 0,
	replay_count: int = 0
) -> void:
	var completed: Array[String] = []
	if failures.is_empty():
		completed.append("battle_seed_soak")
	var deferred: Array[String] = []
	var report := Support.base_report("soak", _started_at_utc, completed, deferred)
	report["seed_count"] = seed_count
	report["case_count"] = seed_count
	report["maximum_final_tick"] = maximum_tick
	report["unique_result_hash_count"] = unique_result_hashes
	report["deterministic_replay_count"] = replay_count
	report["scope"] = "combat-core"
	report["global_ac_030"] = "downstream"
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var written := Support.write_json_artifact(ARTIFACT_PATH, report)
	quit(3 if written != OK else exit_code)
