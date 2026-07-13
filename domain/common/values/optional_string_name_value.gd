class_name OptionalStringNameValue
extends RefCounted

var value: StringName

static func of(p_value: StringName) -> OptionalStringNameValue:
	return OptionalStringNameValue.new(p_value)

func _init(p_value: StringName) -> void:
	value = p_value

func deep_clone() -> OptionalStringNameValue:
	return OptionalStringNameValue.new(value)
