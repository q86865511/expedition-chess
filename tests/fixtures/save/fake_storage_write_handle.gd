class_name FakeStorageWriteHandle
extends StorageWriteHandle

var pending_bytes: PackedByteArray = PackedByteArray()
var flushed: bool = false
var closed: bool = false

func _init(p_logical_path: StringName) -> void:
	super(p_logical_path)
