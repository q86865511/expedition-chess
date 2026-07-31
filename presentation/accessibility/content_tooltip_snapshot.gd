class_name ContentTooltipSnapshot
extends RefCounted

var label_key: StringName
var text: String
var numeric_value: int
var locale: StringName
var locale_generation: int
var depth: int

func _init(
	p_label_key: StringName,
	p_text: String,
	p_numeric_value: int,
	p_locale: StringName,
	p_locale_generation: int,
	p_depth: int
) -> void:
	label_key = p_label_key
	text = p_text
	numeric_value = p_numeric_value
	locale = p_locale
	locale_generation = p_locale_generation
	depth = p_depth

func deep_clone() -> ContentTooltipSnapshot:
	return ContentTooltipSnapshot.new(
		label_key,
		text,
		numeric_value,
		locale,
		locale_generation,
		depth
	)
