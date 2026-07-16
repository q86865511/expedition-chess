class_name BattleResultCodecV1
extends RefCounted

const VERSION: int = 1
const MAX_TICK: int = 1800

var _hash_regex := RegEx.new()
var _entity_regex := RegEx.new()

func _init() -> void:
	_hash_regex.compile("^[0-9a-f]{64}$")
	_entity_regex.compile("^[ues]_[0-9a-f]{16}$")

func seal(value: BattleResultRecord) -> BattleResultCodecResult:
	var invalid := _validate(value, false)
	if invalid != null:
		return BattleResultCodecResult.new(false, PackedByteArray(), null, invalid)
	var sealed := value.deep_clone()
	sealed.result_hash = StringName(_result_hash(sealed))
	return BattleResultCodecResult.decoded(sealed)

func encode(value: BattleResultRecord) -> BattleResultCodecResult:
	var invalid := _validate(value, true)
	if invalid != null:
		return BattleResultCodecResult.new(false, PackedByteArray(), null, invalid)
	return BattleResultCodecResult.encoded(_write(value, true).to_utf8_buffer())

func decode(bytes: PackedByteArray) -> BattleResultCodecResult:
	if bytes.is_empty():
		return BattleResultCodecResult.failure(
			BattleResultCodecError.CANONICAL_INVALID, &"canonical_bytes"
		)
	var reader := BattleCanonicalReader.new(bytes.get_string_from_utf8())
	var value := BattleResultRecord.new()
	reader.begin_object(&"result")
	reader.read_key("setup_schema_version", true, &"result.setup_schema_version")
	value.setup_schema_version = reader.read_int(&"result.setup_schema_version")
	value.hash_version = _read_int(reader, "hash_version")
	value.rng_version = _read_int(reader, "rng_version")
	value.simulation_version = _read_int(reader, "simulation_version")
	value.event_codec_version = _read_int(reader, "event_codec_version")
	value.result_codec_version = _read_int(reader, "result_codec_version")
	value.battle_setup_hash = _read_name(reader, "battle_setup_hash")
	value.outcome = _read_name(reader, "outcome")
	value.final_tick = _read_int(reader, "final_tick")
	reader.read_key("survivor_instance_ids", false, &"result.survivor_instance_ids")
	value.survivor_instance_ids = _read_ids(reader, &"result.survivor_instance_ids")
	value.expedition_damage = _read_int(reader, "expedition_damage")
	reader.read_key("run_mutation_proposals", false, &"result.run_mutation_proposals")
	var proposals := _read_proposals(reader)
	if not proposals.ok:
		return proposals
	value.run_mutation_proposals = proposals.record.run_mutation_proposals
	value.summary_hash = _read_name(reader, "summary_hash")
	value.result_hash = _read_name(reader, "result_hash")
	reader.end_object(&"result")
	if reader.failed() or not reader.at_end():
		return BattleResultCodecResult.failure(
			BattleResultCodecError.CANONICAL_INVALID,
			reader.error_path() if reader.failed() else &"canonical_bytes"
		)
	var invalid := _validate(value, true)
	if invalid != null:
		return BattleResultCodecResult.new(false, PackedByteArray(), null, invalid)
	var canonical := _write(value, true).to_utf8_buffer()
	if canonical != bytes:
		return BattleResultCodecResult.failure(
			BattleResultCodecError.CANONICAL_INVALID, &"canonical_bytes"
		)
	return BattleResultCodecResult.decoded(value)

func preimage_bytes(value: BattleResultRecord) -> BattleResultCodecResult:
	var invalid := _validate(value, false)
	if invalid != null:
		return BattleResultCodecResult.new(false, PackedByteArray(), null, invalid)
	return BattleResultCodecResult.encoded(_write(value, false).to_utf8_buffer())

