class_name AudioSettingsAdapter
extends SettingsAdapterPort

const PREFLIGHT_FAILED: StringName = &"SETTINGS_AUDIO_PREFLIGHT_FAILED"
const ACTIVATION_FAILED: StringName = &"SETTINGS_AUDIO_ACTIVATION_FAILED"

var _audio_coordinator: AudioCoordinator


class AudioActivationToken:
	extends SettingsActivationToken

	var _audio_coordinator: AudioCoordinator
	var _snapshot: SettingsSnapshot


	func _init(
		p_candidate_digest: String,
		p_audio_coordinator: AudioCoordinator,
		p_snapshot: SettingsSnapshot
	) -> void:
		super._init(p_candidate_digest)
		_audio_coordinator = p_audio_coordinator
		_snapshot = p_snapshot.deep_clone()


	func activate() -> StringName:
		if _audio_coordinator == null:
			return AudioSettingsAdapter.ACTIVATION_FAILED
		var result: AudioApplicationResult = _audio_coordinator.apply_committed(
			_snapshot.deep_clone()
		)
		return &"" if result.ok else result.error.source_code


func _init(p_audio_coordinator: AudioCoordinator) -> void:
	_audio_coordinator = p_audio_coordinator


func preflight(
	plan: SettingsSnapshot,
	candidate_digest: String
) -> SettingsAdapterPreflightResult:
	if (
		plan == null
		or candidate_digest.is_empty()
		or _audio_coordinator == null
	):
		return SettingsAdapterPreflightResult.failure(
			DiagnosticError.new(
				PREFLIGHT_FAILED,
				&"error.settings.audio_preflight"
			)
		)
	return SettingsAdapterPreflightResult.success(
		AudioActivationToken.new(candidate_digest, _audio_coordinator, plan)
	)


func activate_safe_fallback() -> void:
	if _audio_coordinator != null:
		_audio_coordinator.apply_committed(SettingsSnapshot.new())


func rebuild_from_committed(snapshot: SettingsSnapshot) -> void:
	if _audio_coordinator != null and snapshot != null:
		_audio_coordinator.apply_committed(snapshot.deep_clone())
