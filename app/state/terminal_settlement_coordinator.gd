class_name TerminalSettlementCoordinator
extends RefCounted

## R12 A01/A02 ownership sequence:
## save authoritative candidate while repository-owned -> capture receipt/profile/
## committed bytes digest -> revoke RUN writers/session -> install application
## RESULTS state/snapshot -> release repository -> present the installed clone.

const TERMINAL_BUSY: StringName = &"TERMINAL_SETTLEMENT_BUSY"
const TERMINAL_INVALID: StringName = &"TERMINAL_SETTLEMENT_INVALID"
const TERMINAL_SAVE_FAILED: StringName = &"TERMINAL_SETTLEMENT_SAVE_FAILED"
const RESULTS: StringName = &"RESULTS"
const FALLBACK: StringName = &"RESULTS_FALLBACK"

var _save_repository: SaveRepository
var _handoff_port: TerminalPresentationHandoffPort
var _run_writer_revoke: Callable
var _session_invalidate: Callable
var _session_release: Callable
var _application_results_seal: Callable
var _terminal_guard: bool = false


func _init(
	p_save_repository: SaveRepository,
	p_handoff_port: TerminalPresentationHandoffPort,
	p_run_writer_revoke: Callable,
	p_session_invalidate: Callable,
	p_session_release: Callable,
	p_application_results_seal: Callable = Callable()
) -> void:
	_save_repository = p_save_repository
	_handoff_port = p_handoff_port
	_run_writer_revoke = p_run_writer_revoke
	_session_invalidate = p_session_invalidate
	_session_release = p_session_release
	_application_results_seal = p_application_results_seal


func settle(meta_reward_table: MetaRewardTableDef) -> AppActionResult:
	if _terminal_guard:
		return _failure(TERMINAL_BUSY)
	if _save_repository == null or meta_reward_table == null:
		return _failure(TERMINAL_INVALID)
	_terminal_guard = true
	if not _save_repository._begin_writer_ownership():
		_terminal_guard = false
		return _failure(TERMINAL_BUSY)

	var loaded := _save_repository._load_while_owned()
	if not loaded.ok or loaded.run_status != LoadResult.RunStatus.LOADED \
		or loaded.run == null \
		or loaded.run.run_phase != RunState.RunPhase.RESULTS:
		_release_ownership()
		return _failure(TERMINAL_INVALID)
	var run_id := StringName(loaded.run.run_id)
	var settled_profile := MetaSettlementService.try_settle(
		loaded.profile, loaded.run, meta_reward_table
	)
	if settled_profile == null:
		_release_ownership()
		return _failure(TERMINAL_INVALID)
	var root := SaveRoot.new(
		SaveSchemaContract.CURRENT,
		loaded.run.content_snapshot.content_version_value(),
		"0.2.0",
		1,
		1,
		RunCommitClock.new().now_utc(),
		settled_profile,
		null
	)
	var saved := _save_repository._save_while_owned(root)
	if not saved.ok:
		_release_ownership()
		return _failure(TERMINAL_SAVE_FAILED)

	var committed_digest := (
		saved.committed_digest.value
		if saved.committed_digest != null
		else ""
	)
	var receipt_id := _receipt_id_for_run(settled_profile, run_id)
	var receipt := _receipt_for_run(settled_profile, run_id)
	var snapshot := ResultsPresentationSnapshot.capture(
		settled_profile,
		receipt,
		run_id,
		committed_digest,
		true
	)

	# The durable save is now irreversible. Revoke every RUN authority first,
	# then seal the authoritative snapshot into application state using only
	# application-local authority. Repository capabilities remain mandatory for
	# the later cross-boundary presentation handoff, but can no longer block the
	# fail-closed RESULTS state.
	if _run_writer_revoke.is_valid():
		_run_writer_revoke.call()
	if _session_invalidate.is_valid():
		_session_invalidate.call()
	if _session_release.is_valid():
		_session_release.call()
	var sealed := _seal_application_results(
		snapshot,
		&"TERMINAL_POSTCOMMIT_SEAL"
	)

	var fallback_capability := (
		_save_repository._issue_terminal_postcommit_fallback_capability(
			run_id,
			receipt_id
		)
	)
	var capability: TerminalSettlementPresentationCapability = (
		_save_repository._issue_terminal_settlement_presentation_capability(
			run_id,
			receipt_id
		)
	)
	var capability_valid := (
		capability != null
		and _save_repository
			._consume_terminal_settlement_presentation_capability(
				capability,
				snapshot
			)
	)
	if not capability_valid:
		_save_repository._revoke_terminal_settlement_presentation_capability(
			capability
		)
	var install_cause: StringName = &""
	if not capability_valid:
		install_cause = &"TERMINAL_CAPABILITY_INVALID"
	elif _handoff_port == null:
		install_cause = &"TERMINAL_HANDOFF_PORT_MISSING"

	var installed: AppActionResult = null
	if install_cause.is_empty():
		installed = _handoff_port.install_application_handoff(
			capability,
			snapshot.deep_clone()
		)
		if not installed.ok:
			install_cause = (
				installed.error.source_code
				if installed.error != null
				else FALLBACK
			)
	var presentation_ready := (
		installed != null and installed.ok
	)
	if (
		not presentation_ready
		and _handoff_port is ApplicationTerminalHandoffPort
	):
		var bridged := _install_fail_closed_handoff(
			fallback_capability,
			snapshot,
			install_cause
			if not install_cause.is_empty()
			else FALLBACK
		)
		presentation_ready = bridged.ok
		if not bridged.ok:
			installed = bridged
	elif not presentation_ready and sealed.ok:
		# Test doubles and application-local ports may already own the sealed
		# clone without an InstalledResultsPresentationCapability boundary.
		presentation_ready = true
		installed = sealed

	if not presentation_ready:
		_save_repository._revoke_terminal_postcommit_fallback_capability(
			fallback_capability
		)
		_release_ownership()
		return (
			installed
			if installed != null
			else _committed_failure(FALLBACK)
		)
	if install_cause.is_empty() or not (
		_handoff_port is ApplicationTerminalHandoffPort
	):
		_save_repository._revoke_terminal_postcommit_fallback_capability(
			fallback_capability
		)

	# Presentation intentionally starts after release. It receives only the
	# previously captured clone; any competing public repository operation can
	# no longer alter the receipt/profile pair being rendered.
	_release_ownership()
	return _handoff_port.present_installed_handoff()


