class_name BattleInitializationResult
extends RefCounted

var ok: bool
var error: BattleSimulationError

static func success() -> BattleInitializationResult:
	return BattleInitializationResult.new(true, null)

static func failure(error_value: BattleSimulationError) -> BattleInitializationResult:
	return BattleInitializationResult.new(false, error_value)

func _init(p_ok: bool, p_error: BattleSimulationError) -> void:
	ResultInvariant.require(p_ok, p_error, true, true)
	ok = p_ok
	error = p_error.deep_clone() if p_error != null else null
