class_name BattleEventStreamHasher
extends RefCounted

var _hash_regex := RegEx.new()
var _event_codec := BattleEventCodecV1.new()

func _init() -> void:
	_hash_regex.compile("^[0-9a-f]{64}$")

func framed_bytes(events: Array[BattleEvent]) -> BattleEventCodecResult:
	var output := PackedByteArray()
	var previous_tick := -1
	for index: int in range(events.size()):
		var event := events[index]
		if event == null or event.sequence != index or event.tick < previous_tick:
			return BattleEventCodecResult.failure(
				BattleEventCodecError.INVALID, &"event_stream_order"
			)
		var encoded := _event_codec.encode(event)
		if not encoded.ok:
			return encoded
		_append_u32(output, encoded.canonical_bytes.size())
		output.append_array(encoded.canonical_bytes)
		previous_tick = event.tick
	return BattleEventCodecResult.encoded(output)

func summary_hash(setup_hash: StringName, events: Array[BattleEvent]) -> String:
	if _hash_regex.search(String(setup_hash)) == null:
		return ""
	var framed := framed_bytes(events)
	if not framed.ok:
		return ""
	var bytes := "BRS1".to_ascii_buffer()
	bytes.append_array(String(setup_hash).hex_decode())
	bytes.append_array(framed.canonical_bytes)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

func _append_u32(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 24) & 0xff)
	bytes.append((value >> 16) & 0xff)
	bytes.append((value >> 8) & 0xff)
	bytes.append(value & 0xff)
