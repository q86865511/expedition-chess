class_name BattleResultQuery
extends RefCounted

var ok: bool
var result: BattleResult
var error: BattleSimulationError

static func success(value: BattleResult) -> BattleResultQuery:
	return BattleResultQuery.new(true, value, null)

static func failure(error_value: BattleSimulationError) -> BattleResultQuery:
	return BattleResultQuery.new(false, null, error_value)

func _init(
	p_ok: bool,
	p_result: BattleResult,
	p_error: BattleSimulationError
) -> void:
	ok = p_ok
	result = p_result.deep_clone() if p_result != null else null
	error = p_error.deep_clone() if p_error != null else null
