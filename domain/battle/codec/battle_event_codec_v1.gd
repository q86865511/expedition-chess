class_name BattleEventCodecV1
extends RefCounted

const VERSION: int = 1
const MAX_TICK: int = 1800
const MAX_I32: int = 2147483647

var _stable_ids := StableIdValidator.new()
var _entity_ids := RegEx.new()

func _init() -> void:
	_entity_ids.compile("^[ues]_[0-9a-f]{16}$")

func encode(value: BattleEvent) -> BattleEventCodecResult:
	var invalid := _validate(value)
	if invalid != null:
		return BattleEventCodecResult.new(false, PackedByteArray(), null, invalid)
	return BattleEventCodecResult.encoded(_write(value).to_utf8_buffer())

func decode(bytes: PackedByteArray) -> BattleEventCodecResult:
	if bytes.is_empty():
		return BattleEventCodecResult.failure(
			BattleEventCodecError.CANONICAL_INVALID, &"canonical_bytes"
		)
	var reader := BattleCanonicalReader.new(bytes.get_string_from_utf8())
	var value := BattleEvent.new()
	reader.begin_object(&"event")
	reader.read_key("event_codec_version", true, &"event.event_codec_version")
	value.event_codec_version = reader.read_int(&"event.event_codec_version")
	reader.read_key("tick", false, &"event.tick")
	value.tick = reader.read_int(&"event.tick")
	reader.read_key("sequence", false, &"event.sequence")
	value.sequence = reader.read_int(&"event.sequence")
	reader.read_key("type", false, &"event.type")
	value.type = StringName(reader.read_string(&"event.type"))
	reader.read_key("source_instance_id", false, &"event.source_instance_id")
	if reader.next_is_null():
		reader.read_null(&"event.source_instance_id")
	else:
		value.source_instance_id = OptionalStringNameValue.of(
			StringName(reader.read_string(&"event.source_instance_id"))
		)
	reader.read_key("target_instance_ids", false, &"event.target_instance_ids")
	value.target_instance_ids = _read_ids(reader, &"event.target_instance_ids")
	reader.read_key("payload", false, &"event.payload")
	value.payload = _read_payload(reader, value.type)
	reader.end_object(&"event")
	if reader.failed() or not reader.at_end():
		return BattleEventCodecResult.failure(
			BattleEventCodecError.CANONICAL_INVALID,
			reader.error_path() if reader.failed() else &"canonical_bytes"
		)
	var invalid := _validate(value)
	if invalid != null:
		return BattleEventCodecResult.new(false, PackedByteArray(), null, invalid)
	var canonical := _write(value).to_utf8_buffer()
	if canonical != bytes:
		return BattleEventCodecResult.failure(
			BattleEventCodecError.CANONICAL_INVALID, &"canonical_bytes"
		)
	return BattleEventCodecResult.decoded(value)

func _validate(value: BattleEvent) -> BattleEventCodecError:
	if value == null:
		return _error(BattleEventCodecError.INVALID, &"event")
	if value.event_codec_version != VERSION:
		return _error(BattleEventCodecError.VERSION_UNSUPPORTED, &"event_codec_version")
	if value.tick < 0 or value.tick > MAX_TICK:
		return _error(BattleEventCodecError.INVALID, &"tick")
	if value.sequence < 0:
		return _error(BattleEventCodecError.INVALID, &"sequence")
	if not BattleEvent.TYPES.has(value.type):
		return _error(BattleEventCodecError.TYPE_UNKNOWN, &"type")
	if value.source_instance_id != null and not _entity_id(value.source_instance_id.value):
		return _error(BattleEventCodecError.INVALID, &"source_instance_id")
	if not _ordered_entity_ids(value.target_instance_ids):
		return _error(BattleEventCodecError.INVALID, &"target_instance_ids")
	var identity_error := _validate_identity(value)
	if identity_error != null:
		return identity_error
	return _validate_payload(value)

