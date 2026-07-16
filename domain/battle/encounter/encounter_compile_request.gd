class_name EncounterCompileRequest
extends RefCounted

var manifest_digest: String = ""
var encounter_id: StringName = &""
var node_id: StringName = &""
var act_index: int = 0
var depth: int = 0
var challenge_level: int = 0

func deep_clone() -> EncounterCompileRequest:
	var copied := EncounterCompileRequest.new()
	copied.manifest_digest = manifest_digest
	copied.encounter_id = encounter_id
	copied.node_id = node_id
	copied.act_index = act_index
	copied.depth = depth
	copied.challenge_level = challenge_level
	return copied
