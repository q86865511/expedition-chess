extends GutTest

const Frames = preload(
	"res://assets/production/units/slice_player_00.tres"
)
const ALLY_ID: StringName = &"u_0000000000000001"
const ENEMY_ID: StringName = &"e_0000000000000001"
const SUMMON_ID: StringName = &"s_0000000000000001"


func test_after_values_and_move_destination_drive_renderer_snapshot() -> void:
	var setup := _setup_snapshot()
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(setup), &"")
	var damage := _damage(ALLY_ID, 61)
	var heal := _heal(ALLY_ID, 74)
	var mana := _mana(ALLY_ID, 53)
	var move := _move(ALLY_ID, Vector2i(1, 2), Vector2i(4, 3))
	var events: Array = [damage, heal, mana, move]
	var codec := BattleEventCodecV1.new()
	var committed_bytes: Array[PackedByteArray] = []
	for event: BattleEvent in events:
		var encoded := codec.encode(event)
		assert_true(encoded.ok)
		committed_bytes.append(encoded.canonical_bytes.duplicate())

	assert_eq(projection.apply_window(events), &"")
	var presented := projection.snapshot_clone()
	var ally := _unit(presented, ALLY_ID)
	assert_not_null(ally)
	if ally == null:
		return
	assert_eq(ally.health, 74, "heal must copy health_after, not recompute it")
	assert_eq(ally.mana, 53, "mana must copy mana_after, not apply delta")
	assert_eq(ally.logical_cell, Vector2i(4, 3))

	# The reducer owns a clone: neither setup nor committed transcript payloads
	# may be rewritten while presentation advances.
	var setup_ally := _unit(setup, ALLY_ID)
	assert_eq(setup_ally.health, 100)
	assert_eq(setup_ally.mana, 10)
	assert_eq(setup_ally.logical_cell, Vector2i(1, 2))
	assert_eq((damage.payload as DamageEventPayload).health_after, 61)
	assert_eq((heal.payload as HealEventPayload).health_after, 74)
	assert_eq((mana.payload as ManaEventPayload).mana_after, 53)
	assert_eq((move.payload as MoveEventPayload).to_x, 4)
	assert_eq((move.payload as MoveEventPayload).to_y, 3)
	for index: int in events.size():
		var reencoded := codec.encode(events[index] as BattleEvent)
		assert_true(reencoded.ok)
		assert_eq(reencoded.canonical_bytes, committed_bytes[index])

	var renderer := WorldBoardRenderer.new()
	add_child_autofree(renderer)
	assert_eq(renderer.render_snapshot(presented), &"")
	var sprite := renderer.unit_sprite(ALLY_ID)
	assert_not_null(sprite)
	if sprite != null:
		assert_eq(sprite.get_meta(&"logical_cell"), Vector2i(4, 3))
		assert_eq(
			sprite.position,
			BoardProjection.new().project_cell(Vector2i(4, 3)).round()
		)


func test_unknown_target_rejects_whole_window_without_partial_update() -> void:
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(_setup_snapshot()), &"")
	var events: Array = [
		_damage(ALLY_ID, 40),
		_mana(&"u_ffffffffffffffff", 75),
	]

	assert_eq(
		projection.apply_window(events),
		CombatWorldEventProjection.EVENT_TARGET_UNKNOWN
	)
	var unchanged := _unit(
		projection.snapshot_clone(),
		ALLY_ID
	)
	assert_not_null(unchanged)
	if unchanged != null:
		assert_eq(unchanged.health, 100)
		assert_eq(unchanged.mana, 10)
		assert_eq(unchanged.logical_cell, Vector2i(1, 2))


