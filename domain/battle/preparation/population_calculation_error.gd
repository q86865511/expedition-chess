class_name PopulationCalculationError
extends RefCounted

const INVALID_BASE_LEVEL: StringName = &"POPULATION_BASE_LEVEL_INVALID"
const INVALID_SOURCE: StringName = &"POPULATION_SOURCE_INVALID"
const DUPLICATE_SOURCE: StringName = &"POPULATION_SOURCE_DUPLICATE"
const OVERFLOW: StringName = &"POPULATION_OVERFLOW"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> PopulationCalculationError:
	return PopulationCalculationError.new(code, field_path)
