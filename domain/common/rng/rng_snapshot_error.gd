class_name RngSnapshotError
extends RefCounted

var code: StringName = &"RNG_SNAPSHOT_INVALID"
var field_path: StringName = &"snapshot"
var source_id: StringName = &""

static func create(error_code: StringName, path: StringName) -> RngSnapshotError:
	var value := RngSnapshotError.new()
	value.code = error_code
	value.field_path = path
	return value
