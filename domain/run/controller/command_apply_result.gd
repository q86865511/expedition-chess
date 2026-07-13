class_name CommandApplyResult
extends RefCounted

var ok: bool
var draft: RunState
var operation_receipts: Array[TransactionReceiptState] = []
var error: CommandApplyError

static func success(
	p_draft: RunState,
	p_operation_receipts: Array[TransactionReceiptState] = []
) -> CommandApplyResult:
	return CommandApplyResult.new(true, p_draft, p_operation_receipts, null)

static func failure(p_error: CommandApplyError) -> CommandApplyResult:
	var no_receipts: Array[TransactionReceiptState] = []
	return CommandApplyResult.new(false, null, no_receipts, p_error)

func _init(
	p_ok: bool,
	p_draft: RunState,
	p_operation_receipts: Array[TransactionReceiptState],
	p_error: CommandApplyError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_draft != null,
		p_draft == null and p_operation_receipts.is_empty()
	)
	ok = p_ok
	draft = p_draft.deep_clone() if p_draft != null else null
	for receipt: TransactionReceiptState in p_operation_receipts:
		operation_receipts.append(receipt.deep_clone())
	error = p_error.deep_clone() if p_error != null else null
