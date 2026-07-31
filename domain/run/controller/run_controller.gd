class_name RunController
extends RefCounted

signal view_published(view_state: RunViewState)

var _session: RunSession
var _save_repository: SaveRepository
var _validator: RunStateValidator
var _save_root_factory: RunSaveRootFactory
var _battle_catalog: BattleRuleCatalog
var _transaction_active: bool = false

func _init(
	p_session: RunSession,
	p_save_repository: SaveRepository,
	p_validator: RunStateValidator = null,
	p_save_root_factory: RunSaveRootFactory = null,
	p_battle_catalog: BattleRuleCatalog = null
) -> void:
	_session = p_session
	_save_repository = p_save_repository
	_validator = p_validator if p_validator != null else RunStateValidator.new()
	_save_root_factory = (
		p_save_root_factory
		if p_save_root_factory != null
		else RunSaveRootFactory.new()
	)
	# Pinned equipment-rule catalog held for the run's lifetime so the
	# "bound item must be an EquipmentDef" invariant (run_state_validator.gd
	# _validate_equipment_kind) runs on every commit instead of being dead code.
	# deep_clone keeps presentation/domain from retaining a mutable reference.
	_battle_catalog = p_battle_catalog.deep_clone() if p_battle_catalog != null else null

func transition(event: RunEvent) -> RunTransitionResult:
	var phase := _session.view_state().run_phase
	if event == null or not event.is_concrete():
		return RunTransitionResult.failure(
			RunTransitionError.new(RunTransitionError.INVALID_EVENT, phase, &"event")
		)
	if not can_transition(event):
		return RunTransitionResult.failure(
			RunTransitionError.new(RunTransitionError.INVALID_EDGE, phase, &"run_phase")
		)
	if _transaction_active:
		return RunTransitionResult.failure(
			RunTransitionError.new(RunTransitionError.TRANSACTION_BUSY, phase, &"transaction")
		)
	_transaction_active = true
	var draft := _session.run_snapshot()
	var pinned_content_snapshot := draft.content_snapshot.deep_clone()
	var apply_result := event.apply_to(draft)
	if not apply_result.ok or apply_result.draft == null:
		_transaction_active = false
		var field_path := apply_result.error.field_path if apply_result.error != null else &"event"
		var source_code := apply_result.error.code if apply_result.error != null else &"RUN_APPLY_RESULT_INVALID"
		var diagnostics: Array[DiagnosticValue] = [
			DiagnosticValue.from_string(&"apply_code", String(source_code)),
		]
		if apply_result.error != null:
			for diagnostic: DiagnosticValue in apply_result.error.diagnostic_values:
				diagnostics.append(diagnostic.deep_clone())
		return RunTransitionResult.failure(
			RunTransitionError.new(
				RunTransitionError.APPLY_FAILED,
				phase,
				field_path,
				null,
				diagnostics
			)
		)
	draft = apply_result.draft.deep_clone()
	draft.run_phase = event.target_phase
	var commit_result := _commit_draft(draft, pinned_content_snapshot)
	if not commit_result.ok:
		_transaction_active = false
		return RunTransitionResult.failure(_transition_error_from_commit(phase, commit_result.error))
	view_published.emit(commit_result.view_state.deep_clone())
	_transaction_active = false
	return RunTransitionResult.success(commit_result.view_state)

