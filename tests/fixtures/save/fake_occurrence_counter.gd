class_name FakeOccurrenceCounter
extends RefCounted

var operation_kind: StringName
var logical_path: StringName
var count: int

func _init(p_operation_kind: StringName, p_logical_path: StringName, p_count: int = 0) -> void:
	operation_kind = p_operation_kind
	logical_path = p_logical_path
	count = p_count
