class_name AudioCoordinator
extends Node

const AUDIO_BUS_APPLY_FAILED: StringName = &"AUDIO_BUS_APPLY_FAILED"

var _port: AudioBusPort
var _current: SettingsSnapshot = SettingsSnapshot.new()


func _init(p_port: AudioBusPort = null) -> void:
	_port = p_port if p_port != null else GodotAudioBusPort.new()


func apply_committed(snapshot: SettingsSnapshot) -> AudioApplicationResult:
	if snapshot == null:
		return _failure(
			AUDIO_BUS_APPLY_FAILED,
			&"error.audio.committed_snapshot_missing"
		)
	var candidate := snapshot.deep_clone()
	var typed_assignments: Array[AudioBusAssignment] = [
		_typed_assignment(
			AudioBusKind.name_for(AudioBusKind.Kind.MASTER),
			candidate.master_volume_bps,
			candidate.master_muted
		),
		_typed_assignment(
			AudioBusKind.name_for(AudioBusKind.Kind.MUSIC),
			candidate.music_volume_bps,
			candidate.music_muted
		),
		_typed_assignment(
			AudioBusKind.name_for(AudioBusKind.Kind.SFX),
			candidate.sfx_volume_bps,
			candidate.sfx_muted
		),
		_typed_assignment(
			AudioBusKind.name_for(AudioBusKind.Kind.UI),
			candidate.ui_volume_bps,
			candidate.ui_muted
		),
	]
	var apply_result: AudioBusBatchResult = _port.apply_batch(
		AudioBusBatch.new(typed_assignments)
	)
	if not _result_ok(apply_result):
		var code := _result_code(apply_result)
		if code.is_empty():
			code = AUDIO_BUS_APPLY_FAILED
		return _failure(code, _message_key_for(code))
	_current = candidate.deep_clone()
	return AudioApplicationResult.success(_current)


func current_snapshot() -> SettingsSnapshot:
	return _current.deep_clone()


# Legacy foundation compatibility. New presentation code applies committed
# SettingsSnapshot values through apply_committed().
func set_muted(value: bool) -> void:
	var candidate := _current.deep_clone()
	candidate.master_muted = value
	apply_committed(candidate)


func is_muted() -> bool:
	return _current.master_muted


func _typed_assignment(
	bus: StringName,
	volume_bps: int,
	muted: bool
) -> AudioBusAssignment:
	var linear_volume := float(volume_bps) / 10000.0
	return AudioBusAssignment.new(
		bus,
		volume_bps,
		linear_to_db(linear_volume),
		muted or volume_bps == 0
	)


func _result_ok(value: Variant) -> bool:
	if typeof(value) == TYPE_DICTIONARY:
		return bool((value as Dictionary).get("ok", false))
	if value is Object:
		return bool((value as Object).get("ok"))
	return false


func _result_code(value: Variant) -> StringName:
	if typeof(value) == TYPE_DICTIONARY:
		return StringName((value as Dictionary).get("error_code", &""))
	if value is Object:
		return StringName((value as Object).get("error_code"))
	return &""


func _message_key_for(code: StringName) -> StringName:
	match code:
		AudioBusPort.AUDIO_BUS_MISSING:
			return &"error.audio.bus_missing"
		AudioBusPort.AUDIO_BUS_APPLY_PRECOMMIT_FAULT:
			return &"error.audio.apply_precommit_fault"
		AudioBusPort.AUDIO_BUS_BATCH_INVALID:
			return &"error.audio.batch_invalid"
		AudioBusPort.AUDIO_BUS_VALUE_INVALID:
			return &"error.audio.value_invalid"
		_:
			return &"error.audio.apply_failed"


func _failure(
	code: StringName,
	message_key: StringName
) -> AudioApplicationResult:
	return AudioApplicationResult.failure(
		DiagnosticError.new(code, message_key)
	)
