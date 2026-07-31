class_name LocalizationCatalogLoadResult
extends RefCounted

var ok: bool
var catalog: LocalizationCatalog
var error: LocalizationCatalogLoadError

static func success(value: LocalizationCatalog) -> LocalizationCatalogLoadResult:
	return LocalizationCatalogLoadResult.new(true, value, null)

static func failure(
	value: LocalizationCatalogLoadError
) -> LocalizationCatalogLoadResult:
	return LocalizationCatalogLoadResult.new(false, null, value)

func _init(
	p_ok: bool,
	p_catalog: LocalizationCatalog,
	p_error: LocalizationCatalogLoadError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_catalog != null and p_error == null,
		p_catalog == null and p_error != null
	)
	ok = p_ok
	catalog = p_catalog if p_ok else null
	error = p_error if not p_ok else null
