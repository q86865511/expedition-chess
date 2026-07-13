class_name BoardPlacementState
extends RefCounted

var logical_y: int
var logical_x: int
var unit_instance_id: String

func _init(p_logical_y: int, p_logical_x: int, p_unit_instance_id: String) -> void:
	logical_y = p_logical_y
	logical_x = p_logical_x
	unit_instance_id = p_unit_instance_id

func deep_clone() -> BoardPlacementState:
	return BoardPlacementState.new(logical_y, logical_x, unit_instance_id)
