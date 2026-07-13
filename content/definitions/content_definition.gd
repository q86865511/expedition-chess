class_name ContentDefinition
extends Resource

@export var id: StringName
@export var schema_version: int = 1
@export var display_name_key: StringName
@export var unlock_refs: Array[StringName] = []
@export var asset_refs: Array[String] = []

func referenced_content_ids() -> Array[StringName]:
	return unlock_refs.duplicate()

func category_name() -> StringName:
	return &"unknown"

func deep_authoring_clone() -> ContentDefinition:
	return duplicate(true) as ContentDefinition
