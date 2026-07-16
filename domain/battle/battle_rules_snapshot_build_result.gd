class_name BattleRulesSnapshotBuildResult
extends RefCounted

var ok: bool
var snapshot: BattleRulesSnapshot
var error: BattleRulesSnapshotBuildError

static func success(value: BattleRulesSnapshot) -> BattleRulesSnapshotBuildResult:
	return BattleRulesSnapshotBuildResult.new(true, value, null)

static func failure(
	code: StringName,
	path: StringName = &"",
	source: StringName = &""
) -> BattleRulesSnapshotBuildResult:
	return BattleRulesSnapshotBuildResult.new(
		false, null, BattleRulesSnapshotBuildError.new(code, path, source)
	)

func _init(
	p_ok: bool,
	p_snapshot: BattleRulesSnapshot,
	p_error: BattleRulesSnapshotBuildError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_snapshot != null, p_snapshot == null)
	ok = p_ok
	snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	error = p_error.deep_clone() if p_error != null else null
