class_name RunRelicTableBuildResult
extends RefCounted

var ok: bool
var table: RunRelicTable
var error: RunRelicTableError

static func success(p_table: RunRelicTable) -> RunRelicTableBuildResult:
	return RunRelicTableBuildResult.new(true, p_table, null)

static func failure(code: StringName, path: StringName, source_id: StringName = &"") -> RunRelicTableBuildResult:
	return RunRelicTableBuildResult.new(false, null, RunRelicTableError.new(code, path, source_id))

func _init(p_ok: bool, p_table: RunRelicTable, p_error: RunRelicTableError) -> void:
	ResultInvariant.require(p_ok, p_error, p_table != null, p_table == null)
	ok = p_ok
	table = p_table.deep_clone() if p_table != null else null
	error = p_error.deep_clone() if p_error != null else null
