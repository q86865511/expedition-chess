class_name SettingsApplicationCoordinator
extends SettingsApplicationPort

const APPLY_IN_PROGRESS: StringName = &"SETTINGS_APPLY_IN_PROGRESS"
const INVALID_ENUM: StringName = &"SETTINGS_INVALID_ENUM"
const INVALID_FIELD_TYPE: StringName = &"SETTINGS_INVALID_FIELD_TYPE"
const FIELD_OUT_OF_RANGE: StringName = &"SETTINGS_FIELD_OUT_OF_RANGE"
const PREFLIGHT_FAILED: StringName = &"SETTINGS_ADAPTER_PREFLIGHT_FAILED"
const PLAN_MUTATED: StringName = &"SETTINGS_ADAPTER_PLAN_MUTATED"
const TOKEN_INVALID: StringName = &"SETTINGS_ACTIVATION_TOKEN_INVALID"
const TOKEN_DIGEST_MISMATCH: StringName = &"SETTINGS_ACTIVATION_DIGEST_MISMATCH"
const STORAGE_FAULT: StringName = &"SETTINGS_STORAGE_FAULT"
const ACTIVATION_DIAGNOSTIC: StringName = &"SETTINGS_ADAPTER_ACTIVATION_DIAGNOSTIC"
const REBUILD_FAILED: StringName = &"SETTINGS_REBUILD_FAILED"

const VALID_LOCALES: Array[StringName] = [&"zh_TW", &"en"]
const VALID_UI_SCALES: Array[int] = [100, 125, 150]
const VALID_COLOR_VISION_MODES: Array[StringName] = [
	&"default",
	&"protanopia",
	&"deuteranopia",
	&"tritanopia",
]
const VALID_DAMAGE_DENSITIES: Array[StringName] = [
	&"off",
	&"reduced",
	&"full",
]

static var _apply_in_progress: bool = false

var _repository: Object
var _adapters: Array[Object] = []


func _init(
	p_repository: Object,
	p_theme_adapter: Object,
	p_viewport_adapter: Object,
	p_localization_adapter: Object,
	p_audio_adapter: Object
) -> void:
	_repository = p_repository
	_adapters.assign([
		p_theme_adapter,
		p_viewport_adapter,
		p_localization_adapter,
		p_audio_adapter,
	])


func apply(candidate: SettingsSnapshot) -> SettingsApplicationResult:
	if _apply_in_progress:
		return _failure(APPLY_IN_PROGRESS)
	_apply_in_progress = true
	var result := _apply_owned(candidate)
	_apply_in_progress = false
	return result


func rebuild_from_repository() -> SettingsApplicationResult:
	if _apply_in_progress:
		return _failure(APPLY_IN_PROGRESS)
	_apply_in_progress = true
	var result := _rebuild_owned()
	_apply_in_progress = false
	return result


func _apply_owned(candidate: SettingsSnapshot) -> SettingsApplicationResult:
	if candidate == null:
		return _failure(INVALID_FIELD_TYPE)
	if not _dependencies_are_valid():
		return _failure(INVALID_FIELD_TYPE)

	var normalized := candidate.deep_clone()
	var validation_code := _validate(normalized)
	if not validation_code.is_empty():
		return _failure(validation_code)
	var candidate_digest := _digest(normalized)
	if candidate_digest.is_empty():
		return _failure(INVALID_FIELD_TYPE)

	var tokens: Array[Object] = []
	for adapter: Object in _adapters:
		var private_plan := normalized.deep_clone()
		var preflight: Variant = adapter.call(
			"preflight",
			private_plan,
			candidate_digest
		)
		if not _result_ok(preflight):
			return _failure(_result_error_code(preflight, PREFLIGHT_FAILED))
		if _digest(private_plan) != candidate_digest:
			return _failure(PLAN_MUTATED)
		var token: Variant = _result_field(preflight, &"token")
		if not token is Object or not token.has_method("activate"):
			return _failure(TOKEN_INVALID)
		if String(token.get("candidate_digest")) != candidate_digest:
			return _failure(TOKEN_DIGEST_MISMATCH)
		tokens.append(token)

	var save_result: Variant = _repository.call("save", normalized.deep_clone())
	if not _result_ok(save_result):
		return _failure(_result_error_code(save_result, STORAGE_FAULT))
	var committed := _result_field(save_result, &"snapshot") as SettingsSnapshot
	if committed == null:
		return _recover_postcommit(normalized, STORAGE_FAULT)

	for token: Object in tokens:
		var activation_result: Variant = token.call("activate")
		var activation_code := _activation_code(activation_result)
		if not activation_code.is_empty():
			return _recover_postcommit(committed, activation_code)
	return SettingsApplicationResult.success(committed)


func _rebuild_owned() -> SettingsApplicationResult:
	if not _dependencies_are_valid():
		return _failure(INVALID_FIELD_TYPE)
	var committed := _repository.call("current_snapshot") as SettingsSnapshot
	if committed == null:
		return _failure(REBUILD_FAILED)
	var validation_code := _validate(committed)
	if not validation_code.is_empty():
		return _failure(validation_code)
	for adapter: Object in _adapters:
		adapter.call("rebuild_from_committed", committed.deep_clone())
	return SettingsApplicationResult.success(committed)


