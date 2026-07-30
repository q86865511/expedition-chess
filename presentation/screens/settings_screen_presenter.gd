class_name SettingsScreenPresenter
extends RefCounted

const SETTINGS_PORT_INVALID: StringName = &"SETTINGS_PORT_INVALID"
const SETTINGS_DRAFT_INVALID: StringName = &"SETTINGS_DRAFT_INVALID"
const SETTINGS_INVALID_ENUM: StringName = &"SETTINGS_INVALID_ENUM"
const SETTINGS_FIELD_OUT_OF_RANGE: StringName = &"SETTINGS_FIELD_OUT_OF_RANGE"

const _VALID_LOCALES: Array[StringName] = [&"zh_TW", &"en"]
const _VALID_UI_SCALES: Array[int] = [100, 125, 150]
const _VALID_COLOR_VISION_MODES: Array[StringName] = [
	&"default",
	&"protanopia",
	&"deuteranopia",
	&"tritanopia",
]
const _VALID_DAMAGE_DENSITIES: Array[StringName] = [&"off", &"reduced", &"full"]

var _port: SettingsApplicationPort
var _draft: SettingsSnapshot
var _visible_error_key: StringName = &""
var _focused_control_id: StringName = &"settings.apply"


func bind(
	port: SettingsApplicationPort,
	initial_snapshot: SettingsSnapshot
) -> StringName:
	if port == null:
		return SETTINGS_PORT_INVALID
	if initial_snapshot == null:
		return SETTINGS_DRAFT_INVALID
	_port = port
	_draft = initial_snapshot.deep_clone()
	_visible_error_key = &""
	_focused_control_id = &"settings.apply"
	return &""


func edit_draft(candidate: SettingsSnapshot) -> StringName:
	var validation_error := _validate(candidate)
	if not validation_error.is_empty():
		return validation_error
	_draft = candidate.deep_clone()
	_visible_error_key = &""
	return &""


func submit() -> SettingsApplicationResult:
	if _port == null or _draft == null:
		return _component_failure(
			SETTINGS_PORT_INVALID,
			&"error.settings.port_invalid"
		)
	var result := _port.apply(_draft.deep_clone())
	if result == null:
		return _component_failure(
			SETTINGS_PORT_INVALID,
			&"error.settings.application_invalid_result"
		)
	_visible_error_key = (
		result.error.message_key
		if result.error != null
		else &""
	)
	_focused_control_id = &"settings.apply"
	return result


func visible_error_key() -> StringName:
	return _visible_error_key


func focused_control_id() -> StringName:
	return _focused_control_id


func dismiss_error() -> void:
	_visible_error_key = &""
	_focused_control_id = &"settings.apply"


func _validate(candidate: SettingsSnapshot) -> StringName:
	if candidate == null or candidate.schema_version != 1:
		return SETTINGS_DRAFT_INVALID
	if (
		candidate.locale not in _VALID_LOCALES
		or candidate.color_vision_mode not in _VALID_COLOR_VISION_MODES
		or candidate.damage_number_density not in _VALID_DAMAGE_DENSITIES
	):
		return SETTINGS_INVALID_ENUM
	if candidate.ui_scale_percent not in _VALID_UI_SCALES:
		return SETTINGS_FIELD_OUT_OF_RANGE
	for volume: int in [
		candidate.master_volume_bps,
		candidate.music_volume_bps,
		candidate.sfx_volume_bps,
		candidate.ui_volume_bps,
	]:
		if volume < 0 or volume > 10000:
			return SETTINGS_FIELD_OUT_OF_RANGE
	return &""


func _component_failure(
	source_code: StringName,
	message_key: StringName
) -> SettingsApplicationResult:
	_visible_error_key = message_key
	_focused_control_id = &"settings.apply"
	return SettingsApplicationResult.failure(
		DiagnosticError.new(source_code, message_key)
	)
