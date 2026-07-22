class_name MapGenerationRequest
extends RefCounted

var run_id: StringName
var run_seed: U64Bits
var catalog: EconomyExpeditionCatalog

func _init(p_run_id: StringName, p_run_seed: U64Bits, p_catalog: EconomyExpeditionCatalog) -> void:
	run_id = p_run_id
	run_seed = p_run_seed.deep_clone() if p_run_seed != null else null
	catalog = p_catalog.deep_clone() if p_catalog != null else null
