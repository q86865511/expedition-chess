class_name BattlePlaybackController
extends RefCounted

const VALID_SPEEDS: Array[int] = [1, 2, 4]
const PLAYBACK_SPEED_INVALID: StringName = &"PLAYBACK_SPEED_INVALID"
const PLAYBACK_ADVANCE_INVALID: StringName = &"PLAYBACK_ADVANCE_INVALID"

var _cursor: int = 0
var _speed: int = 1
var _paused: bool = false
var _event_count: int = 0
var _identity: BattleTranscriptIdentity


func _init(
	p_identity: BattleTranscriptIdentity = null,
	p_event_count: int = 0
) -> void:
	_identity = p_identity.deep_clone() if p_identity != null else null
	_event_count = maxi(p_event_count, 0)


func snapshot() -> BattlePlaybackState:
	var state := BattlePlaybackState.new()
	state.cursor = _cursor
	state.speed = StringName("x%d" % _speed)
	state.paused = _paused
	state.transcript_identity = (
		_identity.deep_clone() if _identity != null else null
	)
	return state


func set_speed(value: int) -> BattlePlaybackCommandResult:
	if not VALID_SPEEDS.has(value):
		return BattlePlaybackCommandResult.failure(_error(
			PLAYBACK_SPEED_INVALID,
			&"error.presentation.playback_speed_invalid"
		))
	_speed = value
	return BattlePlaybackCommandResult.success()


func set_paused(value: bool) -> BattlePlaybackCommandResult:
	_paused = value
	return BattlePlaybackCommandResult.success()


func advance(frame_units: int) -> BattlePlaybackCommandResult:
	if frame_units <= 0:
		return BattlePlaybackCommandResult.failure(_error(
			PLAYBACK_ADVANCE_INVALID,
			&"error.presentation.playback_advance_invalid"
		))
	if not _paused:
		_cursor = mini(_event_count, _cursor + frame_units * _speed)
	return BattlePlaybackCommandResult.success()


## Session-private cursor update after a backpressured buffer window is drained.
## This consumes no gameplay state and deliberately ignores presentation speed.
func _consume_events(count: int) -> void:
	if count > 0:
		_cursor = mini(_event_count, _cursor + count)


func _error(code: StringName, message_key: StringName) -> DiagnosticError:
	return DiagnosticError.new(code, message_key)