func _recover_postcommit(
	committed: SettingsSnapshot,
	activation_code: StringName
) -> SettingsApplicationResult:
	for adapter: Object in _adapters:
		adapter.call("activate_safe_fallback")
	var fresh := _repository.call("current_snapshot") as SettingsSnapshot
	if fresh != null:
		for adapter: Object in _adapters:
			adapter.call("rebuild_from_committed", fresh.deep_clone())
	var exposed := fresh if fresh != null else committed
	var code := (
		activation_code
		if not activation_code.is_empty()
		else ACTIVATION_DIAGNOSTIC
	)
	return SettingsApplicationResult.committed_presentation_failure(
		exposed,
		DiagnosticError.new(code, &"error.settings.activation_diagnostic")
	)


func _dependencies_are_valid() -> bool:
	if (
		_repository == null
		or not _repository.has_method("save")
		or not _repository.has_method("current_snapshot")
		or _adapters.size() != 4
	):
		return false
	for adapter: Object in _adapters:
		if (
			adapter == null
			or not adapter.has_method("preflight")
			or not adapter.has_method("activate_safe_fallback")
			or not adapter.has_method("rebuild_from_committed")
		):
			return false
	return true


func _validate(snapshot: SettingsSnapshot) -> StringName:
	if snapshot.schema_version != 1:
		return INVALID_FIELD_TYPE
	if snapshot.locale not in VALID_LOCALES:
		return INVALID_ENUM
	if snapshot.ui_scale_percent not in VALID_UI_SCALES:
		return FIELD_OUT_OF_RANGE
	if snapshot.color_vision_mode not in VALID_COLOR_VISION_MODES:
		return INVALID_ENUM
	if snapshot.damage_number_density not in VALID_DAMAGE_DENSITIES:
		return INVALID_ENUM
	var volumes: Array[int] = [
		snapshot.master_volume_bps,
		snapshot.music_volume_bps,
		snapshot.sfx_volume_bps,
		snapshot.ui_volume_bps,
	]
	for volume: int in volumes:
		if volume < 0 or volume > 10000:
			return FIELD_OUT_OF_RANGE
	return &""


func _digest(snapshot: SettingsSnapshot) -> String:
	var canonical := {
		"schema_version": snapshot.schema_version,
		"locale": String(snapshot.locale),
		"ui_scale_percent": snapshot.ui_scale_percent,
		"color_vision_mode": String(snapshot.color_vision_mode),
		"reduced_motion": snapshot.reduced_motion,
		"reduced_flash": snapshot.reduced_flash,
		"reduced_particles": snapshot.reduced_particles,
		"damage_number_density": String(snapshot.damage_number_density),
		"master_volume_bps": snapshot.master_volume_bps,
		"master_muted": snapshot.master_muted,
		"music_volume_bps": snapshot.music_volume_bps,
		"music_muted": snapshot.music_muted,
		"sfx_volume_bps": snapshot.sfx_volume_bps,
		"sfx_muted": snapshot.sfx_muted,
		"ui_volume_bps": snapshot.ui_volume_bps,
		"ui_muted": snapshot.ui_muted,
	}
	return JSON.stringify(canonical).sha256_text()


func _result_ok(value: Variant) -> bool:
	return bool(_result_field(value, &"ok"))


func _result_field(value: Variant, key: StringName) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).get(key)
	if value is Object:
		return (value as Object).get(key)
	return null


func _result_error_code(
	value: Variant,
	fallback: StringName
) -> StringName:
	var error: Variant = _result_field(value, &"error")
	if error != null:
		var source_code: Variant = _result_field(error, &"source_code")
		if source_code != null and not StringName(source_code).is_empty():
			return StringName(source_code)
		var code: Variant = _result_field(error, &"code")
		if code != null and not StringName(code).is_empty():
			return StringName(code)
	var direct: Variant = _result_field(value, &"error_code")
	if direct != null and not StringName(direct).is_empty():
		return StringName(direct)
	return fallback


func _activation_code(value: Variant) -> StringName:
	if value == null:
		return &""
	if typeof(value) in [TYPE_STRING, TYPE_STRING_NAME]:
		return StringName(value)
	if _result_ok(value):
		return &""
	return _result_error_code(value, ACTIVATION_DIAGNOSTIC)


func _failure(code: StringName) -> SettingsApplicationResult:
	return SettingsApplicationResult.failure(
		DiagnosticError.new(code, _message_key_for(code))
	)


func _message_key_for(code: StringName) -> StringName:
	match code:
		APPLY_IN_PROGRESS:
			return &"error.settings.apply_in_progress"
		INVALID_ENUM:
			return &"error.settings.invalid_enum"
		INVALID_FIELD_TYPE:
			return &"error.settings.invalid_field_type"
		FIELD_OUT_OF_RANGE:
			return &"error.settings.field_out_of_range"
		PLAN_MUTATED:
			return &"error.settings.adapter_plan_mutated"
		TOKEN_INVALID, TOKEN_DIGEST_MISMATCH:
			return &"error.settings.activation_token_invalid"
		STORAGE_FAULT:
			return &"error.settings.storage_fault"
		REBUILD_FAILED:
			return &"error.settings.rebuild_failed"
		_:
			return &"error.settings.application_failed"
