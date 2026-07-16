class_name RunSaveRootFactory
extends RefCounted

var _app_version: String
var _clock: RunCommitClock

func _init(p_app_version: String = "0.2.0", p_clock: RunCommitClock = null) -> void:
	_app_version = p_app_version
	_clock = p_clock if p_clock != null else RunCommitClock.new()

func build(profile: ProfileState, run: RunState) -> SaveRoot:
	return SaveRoot.new(
		SaveSchemaContract.CURRENT,
		run.content_snapshot.content_version_value(),
		_app_version,
		1,
		1,
		_clock.now_utc(),
		profile,
		run
	)
