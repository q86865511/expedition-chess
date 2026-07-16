class_name CombatLabPresenter
extends RefCounted

var _setup: BattleSetup
var _events: Array[BattleEvent] = []
var _result: BattleResult

func present_setup(value: BattleSetup) -> void:
	_setup = value.deep_clone() if value != null else null
	_events.clear()
	_result = null

func present_events(values: Array[BattleEvent]) -> void:
	for event: BattleEvent in values:
		_events.append(event.deep_clone())

func present_result(value: BattleResult) -> void:
	_result = value.deep_clone() if value != null else null

func setup_view() -> BattleSetup:
	return _setup.deep_clone() if _setup != null else null

func event_view() -> Array[BattleEvent]:
	var result: Array[BattleEvent] = []
	for event: BattleEvent in _events:
		result.append(event.deep_clone())
	return result

func result_view() -> BattleResult:
	return _result.deep_clone() if _result != null else null
