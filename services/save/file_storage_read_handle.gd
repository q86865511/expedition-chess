class_name FileStorageReadHandle
extends StorageReadHandle

var file: FileAccess

func _init(p_logical_path: StringName, p_file: FileAccess) -> void:
	super(p_logical_path)
	file = p_file
