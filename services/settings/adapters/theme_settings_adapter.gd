class_name ThemeSettingsAdapter
extends SettingsAdapterPort

const PREFLIGHT_FAILED: StringName = &"SETTINGS_THEME_PREFLIGHT_FAILED"
const ACTIVATION_FAILED: StringName = &"SETTINGS_THEME_ACTIVATION_FAILED"

var _consumer: Object


class ThemeActivationToken:
	extends SettingsActivationToken

	var _consumer: Object
	var _snapshot: SettingsSnapshot


	func _init(
		p_candidate_digest: String,
		p_consumer: Object,
		p_snapshot: SettingsSnapshot
	) -> void:
		super._init(p_candidate_digest)
		_consumer = p_consumer
		_snapshot = p_snapshot.deep_clone()


	func activate() -> StringName:
		if _consumer == null or not _consumer.has_method("activate"):
			return ThemeSettingsAdapter.ACTIVATION_FAILED
		return ThemeSettingsAdapter._result_error_code(
			_consumer.call("activate", &"theme", _snapshot.deep_clone()),
			ThemeSettingsAdapter.ACTIVATION_FAILED
		)


func _init(p_consumer: Object) -> void:
	_consumer = p_consumer


func preflight(
	plan: SettingsSnapshot,
	candidate_digest: String
) -> SettingsAdapterPreflightResult:
	if (
		plan == null
		or candidate_digest.is_empty()
		or _consumer == null
		or not _consumer.has_method("preflight")
	):
		return _failure(PREFLIGHT_FAILED)
	var error_code := _result_error_code(
		_consumer.call("preflight", &"theme", plan.deep_clone()),
		PREFLIGHT_FAILED
	)
	if not error_code.is_empty():
		return _failure(error_code)
	return SettingsAdapterPreflightResult.success(
		ThemeActivationToken.new(candidate_digest, _consumer, plan)
	)


func activate_safe_fallback() -> void:
	if _consumer != null and _consumer.has_method("activate_safe_fallback"):
		_consumer.call("activate_safe_fallback", &"theme")


func rebuild_from_committed(snapshot: SettingsSnapshot) -> void:
	if (
		snapshot != null
		and _consumer != null
		and _consumer.has_method("activate")
	):
		_consumer.call("activate", &"theme", snapshot.deep_clone())


static func _result_error_code(
	value: Variant,
	fallback: StringName
) -> StringName:
	if value == null:
		return &""
	if typeof(value) in [TYPE_STRING, TYPE_STRING_NAME]:
		return StringName(value)
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary := value as Dictionary
		if bool(dictionary.get("ok", false)):
			return &""
		return StringName(dictionary.get("error_code", fallback))
	if value is Object:
		var ok_value: Variant = value.get("ok")
		if ok_value != null and bool(ok_value):
			return &""
		var error_value: Variant = value.get("error")
		if error_value is Object:
			var source_code: Variant = error_value.get("source_code")
			if source_code != null:
				return StringName(source_code)
	return fallback


func _failure(code: StringName) -> SettingsAdapterPreflightResult:
	return SettingsAdapterPreflightResult.failure(
		DiagnosticError.new(code, &"error.settings.theme_preflight")
	)
