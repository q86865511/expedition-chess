class_name CombatCoordinator
extends RefCounted

signal events_published(events: Array[BattleEvent])
signal result_published(result: BattleResult)

const VALID_SPEEDS: Array[int] = [1, 2, 4]

var _controller: RunController
var _simulation: BattleSimulation
var _paused: bool = false
var _speed: int = 1
var _active: bool = false
var _pending_result: BattleResult
var _pending_receipt: BattleResultValidationReceipt
var _pending_terminal_events: Array[BattleEvent] = []

func _init(controller: RunController) -> void:
	_controller = controller

func begin_or_resume() -> CombatCoordinatorResult:
	if _controller == null or _active:
		return _failure(
			CombatCoordinatorError.LIFECYCLE_INVALID, &"begin_or_resume"
		)
	var committed := _controller.committed_combat_snapshot()
	if committed == null or committed.run_phase != RunState.RunPhase.COMBAT \
		or committed.resolution_state == null:
		return _failure(
			CombatCoordinatorError.COMMITTED_STATE_INVALID, &"committed_state"
		)
	if committed.resolution_state is BattleResultPendingResolutionState:
		var pending := committed.resolution_state as BattleResultPendingResolutionState
		if pending.battle_result == null:
			return _failure(
				CombatCoordinatorError.COMMITTED_STATE_INVALID,
				&"battle_result_pending.battle_result"
			)
		result_published.emit(pending.battle_result.deep_clone())
		return CombatCoordinatorResult.success(true)
	if not committed.resolution_state is CombatPendingResolutionState:
		return _failure(
			CombatCoordinatorError.COMMITTED_STATE_INVALID, &"resolution_state"
		)
	var pending := committed.resolution_state as CombatPendingResolutionState
	if pending.battle_setup == null:
		return _failure(
			CombatCoordinatorError.COMMITTED_STATE_INVALID, &"combat_pending.battle_setup"
		)
	var envelope := BattleSetupEnvelopeVerifier.new().verify(
		pending.battle_setup, committed.run_seed
	)
	if not envelope.ok:
		return _failure(
			CombatCoordinatorError.SETUP_ENVELOPE_INVALID,
			envelope.error.field_path,
			envelope.error.code
		)
	var simulation := BattleSimulation.new()
	var initialized := simulation.initialize(pending.battle_setup)
	if not initialized.ok:
		return _failure(
			CombatCoordinatorError.SIMULATION_INITIALIZATION_FAILED,
			initialized.error.field_path,
			initialized.error.code
		)
	_simulation = simulation
	_active = true
	return CombatCoordinatorResult.success()

func advance() -> CombatCoordinatorStepResult:
	if not _active or _simulation == null:
		return _step_failure(
			CombatCoordinatorError.LIFECYCLE_INVALID, &"advance"
		)
	if _pending_result != null:
		return _commit_pending_result()
	if _paused:
		return CombatCoordinatorStepResult.success(0)
	var advanced := 0
	for _index: int in range(_speed):
		var stepped := _simulation.step()
		if not stepped.ok:
			return _step_failure(
				CombatCoordinatorError.SIMULATION_STEP_FAILED,
				stepped.error.field_path,
				stepped.error.code
			)
		advanced += 1
		_publish_live_events(stepped.events)
		if stepped.finished:
			var queried := _simulation.result()
			if not queried.ok or queried.result == null:
				return _step_failure(
					CombatCoordinatorError.RESULT_QUERY_FAILED,
					queried.error.field_path if queried.error != null else &"result",
					queried.error.code if queried.error != null else &"RESULT_MISSING"
				)
			_pending_result = queried.result.deep_clone()
			_pending_receipt = _simulation.validation_receipt()
			var committed := _commit_pending_result()
			if not committed.ok:
				return committed
			return CombatCoordinatorStepResult.success(advanced, true)
	return CombatCoordinatorStepResult.success(advanced)

func set_paused(value: bool) -> void:
	_paused = value

func is_paused() -> bool:
	return _paused

func set_speed(value: int) -> bool:
	if not VALID_SPEEDS.has(value):
		return false
	_speed = value
	return true

func speed() -> int:
	return _speed

func _publish_live_events(events: Array[BattleEvent]) -> void:
	var live: Array[BattleEvent] = []
	for event: BattleEvent in events:
		if event.type == &"battle_finished":
			_pending_terminal_events.append(event.deep_clone())
		else:
			live.append(event.deep_clone())
	if not live.is_empty():
		events_published.emit(_clone_events(live))

func _commit_pending_result() -> CombatCoordinatorStepResult:
	if _pending_result == null or _pending_receipt == null:
		return _step_failure(
			CombatCoordinatorError.RESULT_QUERY_FAILED, &"pending_result"
		)
	var command := RecordBattleResultCommand.new(
		_pending_result.battle_setup_hash,
		_pending_result.result_hash,
		_pending_result,
		_pending_receipt
	)
	var recorded := _controller.dispatch(command)
	if not recorded.ok:
		return _step_failure(
			CombatCoordinatorError.RESULT_COMMIT_FAILED,
			recorded.error.field_path if recorded.error != null else &"record_result",
			recorded.error.code if recorded.error != null else &"COMMAND_FAILED"
		)
	if not _pending_terminal_events.is_empty():
		events_published.emit(_clone_events(_pending_terminal_events))
	result_published.emit(_pending_result.deep_clone())
	_pending_terminal_events.clear()
	_pending_result = null
	_pending_receipt = null
	_simulation = null
	_active = false
	return CombatCoordinatorStepResult.success(0, true)

func _clone_events(source: Array[BattleEvent]) -> Array[BattleEvent]:
	var result: Array[BattleEvent] = []
	for event: BattleEvent in source:
		result.append(event.deep_clone())
	return result

func _failure(
	code: StringName,
	path: StringName,
	source_code: StringName = &""
) -> CombatCoordinatorResult:
	return CombatCoordinatorResult.failure(
		CombatCoordinatorError.new(code, path, source_code)
	)

func _step_failure(
	code: StringName,
	path: StringName,
	source_code: StringName = &""
) -> CombatCoordinatorStepResult:
	return CombatCoordinatorStepResult.failure(
		CombatCoordinatorError.new(code, path, source_code)
	)
