class_name AccessibilityRuntimeRenderer
extends RefCounted

const SUPPORTED_COLOR_MODES: Array[StringName] = [
	&"standard",
	&"default",
	&"protanopia",
	&"deuteranopia",
	&"tritanopia",
]
const SUPPORTED_UI_SCALES: Array[int] = [100, 125, 150]
const REQUIRED_ACTION_NAMES: Array[StringName] = [
	&"StartAction",
	&"SettingsAction",
	&"ExitAction",
]
const CUE_NODE_NAMES: Dictionary = {
	&"ally": &"AllyCue",
	&"enemy": &"EnemyCue",
	&"trait": &"TraitCue",
	&"rarity": &"RarityCue",
	&"danger": &"DangerCue",
}
const SEMANTIC_CUES: Dictionary = {
	&"ally": {
		"icon": "A",
		"pattern": "solid-border",
	},
	&"enemy": {
		"icon": "E",
		"pattern": "cross-hatch",
	},
	&"trait": {
		"icon": "T",
		"pattern": "linked-diamond",
	},
	&"rarity": {
		"icon": "*",
		"pattern": "double-frame",
	},
	&"danger": {
		"icon": "!",
		"pattern": "warning-stripes",
	},
	&"damage": {
		"icon": "DMG",
		"pattern": "directional-chevron",
	},
}
const MODE_COLORS: Dictionary = {
	&"standard": Color8(93, 214, 255),
	&"default": Color8(93, 214, 255),
	&"protanopia": Color8(86, 180, 233),
	&"deuteranopia": Color8(240, 228, 66),
	&"tritanopia": Color8(213, 94, 0),
}
const MODE_STYLES: Dictionary = {
	&"default": {
		"background": Color8(9, 15, 26),
		"accent": Color8(93, 214, 255),
		"damage": Color8(255, 142, 142),
		"rule": Color8(184, 255, 184),
	},
	&"protanopia": {
		"background": Color8(12, 25, 38),
		"accent": Color8(86, 180, 233),
		"damage": Color8(230, 159, 0),
		"rule": Color8(204, 237, 255),
	},
	&"deuteranopia": {
		"background": Color8(28, 27, 12),
		"accent": Color8(240, 228, 66),
		"damage": Color8(0, 158, 115),
		"rule": Color8(250, 240, 170),
	},
	&"tritanopia": {
		"background": Color8(34, 17, 10),
		"accent": Color8(213, 94, 0),
		"damage": Color8(204, 121, 167),
		"rule": Color8(255, 210, 150),
	},
}
const DAMAGE_EVENT_BUDGETS: Dictionary = {
	&"off": 0,
	&"reduced": 24,
	&"full": 96,
}
const TOOLTIP_MAX_DEPTH: int = 2
const TOOLTIP_LAYER_PATHS: Array[NodePath] = [
	^"TooltipStack/TooltipDepth1",
	^"TooltipStack/TooltipDepth2",
	^"TooltipStack/TooltipDepth3",
]

var _applied_root_id: int
var _color_mode: StringName = &"standard"
var _ui_scale_percent: int = 100
var _settings_root_id: int
var _motion_effects_enabled: bool = true
var _flash_effects_enabled: bool = true
var _particle_effects_enabled: bool = true
var _damage_number_density: StringName = &"full"
var _damage_event_budget: int = 96
var _tooltip_root_id: int
var _opened_tooltip_depth: int


func apply(
	root: Control,
	color_mode: StringName,
	ui_scale_percent: int
) -> Dictionary:
	if root == null:
		return _failure(&"ACCESSIBILITY_ROOT_MISSING")
	if color_mode not in SUPPORTED_COLOR_MODES:
		return _failure(&"ACCESSIBILITY_COLOR_MODE_UNSUPPORTED")
	if ui_scale_percent not in SUPPORTED_UI_SCALES:
		return _failure(&"ACCESSIBILITY_UI_SCALE_UNSUPPORTED")

	_applied_root_id = root.get_instance_id()
	_color_mode = color_mode
	_ui_scale_percent = ui_scale_percent
	var accent: Color = MODE_COLORS[color_mode]
	var locale := StringName(TranslationServer.get_locale())
	if locale not in [&"zh_TW", &"en"]:
		locale = &"zh_TW"
	var localization := ProductionAccessibilityLocalization.new()
	for semantic: StringName in CUE_NODE_NAMES:
		var label := root.find_child(
			String(CUE_NODE_NAMES[semantic]), true, false
		) as Label
		if label == null:
			return _failure(&"ACCESSIBILITY_REQUIRED_CUE_MISSING")
		var cue: Dictionary = SEMANTIC_CUES[semantic]
		label.text = localization.semantic(locale, semantic)
		label.add_theme_color_override(&"font_color", accent)
		label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		label.add_theme_constant_override(&"outline_size", 2)
		label.set_meta(&"semantic_pattern", cue["pattern"])

	var first_action: Button
	for action_name: StringName in REQUIRED_ACTION_NAMES:
		var button := root.find_child(String(action_name), true, false) as Button
		if button == null:
			return _failure(&"ACCESSIBILITY_REQUIRED_ACTION_MISSING")
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_stylebox_override(
			&"focus",
			_focus_style(accent)
		)
		if first_action == null:
			first_action = button
	if first_action != null and first_action.is_inside_tree():
		first_action.grab_focus()

	return {
		"ok": true,
		"error": &"",
		"color_mode": _color_mode,
		"ui_scale_percent": _ui_scale_percent,
	}


