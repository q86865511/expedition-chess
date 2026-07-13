class_name RunKeyState
extends RuntimeKeyState

var profile_id: String = ""
var next_run_serial: U64Bits = null

static func create(profile: String, serial: U64Bits, key_digest: StringName) -> RunKeyState:
	var value := RunKeyState.new()
	value.kind = &"run"
	value.profile_id = profile
	value.next_run_serial = serial.deep_clone()
	value.digest = key_digest
	return value

func deep_clone() -> RuntimeKeyState:
	return create(profile_id, next_run_serial, digest)
