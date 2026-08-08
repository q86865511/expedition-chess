class_name ExpeditionThemeRuntime
extends RefCounted

const BASE_THEME: Theme = preload("res://theme/expedition_theme.tres")
const SUPPORTED_SCALES: Array[int] = [100, 125, 150]
const TYPE_SIZES: Dictionary = {
	&"ExpeditionTitle": 32,
	&"ExpeditionHeading": 24,
	&"ExpeditionAuxiliary": 16,
}
const TOKEN_SIZES: Dictionary = {
	&"title": 32,
	&"heading": 24,
	&"body": 18,
	&"auxiliary": 16,
}
const SPACING_TOKENS: Dictionary = {
	&"space_1": 4,
	&"space_2": 8,
	&"space_3": 12,
	&"space_4": 16,
	&"space_6": 24,
	&"space_8": 32,
	&"safe_margin": 24,
	&"gutter": 16,
	&"min_button_height": 48,
}


func apply(host: Control, scale_percent: int) -> bool:
	if host == null or scale_percent not in SUPPORTED_SCALES:
		return false
	var factor := float(scale_percent) / 100.0
	var base_metrics := _capture_control_metrics(host)
	var runtime_theme := BASE_THEME.duplicate(false) as Theme
	if runtime_theme == null:
		return false
	runtime_theme.default_font_size = roundi(18.0 * factor)
	for type_name: StringName in TYPE_SIZES:
		runtime_theme.set_font_size(
			&"font_size", type_name, roundi(float(TYPE_SIZES[type_name]) * factor)
		)
	for token: StringName in TOKEN_SIZES:
		runtime_theme.set_font_size(
			token, &"ExpeditionTypeScale", roundi(float(TOKEN_SIZES[token]) * factor)
		)
	for token: StringName in SPACING_TOKENS:
		runtime_theme.set_constant(
			token, &"ExpeditionSpacing", roundi(float(SPACING_TOKENS[token]) * factor)
		)
	runtime_theme.set_constant(&"separation", &"HBoxContainer", roundi(16.0 * factor))
	runtime_theme.set_constant(&"separation", &"VBoxContainer", roundi(12.0 * factor))
	runtime_theme.set_constant(&"h_separation", &"GridContainer", roundi(12.0 * factor))
	runtime_theme.set_constant(&"v_separation", &"GridContainer", roundi(8.0 * factor))
	host.theme = runtime_theme
	_apply_control_metrics(host, factor, base_metrics)
	host.set_meta(&"effective_theme_scale_percent", scale_percent)
	return true


func _capture_control_metrics(host: Control) -> Dictionary:
	var result: Dictionary = {}
	for node: Node in host.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button == null:
			continue
		var baseline: Vector2
		if button.has_meta(&"expedition_theme_base_minimum"):
			baseline = button.get_meta(&"expedition_theme_base_minimum")
		else:
			baseline = _authored_button_minimum(button)
		baseline.y = maxf(baseline.y, float(SPACING_TOKENS[&"min_button_height"]))
		button.set_meta(&"expedition_theme_base_minimum", baseline)
		result[button.get_instance_id()] = baseline
	return result


func _authored_button_minimum(button: BaseButton) -> Vector2:
	var baseline := button.custom_minimum_size
	if baseline.x > 0.0 and baseline.y > 0.0:
		return baseline
	# 新畫面會先進入已套縮放 Theme 的 host，之後才觸發 deferred reapply。
	# 暫時以 100% 權威 Theme 量測未 authored 的軸，避免把繼承到的 150% 尺寸
	# 寫入 base meta，亦保留文字按鈕的真實最小寬度。
	var assigned_theme := button.theme
	button.theme = BASE_THEME
	var combined := button.get_combined_minimum_size()
	button.theme = assigned_theme
	if baseline.x <= 0.0:
		baseline.x = combined.x
	if baseline.y <= 0.0:
		baseline.y = combined.y
	return baseline


func _apply_control_metrics(
	host: Control,
	factor: float,
	base_metrics: Dictionary
) -> void:
	for node: Node in host.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button == null:
			continue
		var base_size: Vector2 = button.get_meta(
			&"expedition_theme_base_minimum",
			base_metrics.get(button.get_instance_id(), Vector2.ZERO)
		)
		var scaled_width := (
			base_size.x
			if _uses_responsive_b1_width(button)
			else ceilf(base_size.x * factor)
		)
		button.custom_minimum_size = (
			base_size
			if bool(button.get_meta(&"expedition_theme_fixed_minimum", false))
			else Vector2(scaled_width, ceilf(base_size.y * factor))
		)


func _uses_responsive_b1_width(control: Control) -> bool:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ProductionScreen:
			return ancestor.get_node_or_null(^"B1Layout") != null
		ancestor = ancestor.get_parent()
	return false