func runtime_report(root: Control) -> Dictionary:
	if root == null or root.get_instance_id() != _applied_root_id:
		return _failure(&"ACCESSIBILITY_ROOT_NOT_APPLIED")
	var ui_root := root.find_child("UiProbe", true, false) as Control
	if (
		ui_root == null
		or ui_root.size.x <= 0.0
		or ui_root.size.y <= 0.0
	):
		return _failure(&"ACCESSIBILITY_ROOT_SIZE_INVALID")
	var semantic_cues: Dictionary = {}
	for semantic: StringName in SEMANTIC_CUES:
		var cue := (
			SEMANTIC_CUES[semantic] as Dictionary
		).duplicate(true)
		var label: Label
		if CUE_NODE_NAMES.has(semantic):
			label = root.find_child(
				String(CUE_NODE_NAMES[semantic]),
				true,
				false
			) as Label
		cue["text"] = label.text if label != null else ""
		semantic_cues[semantic] = cue
	var clipped := _clipped_required_controls(root)
	return {
		"ok": true,
		"error": &"",
		"color_mode": _color_mode,
		"ui_scale_percent": _ui_scale_percent,
		"focus_visible": _focus_is_visible(root),
		"required_actions_reachable": _actions_are_reachable(root),
		"clipped_required_controls": clipped,
		"semantic_cues": semantic_cues,
	}


func apply_settings(
	root: Control,
	snapshot: SettingsSnapshot
) -> Dictionary:
	if root == null or snapshot == null:
		return _failure(&"ACCESSIBILITY_SETTINGS_INPUT_INVALID")
	if root.size.x <= 0.0 or root.size.y <= 0.0:
		return _failure(&"ACCESSIBILITY_ROOT_SIZE_INVALID")
	if not DAMAGE_EVENT_BUDGETS.has(snapshot.damage_number_density):
		return _failure(&"ACCESSIBILITY_DAMAGE_DENSITY_INVALID")

	var motion_probe: Node = root.get_node_or_null(^"MotionProbe")
	var flash_probe: Node = root.get_node_or_null(^"FlashProbe")
	var particle_probe: Node = root.get_node_or_null(^"ParticleProbe")
	var rule_information: Node = root.get_node_or_null(^"RuleInformation")
	var damage_host: Node = root.get_node_or_null(^"DamageEvents")
	if (
		not motion_probe is CanvasItem
		or not flash_probe is CanvasItem
		or not particle_probe is CPUParticles2D
		or not rule_information is CanvasItem
		or damage_host == null
	):
		return _failure(&"ACCESSIBILITY_RUNTIME_NODE_MISSING")

	_motion_effects_enabled = not snapshot.reduced_motion
	_flash_effects_enabled = not snapshot.reduced_flash
	_particle_effects_enabled = not snapshot.reduced_particles
	_damage_number_density = snapshot.damage_number_density
	_damage_event_budget = int(
		DAMAGE_EVENT_BUDGETS[_damage_number_density]
	)
	_settings_root_id = root.get_instance_id()
	_apply_responsive_layout(root, snapshot.ui_scale_percent)
	_apply_color_semantics(root, snapshot.color_vision_mode)

	(motion_probe as CanvasItem).visible = _motion_effects_enabled
	(flash_probe as CanvasItem).visible = _flash_effects_enabled
	(particle_probe as CanvasItem).visible = _particle_effects_enabled
	(particle_probe as CPUParticles2D).emitting = _particle_effects_enabled
	(rule_information as CanvasItem).visible = true
	damage_host.set_meta(&"event_budget", _damage_event_budget)
	root.set_meta(&"reduced_motion", snapshot.reduced_motion)
	root.set_meta(&"reduced_flash", snapshot.reduced_flash)
	root.set_meta(&"reduced_particles", snapshot.reduced_particles)
	root.set_meta(&"damage_number_density", _damage_number_density)
	root.set_meta(&"rule_information_visible", true)
	root.set_meta(
		&"effective_ui_scale_percent",
		snapshot.ui_scale_percent
	)
	root.set_meta(
		&"effective_color_vision_mode",
		snapshot.color_vision_mode
	)
	root.set_meta(
		&"semantic_pattern_token",
		&"directional-chevron+warning-stripes"
	)

	var samples := _damage_samples(damage_host)
	var visible_limit := samples.size()
	match _damage_number_density:
		&"off":
			visible_limit = 0
		&"reduced":
			visible_limit = mini(1, samples.size())
	for index: int in samples.size():
		samples[index].visible = index < visible_limit

	return {
		"ok": true,
		"error": &"",
		"damage_event_budget": _damage_event_budget,
		"rule_information_visible": true,
	}