func _validate_identity(value: BattleEvent) -> BattleEventCodecError:
	var has_source := value.source_instance_id != null
	var target_count := value.target_instance_ids.size()
	match value.type:
		&"spawn":
			if target_count != 1:
				return _error(BattleEventCodecError.INVALID, &"target_instance_ids")
		&"move":
			if not has_source or target_count != 0:
				return _error(BattleEventCodecError.INVALID, &"identity")
		&"attack":
			if not has_source or target_count != 1:
				return _error(BattleEventCodecError.INVALID, &"identity")
		&"cast":
			if not has_source or target_count > 1:
				return _error(BattleEventCodecError.INVALID, &"identity")
		&"damage":
			if target_count != 1:
				return _error(BattleEventCodecError.INVALID, &"target_instance_ids")
		&"heal", &"shield", &"mana", &"modifier", &"status":
			if target_count != 1:
				return _error(BattleEventCodecError.INVALID, &"target_instance_ids")
		&"death":
			if not has_source or target_count > 1:
				return _error(BattleEventCodecError.INVALID, &"identity")
		&"boss_phase", &"summon_failure":
			if not has_source or target_count != 0:
				return _error(BattleEventCodecError.INVALID, &"identity")
		&"battle_finished":
			if has_source:
				return _error(BattleEventCodecError.INVALID, &"source_instance_id")
	return null

func _validate_payload(value: BattleEvent) -> BattleEventCodecError:
	if value.payload == null:
		return _error(BattleEventCodecError.PAYLOAD_INVALID, &"payload")
	match value.type:
		&"spawn":
			if not value.payload is SpawnEventPayload:
				return _payload_error()
			var p := value.payload as SpawnEventPayload
			if not _stable_ids.is_valid(p.unit_id) or not p.side in [&"player", &"enemy"] \
				or not p.origin in [&"player", &"encounter", &"summon"] \
				or not _cell(p.logical_y, p.logical_x):
				return _payload_error()
		&"move":
			if not value.payload is MoveEventPayload:
				return _payload_error()
			var p := value.payload as MoveEventPayload
			if not _cell(p.from_y, p.from_x) or not _cell(p.to_y, p.to_x) \
				or (p.from_y == p.to_y and p.from_x == p.to_x):
				return _payload_error()
		&"attack":
			if not value.payload is AttackEventPayload:
				return _payload_error()
			var p := value.payload as AttackEventPayload
			if p.raw_damage < 0 or not _stable_ids.is_valid(p.presentation_profile):
				return _payload_error()
		&"cast":
			if not value.payload is CastEventPayload:
				return _payload_error()
			var p := value.payload as CastEventPayload
			if not _stable_ids.is_valid(p.ability_id) or not p.action in [&"start", &"resolve", &"fizzle"] \
				or p.resolve_tick < 0 or p.resolve_tick > MAX_TICK:
				return _payload_error()
			if p.action == &"fizzle" and not p.fizzle_reason in [&"target_invalid", &"caster_death"]:
				return _payload_error()
			if p.action != &"fizzle" and p.fizzle_reason != &"none":
				return _payload_error()
		&"damage":
			if not value.payload is DamageEventPayload:
				return _payload_error()
			var p := value.payload as DamageEventPayload
			if not p.damage_type in [&"physical", &"magical", &"true"] \
				or not _nonnegative_values([p.raw_amount, p.post_resistance_amount, p.shield_absorbed, p.health_damage, p.health_after]) \
				or (p.damage_type == &"true" and p.post_resistance_amount != p.raw_amount) \
				or p.shield_absorbed + p.health_damage > p.post_resistance_amount:
				return _payload_error()
		&"heal":
			if not value.payload is HealEventPayload:
				return _payload_error()
			var p := value.payload as HealEventPayload
			if not _nonnegative_values([p.requested, p.applied, p.health_after]) or p.applied > p.requested:
				return _payload_error()
		&"shield":
			if not value.payload is ShieldEventPayload:
				return _payload_error()
			var p := value.payload as ShieldEventPayload
			if p.remaining < 0 or p.expires_tick < 0 or p.expires_tick > MAX_TICK:
				return _payload_error()
		&"mana":
			if not value.payload is ManaEventPayload:
				return _payload_error()
			var p := value.payload as ManaEventPayload
			if not p.reason in [&"attack", &"damaged", &"effect", &"cast_reset"] or p.mana_after < 0:
				return _payload_error()
		&"modifier":
			if not value.payload is ModifierEventPayload:
				return _payload_error()
			var p := value.payload as ModifierEventPayload
			if not p.stat in [&"attack", &"armor", &"magic_resist", &"attack_speed_milli", &"move_speed_milli"] \
				or not p.mode in [&"add", &"multiply_bps"] or not p.action in [&"apply", &"expire"] \
				or p.expires_tick < 0 or p.expires_tick > MAX_TICK:
				return _payload_error()
		&"status":
			if not value.payload is StatusEventPayload:
				return _payload_error()
			var p := value.payload as StatusEventPayload
			if not _stable_ids.is_valid(p.status_id) \
				or not p.action in [&"apply", &"replace", &"refresh", &"stack", &"remove", &"expire"] \
				or p.stacks < 0 or p.remaining_ticks < 0:
				return _payload_error()
			if p.action == &"remove" and (p.stacks != 0 or p.remaining_ticks != 0):
				return _payload_error()
		&"death":
			if not value.payload is DeathEventPayload:
				return _payload_error()
			var p := value.payload as DeathEventPayload
			if not p.origin in [&"player", &"encounter", &"summon"] or not _cell(p.logical_y, p.logical_x):
				return _payload_error()
		&"boss_phase":
			if not value.payload is BossPhaseEventPayload:
				return _payload_error()
			var p := value.payload as BossPhaseEventPayload
			if p.phase_index < 0 or p.hp_threshold_bps < 0 or p.hp_threshold_bps > 10000:
				return _payload_error()
		&"summon_failure":
			if not value.payload is SummonFailureEventPayload:
				return _payload_error()
			var p := value.payload as SummonFailureEventPayload
			if not _stable_ids.is_valid(p.unit_id) or p.request_ordinal < 0 \
				or not p.reason in [&"no_cell", &"entity_budget", &"max_active"]:
				return _payload_error()
		&"battle_finished":
			if not value.payload is BattleFinishedEventPayload:
				return _payload_error()
			var p := value.payload as BattleFinishedEventPayload
			if not p.outcome in [&"player_win", &"player_loss"] or p.expedition_damage < 0:
				return _payload_error()
	return null

