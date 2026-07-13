class_name CatalogClosureResult
extends RefCounted

var ok: bool
var active_ids: Array[StringName] = []
var error: CatalogCompileError

static func success(values: Array[StringName]) -> CatalogClosureResult:
	return CatalogClosureResult.new(true, values, null)

static func failure(code: StringName, path: StringName = &"", source: StringName = &"") -> CatalogClosureResult:
	var empty_ids: Array[StringName] = []
	return CatalogClosureResult.new(false, empty_ids, CatalogCompileError.new(code, path, source))

func _init(p_ok: bool, p_active_ids: Array[StringName], p_error: CatalogCompileError) -> void:
	ResultInvariant.require(p_ok, p_error, true, p_active_ids.is_empty())
	ok = p_ok
	active_ids.clear()
	if p_ok: active_ids.assign(p_active_ids)
	error = p_error if not p_ok else null