func _apply_responsive_layout(root: Control, scale_percent: int) -> void:
	var safe_size := root.size
	var factor := float(scale_percent) / 100.0
	var margin := 32.0
	var content_width := maxf(safe_size.x - margin * 2.0, 320.0)
	var right_width := minf(420.0 * factor, content_width * 0.48)
	var right_x := safe_size.x - margin - right_width

	_place(root, ^"Background", Vector2(16.0, 16.0), safe_size - Vector2(32.0, 32.0))
	_place(
		root,
		^"StateSummary",
		Vector2(margin, 32.0),
		Vector2(content_width, 42.0 * factor)
	)
	_place(
		root,
		^"MotionProbe",
		Vector2(margin, 112.0),
		Vector2(280.0 * factor, 64.0 * factor)
	)
	_place(
		root,
		^"FlashProbe",
		Vector2(margin, 196.0),
		Vector2(280.0 * factor, 64.0 * factor)
	)
	var particles := root.get_node_or_null(^"ParticleProbe") as Node2D
	if particles != null:
		particles.position = Vector2(
			margin + 140.0 * factor,
			300.0 + 26.0 * (factor - 1.0)
		)
	_place(
		root,
		^"RuleInformation",
		Vector2(margin, 376.0),
		Vector2(maxf(right_x - margin * 2.0, 300.0), 52.0 * factor)
	)
	_place(
		root,
		^"SemanticPatternCue",
		Vector2(margin, 450.0),
		Vector2(maxf(right_x - margin * 2.0, 300.0), 44.0 * factor)
	)
	_place(
		root,
		^"DamageEvents",
		Vector2(right_x, 112.0),
		Vector2(right_width, 160.0 * factor)
	)
	var tooltip_height := minf(
		190.0 * factor,
		maxf(safe_size.y - 390.0, 120.0)
	)
	_place(
		root,
		^"TooltipStack",
		Vector2(right_x, 300.0),
		Vector2(right_width, tooltip_height)
	)
	var cjk_height := 56.0 * factor
	_place(
		root,
		^"CjkBody",
		Vector2(margin, safe_size.y - margin - cjk_height),
		Vector2(maxf(right_x - margin * 4.0, 300.0), cjk_height)
	)
	_set_font_size(root, ^"StateSummary", roundi(20.0 * factor))
	_set_font_size(root, ^"SemanticPatternCue", roundi(18.0 * factor))
	_set_font_size(root, ^"CjkBody", roundi(22.0 * factor))


func _apply_color_semantics(root: Control, color_mode: StringName) -> void:
	var style_value: Variant = MODE_STYLES.get(color_mode)
	if not style_value is Dictionary:
		style_value = MODE_STYLES[&"default"]
	var style := style_value as Dictionary
	var background := root.get_node_or_null(^"Background") as ColorRect
	if background != null:
		background.color = style["background"]
	var summary := root.get_node_or_null(^"StateSummary") as Label
	if summary != null:
		summary.add_theme_color_override(&"font_color", style["accent"])
	var rule := root.get_node_or_null(^"RuleInformation") as Label
	if rule != null:
		rule.add_theme_color_override(&"font_color", style["rule"])
	var pattern := root.get_node_or_null(^"SemanticPatternCue") as Label
	if pattern != null:
		pattern.visible = true
		pattern.add_theme_color_override(&"font_color", style["accent"])
		pattern.add_theme_color_override(&"font_outline_color", Color.BLACK)
		pattern.add_theme_constant_override(&"outline_size", 2)
	for sample: CanvasItem in _damage_samples(
		root.get_node_or_null(^"DamageEvents")
	):
		if sample is Label:
			(sample as Label).add_theme_color_override(
				&"font_color",
				style["damage"]
			)


func _place(
	root: Control,
	path: NodePath,
	position: Vector2,
	size: Vector2
) -> void:
	var control := root.get_node_or_null(path) as Control
	if control == null:
		return
	control.position = position
	control.size = Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))


