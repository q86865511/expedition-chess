class_name FakeStorageReadHandle
extends StorageReadHandle

var snapshot_bytes: PackedByteArray
var closed: bool = false

func _init(p_logical_path: StringName, p_snapshot_bytes: PackedByteArray) -> void:
	super(p_logical_path)
	snapshot_bytes = p_snapshot_bytes.duplicate()
