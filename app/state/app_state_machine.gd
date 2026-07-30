class_name AppStateMachine
extends RefCounted

enum State { BOOT, MENU, CAMP, RUN, RESULTS }

var _state: State = State.BOOT
var _save_repository: SaveRepository

func _init(p_save_repository: SaveRepository = null) -> void:
	_save_repository = p_save_repository

func state() -> State:
	return _state

func can_transition(event: AppEvent) -> bool:
	return _validate_edge(event) == null and not _requires_commit(event.kind)

func transition(event: AppEvent) -> AppTransitionResult:
	var validation_error := _validate_edge(event)
	if validation_error != null:
		return AppTransitionResult.failure(_state, validation_error)
	if _requires_commit(event.kind):
		return AppTransitionResult.failure(
			_state,
			AppTransitionError.new(
				AppTransitionError.COMMIT_REQUIRED, _state, event.kind
			)
		)
	return _apply(event)

func transition_after_save(
	event: AppEvent,
	save_result: SaveResult
) -> AppTransitionResult:
	var validation_error := _validate_edge(event)
	if validation_error != null:
		return AppTransitionResult.failure(_state, validation_error)
	if event.kind not in [
		AppEvent.Kind.START_RUN,
		AppEvent.Kind.FINISH_RUN,
		AppEvent.Kind.ABANDON_RUN,
	] or _save_repository == null \
		or not _save_repository._consume_save_commit(save_result):
		return AppTransitionResult.failure(
			_state,
			AppTransitionError.new(
				AppTransitionError.COMMIT_REQUIRED, _state, event.kind
			)
		)
	return _apply(event)

func transition_after_active_run_load(
	event: AppEvent,
	load_result: LoadResult
) -> AppTransitionResult:
	var validation_error := _validate_edge(event)
	if validation_error != null:
		return AppTransitionResult.failure(_state, validation_error)
	if event.kind != AppEvent.Kind.ACTIVE_RUN_LOADED \
		or _save_repository == null \
		or not _save_repository._consume_active_run_load(load_result):
		return AppTransitionResult.failure(
			_state,
			AppTransitionError.new(
				AppTransitionError.COMMIT_REQUIRED, _state, event.kind
			)
		)
	return _apply(event)

func transition_after_terminal_handoff(event: AppEvent) -> AppTransitionResult:
	var validation_error := _validate_edge(event)
	if validation_error != null:
		return AppTransitionResult.failure(_state, validation_error)
	if event.kind != AppEvent.Kind.FINISH_RUN:
		return AppTransitionResult.failure(
			_state,
			AppTransitionError.new(
				AppTransitionError.COMMIT_REQUIRED, _state, event.kind
			)
		)
	return _apply(event)

func _apply(event: AppEvent) -> AppTransitionResult:
	_state = _target_for(event.kind)
	return AppTransitionResult.success(_state)

func _validate_edge(event: AppEvent) -> AppTransitionError:
	if event == null:
		return AppTransitionError.new(AppTransitionError.INVALID_EVENT, _state, -1)
	if not _edge_is_allowed(_state, event.kind):
		return AppTransitionError.new(
			AppTransitionError.INVALID_EDGE, _state, event.kind
		)
	return null

func _edge_is_allowed(from_state: State, event_kind: AppEvent.Kind) -> bool:
	match from_state:
		State.BOOT:
			# ACTIVE_RUN_LOADED remains a proof-gated compatibility edge for
			# direct state-machine consumers. ApplicationRoot never uses it
			# during G2 boot: every successful boot dispatches BOOT_COMPLETED
			# and rests at MENU.
			return event_kind == AppEvent.Kind.BOOT_COMPLETED \
				or event_kind == AppEvent.Kind.ACTIVE_RUN_LOADED
		State.MENU:
			return event_kind == AppEvent.Kind.OPEN_CAMP \
				or event_kind == AppEvent.Kind.CONTINUE_RUN
		State.CAMP:
			return event_kind == AppEvent.Kind.RETURN_TO_MENU \
				or event_kind == AppEvent.Kind.START_RUN
		State.RUN:
			return event_kind == AppEvent.Kind.FINISH_RUN \
				or event_kind == AppEvent.Kind.ABANDON_RUN \
				or event_kind == AppEvent.Kind.RETURN_TO_MENU
		State.RESULTS:
			return event_kind == AppEvent.Kind.RETURN_RESULTS_TO_CAMP \
				or event_kind == AppEvent.Kind.RETURN_RESULTS_TO_MENU \
				or event_kind == AppEvent.Kind.ACKNOWLEDGE_RESULTS
	return false

func _requires_commit(event_kind: AppEvent.Kind) -> bool:
	return event_kind == AppEvent.Kind.START_RUN \
		or event_kind == AppEvent.Kind.FINISH_RUN \
		or event_kind == AppEvent.Kind.ABANDON_RUN \
		or event_kind == AppEvent.Kind.ACTIVE_RUN_LOADED

func _target_for(event_kind: AppEvent.Kind) -> State:
	match event_kind:
		AppEvent.Kind.BOOT_COMPLETED:
			return State.MENU
		AppEvent.Kind.OPEN_CAMP:
			return State.CAMP
		AppEvent.Kind.RETURN_TO_MENU:
			return State.MENU
		AppEvent.Kind.START_RUN:
			return State.RUN
		AppEvent.Kind.ACTIVE_RUN_LOADED:
			return State.RUN
		AppEvent.Kind.CONTINUE_RUN:
			return State.RUN
		AppEvent.Kind.FINISH_RUN:
			return State.RESULTS
		AppEvent.Kind.ABANDON_RUN, AppEvent.Kind.ACKNOWLEDGE_RESULTS, \
		AppEvent.Kind.RETURN_RESULTS_TO_CAMP:
			return State.CAMP
		AppEvent.Kind.RETURN_RESULTS_TO_MENU:
			return State.MENU
	return _state
