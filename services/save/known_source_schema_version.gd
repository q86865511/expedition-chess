class_name KnownSourceSchemaVersion
extends SourceSchemaVersionState

var value: int

func _init(p_value: int) -> void:
	value = p_value

func deep_clone() -> SourceSchemaVersionState:
	return KnownSourceSchemaVersion.new(value)