func _validate(value: BattleResultRecord, require_hash: bool) -> BattleResultCodecError:
	if value == null:
		return _error(BattleResultCodecError.INVALID, &"result")
	if value.setup_schema_version != 2 or value.hash_version != 1 or value.rng_version != 1 \
		or value.simulation_version != 1 or value.event_codec_version != 1 \
		or value.result_codec_version != VERSION:
		return _error(BattleResultCodecError.VERSION_UNSUPPORTED, &"version_tuple")
	if not _hash(value.battle_setup_hash):
		return _error(BattleResultCodecError.INVALID, &"battle_setup_hash")
	if not value.outcome in [&"player_win", &"player_loss"]:
		return _error(BattleResultCodecError.INVALID, &"outcome")
	if value.final_tick < 0 or value.final_tick > MAX_TICK:
		return _error(BattleResultCodecError.INVALID, &"final_tick")
	if not _ordered_entity_ids(value.survivor_instance_ids):
		return _error(BattleResultCodecError.INVALID, &"survivor_instance_ids")
	if value.expedition_damage < 0:
		return _error(BattleResultCodecError.INVALID, &"expedition_damage")
	if value.outcome == &"player_win" and value.expedition_damage != 0:
		return _error(BattleResultCodecError.INVALID, &"expedition_damage")
	var proposal_error := _validate_proposals(value.run_mutation_proposals)
	if proposal_error != null:
		return proposal_error
	if not _hash(value.summary_hash):
		return _error(BattleResultCodecError.INVALID, &"summary_hash")
	if require_hash:
		if not _hash(value.result_hash):
			return _error(BattleResultCodecError.INVALID, &"result_hash")
		if String(value.result_hash) != _result_hash(value):
			return _error(BattleResultCodecError.HASH_MISMATCH, &"result_hash")
	return null

func _validate_proposals(values: Array[RunMutationProposal]) -> BattleResultCodecError:
	var previous: RunMutationProposal = null
	for index: int in range(values.size()):
		var value := values[index]
		if value == null:
			return _error(BattleResultCodecError.INVALID, StringName("run_mutation_proposals.%d" % index))
		var restored := RunMutationProposal.restore(
			value.claim_scope,
			value.source_instance_or_slot,
			value.effect_id,
			value.operation_index,
			value.operation_kind,
			value.amount,
			value.payload_digest
		)
		if not restored.ok:
			return _error(BattleResultCodecError.INVALID, StringName("run_mutation_proposals.%d" % index))
		if previous != null:
			if previous.identity_key() == value.identity_key():
				return _error(BattleResultCodecError.PROPOSAL_CONFLICT, &"run_mutation_proposals")
			if not _proposal_precedes(previous, value):
				return _error(BattleResultCodecError.INVALID, &"run_mutation_proposals")
		previous = value
	return null

func _proposal_precedes(left: RunMutationProposal, right: RunMutationProposal) -> bool:
	if left.claim_scope != right.claim_scope:
		return String(left.claim_scope) < String(right.claim_scope)
	if left.source_instance_or_slot != right.source_instance_or_slot:
		return left.source_instance_or_slot < right.source_instance_or_slot
	if left.effect_id != right.effect_id:
		return String(left.effect_id) < String(right.effect_id)
	return left.operation_index < right.operation_index

func _write(value: BattleResultRecord, include_result_hash: bool) -> String:
	var fields: Array[String] = [
		_field("setup_schema_version", str(value.setup_schema_version)),
		_field("hash_version", str(value.hash_version)),
		_field("rng_version", str(value.rng_version)),
		_field("simulation_version", str(value.simulation_version)),
		_field("event_codec_version", str(value.event_codec_version)),
		_field("result_codec_version", str(value.result_codec_version)),
		_field("battle_setup_hash", _quote(String(value.battle_setup_hash))),
		_field("outcome", _quote(String(value.outcome))),
		_field("final_tick", str(value.final_tick)),
		_field("survivor_instance_ids", _write_ids(value.survivor_instance_ids)),
		_field("expedition_damage", str(value.expedition_damage)),
		_field("run_mutation_proposals", _write_proposals(value.run_mutation_proposals)),
		_field("summary_hash", _quote(String(value.summary_hash))),
	]
	if include_result_hash:
		fields.append(_field("result_hash", _quote(String(value.result_hash))))
	return "{" + ",".join(fields) + "}"

