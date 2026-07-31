class_name NodeServiceAuthority
extends RefCounted

## design.md §5（:208-214）：node service 期間的每一個命令都要求同一份 service
## authority——resolution 必須是 NodeServicePendingResolutionState、service_kind
## 相符，且命令攜帶的 (expected_run_id, node_id, choice_receipt_digest) 與
## canonical pending 逐欄相等。三個欄位各有具名拒絕碼，呼叫端只提供前綴
## （例：DISMANTLE_NODE_SERVICE_RUN_MISMATCH／EXIT_NODE_SERVICE_NODE_MISMATCH），
## 錯在哪一欄才不會被壓成同一個泛用碼。

static func try_reject(
	draft: RunState,
	service_kind: StringName,
	expected_run_id: String,
	node_id: StringName,
	choice_receipt_digest: String,
	source_code_prefix: StringName
) -> CommandApplyError:
	var pending := (
		draft.resolution_state as NodeServicePendingResolutionState
		if draft != null
		else null
	)
	if pending == null or pending.service_kind != service_kind:
		return _error(
			&"run.resolution_state", source_code_prefix, &"RESOLUTION_INVALID"
		)
	if expected_run_id != draft.run_id:
		return _error(
			&"run.run_id", source_code_prefix, &"RUN_MISMATCH"
		)
	if node_id != pending.node_id:
		return _error(
			&"run.resolution_state.node_id", source_code_prefix, &"NODE_MISMATCH"
		)
	if choice_receipt_digest != pending.choice_receipt_digest:
		return _error(
			&"run.resolution_state.choice_receipt_digest",
			source_code_prefix,
			&"RECEIPT_MISMATCH"
		)
	return null

static func _error(
	field_path: StringName,
	source_code_prefix: StringName,
	suffix: StringName
) -> CommandApplyError:
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(
			&"source_code",
			"%s_%s" % [String(source_code_prefix), String(suffix)]
		),
	]
	return CommandApplyError.new(
		CommandApplyError.APPLY_REJECTED, field_path, null, diagnostics
	)
