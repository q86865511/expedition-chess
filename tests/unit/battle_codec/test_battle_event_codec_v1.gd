extends GutTest

const SOURCE: StringName = &"u_0000000000000001"
const TARGET: StringName = &"e_0000000000000001"

func test_all_fourteen_event_payloads_round_trip_canonical_bytes() -> void:
	var codec := BattleEventCodecV1.new()
	var events := _events()
	assert_eq(events.size(), BattleEvent.TYPES.size())
	for index: int in range(events.size()):
		var event := events[index]
		event.sequence = index
		var encoded := codec.encode(event)
		assert_true(encoded.ok, String(event.type))
		if not encoded.ok:
			continue
		var decoded := codec.decode(encoded.canonical_bytes)
		assert_true(decoded.ok, String(event.type))
		assert_eq(decoded.event.type, event.type)
		assert_eq(
			codec.encode(decoded.event).canonical_bytes,
			encoded.canonical_bytes,
			String(event.type)
		)

func test_unknown_type_wrong_payload_and_noncanonical_bytes_are_rejected() -> void:
	var codec := BattleEventCodecV1.new()
	var unknown := _event(&"unknown", SOURCE, [], SpawnEventPayload.new())
	var rejected := codec.encode(unknown)
	assert_false(rejected.ok)
	assert_eq(rejected.error.code, BattleEventCodecError.TYPE_UNKNOWN)
	var wrong := _events()[0]
	wrong.payload = DamageEventPayload.new()
	assert_false(codec.encode(wrong).ok)
	var valid := codec.encode(_events()[0])
	var noncanonical := (" " + valid.canonical_bytes.get_string_from_utf8()).to_utf8_buffer()
	assert_false(codec.decode(noncanonical).ok)

func _events() -> Array[BattleEvent]:
	var values: Array[BattleEvent] = []
	var spawn := SpawnEventPayload.new()
	spawn.unit_id = &"unit.codec_proxy"
	spawn.side = &"player"
	spawn.origin = &"player"
	spawn.logical_y = 3
	spawn.logical_x = 3
	values.append(_event(&"spawn", &"", [SOURCE], spawn))
	var move := MoveEventPayload.new()
	move.from_y = 3; move.from_x = 3; move.to_y = 3; move.to_x = 4
	values.append(_event(&"move", SOURCE, [], move))
	var attack := AttackEventPayload.new()
	attack.raw_damage = 10; attack.presentation_profile = &"basic.frontline"
	values.append(_event(&"attack", SOURCE, [TARGET], attack))
	var cast := CastEventPayload.new()
	cast.ability_id = &"ability.codec_proxy"; cast.action = &"resolve"
	cast.fizzle_reason = &"none"; cast.resolve_tick = 1
	values.append(_event(&"cast", SOURCE, [TARGET], cast))
	var damage := DamageEventPayload.new()
	damage.damage_type = &"physical"; damage.raw_amount = 10
	damage.post_resistance_amount = 10; damage.health_damage = 10
	damage.health_after = 90
	values.append(_event(&"damage", SOURCE, [TARGET], damage))
	var heal := HealEventPayload.new()
	heal.requested = 10; heal.applied = 10; heal.health_after = 100
	values.append(_event(&"heal", SOURCE, [SOURCE], heal))
	var shield := ShieldEventPayload.new()
	shield.delta = 10; shield.remaining = 10; shield.expires_tick = 20
	values.append(_event(&"shield", SOURCE, [SOURCE], shield))
	var mana := ManaEventPayload.new()
	mana.reason = &"attack"; mana.delta = 10; mana.mana_after = 10
	values.append(_event(&"mana", SOURCE, [SOURCE], mana))
	var modifier := ModifierEventPayload.new()
	modifier.stat = &"attack"; modifier.mode = &"add"; modifier.amount = 1
	modifier.expires_tick = 20; modifier.action = &"apply"
	values.append(_event(&"modifier", SOURCE, [SOURCE], modifier))
	var status := StatusEventPayload.new()
	status.status_id = &"effect.codec_status"; status.action = &"apply"
	status.stacks = 1; status.remaining_ticks = 20
	values.append(_event(&"status", SOURCE, [SOURCE], status))
	var death := DeathEventPayload.new()
	death.origin = &"encounter"; death.logical_y = 4; death.logical_x = 3
	values.append(_event(&"death", TARGET, [SOURCE], death))
	var phase := BossPhaseEventPayload.new()
	phase.phase_index = 1; phase.hp_threshold_bps = 5000
	values.append(_event(&"boss_phase", TARGET, [], phase))
	var failure := SummonFailureEventPayload.new()
	failure.unit_id = &"unit.codec_summon"; failure.request_ordinal = 0
	failure.reason = &"max_active"
	values.append(_event(&"summon_failure", SOURCE, [], failure))
	var finished := BattleFinishedEventPayload.new()
	finished.outcome = &"player_win"; finished.expedition_damage = 0
	values.append(_event(&"battle_finished", &"", [SOURCE], finished))
	return values

func _event(
	type: StringName,
	source: StringName,
	targets: Array[StringName],
	payload: BattleEventPayload
) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = type
	event.source_instance_id = OptionalStringNameValue.of(source) \
		if not source.is_empty() else null
	event.target_instance_ids = targets.duplicate()
	event.payload = payload
	return event
