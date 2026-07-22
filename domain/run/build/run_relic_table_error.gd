class_name RunRelicTableError
extends RefCounted

const INPUT_INVALID: StringName = &"RUN_RELIC_INPUT_INVALID"
const RESOLVE_FAILED: StringName = &"RUN_RELIC_RESOLVE_FAILED"
const CATEGORY_MISMATCH: StringName = &"RUN_RELIC_CATEGORY_MISMATCH"
const PAYLOAD_INVALID: StringName = &"RUN_RELIC_PAYLOAD_INVALID"

var code: StringName
var field_path: StringName
var source_id: StringName

func _init(p_code: StringName, p_field_path: StringName, p_source_id: StringName = &"") -> void:
	code = p_code
	field_path = p_field_path
	source_id = p_source_id

func deep_clone() -> RunRelicTableError:
	return RunRelicTableError.new(code, field_path, source_id)
