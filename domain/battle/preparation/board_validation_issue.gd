class_name BoardValidationIssue
extends RefCounted

const REQUEST_INVALID: StringName = &"BOARD_REQUEST_INVALID"
const OUT_OF_BOUNDS: StringName = &"BOARD_OUT_OF_BOUNDS"
const WRONG_HALF: StringName = &"BOARD_WRONG_HALF"
const CELL_OVERLAP: StringName = &"BOARD_CELL_OVERLAP"
const UNIT_REFERENCE_MISSING: StringName = &"BOARD_UNIT_REFERENCE_MISSING"
const UNIT_DUPLICATE: StringName = &"BOARD_UNIT_DUPLICATE"
const UNIT_UNASSIGNED: StringName = &"BOARD_UNIT_UNASSIGNED"
const OVER_CAPACITY: StringName = &"BOARD_OVER_CAPACITY"
const PHYSICAL_LIMIT: StringName = &"BOARD_PHYSICAL_LIMIT"
const BENCH_TOO_LARGE: StringName = &"BENCH_TOO_LARGE"
const BENCH_EMPTY_SLOT: StringName = &"BENCH_EMPTY_SLOT"
const POPULATION_INVALID: StringName = &"POPULATION_INVALID"

var code: StringName
var logical_y: int
var logical_x: int
var instance_id: String

func _init(
	p_code: StringName,
	p_logical_y: int = -1,
	p_logical_x: int = -1,
	p_instance_id: String = ""
) -> void:
	code = p_code
	logical_y = p_logical_y
	logical_x = p_logical_x
	instance_id = p_instance_id

func deep_clone() -> BoardValidationIssue:
	return BoardValidationIssue.new(code, logical_y, logical_x, instance_id)

func precedes(other: BoardValidationIssue) -> bool:
	if code != other.code:
		return String(code) < String(other.code)
	if logical_y != other.logical_y:
		return logical_y < other.logical_y
	if logical_x != other.logical_x:
		return logical_x < other.logical_x
	return instance_id < other.instance_id
