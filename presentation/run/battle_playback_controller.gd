class_name BattlePlaybackController
extends RefCounted

const VALID_SPEEDS: Array[int] = [1, 2, 4]
const PLAYBACK_SPEED_INVALID: StringName = &"PLAYBACK_SPEED_INVALID"
const PLAYBACK_ADVANCE_INVALID: StringName = &"PLAYBACK_ADVANCE_INVALID"
## presentation-only pacing：1× 以 canonical tick 速率重播（battle_setup_inputs_validator
## 硬性要求 tick_rate == 20，即每 tick 50ms）。倍率只改這個 presentation 時鐘，
## 不進 gameplay RNG、simulation tick、result 或 hash。
const CANONICAL_TICK_RATE: int = 20
const TICK_INTERVAL_MS: float = 1000.0 / float(CANONICAL_TICK_RATE)

var _cursor: int = 0
var _speed: int = 1
var _paused: bool = false
var _event_count: int = 0
var _presentation_accumulator_ms: float = 0.0
var _presentation_tick: int = 0
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


func is_paused() -> bool:
	return _paused


func has_reached_end() -> bool:
	return _cursor >= _event_count


## Session-private frame pacing. Advances the presentation clock and returns the
## highest canonical tick that may be presented now. Paused playback never calls
## this, so the clock and the cursor cannot drift while paused.
func _advance_presentation_tick(delta_ms: float) -> int:
	if delta_ms > 0.0:
		_presentation_accumulator_ms += delta_ms * float(_speed)
		var unlocked := int(_presentation_accumulator_ms / TICK_INTERVAL_MS)
		if unlocked > 0:
			_presentation_accumulator_ms -= float(unlocked) * TICK_INTERVAL_MS
			_presentation_tick += unlocked
	return _presentation_tick


## Session-private cursor update after a backpressured buffer window is drained.
## This consumes no gameplay state and deliberately ignores presentation speed.
func _consume_events(count: int) -> void:
	if count > 0:
		_cursor = mini(_event_count, _cursor + count)


func _error(code: StringName, message_key: StringName) -> DiagnosticError:
	return DiagnosticError.new(code, message_key)
