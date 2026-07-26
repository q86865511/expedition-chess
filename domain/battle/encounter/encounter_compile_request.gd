class_name EncounterCompileRequest
extends RefCounted

var manifest_digest: String = ""
var encounter_id: StringName = &""
var node_id: StringName = &""
var act_index: int = 0
var depth: int = 0
var challenge_level: int = 0
## design §6.3 軌 A（S5-AC-010）：ChallengeAffixResolver 解出的敵方詞綴 effect id，由 node entry
## 填入；EncounterCompiler 與 encounter 自帶的 affix_ids 取聯集後走同一條敵方管線。空陣列＝
## Challenge 0／未提供詞綴，行為與 S5 之前完全一致。
var challenge_affix_effect_ids: Array[StringName] = []

func deep_clone() -> EncounterCompileRequest:
	var copied := EncounterCompileRequest.new()
	copied.manifest_digest = manifest_digest
	copied.encounter_id = encounter_id
	copied.node_id = node_id
	copied.act_index = act_index
	copied.depth = depth
	copied.challenge_level = challenge_level
	copied.challenge_affix_effect_ids = challenge_affix_effect_ids.duplicate()
	return copied
