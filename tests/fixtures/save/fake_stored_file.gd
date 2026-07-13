class_name FakeStoredFile
extends RefCounted

var logical_path: StringName
var bytes: PackedByteArray

func _init(p_logical_path: StringName, p_bytes: PackedByteArray) -> void:
	logical_path = p_logical_path
	bytes = p_bytes.duplicate()

func deep_clone() -> FakeStoredFile:
	return FakeStoredFile.new(logical_path, bytes)
