class_name ContentIdMigrationRequest
extends RefCounted

var content_id: StringName
var expected_category: StringName
var required_for_active_run: bool
var field_path: StringName

func _init(
	p_content_id: StringName,
	p_expected_category: StringName,
	p_required_for_active_run: bool,
	p_field_path: StringName
) -> void:
	content_id = p_content_id
	expected_category = p_expected_category
	required_for_active_run = p_required_for_active_run
	field_path = p_field_path

func deep_clone() -> ContentIdMigrationRequest:
	return ContentIdMigrationRequest.new(
		content_id, expected_category, required_for_active_run, field_path
	)
