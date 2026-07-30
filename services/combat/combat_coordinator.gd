class_name CombatCoordinator
extends RefCounted

signal events_published(events: Array[BattleEvent])
signal result_published(result: BattleResult)

const VALID_SPEEDS: Array[int] = [1, 2, 4]

var _controller: RunController
var _presentation_session: RefCounted
var _simulation: BattleSimulation
var _paused: bool = false
var _speed: int = 1
var _active: bool = false
var _pending_result: BattleResult
var _pending_receipt: BattleResultValidationReceipt
var _pending_transcript: PendingBattleTranscriptAccumulator
var _active_run_id: StringName
var _active_setup_hash: String


func _init(
	controller: RunController,
	p_presentation_session: RefCounted = null
) -> void:
	_controller = controller
	_presentation_session = p_presentation_session


func bind_presentation_session(session: RefCounted) -> void:
	_presentation_session = session

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
		if _presentation_session != null \
			and _presentation_session.has_method(&"release_playback"):
			_presentation_session.call(&"release_playback", &"result_pending_reload")
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
	if _presentation_session != null \
		and _presentation_session.has_method(&"release_playback"):
		_presentation_session.call(&"release_playback", &"new_battle")
	var event_budget := pending.battle_setup.inputs.battle_rules.event_budget
	_pending_transcript = PendingBattleTranscriptAccumulator.new(event_budget)
	_active_run_id = &""
	if _presentation_session != null:
		var view := _controller.view_state()
		if view == null:
			_pending_transcript.discard_on_save_failure()
			_pending_transcript = null
			return _failure(
				CombatCoordinatorError.COMMITTED_STATE_INVALID,
				&"run_view"
			)
		_active_run_id = StringName(view.run_id)
	_active_setup_hash = String(pending.battle_setup.battle_setup_hash)
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
	# Compatibility-only direct coordinator consumers may still pause their
	# legacy harness. Production always binds RunPresentationSession, where
	# pause belongs exclusively to BattlePlaybackController.
	if _paused and _presentation_session == null:
		return CombatCoordinatorStepResult.success(0)
	# Canonical simulation advances exactly one tick per call. Playback speed
	# never enters gameplay RNG, simulation ticks, result hashes, or saves.
	var stepped := _simulation.step()
	if not stepped.ok:
		return _step_failure(
			CombatCoordinatorError.SIMULATION_STEP_FAILED,
			stepped.error.field_path,
			stepped.error.code
		)
	if _pending_transcript == null \
		or not _pending_transcript.append_events(stepped.events):
		_discard_production_attempt()
		return _step_failure(
			CombatCoordinatorError.SIMULATION_STEP_FAILED,
			&"event_budget",
			&"BATTLE_SIMULATION_BUDGET_EXCEEDED"
		)
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
		return CombatCoordinatorStepResult.success(1, true)
	return CombatCoordinatorStepResult.success(1)

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
		if _presentation_session != null:
			_discard_production_attempt()
		return _step_failure(
			CombatCoordinatorError.RESULT_COMMIT_FAILED,
			recorded.error.field_path if recorded.error != null else &"record_result",
			recorded.error.code if recorded.error != null else &"COMMAND_FAILED"
		)
	if _presentation_session != null and _pending_transcript != null:
		var encoded_byte_count := _pending_transcript.encoded_byte_count()
		if encoded_byte_count < 0:
			encoded_byte_count = BattleTranscriptBuffer.MAX_BYTE_BUDGET + 1
		var identity := BattleTranscriptIdentity.new()
		identity.run_id = _active_run_id
		identity.battle_setup_hash = _active_setup_hash
		identity.committed_result_digest = String(_pending_result.result_hash)
		identity.resolution_identity = _pending_result.result_hash
		_presentation_session.call(
			&"_accept_committed_transcript",
			_pending_transcript,
			identity,
			encoded_byte_count
		)
	elif _pending_transcript != null:
		# Compatibility surface for pre-G2 direct coordinator harnesses. The
		# production path above never exposes raw transcript events by signal.
		var transferred: Array[BattleEvent] = \
			_pending_transcript._seal_and_transfer()
		events_published.emit(_clone_events(transferred))
	result_published.emit(_pending_result.deep_clone())
	_pending_result = null
	_pending_receipt = null
	_pending_transcript = null
	_simulation = null
	_active = false
	return CombatCoordinatorStepResult.success(0, true)


func _discard_production_attempt() -> void:
	if _pending_transcript != null:
		_pending_transcript.discard_on_save_failure()
	_pending_transcript = null
	_pending_result = null
	_pending_receipt = null
	_simulation = null
	_active = false
	_active_run_id = &""
	_active_setup_hash = ""

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
