class_name LiveScreenPlaybackPort
extends RefCounted

const SCREEN_NOT_ACTIVE: StringName = &"SCREEN_NOT_ACTIVE"

var _lease: LiveScreenLease
var _registry: LiveScreenLeaseRegistry
var _session: RunPresentationSession


func _init(
	p_lease: LiveScreenLease = null,
	p_registry: LiveScreenLeaseRegistry = null,
	p_session: RunPresentationSession = null
) -> void:
	_lease = p_lease.deep_clone() if p_lease != null else null
	_registry = p_registry
	_session = p_session


func try_playback() -> BattlePlaybackStateResult:
	if not _is_active():
		return BattlePlaybackStateResult.failure(_screen_not_active_error())
	return _session.try_playback()


func set_speed(multiplier: int) -> BattlePlaybackCommandResult:
	if not _is_active():
		return BattlePlaybackCommandResult.failure(_screen_not_active_error())
	return _session.set_playback_speed(multiplier)


func set_paused(paused: bool) -> BattlePlaybackCommandResult:
	if not _is_active():
		return BattlePlaybackCommandResult.failure(_screen_not_active_error())
	return _session.set_playback_paused(paused)


func drain_window(
	expected_identity: BattleTranscriptIdentity,
	max_count: int
) -> BattleEventWindowResult:
	if not _is_active():
		return BattleEventWindowResult.failure(_screen_not_active_error())
	return _session.drain_playback_window(expected_identity, max_count)


func advance_playback(delta_ms: float) -> BattleEventWindowResult:
	if not _is_active():
		return BattleEventWindowResult.failure(_screen_not_active_error())
	return _session.advance_playback(delta_ms)


func _is_active() -> bool:
	return (
		_session != null
		and _registry != null
		and _registry.is_active(_lease)
	)


func _screen_not_active_error() -> DiagnosticError:
	return DiagnosticError.new(
		SCREEN_NOT_ACTIVE,
		&"error.presentation.screen_not_active"
	)
