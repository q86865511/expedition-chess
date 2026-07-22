class_name EconomyCatalogBuildResult
extends RefCounted

var ok: bool
var catalog: EconomyExpeditionCatalog
var error: EconomyCatalogError

static func success(p_catalog: EconomyExpeditionCatalog) -> EconomyCatalogBuildResult:
	return EconomyCatalogBuildResult.new(true, p_catalog, null)

static func failure(code: StringName, path: StringName, source_id: StringName = &"") -> EconomyCatalogBuildResult:
	return EconomyCatalogBuildResult.new(false, null, EconomyCatalogError.new(code, path, source_id))

func _init(p_ok: bool, p_catalog: EconomyExpeditionCatalog, p_error: EconomyCatalogError) -> void:
	ResultInvariant.require(p_ok, p_error, p_catalog != null, p_catalog == null)
	ok = p_ok
	catalog = p_catalog.deep_clone() if p_catalog != null else null
	error = p_error.deep_clone() if p_error != null else null
