class_name EconomyValueRule
extends RefCounted

var key: int
var value: int

func _init(p_key: int, p_value: int) -> void:
	key = p_key
	value = p_value

func deep_clone() -> EconomyValueRule:
	return EconomyValueRule.new(key, value)