func dispatch(command: RunCommand) -> CommandResult:
	var phase := _session.view_state().run_phase
	if command == null or not command.is_concrete():
		return CommandResult.failure(
			CommandError.new(CommandError.INVALID_COMMAND, phase, &"command")
		)
	if _transaction_active:
		return CommandResult.failure(
			CommandError.new(CommandError.TRANSACTION_BUSY, phase, &"transaction")
		)
	_transaction_active = true
	var draft := _session.run_snapshot()
	var pinned_content_snapshot := draft.content_snapshot.deep_clone()
	var apply_result := command.apply_to(draft)
	if not apply_result.ok or apply_result.draft == null:
		_transaction_active = false
		var field_path := apply_result.error.field_path if apply_result.error != null else &"command"
		var source_code := apply_result.error.code if apply_result.error != null else &"RUN_APPLY_RESULT_INVALID"
		var diagnostics: Array[DiagnosticValue] = [
			DiagnosticValue.from_string(&"apply_code", String(source_code)),
		]
		if apply_result.error != null:
			for diagnostic: DiagnosticValue in apply_result.error.diagnostic_values:
				diagnostics.append(diagnostic.deep_clone())
		return CommandResult.failure(
			CommandError.new(
				CommandError.APPLY_FAILED,
				phase,
				field_path,
				null,
				diagnostics
			)
		)
	var commit_result := _commit_draft(apply_result.draft, pinned_content_snapshot)
	if not commit_result.ok:
		_transaction_active = false
		return CommandResult.failure(_command_error_from_commit(phase, commit_result.error))
	view_published.emit(commit_result.view_state.deep_clone())
	_transaction_active = false
	return CommandResult.success(commit_result.view_state)

func view_state() -> RunViewState:
	return _session.view_state()

func committed_combat_snapshot() -> CombatCommittedSnapshot:
	return _session.committed_combat_snapshot().deep_clone()

## T10 (design.md §8) -- read-only deep-clone accessor for ViewModels: never
## the same object graph as the canonical run, so a ViewModel can never retain
## a mutable domain reference.
func roster_snapshot() -> RosterState:
	return _session.run_snapshot().roster_state.deep_clone()

## S5 wave5 (design.md §8) -- read-only deep-clone accessor in the same family as
## roster_snapshot(): the run presentation needs the map's nodes/edges to offer the
## reachable-node choice, and must never hold a reference into the canonical run.
func map_snapshot() -> MapState:
	return _session.run_snapshot().map_state.deep_clone()

## S5 wave5 (design.md §8) -- read-only deep-clone accessor in the same family as
## roster_snapshot(): RunViewState carries only the aggregate economy numbers, while
## the shop offers themselves are needed to drive a purchase.
func economy_snapshot() -> EconomyState:
	return _session.run_snapshot().economy_state.deep_clone()

## T10 (design.md §8) -- read-only deep-clone accessor for ViewModels; null
## when the run's resolution_state is not currently a
## RewardPendingResolutionState (i.e. no pending reward to preview/resolve).
func pending_reward_snapshot() -> PendingRewardState:
	var resolution: ResolutionState = _session.run_snapshot().resolution_state
	var reward_resolution: RewardPendingResolutionState = resolution as RewardPendingResolutionState
	return reward_resolution.pending_reward.deep_clone() if reward_resolution != null else null

func node_choice_pending_snapshot() -> NodeChoicePendingState:
	var resolution: ResolutionState = _session.run_snapshot().resolution_state
	var pending := resolution as NodeChoicePendingState
	return (
		pending.deep_clone() as NodeChoicePendingState
		if pending != null
		else null
	)

func can_transition(event: RunEvent) -> bool:
	if event == null or not event.is_concrete():
		return false
	return _edge_is_allowed(_session.view_state().run_phase, event.target_phase)

