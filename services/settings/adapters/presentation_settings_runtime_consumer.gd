class_name PresentationSettingsRuntimeConsumer
extends RefCounted

const RUNTIME_MISSING: StringName = &"SETTINGS_PRESENTATION_RUNTIME_MISSING"
const KIND_UNKNOWN: StringName = &"SETTINGS_PRESENTATION_KIND_UNKNOWN"
const SUPPORTED_KINDS: Array[StringName] = [
	&"theme",
	&"viewport",
	&"localization",
]
const ACCESSIBILITY_HOST_NAME: StringName = &"AccessibilityRuntime"

var _host: Control
var _viewport_runtime: Object
var _runtime_by_kind: Dictionary = {}
var _last_theme_snapshot: SettingsSnapshot
var _last_viewport_snapshot: SettingsSnapshot
var _localization_catalog: LocalizationCatalog


func _init(
	p_host: Control,
	p_viewport_runtime: Object = null
) -> void:
	_host = p_host
	_viewport_runtime = p_viewport_runtime
	if _host != null and not _host.child_entered_tree.is_connected(
		_on_host_child_entered
	):
		_host.child_entered_tree.connect(_on_host_child_entered)


## boot 順序上 settings runtime 早於內容載入，正式 catalog 只能在 boot 成功後補注入
## （review N3）。已安裝的 accessibility host 立即重綁，之後才安裝的 host 由
## `_apply_accessibility` 在下一次套用時綁上。
func bind_localization_catalog(catalog: LocalizationCatalog) -> void:
	if catalog == null:
		return
	_localization_catalog = catalog
	var runtime := _accessibility_host()
	if runtime != null and runtime.has_method(&"bind_localization_catalog"):
		runtime.call(&"bind_localization_catalog", catalog)


func preflight(kind: StringName, plan: SettingsSnapshot) -> StringName:
	if _host == null or plan == null:
		return RUNTIME_MISSING
	if kind not in SUPPORTED_KINDS:
		return KIND_UNKNOWN
	return &""


func activate(kind: StringName, snapshot: SettingsSnapshot) -> StringName:
	var error_code := preflight(kind, snapshot)
	if not error_code.is_empty():
		return error_code
	_runtime_by_kind[kind] = snapshot.deep_clone()
	match kind:
		&"theme":
			_host.set_meta(&"color_vision_mode", snapshot.color_vision_mode)
			_host.set_meta(&"reduced_motion", snapshot.reduced_motion)
			_host.set_meta(&"reduced_flash", snapshot.reduced_flash)
			_host.set_meta(&"reduced_particles", snapshot.reduced_particles)
			_host.set_meta(
				&"damage_number_density",
				snapshot.damage_number_density
			)
			_last_theme_snapshot = snapshot.deep_clone()
			var accessibility_error := _apply_accessibility(snapshot)
			if not accessibility_error.is_empty():
				return accessibility_error
		&"viewport":
			if (
				_viewport_runtime != null
				and _viewport_runtime.has_method(&"apply_ui_scale")
			):
				var viewport_error := StringName(
					_viewport_runtime.call(
						&"apply_ui_scale",
						snapshot.ui_scale_percent
					)
				)
				if not viewport_error.is_empty():
					return viewport_error
			_host.set_meta(&"ui_scale_percent", snapshot.ui_scale_percent)
			_last_viewport_snapshot = snapshot.deep_clone()
			_apply_ui_scale(snapshot.ui_scale_percent)
		&"localization":
			TranslationServer.set_locale(String(snapshot.locale))
	return &""


func activate_safe_fallback(kind: StringName) -> void:
	activate(kind, SettingsSnapshot.new())


func runtime_snapshot(kind: StringName) -> SettingsSnapshot:
	var snapshot: Variant = _runtime_by_kind.get(kind)
	return snapshot.deep_clone() if snapshot is SettingsSnapshot else null


func runtime_accessibility_report() -> AccessibilityRuntimeReport:
	var runtime := _accessibility_host()
	if runtime == null \
		or not runtime.has_method(&"runtime_accessibility_report"):
		return AccessibilityRuntimeReport.failure(
			&"SETTINGS_ACCESSIBILITY_RUNTIME_MISSING"
		)
	var report: Variant = runtime.call(&"runtime_accessibility_report")
	if report is AccessibilityRuntimeReport:
		return (report as AccessibilityRuntimeReport).deep_clone()
	return AccessibilityRuntimeReport.failure(
		&"SETTINGS_ACCESSIBILITY_REPORT_INVALID"
	)


