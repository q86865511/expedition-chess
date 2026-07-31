class_name ContentTooltipFormatResult
extends RefCounted

var ok: bool
var snapshot: ContentTooltipSnapshot
var error_code: StringName

static func success(
	value: ContentTooltipSnapshot
) -> ContentTooltipFormatResult:
	return ContentTooltipFormatResult.new(true, value, &"")

static func failure(code: StringName) -> ContentTooltipFormatResult:
	return ContentTooltipFormatResult.new(false, null, code)

func _init(
	p_ok: bool,
	p_snapshot: ContentTooltipSnapshot,
	p_error_code: StringName
) -> void:
	ok = p_ok
	snapshot = p_snapshot.deep_clone() if p_ok and p_snapshot != null else null
	error_code = &"" if p_ok else p_error_code