func _write(value: BattleEvent) -> String:
	var source := "null"
	if value.source_instance_id != null:
		source = _quote(String(value.source_instance_id.value))
	return "{" + ",".join([
		_field("event_codec_version", str(value.event_codec_version)),
		_field("tick", str(value.tick)),
		_field("sequence", str(value.sequence)),
		_field("type", _quote(String(value.type))),
		_field("source_instance_id", source),
		_field("target_instance_ids", _write_ids(value.target_instance_ids)),
		_field("payload", _write_payload(value)),
	]) + "}"

func _write_payload(value: BattleEvent) -> String:
	match value.type:
		&"spawn":
			var p := value.payload as SpawnEventPayload
			return _object([_field("unit_id", _quote(String(p.unit_id))), _field("side", _quote(String(p.side))), _field("origin", _quote(String(p.origin))), _field("logical_y", str(p.logical_y)), _field("logical_x", str(p.logical_x))])
		&"move":
			var p := value.payload as MoveEventPayload
			return _object([_field("from_y", str(p.from_y)), _field("from_x", str(p.from_x)), _field("to_y", str(p.to_y)), _field("to_x", str(p.to_x))])
		&"attack":
			var p := value.payload as AttackEventPayload
			return _object([_field("raw_damage", str(p.raw_damage)), _field("presentation_profile", _quote(String(p.presentation_profile)))])
		&"cast":
			var p := value.payload as CastEventPayload
			return _object([_field("ability_id", _quote(String(p.ability_id))), _field("action", _quote(String(p.action))), _field("fizzle_reason", _quote(String(p.fizzle_reason))), _field("resolve_tick", str(p.resolve_tick))])
		&"damage":
			var p := value.payload as DamageEventPayload
			return _object([_field("damage_type", _quote(String(p.damage_type))), _field("raw_amount", str(p.raw_amount)), _field("post_resistance_amount", str(p.post_resistance_amount)), _field("shield_absorbed", str(p.shield_absorbed)), _field("health_damage", str(p.health_damage)), _field("health_after", str(p.health_after))])
		&"heal":
			var p := value.payload as HealEventPayload
			return _object([_field("requested", str(p.requested)), _field("applied", str(p.applied)), _field("health_after", str(p.health_after))])
		&"shield":
			var p := value.payload as ShieldEventPayload
			return _object([_field("delta", str(p.delta)), _field("remaining", str(p.remaining)), _field("expires_tick", str(p.expires_tick))])
		&"mana":
			var p := value.payload as ManaEventPayload
			return _object([_field("reason", _quote(String(p.reason))), _field("delta", str(p.delta)), _field("mana_after", str(p.mana_after))])
		&"modifier":
			var p := value.payload as ModifierEventPayload
			return _object([_field("stat", _quote(String(p.stat))), _field("mode", _quote(String(p.mode))), _field("amount", str(p.amount)), _field("expires_tick", str(p.expires_tick)), _field("action", _quote(String(p.action)))])
		&"status":
			var p := value.payload as StatusEventPayload
			return _object([_field("status_id", _quote(String(p.status_id))), _field("action", _quote(String(p.action))), _field("stacks", str(p.stacks)), _field("remaining_ticks", str(p.remaining_ticks))])
		&"death":
			var p := value.payload as DeathEventPayload
			return _object([_field("origin", _quote(String(p.origin))), _field("logical_y", str(p.logical_y)), _field("logical_x", str(p.logical_x))])
		&"boss_phase":
			var p := value.payload as BossPhaseEventPayload
			return _object([_field("phase_index", str(p.phase_index)), _field("hp_threshold_bps", str(p.hp_threshold_bps))])
		&"summon_failure":
			var p := value.payload as SummonFailureEventPayload
			return _object([_field("unit_id", _quote(String(p.unit_id))), _field("request_ordinal", str(p.request_ordinal)), _field("reason", _quote(String(p.reason)))])
		&"battle_finished":
			var p := value.payload as BattleFinishedEventPayload
			return _object([_field("outcome", _quote(String(p.outcome))), _field("expedition_damage", str(p.expedition_damage))])
	return "{}"