func _set_font_size(root: Control, path: NodePath, size: int) -> void:
	var label := root.get_node_or_null(path) as Label
	if label != null:
		label.add_theme_font_size_override(&"font_size", size)


func runtime_effect_report(root: Control) -> Dictionary:
	if root == null or root.get_instance_id() != _settings_root_id:
		return _failure(&"ACCESSIBILITY_SETTINGS_NOT_APPLIED")
	return {
		"ok": true,
		"error": &"",
		"motion_effects_enabled": _motion_effects_enabled,
		"flash_effects_enabled": _flash_effects_enabled,
		"particle_effects_enabled": _particle_effects_enabled,
		"damage_number_density": _damage_number_density,
		"damage_event_budget": _damage_event_budget,
		"visible_damage_samples": _visible_damage_samples(root),
		"rule_information_visible": bool(
			root.get_meta(&"rule_information_visible", false)
		),
	}


func open_tooltip(root: Control, depth: int) -> Dictionary:
	if root == null:
		return _tooltip_failure(&"ACCESSIBILITY_TOOLTIP_ROOT_MISSING")
	if depth < 0 or depth > TOOLTIP_MAX_DEPTH:
		return _tooltip_failure(&"ACCESSIBILITY_TOOLTIP_DEPTH_INVALID")
	var layers := _tooltip_layers(root)
	if layers.size() != TOOLTIP_LAYER_PATHS.size():
		return _tooltip_failure(&"ACCESSIBILITY_TOOLTIP_LAYER_MISSING")

	for index: int in layers.size():
		layers[index].visible = index < depth and index < TOOLTIP_MAX_DEPTH
	_opened_tooltip_depth = depth
	_tooltip_root_id = root.get_instance_id()
	return {
		"ok": true,
		"error": &"",
		"accepted": true,
		"opened_depth": _opened_tooltip_depth,
	}


func tooltip_report(root: Control) -> Dictionary:
	if root == null or root.get_instance_id() != _tooltip_root_id:
		return _failure(&"ACCESSIBILITY_TOOLTIP_NOT_OPENED")
	var visible_layers := 0
	for layer: CanvasItem in _tooltip_layers(root):
		if layer.visible:
			visible_layers += 1
	return {
		"ok": true,
		"error": &"",
		"opened_depth": _opened_tooltip_depth,
		"visible_layers": visible_layers,
		"maximum_depth": TOOLTIP_MAX_DEPTH,
	}


func tooltip_max_depth() -> int:
	return TOOLTIP_MAX_DEPTH


func _actions_are_reachable(root: Control) -> bool:
	for action_name: StringName in REQUIRED_ACTION_NAMES:
		var button := root.find_child(String(action_name), true, false) as Button
		if button == null or not button.visible or button.disabled \
			or button.focus_mode != Control.FOCUS_ALL:
			return false
	return true


func _focus_is_visible(root: Control) -> bool:
	for action_name: StringName in REQUIRED_ACTION_NAMES:
		var button := root.find_child(String(action_name), true, false) as Button
		if button == null or not button.has_theme_stylebox_override(&"focus"):
			return false
	return true


func _clipped_required_controls(root: Control) -> Array[StringName]:
	var result: Array[StringName] = []
	var ui_root := root.find_child("UiProbe", true, false) as Control
	if ui_root == null:
		return REQUIRED_ACTION_NAMES.duplicate()
	var bounds := Rect2(Vector2.ZERO, ui_root.size)
	for action_name: StringName in REQUIRED_ACTION_NAMES:
		var button := root.find_child(String(action_name), true, false) as Button
		if button == null:
			result.append(action_name)
			continue
		var control_rect := Rect2(button.position, button.size)
		if not bounds.encloses(control_rect):
			result.append(action_name)
	return result


func _focus_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.13, 1.0)
	style.border_color = accent
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	return style


func _damage_samples(host: Node) -> Array[CanvasItem]:
	var result: Array[CanvasItem] = []
	for child: Node in host.get_children():
		if child is CanvasItem:
			result.append(child as CanvasItem)
	return result


func _visible_damage_samples(root: Control) -> int:
	var host: Node = root.get_node_or_null(^"DamageEvents")
	if host == null:
		return 0
	var result := 0
	for sample: CanvasItem in _damage_samples(host):
		if sample.visible:
			result += 1
	return result


func _tooltip_layers(root: Control) -> Array[CanvasItem]:
	var result: Array[CanvasItem] = []
	for path: NodePath in TOOLTIP_LAYER_PATHS:
		var layer: Node = root.get_node_or_null(path)
		if layer is CanvasItem:
			result.append(layer as CanvasItem)
	return result


func _tooltip_failure(error: StringName) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"accepted": false,
	}


func _failure(error: StringName) -> Dictionary:
	return {
		"ok": false,
		"error": error,
	}
