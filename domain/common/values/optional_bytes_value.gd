class_name OptionalBytesValue
extends RefCounted

var value: PackedByteArray

func _init(p_value: PackedByteArray) -> void:
	value = p_value.duplicate()

func deep_clone() -> OptionalBytesValue:
	return OptionalBytesValue.new(value)
