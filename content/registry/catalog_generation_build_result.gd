class_name CatalogGenerationBuildResult
extends RefCounted

var ok: bool
var draft: CatalogGenerationDraft
var error: CatalogCompileError

static func success(value: CatalogGenerationDraft) -> CatalogGenerationBuildResult:
	return CatalogGenerationBuildResult.new(true, value, null)

static func failure(code: StringName, path: StringName = &"", source: StringName = &"") -> CatalogGenerationBuildResult:
	return CatalogGenerationBuildResult.new(false, null, CatalogCompileError.new(code, path, source))

func _init(p_ok: bool, p_draft: CatalogGenerationDraft, p_error: CatalogCompileError) -> void:
	ResultInvariant.require(p_ok, p_error, p_draft != null, p_draft == null)
	ok = p_ok
	draft = p_draft.deep_clone() if p_ok and p_draft != null else null
	error = p_error if not p_ok else null
