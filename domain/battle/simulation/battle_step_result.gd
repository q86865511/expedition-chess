class_name BattleStepResult
extends RefCounted

var ok: bool
var tick: int
var events: Array[BattleEvent] = []
var finished: bool
var error: BattleSimulationError

static func success(
	p_tick: int,
	p_events: Array[BattleEvent],
	p_finished: bool
) -> BattleStepResult:
	return BattleStepResult.new(true, p_tick, p_events, p_finished, null)

static func failure(error_value: BattleSimulationError) -> BattleStepResult:
	var empty: Array[BattleEvent] = []
	return BattleStepResult.new(false, 0, empty, false, error_value)

func _init(
	p_ok: bool,
	p_tick: int,
	p_events: Array[BattleEvent],
	p_finished: bool,
	p_error: BattleSimulationError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_tick >= 0,
		p_tick == 0 and p_events.is_empty() and not p_finished
	)
	ok = p_ok
	tick = p_tick
	for event: BattleEvent in p_events:
		events.append(event.deep_clone())
	finished = p_finished
	error = p_error.deep_clone() if p_error != null else null
