class_name OptionalBoolValue
extends RefCounted

var value: bool

func _init(p_value: bool) -> void:
	value = p_value

func deep_clone() -> OptionalBoolValue:
	return OptionalBoolValue.new(value)
