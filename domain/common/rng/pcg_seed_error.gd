class_name PcgSeedError
extends RefCounted

var code: StringName = &"RNG_SNAPSHOT_INVALID"
var field_path: StringName = &"seed"
var source_id: StringName = &""

static func create(error_code: StringName, path: StringName) -> PcgSeedError:
	var value := PcgSeedError.new()
	value.code = error_code
	value.field_path = path
	return value
