class_name BattleTranscriptBuffer
extends RefCounted

const MAX_PUBLIC_WINDOW: int = 4096
const MAX_BYTE_BUDGET: int = 64 * 1024 * 1024
const PLAYBACK_WINDOW_COUNT_INVALID: StringName = &"PLAYBACK_WINDOW_COUNT_INVALID"
const PLAYBACK_IDENTITY_MISMATCH: StringName = &"PLAYBACK_IDENTITY_MISMATCH"
const PLAYBACK_CURSOR_INVALID: StringName = &"PLAYBACK_CURSOR_INVALID"

var _identity: BattleTranscriptIdentity
var _events: Array = []
var _event_budget: int
var _encoded_byte_count: int


func _init(
	p_identity: BattleTranscriptIdentity = null,
	p_transferred_events: Array = [],
	p_event_budget: int = 0,
	p_encoded_byte_count: int = 0
) -> void:
	_identity = p_identity.deep_clone() if p_identity != null else null
	# Ownership is transferred from the revoked precommit accumulator. Do not
	# clone here: after this assignment the session-private buffer is the sole
	# holder of the raw event storage.
	_events = p_transferred_events
	_event_budget = maxi(p_event_budget, 0)
	_encoded_byte_count = maxi(p_encoded_byte_count, 0)


func event_count() -> int:
	return _events.size()


func encoded_byte_count() -> int:
	return _encoded_byte_count


func byte_budget() -> int:
	return mini(_event_budget * 1024, MAX_BYTE_BUDGET)


func is_within_budget() -> bool:
	return (
		_identity != null
		and _events.size() <= _event_budget
		and _encoded_byte_count <= byte_budget()
	)


func drain_window(
	expected_identity: BattleTranscriptIdentity,
	max_count: int,
	cursor: int = 0
) -> BattleEventWindowResult:
	if max_count < 1 or max_count > MAX_PUBLIC_WINDOW:
		return _failure(
			PLAYBACK_WINDOW_COUNT_INVALID,
			&"error.presentation.playback_window_count_invalid"
		)
	if not _same_identity(expected_identity, _identity):
		return _failure(
			PLAYBACK_IDENTITY_MISMATCH,
			&"error.presentation.playback_identity_mismatch"
		)
	if cursor < 0 or cursor > _events.size():
		return _failure(
			PLAYBACK_CURSOR_INVALID,
			&"error.presentation.playback_cursor_invalid"
		)
	var end := mini(cursor + max_count, _events.size())
	var window := BattleEventWindow.new()
	window.identity = _identity.deep_clone()
	for index: int in range(cursor, end):
		var event := _events[index] as BattleEvent
		window.events.append(event.deep_clone())
	window.exhausted = end >= _events.size()
	return BattleEventWindowResult.new(true, window, null)


## Session-private：從 cursor 起、canonical tick <= max_tick 的連續事件數，仍受 4096
## backpressure 上限約束。只用來換算「這一 frame 可呈現到哪裡」，不取出、不重排事件。
func _events_through_tick(cursor: int, max_tick: int) -> int:
	if cursor < 0 or cursor >= _events.size():
		return 0
	var count := 0
	while cursor + count < _events.size() and count < MAX_PUBLIC_WINDOW:
		var event := _events[cursor + count] as BattleEvent
		if event == null or event.tick > max_tick:
			break
		count += 1
	return count


func revoke() -> void:
	_events.clear()
	_identity = null
	_event_budget = 0
	_encoded_byte_count = 0


func _same_identity(
	left: BattleTranscriptIdentity,
	right: BattleTranscriptIdentity
) -> bool:
	return (
		left != null
		and right != null
		and left.run_id == right.run_id
		and left.battle_setup_hash == right.battle_setup_hash
		and left.committed_result_digest == right.committed_result_digest
		and left.resolution_identity == right.resolution_identity
	)


func _failure(
	code: StringName,
	message_key: StringName
) -> BattleEventWindowResult:
	return BattleEventWindowResult.failure(DiagnosticError.new(code, message_key))
