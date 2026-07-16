class_name RecordBattleResultCommand
extends RunCommand

const PHASE_INVALID: StringName = &"RECORD_BATTLE_RESULT_PHASE_INVALID"
const PENDING_SETUP_MISSING: StringName = &"RECORD_BATTLE_RESULT_PENDING_SETUP_MISSING"
const SETUP_HASH_MISMATCH: StringName = &"RECORD_BATTLE_RESULT_SETUP_HASH_MISMATCH"
const ENVELOPE_INVALID: StringName = &"RECORD_BATTLE_RESULT_ENVELOPE_INVALID"
const RESULT_INVALID: StringName = &"RECORD_BATTLE_RESULT_INVALID"
const RESULT_HASH_MISMATCH: StringName = &"RECORD_BATTLE_RESULT_HASH_MISMATCH"
const RECEIPT_MISMATCH: StringName = &"RECORD_BATTLE_RESULT_RECEIPT_MISMATCH"
var _expected_setup_hash: StringName
var _expected_result_hash: StringName
var _result: BattleResult
var _validation_receipt: BattleResultValidationReceipt
var _result_codec: BattleResultCodecV1

func _init(
	p_expected_setup_hash: StringName,
	p_expected_result_hash: StringName,
	p_result: BattleResult,
	p_validation_receipt: BattleResultValidationReceipt,
	p_result_codec: BattleResultCodecV1 = null
) -> void:
	_expected_setup_hash = p_expected_setup_hash
	_expected_result_hash = p_expected_result_hash
	_result = p_result.deep_clone() if p_result != null else null
	_validation_receipt = (
		p_validation_receipt.deep_clone() if p_validation_receipt != null else null
	)
	_result_codec = p_result_codec if p_result_codec != null else BattleResultCodecV1.new()

func is_concrete() -> bool:
	return not _expected_setup_hash.is_empty() \
		and not _expected_result_hash.is_empty() \
		and _result != null \
		and _validation_receipt != null

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null:
		return _rejected(&"command", RESULT_INVALID)
	if draft.run_phase != RunState.RunPhase.COMBAT:
		return _rejected(&"run.run_phase", PHASE_INVALID)
	if draft.resolution_state == null \
		or not draft.resolution_state is CombatPendingResolutionState:
		return _rejected(&"run.resolution_state", PENDING_SETUP_MISSING)
	var pending := draft.resolution_state as CombatPendingResolutionState
	if pending.battle_setup == null:
		return _rejected(&"run.resolution_state.battle_setup", PENDING_SETUP_MISSING)
	var pending_setup_hash := pending.battle_setup.battle_setup_hash
	if pending_setup_hash != _expected_setup_hash \
		or _result.battle_setup_hash != _expected_setup_hash:
		return _rejected(&"expected_setup_hash", SETUP_HASH_MISMATCH)
	var envelope := BattleSetupEnvelopeVerifier.new().verify(
		pending.battle_setup,
		draft.run_seed
	)
	if not envelope.ok:
		return _rejected(
			StringName("run.resolution_state.battle_setup.%s" % String(envelope.error.field_path)),
			ENVELOPE_INVALID
		)
	var recomputed := _result_codec.seal(_result.to_record())
	if not recomputed.ok or recomputed.record == null:
		var field_path := recomputed.error.field_path \
			if recomputed.error != null else &"result"
		return _rejected(
			StringName("result.%s" % String(field_path)),
			RESULT_INVALID
		)
	var recomputed_result_hash := recomputed.record.result_hash
	if _expected_result_hash != _result.result_hash \
		or _expected_result_hash != recomputed_result_hash \
		or _expected_result_hash != _validation_receipt.result_hash:
		return _rejected(&"expected_result_hash", RESULT_HASH_MISMATCH)
	if _validation_receipt.battle_setup_hash != pending_setup_hash \
		or _validation_receipt.battle_setup_envelope_digest \
			!= pending.battle_setup.battle_setup_envelope_digest:
		return _rejected(&"validation_receipt", RECEIPT_MISMATCH)
	draft.resolution_state = BattleResultPendingResolutionState.new(
		String(pending_setup_hash),
		_result
	)
	return CommandApplyResult.success(draft)

func _rejected(field_path: StringName, source_code: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(source_code)),
	]
	return CommandApplyResult.failure(
		CommandApplyError.new(
			CommandApplyError.APPLY_REJECTED,
			field_path,
			null,
			diagnostics
		)
	)