func _read_payload(reader: BattleCanonicalReader, type: StringName) -> BattleEventPayload:
	reader.begin_object(&"event.payload")
	var payload: BattleEventPayload = null
	match type:
		&"spawn":
			var p := SpawnEventPayload.new()
			p.unit_id = _read_name(reader, "unit_id", true)
			p.side = _read_name(reader, "side")
			p.origin = _read_name(reader, "origin")
			p.logical_y = _read_int(reader, "logical_y")
			p.logical_x = _read_int(reader, "logical_x")
			payload = p
		&"move":
			var p := MoveEventPayload.new()
			p.from_y = _read_int(reader, "from_y", true)
			p.from_x = _read_int(reader, "from_x")
			p.to_y = _read_int(reader, "to_y")
			p.to_x = _read_int(reader, "to_x")
			payload = p
		&"attack":
			var p := AttackEventPayload.new()
			p.raw_damage = _read_int(reader, "raw_damage", true)
			p.presentation_profile = _read_name(reader, "presentation_profile")
			payload = p
		&"cast":
			var p := CastEventPayload.new()
			p.ability_id = _read_name(reader, "ability_id", true)
			p.action = _read_name(reader, "action")
			p.fizzle_reason = _read_name(reader, "fizzle_reason")
			p.resolve_tick = _read_int(reader, "resolve_tick")
			payload = p
		&"damage":
			var p := DamageEventPayload.new()
			p.damage_type = _read_name(reader, "damage_type", true)
			p.raw_amount = _read_int(reader, "raw_amount")
			p.post_resistance_amount = _read_int(reader, "post_resistance_amount")
			p.shield_absorbed = _read_int(reader, "shield_absorbed")
			p.health_damage = _read_int(reader, "health_damage")
			p.health_after = _read_int(reader, "health_after")
			payload = p
		&"heal":
			var p := HealEventPayload.new()
			p.requested = _read_int(reader, "requested", true)
			p.applied = _read_int(reader, "applied")
			p.health_after = _read_int(reader, "health_after")
			payload = p
		&"shield":
			var p := ShieldEventPayload.new()
			p.delta = _read_int(reader, "delta", true)
			p.remaining = _read_int(reader, "remaining")
			p.expires_tick = _read_int(reader, "expires_tick")
			payload = p
		&"mana":
			var p := ManaEventPayload.new()
			p.reason = _read_name(reader, "reason", true)
			p.delta = _read_int(reader, "delta")
			p.mana_after = _read_int(reader, "mana_after")
			payload = p
		&"modifier":
			var p := ModifierEventPayload.new()
			p.stat = _read_name(reader, "stat", true)
			p.mode = _read_name(reader, "mode")
			p.amount = _read_int(reader, "amount")
			p.expires_tick = _read_int(reader, "expires_tick")
			p.action = _read_name(reader, "action")
			payload = p
		&"status":
			var p := StatusEventPayload.new()
			p.status_id = _read_name(reader, "status_id", true)
			p.action = _read_name(reader, "action")
			p.stacks = _read_int(reader, "stacks")
			p.remaining_ticks = _read_int(reader, "remaining_ticks")
			payload = p
		&"death":
			var p := DeathEventPayload.new()
			p.origin = _read_name(reader, "origin", true)
			p.logical_y = _read_int(reader, "logical_y")
			p.logical_x = _read_int(reader, "logical_x")
			payload = p
		&"boss_phase":
			var p := BossPhaseEventPayload.new()
			p.phase_index = _read_int(reader, "phase_index", true)
			p.hp_threshold_bps = _read_int(reader, "hp_threshold_bps")
			payload = p
		&"summon_failure":
			var p := SummonFailureEventPayload.new()
			p.unit_id = _read_name(reader, "unit_id", true)
			p.request_ordinal = _read_int(reader, "request_ordinal")
			p.reason = _read_name(reader, "reason")
			payload = p
		&"battle_finished":
			var p := BattleFinishedEventPayload.new()
			p.outcome = _read_name(reader, "outcome", true)
			p.expedition_damage = _read_int(reader, "expedition_damage")
			payload = p
	reader.end_object(&"event.payload")
	return payload