func _commit_draft(
	draft: RunState,
	pinned_content_snapshot: ContentSnapshotState
) -> RunCommitResult:
	if not _session.has_catalog_pin():
		return RunCommitResult.failure(
			RunCommitError.new(
				RunCommitError.Kind.VALIDATION,
				&"content_snapshot.manifest_digest",
				&"RUN_CONTENT_CATALOG_PIN_MISSING"
			)
		)
	if not _session.can_publish():
		return RunCommitResult.failure(
			RunCommitError.new(
				RunCommitError.Kind.SERIAL_EXHAUSTED,
				&"publication_serial",
				&"RUN_PUBLICATION_SERIAL_EXHAUSTED"
			)
		)
	if draft == null \
		or draft.content_snapshot == null \
		or not draft.content_snapshot.canonical_equals(pinned_content_snapshot):
		return RunCommitResult.failure(
			RunCommitError.new(
				RunCommitError.Kind.VALIDATION,
				&"content_snapshot",
				&"RUN_CONTENT_SNAPSHOT_IMMUTABLE"
			)
		)
	if _battle_catalog != null \
		and _battle_catalog.manifest_digest_value() \
			!= draft.content_snapshot.manifest_digest_value():
		return RunCommitResult.failure(
			RunCommitError.new(
				RunCommitError.Kind.VALIDATION,
				&"content_snapshot.manifest_digest",
				&"RUN_CATALOG_GENERATION_MISMATCH"
			)
		)
	var validation_result := _validator.validate_run(draft, 1, 1, _battle_catalog)
	if not validation_result.ok:
		return RunCommitResult.failure(
			RunCommitError.new(
				RunCommitError.Kind.VALIDATION,
				validation_result.error.field_path,
				validation_result.error.code
			)
		)
	# T09 / S5-AC-012 (design.md §8): fold the run-scoped discovery ledger into
	# profile' -- discovery is the profile's only mutable face during a run -- so
	# it commits atomically in the same copy-validate-save-swap as the action
	# that revealed the content. Idempotent union: reload/replay never duplicates.
	var committed_profile := _session.profile_snapshot()
	RunDiscoveryLog.union_into_profile(committed_profile, draft)
	var candidate := _save_root_factory.build(committed_profile, draft)
	var save_result := _save_repository.save(candidate)
	if not save_result.ok:
		var save_field := save_result.error.field_path if save_result.error != null else &"save"
		var save_code := save_result.error.code if save_result.error != null else &"SAVE_UNKNOWN"
		return RunCommitResult.failure(
			RunCommitError.new(RunCommitError.Kind.SAVE, save_field, save_code)
		)
	return RunCommitResult.success(_session._commit_saved_draft(draft, committed_profile))

func _edge_is_allowed(from_phase: RunState.RunPhase, to_phase: RunState.RunPhase) -> bool:
	match from_phase:
		RunState.RunPhase.MAP:
			return to_phase == RunState.RunPhase.PREPARE
		RunState.RunPhase.PREPARE:
			return to_phase == RunState.RunPhase.COMBAT
		RunState.RunPhase.COMBAT:
			return to_phase == RunState.RunPhase.REWARD \
				or to_phase == RunState.RunPhase.MAP \
				or to_phase == RunState.RunPhase.PREPARE \
				or to_phase == RunState.RunPhase.RESULTS
		RunState.RunPhase.REWARD:
			return to_phase == RunState.RunPhase.MAP \
				or to_phase == RunState.RunPhase.RESULTS
		RunState.RunPhase.RESULTS:
			return false
	return false

func _transition_error_from_commit(
	phase: RunState.RunPhase,
	error: RunCommitError
) -> RunTransitionError:
	var code := RunTransitionError.SAVE_FAILED
	match error.kind:
		RunCommitError.Kind.VALIDATION:
			code = RunTransitionError.VALIDATION_FAILED
		RunCommitError.Kind.SERIAL_EXHAUSTED:
			code = RunTransitionError.PUBLICATION_SERIAL_EXHAUSTED
		RunCommitError.Kind.BUSY:
			code = RunTransitionError.TRANSACTION_BUSY
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(error.source_code)),
	]
	return RunTransitionError.new(code, phase, error.field_path, null, diagnostics)

func _command_error_from_commit(
	phase: RunState.RunPhase,
	error: RunCommitError
) -> CommandError:
	var code := CommandError.SAVE_FAILED
	match error.kind:
		RunCommitError.Kind.VALIDATION:
			code = CommandError.VALIDATION_FAILED
		RunCommitError.Kind.SERIAL_EXHAUSTED:
			code = CommandError.PUBLICATION_SERIAL_EXHAUSTED
		RunCommitError.Kind.BUSY:
			code = CommandError.TRANSACTION_BUSY
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(error.source_code)),
	]
	return CommandError.new(code, phase, error.field_path, null, diagnostics)
