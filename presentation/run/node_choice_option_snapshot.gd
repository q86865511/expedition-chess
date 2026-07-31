class_name NodeChoiceOptionSnapshot
extends RefCounted

var choice_id: StringName
var title_key: StringName
var description_key: StringName
var preview_key: StringName
var confirmation_required: bool


func _init(
	p_choice_id: StringName,
	p_title_key: StringName,
	p_description_key: StringName,
	p_preview_key: StringName,
	p_confirmation_required: bool
) -> void:
	choice_id = p_choice_id
	title_key = p_title_key
	description_key = p_description_key
	preview_key = p_preview_key
	confirmation_required = p_confirmation_required


func deep_clone() -> NodeChoiceOptionSnapshot:
	return NodeChoiceOptionSnapshot.new(
		choice_id,
		title_key,
		description_key,
		preview_key,
		confirmation_required
	)
