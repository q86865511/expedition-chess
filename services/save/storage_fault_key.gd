class_name StorageFaultKey
extends RefCounted

const DIRECTORY: StringName = &"DIRECTORY"
const EXISTS: StringName = &"EXISTS"
const OPEN_READ: StringName = &"OPEN_READ"
const READ: StringName = &"READ"
const OPEN_WRITE: StringName = &"OPEN_WRITE"
const WRITE: StringName = &"WRITE"
const FLUSH: StringName = &"FLUSH"
const CLOSE: StringName = &"CLOSE"
const RENAME: StringName = &"RENAME"
const QUARANTINE: StringName = &"QUARANTINE"
const RESTORE: StringName = &"RESTORE"
const REMOVE: StringName = &"REMOVE"

const MAIN: StringName = &"main"
const BACKUP: StringName = &"backup"
const TMP: StringName = &"tmp"
const OLD: StringName = &"old"
const QUARANTINE_PATH: StringName = &"quarantine"

var operation_kind: StringName
var logical_path: StringName
var occurrence: int

func _init(p_operation_kind: StringName, p_logical_path: StringName, p_occurrence: int) -> void:
	operation_kind = p_operation_kind
	logical_path = p_logical_path
	occurrence = p_occurrence

func equals(other: StorageFaultKey) -> bool:
	return other != null and operation_kind == other.operation_kind \
		and logical_path == other.logical_path and occurrence == other.occurrence

func deep_clone() -> StorageFaultKey:
	return StorageFaultKey.new(operation_kind, logical_path, occurrence)
