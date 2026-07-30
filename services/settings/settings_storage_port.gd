class_name SettingsStoragePort
extends RefCounted

## Named storage boundary for SettingsRepository (design.md §"SettingsRepository
## 依 SaveRepository 同紀律..."). Kept separate from SaveStoragePort: that port's
## handle-based contract (open_write/write_buffer/flush_write/...) is a
## different shape than the byte-result contract SettingsRepository actually
## drives (read_bytes/write_bytes/promote_bytes/...), so settings cannot
## borrow the gameplay SaveRepository storage boundary. A concrete double
## that forgets to override one of these methods fails immediately at the
## call site with the built-in RefCounted "unsupported" diagnostic below,
## instead of only surfacing deep inside a fault-injection branch as a bare
## Variant runtime error. Every method returns the named SettingsStorageResult
## (not a Dictionary): public domain APIs use named types project-wide.

const UNSUPPORTED: StringName = &"SETTINGS_STORAGE_FAULT"


func read_bytes(_path: StringName) -> SettingsStorageResult:
	return _unsupported()


func write_bytes(_path: StringName, _bytes: PackedByteArray) -> SettingsStorageResult:
	return _unsupported()


func promote_bytes(_source: StringName, _destination: StringName) -> SettingsStorageResult:
	return _unsupported()


func copy_bytes(_source: StringName, _destination: StringName) -> SettingsStorageResult:
	return _unsupported()


func restore_bytes(source: StringName, destination: StringName) -> SettingsStorageResult:
	return copy_bytes(source, destination)


func remove_bytes(_path: StringName) -> SettingsStorageResult:
	return _unsupported()


func _unsupported() -> SettingsStorageResult:
	return SettingsStorageResult.failure(UNSUPPORTED)
