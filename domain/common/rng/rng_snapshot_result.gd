class_name RngSnapshotResult
extends RefCounted

var ok: bool = false
var snapshot: RngSnapshot = null
var error: RngSnapshotError = null

static func success(value: RngSnapshot) -> RngSnapshotResult:
	return RngSnapshotResult.new(true, value, null)

static func failure(code: StringName, path: StringName = &"") -> RngSnapshotResult:
	return RngSnapshotResult.new(false, null, RngSnapshotError.create(code, path))

func _init(
	p_ok: bool,
	p_snapshot: RngSnapshot,
	p_error: RngSnapshotError
) -> void:
	ResultInvariant.require(
		p_ok, p_error, p_snapshot != null, p_snapshot == null
	)
	ok = p_ok
	snapshot = p_snapshot
	error = p_error
