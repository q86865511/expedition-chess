class_name RuntimeKeyState
extends RefCounted

var kind: StringName = &""
var digest: StringName = &""

func deep_clone() -> RuntimeKeyState:
	var copied := RuntimeKeyState.new()
	copied.kind = kind
	copied.digest = digest
	return copied
