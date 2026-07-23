class_name IncomeQuoteRequest
extends RefCounted

var run_id: StringName
var node_id: StringName
var layer_index: int
var economy_state: EconomyState
var next_transaction_serial: U64Bits
var catalog: EconomyExpeditionCatalog
var relic_table: RunRelicTable
var active_relic_ids: Array[StringName] = []

func _init(
	p_run_id: StringName, p_node_id: StringName, p_layer_index: int,
	p_economy_state: EconomyState, p_next_serial: U64Bits,
	p_catalog: EconomyExpeditionCatalog,
	p_relic_table: RunRelicTable = null,
	p_active_relic_ids: Array[StringName] = []
) -> void:
	run_id = p_run_id
	node_id = p_node_id
	layer_index = p_layer_index
	economy_state = p_economy_state.deep_clone() if p_economy_state != null else null
	next_transaction_serial = p_next_serial.deep_clone() if p_next_serial != null else null
	catalog = p_catalog.deep_clone() if p_catalog != null else null
	relic_table = p_relic_table.deep_clone() if p_relic_table != null else null
	active_relic_ids = p_active_relic_ids.duplicate()