func test_invalid_payload_type_and_move_origin_fail_closed() -> void:
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(_setup_snapshot()), &"")
	var wrong_payload := BattleEvent.new()
	wrong_payload.type = &"damage"
	wrong_payload.target_instance_ids.assign([ALLY_ID])
	wrong_payload.payload = ManaEventPayload.new()
	assert_eq(
		projection.apply_window([wrong_payload]),
		CombatWorldEventProjection.EVENT_INVALID
	)
	var wrong_origin := _move(
		ALLY_ID,
		Vector2i(0, 0),
		Vector2i(2, 2)
	)
	assert_eq(
		projection.apply_window([wrong_origin]),
		CombatWorldEventProjection.EVENT_INVALID
	)
	assert_eq(
		_unit(
			projection.snapshot_clone(),
			ALLY_ID
		).logical_cell,
		Vector2i(1, 2)
	)


func test_unknown_codec_event_is_rejected_without_touching_snapshot() -> void:
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(_setup_snapshot()), &"")
	var event := BattleEvent.new()
	event.type = &"future_event"
	event.payload = BattleEventPayload.new()
	assert_eq(
		projection.apply_window([event]),
		CombatWorldEventProjection.EVENT_INVALID
	)
	assert_eq(
		_unit(
			projection.snapshot_clone(),
			ALLY_ID
		).health,
		100
	)


func test_death_removes_rendered_unit_by_authoritative_source_id() -> void:
	var setup := _setup_snapshot()
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(setup), &"")
	# The payload cell is valid codec data but deliberately differs from the
	# setup cell: stable source identity, not presentation coordinates, owns
	# which entity dies.
	var death := _death(ALLY_ID, &"player", Vector2i(7, 7))
	var codec := BattleEventCodecV1.new()
	var before := codec.encode(death)
	assert_true(before.ok)

	assert_eq(projection.apply_window([death]), &"")
	var presented := projection.snapshot_clone()
	assert_null(_unit(presented, ALLY_ID))
	assert_not_null(_unit(presented, ENEMY_ID))
	assert_not_null(_unit(setup, ALLY_ID), "compose must retain only a clone")
	var after := codec.encode(death)
	assert_true(after.ok)
	assert_eq(after.canonical_bytes, before.canonical_bytes)


func test_late_events_for_dead_rendered_id_are_no_ops_within_window() -> void:
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(_setup_snapshot()), &"")
	var events: Array = [
		_death(ALLY_ID, &"player", Vector2i(1, 2)),
		_damage(ALLY_ID, 0),
		_heal(ALLY_ID, 1),
		_mana(ALLY_ID, 99),
		_move(ALLY_ID, Vector2i(1, 2), Vector2i(2, 2)),
		_damage(ENEMY_ID, 77),
	]
	for event: BattleEvent in events:
		assert_true(BattleEventCodecV1.new().encode(event).ok)

	assert_eq(projection.apply_window(events), &"")
	var presented := projection.snapshot_clone()
	assert_null(_unit(presented, ALLY_ID))
	assert_eq(_unit(presented, ENEMY_ID).health, 77)


func test_setup_id_spawn_after_death_is_no_op_without_resurrection() -> void:
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(_setup_snapshot()), &"")
	var events: Array = [
		_death(ALLY_ID, &"player", Vector2i(1, 2)),
		_spawn(
			ALLY_ID,
			&"unit.codec_proxy",
			&"player",
			&"player",
			Vector2i(3, 3)
		),
		_damage(ALLY_ID, 45),
	]

	assert_eq(projection.apply_window(events), &"")
	assert_null(
		_unit(projection.snapshot_clone(), ALLY_ID),
		"setup spawn lacks fresh max-stat authority and cannot resurrect a sprite"
	)


func test_setup_spawn_is_explicit_no_op_and_does_not_hide_rendered_unit() -> void:
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(_setup_snapshot()), &"")
	var events: Array = [
		_spawn(ALLY_ID, &"unit.codec_proxy", &"player", &"player", Vector2i(3, 3)),
		_damage(ALLY_ID, 48),
	]

	assert_eq(projection.apply_window(events), &"")
	var ally := _unit(projection.snapshot_clone(), ALLY_ID)
	assert_not_null(ally)
	if ally != null:
		assert_eq(ally.health, 48)


