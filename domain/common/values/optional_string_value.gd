class_name OptionalStringValue
extends RefCounted

var value: String

func _init(p_value: String) -> void:
	value = p_value

func deep_clone() -> OptionalStringValue:
	return OptionalStringValue.new(value)
