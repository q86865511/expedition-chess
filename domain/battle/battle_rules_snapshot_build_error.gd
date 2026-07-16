class_name BattleRulesSnapshotBuildError
extends RefCounted

const INPUT_INVALID: StringName = &"BATTLE_RULES_INPUT_INVALID"
const GENERATION_MISMATCH: StringName = &"BATTLE_RULES_GENERATION_MISMATCH"
const REFERENCE_MISSING: StringName = &"BATTLE_RULES_REFERENCE_MISSING"
const CLOSURE_LIMIT: StringName = &"BATTLE_RULES_CLOSURE_LIMIT"
const DUPLICATE_ASSIGNMENT: StringName = &"BATTLE_RULES_DUPLICATE_ASSIGNMENT"
const INTEGER_OVERFLOW: StringName = &"BATTLE_RULES_INTEGER_OVERFLOW"

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(p_code: StringName, p_path: StringName = &"", p_source: StringName = &"") -> void:
	code = p_code
	field_path = p_path
	source_id = OptionalStringNameValue.new(p_source) if not p_source.is_empty() else null

func deep_clone() -> BattleRulesSnapshotBuildError:
	return BattleRulesSnapshotBuildError.new(
		code,
		field_path,
		source_id.value if source_id != null else &""
	)
