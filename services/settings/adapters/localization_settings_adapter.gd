class_name LocalizationSettingsAdapter
extends SettingsAdapterPort

const PREFLIGHT_FAILED: StringName = &"SETTINGS_LOCALIZATION_PREFLIGHT_FAILED"
const ACTIVATION_FAILED: StringName = &"SETTINGS_LOCALIZATION_ACTIVATION_FAILED"

var _consumer: Object
var _catalog: LocalizationCatalog


class LocalizationActivationToken:
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
			return LocalizationSettingsAdapter.ACTIVATION_FAILED
		return ThemeSettingsAdapter._result_error_code(
			_consumer.call("activate", &"localization", _snapshot.deep_clone()),
			LocalizationSettingsAdapter.ACTIVATION_FAILED
		)


func _init(p_consumer: Object, p_catalog: LocalizationCatalog) -> void:
	_consumer = p_consumer
	_catalog = p_catalog


func preflight(
	plan: SettingsSnapshot,
	candidate_digest: String
) -> SettingsAdapterPreflightResult:
	if (
		plan == null
		or candidate_digest.is_empty()
		or _consumer == null
		or not _consumer.has_method("preflight")
		or _catalog == null
		or plan.locale not in _catalog.supported_locales()
	):
		return _failure(PREFLIGHT_FAILED)
	var error_code := ThemeSettingsAdapter._result_error_code(
		_consumer.call("preflight", &"localization", plan.deep_clone()),
		PREFLIGHT_FAILED
	)
	if not error_code.is_empty():
		return _failure(error_code)
	return SettingsAdapterPreflightResult.success(
		LocalizationActivationToken.new(candidate_digest, _consumer, plan)
	)


func activate_safe_fallback() -> void:
	if _consumer != null and _consumer.has_method("activate_safe_fallback"):
		_consumer.call("activate_safe_fallback", &"localization")


func rebuild_from_committed(snapshot: SettingsSnapshot) -> void:
	if (
		snapshot != null
		and _consumer != null
		and _consumer.has_method("activate")
	):
		_consumer.call("activate", &"localization", snapshot.deep_clone())


func _failure(code: StringName) -> SettingsAdapterPreflightResult:
	return SettingsAdapterPreflightResult.failure(
		DiagnosticError.new(code, &"error.settings.localization_preflight")
	)
