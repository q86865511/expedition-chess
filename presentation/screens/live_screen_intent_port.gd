class_name LiveScreenIntentPort
extends RefCounted

const SCREEN_NOT_ACTIVE: StringName = &"SCREEN_NOT_ACTIVE"
const CONFIRMATION_DRAFT_INVALID: StringName = &"CONFIRMATION_DRAFT_INVALID"
const CONFIRMATION_ALREADY_RESOLVED: StringName = &"CONFIRMATION_ALREADY_RESOLVED"

var _lease: LiveScreenLease
var _registry: LiveScreenLeaseRegistry
var _session: RunPresentationSession
var _after_dispatch: Callable
var _next_confirmation_sequence: int = 1
var _confirmation_issuer := RefCounted.new()
var _pending_confirmations: Dictionary[StringName, Dictionary] = {}


func _init(
	p_lease: LiveScreenLease = null,
	p_registry: LiveScreenLeaseRegistry = null,
	p_session: RunPresentationSession = null,
	p_after_dispatch: Callable = Callable()
) -> void:
	_lease = p_lease.deep_clone() if p_lease != null else null
	_registry = p_registry
	_session = p_session
	_after_dispatch = p_after_dispatch


func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
	if not _is_active():
		return RunPresentationResult.failure(_screen_not_active_error())
	if _session == null:
		return RunPresentationResult.failure(_screen_not_active_error())
	var result := _session.dispatch(intent)
	return _route_after_dispatch(result)


func begin_confirmation(
	intent: RunPresentationIntent
) -> ConfirmationDraftResult:
	if not _is_active():
		return ConfirmationDraftResult.failure(_screen_not_active_error())
	if _session == null or intent == null:
		return ConfirmationDraftResult.failure(_draft_error())
	var snapshot := _session.snapshot()
	var nonce := StringName(
		"confirmation.%s.%d" % [String(_lease.lease_id), _next_confirmation_sequence]
	)
	_next_confirmation_sequence += 1
	var draft := ConfirmationDraft.new()
	draft.operation_kind = intent.kind
	draft.snapshot_identity = snapshot.run_id if snapshot != null else &""
	draft.lifecycle = (
		snapshot.app_phase if snapshot != null else &""
	)
	draft.payload_digest = _intent_digest(intent)
	draft.lease_id = _lease.lease_id
	draft.route_generation = _lease.route_generation
	draft._use_nonce = nonce
	draft._intent = intent.deep_clone()
	draft._issuer = _confirmation_issuer
	_pending_confirmations[nonce] = {
		"draft": draft,
		"intent": intent.deep_clone(),
		"digest": draft.payload_digest,
	}
	return ConfirmationDraftResult.new(true, draft, null)


func confirm(
	draft: ConfirmationDraft
) -> RunPresentationResult:
	if not _is_active():
		return RunPresentationResult.failure(_screen_not_active_error())
	var validation_error := _validate_draft(draft)
	if validation_error != null:
		return RunPresentationResult.failure(validation_error)
	var issued: Dictionary = _pending_confirmations[draft._use_nonce]
	var authoritative := issued.get("intent") as RunPresentationIntent
	_pending_confirmations.erase(draft._use_nonce)
	draft._resolved = true
	draft.lifecycle = &"confirmed"
	var result := _session.dispatch(authoritative.deep_clone())
	return _route_after_dispatch(result)


func cancel(
	draft: ConfirmationDraft
) -> ConfirmationCancelResult:
	if not _is_active():
		return ConfirmationCancelResult.failure(_screen_not_active_error())
	var validation_error := _validate_draft(draft)
	if validation_error != null:
		return ConfirmationCancelResult.failure(validation_error)
	_pending_confirmations.erase(draft._use_nonce)
	draft._resolved = true
	draft.lifecycle = &"cancelled"
	return ConfirmationCancelResult.new(true, null)


func _is_active() -> bool:
	return _registry != null and _registry.is_active(_lease)


func _validate_draft(draft: ConfirmationDraft) -> DiagnosticError:
	if (
		draft == null
		or _lease == null
		or draft._issuer != _confirmation_issuer
		or draft.lease_id != _lease.lease_id
		or draft.route_generation != _lease.route_generation
	):
		return _draft_error()
	if not _pending_confirmations.has(draft._use_nonce):
		if not draft._resolved:
			return _draft_error()
		return DiagnosticError.new(
			CONFIRMATION_ALREADY_RESOLVED,
			&"error.presentation.confirmation_already_resolved"
		)
	var issued: Dictionary = _pending_confirmations[draft._use_nonce]
	if issued.get("draft") != draft:
		return _draft_error()
	var authoritative := issued.get("intent") as RunPresentationIntent
	var issued_digest := String(issued.get("digest", ""))
	if (
		draft._intent == null
		or authoritative == null
		or draft._intent.kind != draft.operation_kind
		or draft.payload_digest != issued_digest
		or _intent_digest(draft._intent) != issued_digest
	):
		return _draft_error()
	var current_snapshot := _session.snapshot()
	if (
		current_snapshot == null
		or current_snapshot.run_id != draft.snapshot_identity
		or current_snapshot.app_phase != draft.lifecycle
	):
		return _draft_error()
	return null


func _intent_digest(intent: RunPresentationIntent) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(
		("%d|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s" % [
			intent.kind,
			intent.target_node_id,
			intent.offer_id,
			intent.unit_instance_id,
			intent.item_instance_id,
			intent.secondary_item_instance_id,
			intent.target_unit_instance_id,
			intent.choice_id,
			intent.relic_slot_index,
			str(intent.accept),
			str(intent.abandon),
		]).to_utf8_buffer()
	)
	return context.finish().hex_encode()


func _screen_not_active_error() -> DiagnosticError:
	return DiagnosticError.new(
		SCREEN_NOT_ACTIVE,
		&"error.presentation.screen_not_active"
	)


func _route_after_dispatch(
	result: RunPresentationResult
) -> RunPresentationResult:
	if (
		result == null
		or not (result.ok or result.committed)
		or result.snapshot == null
		or not _after_dispatch.is_valid()
	):
		return result
	var route_result := _after_dispatch.call(result) as AppActionResult
	if route_result == null or not route_result.ok:
		if _registry != null:
			_registry.revoke(_lease)
		var error := (
			route_result.error
			if route_result != null and route_result.error != null
			else DiagnosticError.new(
				&"RUN_ROUTE_ACTIVATION_FAILED",
				&"error.presentation.run_route_activation_failed"
			)
		)
		return RunPresentationResult.postcommit_failure(
			error,
			result.snapshot
		)
	return result


func _draft_error() -> DiagnosticError:
	return DiagnosticError.new(
		CONFIRMATION_DRAFT_INVALID,
		&"error.presentation.confirmation_draft_invalid"
	)