func _write_proposals(values: Array[RunMutationProposal]) -> String:
	var items: Array[String] = []
	for value: RunMutationProposal in values:
		items.append("{" + ",".join([
			_field("claim_scope", _quote(String(value.claim_scope))),
			_field("source_instance_or_slot", _quote(value.source_instance_or_slot)),
			_field("effect_id", _quote(String(value.effect_id))),
			_field("operation_index", str(value.operation_index)),
			_field("operation_kind", _quote(String(value.operation_kind))),
			_field("amount", str(value.amount)),
			_field("payload_digest", _quote(value.payload_digest)),
		]) + "}")
	return "[" + ",".join(items) + "]"

func _read_proposals(reader: BattleCanonicalReader) -> BattleResultCodecResult:
	var holder := BattleResultRecord.new()
	reader.begin_array(&"result.run_mutation_proposals")
	var first := true
	while reader.array_next(first, &"result.run_mutation_proposals"):
		first = false
		var path := StringName("result.run_mutation_proposals.%d" % holder.run_mutation_proposals.size())
		reader.begin_object(path)
		reader.read_key("claim_scope", true, path)
		var claim_scope := StringName(reader.read_string(path))
		reader.read_key("source_instance_or_slot", false, path)
		var source := reader.read_string(path)
		reader.read_key("effect_id", false, path)
		var effect_id := StringName(reader.read_string(path))
		reader.read_key("operation_index", false, path)
		var operation_index := reader.read_int(path)
		reader.read_key("operation_kind", false, path)
		var operation_kind := StringName(reader.read_string(path))
		reader.read_key("amount", false, path)
		var amount := reader.read_int(path)
		reader.read_key("payload_digest", false, path)
		var digest := reader.read_string(path)
		reader.end_object(path)
		var restored := RunMutationProposal.restore(
			claim_scope, source, effect_id, operation_index, operation_kind, amount, digest
		)
		if not restored.ok:
			return BattleResultCodecResult.failure(BattleResultCodecError.INVALID, path)
		holder.run_mutation_proposals.append(restored.proposal)
	return BattleResultCodecResult.decoded(holder)

func _read_ids(reader: BattleCanonicalReader, path: StringName) -> Array[StringName]:
	var values: Array[StringName] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		values.append(StringName(reader.read_string(path)))
	return values

func _read_name(reader: BattleCanonicalReader, key: String) -> StringName:
	var path := StringName("result.%s" % key)
	reader.read_key(key, false, path)
	return StringName(reader.read_string(path))

func _read_int(reader: BattleCanonicalReader, key: String) -> int:
	var path := StringName("result.%s" % key)
	reader.read_key(key, false, path)
	return reader.read_int(path)

func _ordered_entity_ids(values: Array[StringName]) -> bool:
	var previous := ""
	for value: StringName in values:
		var current := String(value)
		if _entity_regex.search(current) == null:
			return false
		if not previous.is_empty() and current <= previous:
			return false
		previous = current
	return true

func _hash(value: StringName) -> bool:
	return _hash_regex.search(String(value)) != null

func _result_hash(value: BattleResultRecord) -> String:
	var bytes := "BRH1".to_ascii_buffer()
	bytes.append_array(_write(value, false).to_utf8_buffer())
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

func _write_ids(values: Array[StringName]) -> String:
	var encoded: Array[String] = []
	for value: StringName in values:
		encoded.append(_quote(String(value)))
	return "[" + ",".join(encoded) + "]"

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

func _error(code: StringName, path: StringName) -> BattleResultCodecError:
	return BattleResultCodecError.new(code, path)
