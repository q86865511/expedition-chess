class_name BalanceTuneEntry
extends RefCounted

var field_path: StringName
var value_text: String


func _init(p_field_path: StringName, p_value_text: String) -> void:
	field_path = p_field_path
	value_text = p_value_text


func deep_clone() -> BalanceTuneEntry:
	return BalanceTuneEntry.new(field_path, value_text)


func is_valid() -> bool:
	return not field_path.is_empty() and not value_text.is_empty()


func canonical_fragment() -> String:
	var path := String(field_path)
	return "%d:%s:%d:%s" % [path.length(), path, value_text.length(), value_text]

