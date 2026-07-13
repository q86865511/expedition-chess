class_name IdLedgerResult
extends RefCounted

var ok: bool = false
var resolved_id: StringName = &""
var resolved_status: StringName = &""
var error: IdLedgerError = null

static func success(id: StringName = &"", status: StringName = &"") -> IdLedgerResult:
	return IdLedgerResult.new(true, id, status, null)

static func failure(error_code: StringName, id: StringName, path: StringName = &"stable_id") -> IdLedgerResult:
	return IdLedgerResult.new(
		false, &"", &"", IdLedgerError.create(error_code, id, path)
	)

func _init(
	p_ok: bool,
	p_resolved_id: StringName,
	p_resolved_status: StringName,
	p_error: IdLedgerError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		true,
		p_resolved_id.is_empty() and p_resolved_status.is_empty()
	)
	ok = p_ok
	resolved_id = p_resolved_id
	resolved_status = p_resolved_status
	error = p_error
