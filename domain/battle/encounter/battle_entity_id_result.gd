class_name BattleEntityIdResult
extends RefCounted

var ok: bool = false
var entity_id: StringName = &""
var canonical_bytes: PackedByteArray = PackedByteArray()
var error: BattleEntityIdError = null

static func success(id: StringName, preimage: PackedByteArray) -> BattleEntityIdResult:
	return BattleEntityIdResult.new(true, id, preimage, null)

static func failure(
	error_code: StringName,
	field_path: StringName
) -> BattleEntityIdResult:
	return BattleEntityIdResult.new(
		false,
		&"",
		PackedByteArray(),
		BattleEntityIdError.create(error_code, field_path)
	)

func _init(
	p_ok: bool,
	p_entity_id: StringName,
	p_canonical_bytes: PackedByteArray,
	p_error: BattleEntityIdError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		not p_entity_id.is_empty() and not p_canonical_bytes.is_empty(),
		p_entity_id.is_empty() and p_canonical_bytes.is_empty()
	)
	ok = p_ok
	entity_id = p_entity_id
	canonical_bytes = p_canonical_bytes.duplicate()
	error = p_error.deep_clone() if p_error != null else null
