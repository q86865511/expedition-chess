class_name MapGenerationRequest
extends RefCounted

var run_id: StringName
var run_seed: U64Bits
var catalog: EconomyExpeditionCatalog
var relic_table: RunRelicTable
var active_relic_ids: Array[StringName] = []

func _init(
	p_run_id: StringName, p_run_seed: U64Bits, p_catalog: EconomyExpeditionCatalog,
	p_relic_table: RunRelicTable = null,
	p_active_relic_ids: Array[StringName] = []
) -> void:
	run_id = p_run_id
	run_seed = p_run_seed.deep_clone() if p_run_seed != null else null
	catalog = p_catalog.deep_clone() if p_catalog != null else null
	relic_table = p_relic_table.deep_clone() if p_relic_table != null else null
	active_relic_ids = p_active_relic_ids.duplicate()
