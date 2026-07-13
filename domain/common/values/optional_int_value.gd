class_name OptionalIntValue
extends RefCounted

var value: int

func _init(p_value: int) -> void:
	value = p_value

func deep_clone() -> OptionalIntValue:
	return OptionalIntValue.new(value)
