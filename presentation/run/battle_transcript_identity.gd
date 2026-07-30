class_name BattleTranscriptIdentity
extends RefCounted

var run_id: StringName
var battle_setup_hash: String
var committed_result_digest: String
var resolution_identity: StringName


func deep_clone() -> BattleTranscriptIdentity:
	var clone := BattleTranscriptIdentity.new()
	clone.run_id = run_id
	clone.battle_setup_hash = battle_setup_hash
	clone.committed_result_digest = committed_result_digest
	clone.resolution_identity = resolution_identity
	return clone
