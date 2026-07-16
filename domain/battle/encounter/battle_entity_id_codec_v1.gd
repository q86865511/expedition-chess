class_name BattleEntityIdCodecV1
extends RefCounted

const INVALID: StringName = &"BATTLE_ENTITY_ID_INVALID"
const HASH_FAILED: StringName = &"BATTLE_ENTITY_ID_HASH_FAILED"
const MAX_U32: int = 0xffffffff
const SHA256_BYTES: int = 32

func encode_enemy(node_id: StringName, spawn_key: String) -> BattleEntityIdResult:
	var node_text := String(node_id)
	if not _is_strict_ascii(node_text):
		return BattleEntityIdResult.failure(INVALID, &"node_id")
	if not _is_spawn_key(spawn_key):
		return BattleEntityIdResult.failure(INVALID, &"spawn_key")
	var preimage := PackedByteArray()
	preimage.append_array("BEI1".to_ascii_buffer())
	_append_framed_ascii(preimage, node_text)
	_append_framed_ascii(preimage, spawn_key)
	return _finish(&"e", preimage)

func encode_summon(
	setup_hash: PackedByteArray,
	summoner_instance_id: StringName,
	effect_id: StringName,
	operation_index: int,
	summon_request_serial: int
) -> BattleEntityIdResult:
	if setup_hash.size() != SHA256_BYTES:
		return BattleEntityIdResult.failure(INVALID, &"setup_hash")
	if not _is_strict_ascii(String(summoner_instance_id)):
		return BattleEntityIdResult.failure(INVALID, &"summoner_instance_id")
	if not _is_strict_ascii(String(effect_id)):
		return BattleEntityIdResult.failure(INVALID, &"effect_id")
	if not _is_u32(operation_index):
		return BattleEntityIdResult.failure(INVALID, &"operation_index")
	if not _is_u32(summon_request_serial):
		return BattleEntityIdResult.failure(INVALID, &"summon_request_serial")
	var preimage := PackedByteArray()
	preimage.append_array("BSI1".to_ascii_buffer())
	preimage.append_array(setup_hash)
	_append_framed_ascii(preimage, String(summoner_instance_id))
	_append_framed_ascii(preimage, String(effect_id))
	_append_u32_be(preimage, operation_index)
	_append_u32_be(preimage, summon_request_serial)
	return _finish(&"s", preimage)

func _finish(prefix: StringName, preimage: PackedByteArray) -> BattleEntityIdResult:
	var digest := _sha256(preimage)
	if digest.size() != SHA256_BYTES:
		return BattleEntityIdResult.failure(HASH_FAILED, &"sha256")
	var first_16_hex := digest.hex_encode().substr(0, 16)
	return BattleEntityIdResult.success(
		StringName("%s_%s" % [String(prefix), first_16_hex]),
		preimage
	)

func _append_framed_ascii(target: PackedByteArray, value: String) -> void:
	var bytes := value.to_ascii_buffer()
	_append_u32_be(target, bytes.size())
	target.append_array(bytes)

func _append_u32_be(target: PackedByteArray, value: int) -> void:
	target.append((value >> 24) & 0xff)
	target.append((value >> 16) & 0xff)
	target.append((value >> 8) & 0xff)
	target.append(value & 0xff)

func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if context.update(bytes) != OK:
		return PackedByteArray()
	return context.finish()

func _is_spawn_key(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if index == 0:
			if code < 97 or code > 122:
				return false
		elif not (code >= 97 and code <= 122) \
			and not (code >= 48 and code <= 57) \
			and code != 95:
			return false
	return true

func _is_strict_ascii(value: String) -> bool:
	if value.is_empty():
		return false
	for byte: int in value.to_utf8_buffer():
		if byte < 33 or byte > 126:
			return false
	return true

func _is_u32(value: int) -> bool:
	return value >= 0 and value <= MAX_U32
