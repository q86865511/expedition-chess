class_name NodeChoicePendingState
extends ResolutionState

var node_id: StringName
var choice_set_id: StringName
var choice_ids: Array[StringName] = []
var content_version: String
var catalog_schema_version: int
var content_codec_version: int
var manifest_digest: String
var lifecycle_nonce: String
var pending_digest: String

func _init(
	p_node_id: StringName,
	p_choice_set_id: StringName,
	p_choice_ids: Array,
	p_content_version: String,
	p_catalog_schema_version: int,
	p_content_codec_version: int,
	p_manifest_digest: String,
	p_lifecycle_nonce: String
) -> void:
	super(Kind.NODE_CHOICE_PENDING)
	node_id = p_node_id
	choice_set_id = p_choice_set_id
	for value: Variant in p_choice_ids:
		choice_ids.append(StringName(value))
	content_version = p_content_version
	catalog_schema_version = p_catalog_schema_version
	content_codec_version = p_content_codec_version
	manifest_digest = p_manifest_digest
	lifecycle_nonce = p_lifecycle_nonce
	pending_digest = _compute_digest()

func is_valid() -> bool:
	var validator := StableIdValidator.new()
	if (
		not _is_node_key_digest(String(node_id))
		or not validator.is_valid(choice_set_id)
	):
		return false
	if choice_ids.size() < 2 or not _is_digest(manifest_digest):
		return false
	if catalog_schema_version != 2 or content_codec_version != 3:
		return false
	if not _is_u64_hex(lifecycle_nonce) \
		or lifecycle_nonce == "0000000000000000":
		return false
	var seen: Dictionary = {}
	for choice_id: StringName in choice_ids:
		if not validator.is_valid(choice_id) or seen.has(choice_id):
			return false
		seen[choice_id] = true
	return pending_digest == _compute_digest()

func deep_clone() -> ResolutionState:
	var clone := NodeChoicePendingState.new(
		node_id,
		choice_set_id,
		choice_ids,
		content_version,
		catalog_schema_version,
		content_codec_version,
		manifest_digest,
		lifecycle_nonce
	)
	clone.pending_digest = pending_digest
	return clone

func _compute_digest() -> String:
	if not _is_digest(manifest_digest) or not _is_u64_hex(lifecycle_nonce):
		return ""
	var bytes := "NCP1".to_ascii_buffer()
	_append_text(bytes, String(node_id))
	_append_text(bytes, String(choice_set_id))
	_append_text(bytes, content_version)
	_append_u32(bytes, catalog_schema_version)
	_append_u32(bytes, content_codec_version)
	bytes.append_array(manifest_digest.hex_decode())
	bytes.append_array(lifecycle_nonce.hex_decode())
	_append_u32(bytes, choice_ids.size())
	for choice_id: StringName in choice_ids:
		_append_text(bytes, String(choice_id))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _append_text(bytes: PackedByteArray, value: String) -> void:
	var raw := value.to_utf8_buffer()
	_append_u32(bytes, raw.size())
	bytes.append_array(raw)

func _append_u32(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 24) & 0xff)
	bytes.append((value >> 16) & 0xff)
	bytes.append((value >> 8) & 0xff)
	bytes.append(value & 0xff)

func _is_digest(value: String) -> bool:
	return value.length() == 64 and value.hex_decode().size() == 32

# runtime node_id 是 RuntimeKeyCodecV1 的 "node_" + 64 lower-hex key digest
func _is_node_key_digest(value: String) -> bool:
	if not value.begins_with("node_"):
		return false
	var suffix := value.trim_prefix("node_")
	return suffix.length() == 64 and suffix == suffix.to_lower() \
		and suffix.hex_decode().size() == 32

func _is_u64_hex(value: String) -> bool:
	return value.length() == 16 and value.hex_decode().size() == 8 \
		and value == value.to_lower()
