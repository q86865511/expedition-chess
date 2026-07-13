class_name RunSessionBuildError
extends RefCounted

const INPUT_INVALID: StringName = &"RUN_SESSION_INPUT_INVALID"
const CATALOG_MISSING: StringName = &"RUN_SESSION_CATALOG_MISSING"
const PINNED_RECEIPT_MISSING: StringName = \
	&"RUN_SESSION_PINNED_RECEIPT_MISSING"
const SNAPSHOT_MISMATCH: StringName = \
	&"RUN_SESSION_CONTENT_SNAPSHOT_MISMATCH"
const LEASE_FAILED: StringName = &"RUN_SESSION_CATALOG_LEASE_FAILED"

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(
	p_code: StringName,
	p_field_path: StringName,
	p_source_id: OptionalStringNameValue = null,
	p_diagnostic_values: Array[DiagnosticValue] = []
) -> void:
	code = p_code
	field_path = p_field_path
	source_id = p_source_id.deep_clone() if p_source_id != null else null
	for diagnostic: DiagnosticValue in p_diagnostic_values:
		diagnostic_values.append(diagnostic.deep_clone())

func deep_clone() -> RunSessionBuildError:
	return RunSessionBuildError.new(code, field_path, source_id, diagnostic_values)
