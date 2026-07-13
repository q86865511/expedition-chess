class_name FileStorageWriteHandle
extends StorageWriteHandle

var file: FileAccess

func _init(p_logical_path: StringName, p_file: FileAccess) -> void:
	super(p_logical_path)
	file = p_file
