class_name ContentSnapshotBuildResult
extends RefCounted

var ok: bool
var snapshot: ContentSnapshotState
var error: ContentSnapshotBuildError

static func success(p_snapshot: ContentSnapshotState) -> ContentSnapshotBuildResult:
	return ContentSnapshotBuildResult.new(true, p_snapshot, null)

static func failure(p_error: ContentSnapshotBuildError) -> ContentSnapshotBuildResult:
	return ContentSnapshotBuildResult.new(false, null, p_error)

func _init(
	p_ok: bool,
	p_snapshot: ContentSnapshotState,
	p_error: ContentSnapshotBuildError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_snapshot != null and p_snapshot.is_validated(),
		p_snapshot == null
	)
	ok = p_ok
	snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	error = p_error.deep_clone() if p_error != null else null