func test_unrenderable_spawn_lifecycle_does_not_rollback_rendered_updates() -> void:
	var setup := _setup_snapshot()
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(setup), &"")
	var spawn := _spawn(
		SUMMON_ID,
		&"unit.codec_summon",
		&"player",
		&"summon",
		Vector2i(2, 3)
	)
	var summon_mana := _mana(SUMMON_ID, 25)
	var summon_move := _move(SUMMON_ID, Vector2i(2, 3), Vector2i(3, 3))
	var summon_death := _death(SUMMON_ID, &"summon", Vector2i(3, 3))
	var events: Array = [
		_damage(ALLY_ID, 63),
		spawn,
		summon_mana,
		summon_move,
		_damage(ALLY_ID, 37),
		summon_death,
	]
	var codec := BattleEventCodecV1.new()
	var canonical_before: Array[PackedByteArray] = []
	for event: BattleEvent in events:
		var encoded := codec.encode(event)
		assert_true(encoded.ok, String(event.type))
		canonical_before.append(encoded.canonical_bytes.duplicate())

	assert_eq(projection.apply_window(events), &"")
	var presented := projection.snapshot_clone()
	var ally := _unit(presented, ALLY_ID)
	assert_not_null(ally)
	if ally != null:
		assert_eq(ally.health, 37)
	assert_null(
		_unit(presented, SUMMON_ID),
		"spawn lacks complete visual/max-stat authority and must not fabricate a unit"
	)
	# Death retains a presentation-only tombstone. A delayed valid event for the
	# known id is a no-op instead of freezing later renderable updates.
	assert_eq(
		projection.apply_window([_damage(SUMMON_ID, 0)]),
		&""
	)
	assert_eq(_unit(projection.snapshot_clone(), ALLY_ID).health, 37)
	assert_eq(_unit(setup, ALLY_ID).health, 100)
	for index: int in events.size():
		var reencoded := codec.encode(events[index] as BattleEvent)
		assert_true(reencoded.ok)
		assert_eq(reencoded.canonical_bytes, canonical_before[index])


func test_same_nonsetup_id_spawn_starts_new_unrenderable_lifecycle() -> void:
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(_setup_snapshot()), &"")
	var summon_spawn := _spawn(
		SUMMON_ID,
		&"unit.codec_summon",
		&"player",
		&"summon",
		Vector2i(2, 3)
	)
	assert_eq(
		projection.apply_window([
			summon_spawn,
			_death(SUMMON_ID, &"summon", Vector2i(2, 3)),
		]),
		&""
	)
	assert_eq(
		projection.apply_window([
			summon_spawn,
			_mana(SUMMON_ID, 20),
			_move(SUMMON_ID, Vector2i(2, 3), Vector2i(3, 3)),
		]),
		&""
	)
	assert_null(_unit(projection.snapshot_clone(), SUMMON_ID))


func test_failed_window_does_not_leak_dead_tombstone() -> void:
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(_setup_snapshot()), &"")
	var malformed_attack := _attack(ALLY_ID, ENEMY_ID, -1)
	assert_false(BattleEventCodecV1.new().encode(malformed_attack).ok)

	assert_eq(
		projection.apply_window([
			_death(ALLY_ID, &"player", Vector2i(1, 2)),
			malformed_attack,
		]),
		CombatWorldEventProjection.EVENT_INVALID
	)
	assert_eq(projection.apply_window([_damage(ALLY_ID, 52)]), &"")
	assert_eq(_unit(projection.snapshot_clone(), ALLY_ID).health, 52)


func test_codec_rejects_malformed_known_event_and_rolls_back_tracking_atomically() -> void:
	var projection := CombatWorldEventProjection.new()
	assert_eq(projection.compose(_setup_snapshot()), &"")
	var spawn := _spawn(
		SUMMON_ID,
		&"unit.codec_summon",
		&"player",
		&"summon",
		Vector2i(2, 3)
	)
	var malformed_attack := _attack(ALLY_ID, ENEMY_ID, -1)
	assert_false(
		BattleEventCodecV1.new().encode(malformed_attack).ok,
		"the formal codec owns ignored-event payload validation"
	)

	assert_eq(
		projection.apply_window([
			_damage(ALLY_ID, 42),
			spawn,
			malformed_attack,
		]),
		CombatWorldEventProjection.EVENT_INVALID
	)
	assert_eq(_unit(projection.snapshot_clone(), ALLY_ID).health, 100)
	# The failed window must not leak its unrenderable-spawn tracking state.
	assert_eq(
		projection.apply_window([_mana(SUMMON_ID, 20)]),
		CombatWorldEventProjection.EVENT_TARGET_UNKNOWN
	)
	assert_eq(_unit(projection.snapshot_clone(), ALLY_ID).health, 100)