func open_accessibility_tooltip(depth: int) -> AccessibilityTooltipResult:
	var runtime := _accessibility_host()
	if runtime == null or not runtime.has_method(&"open_tooltip"):
		return AccessibilityTooltipResult.failure(
			&"SETTINGS_ACCESSIBILITY_RUNTIME_MISSING"
		)
	var result: Variant = runtime.call(&"open_tooltip", depth)
	if result is AccessibilityTooltipResult:
		return (result as AccessibilityTooltipResult).deep_clone()
	return AccessibilityTooltipResult.failure(
		&"SETTINGS_ACCESSIBILITY_REPORT_INVALID"
	)


func _apply_accessibility(snapshot: SettingsSnapshot) -> StringName:
	var runtime := _accessibility_host()
	if runtime == null:
		# Not every route renders combat effects. Keep the committed snapshot so
		# a subsequently installed production host receives the same settings.
		return &""
	if not runtime.has_method(&"apply_committed_settings"):
		return &"SETTINGS_ACCESSIBILITY_BINDING_INVALID"
	# review N3：accessibility host 的文案也走正式 catalog。host 是場景節點（在
	# run_combat.tscn 內），由這條既有的設定套用鏈注入，不另開全域存取點。
	if (
		_localization_catalog != null
		and runtime.has_method(&"bind_localization_catalog")
	):
		runtime.call(&"bind_localization_catalog", _localization_catalog)
	if runtime is Control and (runtime as Control).size == Vector2.ZERO:
		var parent := runtime.get_parent() as Control
		if parent != null and parent.size.x > 0.0 and parent.size.y > 0.0:
			(runtime as Control).set_anchors_preset(
				Control.PRESET_TOP_LEFT
			)
			(runtime as Control).size = parent.size
		else:
			var design_size: Vector2 = runtime.get_meta(
				&"design_size",
				Vector2.ZERO
			)
			if design_size.x > 0.0 and design_size.y > 0.0:
				(runtime as Control).set_anchors_preset(
					Control.PRESET_TOP_LEFT
				)
				(runtime as Control).size = design_size
	var result := runtime.call(
		&"apply_committed_settings",
		snapshot.deep_clone()
	) as AccessibilityRuntimeReport
	if result != null and result.ok:
		return &""
	if result != null and not result.error.is_empty():
		return result.error
	return &"SETTINGS_ACCESSIBILITY_ACTIVATION_FAILED"


func _apply_ui_scale(scale_percent: int) -> void:
	if _host == null or scale_percent not in [100, 125, 150]:
		return
	var factor := float(scale_percent) / 100.0
	for node: Node in _host.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null:
			continue
		button.custom_minimum_size = Vector2(
			240.0 * factor,
			56.0 * factor
		)
		button.add_theme_font_size_override(
			&"font_size",
			roundi(16.0 * factor)
		)
	for node: Node in _host.find_children("*", "OptionButton", true, false):
		var option := node as OptionButton
		if option != null:
			option.custom_minimum_size = Vector2(
				280.0 * factor,
				56.0 * factor
			)
			option.add_theme_font_size_override(
				&"font_size",
				roundi(16.0 * factor)
			)
	for node: Node in _host.find_children("*", "ItemList", true, false):
		var list := node as ItemList
		if list != null:
			list.custom_minimum_size = Vector2(
				360.0 * factor,
				180.0 * factor
			)
			list.add_theme_font_size_override(
				&"font_size",
				roundi(16.0 * factor)
			)


func _accessibility_host() -> Node:
	if _host == null:
		return null
	if _host.name == ACCESSIBILITY_HOST_NAME:
		return _host
	return _host.find_child(
		String(ACCESSIBILITY_HOST_NAME),
		true,
		false
	)


func _on_host_child_entered(_child: Node) -> void:
	if _last_viewport_snapshot != null:
		call_deferred(
			&"_apply_ui_scale",
			_last_viewport_snapshot.ui_scale_percent
		)
	if _last_theme_snapshot == null:
		return
	call_deferred(
		&"_apply_accessibility",
		_last_theme_snapshot.deep_clone()
	)