func _seal_application_results(
	snapshot: ResultsPresentationSnapshot,
	cause: StringName
) -> AppActionResult:
	if snapshot == null:
		return _committed_failure(FALLBACK)
	if _application_results_seal.is_valid():
		return _call_application_results_seal(snapshot, cause)
	if _handoff_port == null:
		return _committed_failure(FALLBACK)
	if _handoff_port is ApplicationTerminalHandoffPort:
		var callback_value: Variant = _handoff_port.get(
			"_fail_closed_commit_callback"
		)
		if typeof(callback_value) == TYPE_CALLABLE:
			var callback: Callable = callback_value
			if not callback.is_valid():
				return _committed_failure(FALLBACK)
			return _call_application_results_seal(
				snapshot,
				cause,
				callback
			)
		return _committed_failure(FALLBACK)
	if _handoff_port.has_method(
		"_install_fail_closed_application_handoff"
	):
		var sealed_value: Variant = _handoff_port.call(
			"_install_fail_closed_application_handoff",
			null,
			snapshot.deep_clone(),
			cause
		)
		if sealed_value is AppActionResult:
			return sealed_value as AppActionResult
	return _committed_failure(FALLBACK)


func _call_application_results_seal(
	snapshot: ResultsPresentationSnapshot,
	cause: StringName,
	callback: Callable = Callable()
) -> AppActionResult:
	var target := (
		callback
		if callback.is_valid()
		else _application_results_seal
	)
	var sealed_value: Variant = target.call(snapshot.deep_clone(), cause)
	return (
		sealed_value as AppActionResult
		if sealed_value is AppActionResult
		else _committed_failure(FALLBACK)
	)


func _install_fail_closed_handoff(
	capability: TerminalPostcommitFallbackCapability,
	snapshot: ResultsPresentationSnapshot,
	cause: StringName
) -> AppActionResult:
	if (
		_handoff_port == null
		or capability == null
		or not _save_repository
			._consume_terminal_postcommit_fallback_capability(
				capability,
				snapshot
			)
		or not _handoff_port.has_method(
			"_install_fail_closed_application_handoff"
		)
	):
		return AppActionResult.committed_presentation_failure(
			DiagnosticError.new(FALLBACK, &"error.presentation.results_fallback")
		)
	var installed: Variant = _handoff_port.call(
		"_install_fail_closed_application_handoff",
		capability,
		snapshot.deep_clone(),
		cause
	)
	return (
		installed as AppActionResult
		if installed is AppActionResult
		else AppActionResult.committed_presentation_failure(
			DiagnosticError.new(FALLBACK, &"error.presentation.results_fallback")
		)
	)


func _receipt_id_for_run(
	profile: ProfileState,
	run_id: StringName
) -> StringName:
	var receipt := _receipt_for_run(profile, run_id)
	return (
		StringName(receipt.key.digest)
		if receipt != null and receipt.key != null
		else &""
	)


func _receipt_for_run(
	profile: ProfileState,
	run_id: StringName
) -> SettlementReceiptState:
	if profile == null:
		return null
	var expected := RuntimeKeySchemaRegistry.new().build_settlement_receipt(run_id)
	if not expected.ok:
		return null
	for receipt: SettlementReceiptState in profile.settlement_receipts:
		if receipt.key != null and receipt.key.digest == expected.key_state.digest:
			return receipt.deep_clone()
	return null


func _release_ownership() -> void:
	_save_repository._release_writer_ownership()
	_terminal_guard = false


func _failure(code: StringName) -> AppActionResult:
	return AppActionResult.failure(
		DiagnosticError.new(code, &"error.presentation.terminal_settlement")
	)


func _committed_failure(code: StringName) -> AppActionResult:
	return AppActionResult.committed_presentation_failure(
		DiagnosticError.new(code, &"error.presentation.results_fallback")
	)
