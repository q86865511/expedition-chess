class_name PinnedCatalogReceiptError
extends RefCounted

const PACK_MISSING: StringName = &"PINNED_CATALOG_PACK_MISSING"
const SELECTION_INVALID: StringName = &"PINNED_CATALOG_SELECTION_INVALID"
const REFERENCE_MISSING: StringName = &"PINNED_CATALOG_REFERENCE_MISSING"
const MANIFEST_MISMATCH: StringName = &"PINNED_CATALOG_MANIFEST_MISMATCH"
const COMPILE_FAILED: StringName = &"PINNED_CATALOG_COMPILE_FAILED"

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
	for value: DiagnosticValue in p_diagnostic_values:
		diagnostic_values.append(value.deep_clone())

func deep_clone() -> PinnedCatalogReceiptError:
	return PinnedCatalogReceiptError.new(code, field_path, source_id, diagnostic_values)
