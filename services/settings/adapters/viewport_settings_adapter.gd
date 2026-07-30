class_name ViewportSettingsAdapter
extends SettingsAdapterPort

const PREFLIGHT_FAILED: StringName = &"SETTINGS_VIEWPORT_PREFLIGHT_FAILED"
const ACTIVATION_FAILED: StringName = &"SETTINGS_VIEWPORT_ACTIVATION_FAILED"

var _consumer: Object
var _policy: WorldViewportPolicy
var _mapper: WindowCoordinateMapper
var _window_size: Vector2i
var _window_size_provider: Callable


class ViewportActivationToken:
	extends SettingsActivationToken

	var _consumer: Object
	var _policy: WorldViewportPolicy
	var _mapper: WindowCoordinateMapper
	var _window_size: Vector2i
	var _snapshot: SettingsSnapshot


	func _init(
		p_candidate_digest: String,
		p_consumer: Object,
		p_policy: WorldViewportPolicy,
		p_mapper: WindowCoordinateMapper,
		p_window_size: Vector2i,
		p_snapshot: SettingsSnapshot
	) -> void:
		super._init(p_candidate_digest)
		_consumer = p_consumer
		_policy = p_policy
		_mapper = p_mapper
		_window_size = p_window_size
		_snapshot = p_snapshot.deep_clone()


	func activate() -> StringName:
		if (
			_consumer == null
			or not _consumer.has_method("activate")
			or _policy == null
			or _mapper == null
		):
			return ViewportSettingsAdapter.ACTIVATION_FAILED
		var configure_error := _mapper.configure(
			_policy.layout_for_window(_window_size),
			_snapshot.ui_scale_percent
		)
		if not configure_error.is_empty():
			return configure_error
		return ThemeSettingsAdapter._result_error_code(
			_consumer.call("activate", &"viewport", _snapshot.deep_clone()),
			ViewportSettingsAdapter.ACTIVATION_FAILED
		)


func _init(
	p_consumer: Object,
	p_policy: WorldViewportPolicy,
	p_mapper: WindowCoordinateMapper,
	p_window_size: Vector2i,
	p_window_size_provider: Callable = Callable()
) -> void:
	_consumer = p_consumer
	_policy = p_policy
	_mapper = p_mapper
	_window_size = p_window_size
	_window_size_provider = p_window_size_provider


func preflight(
	plan: SettingsSnapshot,
	candidate_digest: String
) -> SettingsAdapterPreflightResult:
	if (
		plan == null
		or candidate_digest.is_empty()
		or _consumer == null
		or not _consumer.has_method("preflight")
		or _policy == null
		or _mapper == null
	):
		return _failure(PREFLIGHT_FAILED)
	var current_window_size := _current_window_size()
	var layout := _policy.layout_for_window(current_window_size)
	var probe_mapper := WindowCoordinateMapper.new()
	var configure_error := probe_mapper.configure(layout, plan.ui_scale_percent)
	if not configure_error.is_empty():
		return _failure(configure_error)
	var consumer_error := ThemeSettingsAdapter._result_error_code(
		_consumer.call("preflight", &"viewport", plan.deep_clone()),
		PREFLIGHT_FAILED
	)
	if not consumer_error.is_empty():
		return _failure(consumer_error)
	return SettingsAdapterPreflightResult.success(
		ViewportActivationToken.new(
			candidate_digest,
			_consumer,
			_policy,
			_mapper,
			current_window_size,
			plan
		)
	)


func activate_safe_fallback() -> void:
	var fallback := SettingsSnapshot.new()
	if _policy != null and _mapper != null:
		_mapper.configure(
			_policy.layout_for_window(_current_window_size()),
			fallback.ui_scale_percent
		)
	if _consumer != null and _consumer.has_method("activate_safe_fallback"):
		_consumer.call("activate_safe_fallback", &"viewport")


func rebuild_from_committed(snapshot: SettingsSnapshot) -> void:
	if snapshot == null:
		return
	if _policy != null and _mapper != null:
		_mapper.configure(
			_policy.layout_for_window(_current_window_size()),
			snapshot.ui_scale_percent
		)
	if _consumer != null and _consumer.has_method("activate"):
		_consumer.call("activate", &"viewport", snapshot.deep_clone())


func _failure(code: StringName) -> SettingsAdapterPreflightResult:
	return SettingsAdapterPreflightResult.failure(
		DiagnosticError.new(code, &"error.settings.viewport_preflight")
	)


func _current_window_size() -> Vector2i:
	if _window_size_provider.is_valid():
		var value: Variant = _window_size_provider.call()
		if (
			value is Vector2i
			and (value as Vector2i).x > 0
			and (value as Vector2i).y > 0
		):
			return value as Vector2i
	return _window_size