func _read_ids(reader: BattleCanonicalReader, path: StringName) -> Array[StringName]:
	var values: Array[StringName] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		values.append(StringName(reader.read_string(path)))
	return values

func _read_name(reader: BattleCanonicalReader, key: String, first: bool = false) -> StringName:
	var path := StringName("event.payload.%s" % key)
	reader.read_key(key, first, path)
	return StringName(reader.read_string(path))

func _read_int(reader: BattleCanonicalReader, key: String, first: bool = false) -> int:
	var path := StringName("event.payload.%s" % key)
	reader.read_key(key, first, path)
	return reader.read_int(path)

func _write_ids(values: Array[StringName]) -> String:
	var encoded: Array[String] = []
	for value: StringName in values:
		encoded.append(_quote(String(value)))
	return "[" + ",".join(encoded) + "]"

func _ordered_entity_ids(values: Array[StringName]) -> bool:
	var previous := ""
	for value: StringName in values:
		if not _entity_id(value):
			return false
		var current := String(value)
		if not previous.is_empty() and current <= previous:
			return false
		previous = current
	return true

func _entity_id(value: StringName) -> bool:
	return _entity_ids.search(String(value)) != null

func _cell(y: int, x: int) -> bool:
	return y >= 0 and y <= 7 and x >= 0 and x <= 7

func _nonnegative_values(values: Array[int]) -> bool:
	for value: int in values:
		if value < 0:
			return false
	return true

func _object(fields: Array[String]) -> String:
	return "{" + ",".join(fields) + "}"

func _field(key: String, encoded: String) -> String:
	return _quote(key) + ":" + encoded

func _quote(value: String) -> String:
	var output := "\""
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		match code:
			34: output += "\\\""
			92: output += "\\\\"
			8: output += "\\b"
			12: output += "\\f"
			10: output += "\\n"
			13: output += "\\r"
			9: output += "\\t"
			_:
				if code < 32:
					output += "\\u%04x" % code
				else:
					output += String.chr(code)
	return output + "\""

func _payload_error() -> BattleEventCodecError:
	return _error(BattleEventCodecError.PAYLOAD_INVALID, &"payload")

func _error(code: StringName, path: StringName) -> BattleEventCodecError:
	return BattleEventCodecError.new(code, path)
