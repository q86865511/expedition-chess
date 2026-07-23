class_name ForgeRecipeTableBuildResult
extends RefCounted

var ok: bool
var table: ForgeRecipeTable
var error: ForgeRecipeTableError

static func success(p_table: ForgeRecipeTable) -> ForgeRecipeTableBuildResult:
	return ForgeRecipeTableBuildResult.new(true, p_table, null)

static func failure(code: StringName, path: StringName, source_id: StringName = &"") -> ForgeRecipeTableBuildResult:
	return ForgeRecipeTableBuildResult.new(false, null, ForgeRecipeTableError.new(code, path, source_id))

func _init(p_ok: bool, p_table: ForgeRecipeTable, p_error: ForgeRecipeTableError) -> void:
	ResultInvariant.require(p_ok, p_error, p_table != null, p_table == null)
	ok = p_ok
	table = p_table.deep_clone() if p_table != null else null
	error = p_error.deep_clone() if p_error != null else null
