class_name LegacyContentGenerationResult
extends RefCounted

var ok: bool
var snapshot: ContentCatalogSnapshot
var error: LegacyContentGenerationError

static func success(value: ContentCatalogSnapshot) -> LegacyContentGenerationResult:
	return LegacyContentGenerationResult.new(true, value, null)

static func failure(
	code: StringName,
	field_path: StringName = &""
) -> LegacyContentGenerationResult:
	return LegacyContentGenerationResult.new(
		false, null, LegacyContentGenerationError.new(code, field_path)
	)

func _init(
	p_ok: bool,
	p_snapshot: ContentCatalogSnapshot,
	p_error: LegacyContentGenerationError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_snapshot != null, p_snapshot == null)
	ok = p_ok
	snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	error = p_error.deep_clone() if p_error != null else null
