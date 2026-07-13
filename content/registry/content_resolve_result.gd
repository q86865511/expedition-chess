class_name ContentResolveResult
extends RefCounted

var ok: bool
var value: ContentDefinitionView
var error: ContentResolveError

static func success(p_value: ContentDefinitionView) -> ContentResolveResult:
	return ContentResolveResult.new(true, p_value, null)

static func failure(code: StringName, field_path: StringName = &"", source_id: StringName = &"") -> ContentResolveResult:
	return ContentResolveResult.new(
		false, null, ContentResolveError.new(code, field_path, source_id)
	)

func _init(
	p_ok: bool,
	p_value: ContentDefinitionView,
	p_error: ContentResolveError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_value != null, p_value == null)
	ok = p_ok
	value = p_value.deep_clone() if p_ok and p_value != null else null
	error = p_error.deep_clone() if not p_ok and p_error != null else null
