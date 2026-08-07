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
	var runtime_theme := BASE_THEME.duplicate(true) as Theme
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
	_apply_control_metrics(host, factor)
	host.set_meta(&"effective_theme_scale_percent", scale_percent)
	return true


func _apply_control_metrics(host: Control, factor: float) -> void:
	for node: Node in host.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button == null:
			continue
		var base_size: Vector2 = button.get_meta(
			&"expedition_theme_base_minimum",
			button.get_combined_minimum_size()
		)
		button.set_meta(&"expedition_theme_base_minimum", base_size)
		var scaled_width := (
			base_size.x
			if _uses_responsive_b1_width(button)
			else ceilf(base_size.x * factor)
		)
		button.custom_minimum_size = Vector2(
			scaled_width,
			ceilf(base_size.y * factor)
		)


func _uses_responsive_b1_width(control: Control) -> bool:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ProductionScreen:
			return ancestor.get_node_or_null(^"B1Layout") != null
		ancestor = ancestor.get_parent()
	return false
