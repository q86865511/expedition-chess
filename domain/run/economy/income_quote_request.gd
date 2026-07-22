class_name IncomeQuoteRequest
extends RefCounted

var run_id: StringName
var node_id: StringName
var layer_index: int
var economy_state: EconomyState
var next_transaction_serial: U64Bits
var catalog: EconomyExpeditionCatalog

func _init(
	p_run_id: StringName, p_node_id: StringName, p_layer_index: int,
	p_economy_state: EconomyState, p_next_serial: U64Bits,
	p_catalog: EconomyExpeditionCatalog
) -> void:
	run_id = p_run_id
	node_id = p_node_id
	layer_index = p_layer_index
	economy_state = p_economy_state.deep_clone() if p_economy_state != null else null
	next_transaction_serial = p_next_serial.deep_clone() if p_next_serial != null else null
	catalog = p_catalog.deep_clone() if p_catalog != null else null
