class_name BattleRuleCatalogBuildResult
extends RefCounted

var ok: bool
var catalog: BattleRuleCatalog
var error: BattleRuleCatalogError

static func success(value: BattleRuleCatalog) -> BattleRuleCatalogBuildResult:
	return BattleRuleCatalogBuildResult.new(true, value, null)

static func failure(
	code: StringName,
	field_path: StringName = &"",
	source_id: StringName = &""
) -> BattleRuleCatalogBuildResult:
	return BattleRuleCatalogBuildResult.new(
		false,
		null,
		BattleRuleCatalogError.new(code, field_path, source_id)
	)

func _init(
	p_ok: bool,
	p_catalog: BattleRuleCatalog,
	p_error: BattleRuleCatalogError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_catalog != null, p_catalog == null)
	ok = p_ok
	catalog = p_catalog.deep_clone() if p_catalog != null else null
	error = p_error.deep_clone() if p_error != null else null