func _setup_snapshot() -> WorldBoardSnapshot:
	var result := WorldBoardSnapshot.new()
	result.append_unit(_world_unit(
		ALLY_ID,
		Vector2i(1, 2),
		100,
		10
	))
	result.append_unit(_world_unit(
		ENEMY_ID,
		Vector2i(6, 6),
		120,
		20
	))
	return result


func _world_unit(
	presentation_id: StringName,
	cell: Vector2i,
	health: int,
	mana: int
) -> WorldBoardUnitSnapshot:
	var unit := WorldBoardUnitSnapshot.new()
	unit.presentation_instance_id = presentation_id
	unit.logical_cell = cell
	unit.sprite_frames = Frames
	unit.animation = &"idle_s_star1"
	unit.health = health
	unit.max_health = health
	unit.mana = mana
	unit.max_mana = 100
	return unit


func _damage(target_id: StringName, health_after: int) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"damage"
	event.target_instance_ids.assign([target_id])
	var payload := DamageEventPayload.new()
	payload.damage_type = &"physical"
	payload.health_after = health_after
	event.payload = payload
	return event


func _heal(target_id: StringName, health_after: int) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"heal"
	event.target_instance_ids.assign([target_id])
	var payload := HealEventPayload.new()
	payload.health_after = health_after
	event.payload = payload
	return event


func _mana(target_id: StringName, mana_after: int) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"mana"
	event.target_instance_ids.assign([target_id])
	var payload := ManaEventPayload.new()
	payload.reason = &"effect"
	payload.mana_after = mana_after
	event.payload = payload
	return event


func _move(
	source_id: StringName,
	from_cell: Vector2i,
	to_cell: Vector2i
) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"move"
	event.source_instance_id = OptionalStringNameValue.of(source_id)
	var payload := MoveEventPayload.new()
	payload.from_x = from_cell.x
	payload.from_y = from_cell.y
	payload.to_x = to_cell.x
	payload.to_y = to_cell.y
	event.payload = payload
	return event


func _spawn(
	instance_id: StringName,
	unit_id: StringName,
	side: StringName,
	origin: StringName,
	cell: Vector2i
) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"spawn"
	event.target_instance_ids.assign([instance_id])
	var payload := SpawnEventPayload.new()
	payload.unit_id = unit_id
	payload.side = side
	payload.origin = origin
	payload.logical_x = cell.x
	payload.logical_y = cell.y
	event.payload = payload
	return event


func _death(
	source_id: StringName,
	origin: StringName,
	cell: Vector2i
) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"death"
	event.source_instance_id = OptionalStringNameValue.of(source_id)
	var payload := DeathEventPayload.new()
	payload.origin = origin
	payload.logical_x = cell.x
	payload.logical_y = cell.y
	event.payload = payload
	return event


func _attack(
	source_id: StringName,
	target_id: StringName,
	raw_damage: int
) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"attack"
	event.source_instance_id = OptionalStringNameValue.of(source_id)
	event.target_instance_ids.assign([target_id])
	var payload := AttackEventPayload.new()
	payload.raw_damage = raw_damage
	payload.presentation_profile = &"basic.frontline"
	event.payload = payload
	return event


func _unit(
	snapshot: WorldBoardSnapshot,
	presentation_id: StringName
) -> WorldBoardUnitSnapshot:
	if snapshot == null:
		return null
	for unit: WorldBoardUnitSnapshot in snapshot.units:
		if unit.presentation_instance_id == presentation_id:
			return unit
	return null
