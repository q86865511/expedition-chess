class_name ProductionAccessibilityHost
extends Control

const CAPABILITIES: Array[StringName] = [
	&"motion",
	&"flash",
	&"particles",
	&"density",
	&"tooltip",
	&"cjk",
]

var _renderer := AccessibilityRuntimeRenderer.new()
var _typography := LocalizedTypographyPolicy.new()
var _localization := ProductionAccessibilityLocalization.new()
var _locale: StringName = &"zh_TW"
var _last_effect_report: Dictionary = {}
var _last_cjk_report: Dictionary = {}
var _last_tooltip_report: Dictionary = {
	"ok": true,
	"opened_depth": 0,
	"visible_layers": 0,
	"maximum_depth": 2,
}


func _ready() -> void:
	_make_mouse_passthrough(self)


func apply_committed_settings(
	snapshot: SettingsSnapshot
) -> AccessibilityRuntimeReport:
	if snapshot == null:
		return AccessibilityRuntimeReport.failure(
			&"ACCESSIBILITY_SETTINGS_INPUT_INVALID"
		)
	var effect_report := _renderer.apply_settings(self, snapshot)
	if not _ok(effect_report):
		return AccessibilityRuntimeReport.failure(
			StringName(effect_report.get(
				"error",
				&"ACCESSIBILITY_SETTINGS_APPLY_FAILED"
			))
		)
	_locale = snapshot.locale
	var composition := get_parent().get_node_or_null(^"Composition")
	if (
		composition != null
		and composition.has_method(&"apply_color_vision_mode")
	):
		composition.call(
			&"apply_color_vision_mode",
			snapshot.color_vision_mode
		)
	var cjk_label := get_node_or_null(^"CjkBody") as Label
	var localized_text := _localization.resolve(
		snapshot.locale,
		ProductionAccessibilityLocalization.COMBAT_RULE_KEY
	)
	if localized_text.is_empty():
		return AccessibilityRuntimeReport.failure(
			&"ACCESSIBILITY_LOCALIZATION_MISSING"
		)
	var typography_report := _typography.apply_to(
		cjk_label,
		snapshot.locale,
		localized_text
	)
	if not _ok(typography_report):
		return AccessibilityRuntimeReport.failure(
			StringName(typography_report.get(
				"error_code",
				&"ACCESSIBILITY_TYPOGRAPHY_APPLY_FAILED"
			))
		)
	_last_effect_report = (
		_renderer.runtime_effect_report(self) as Dictionary
	).duplicate(true)
	_last_cjk_report = typography_report.duplicate(true)
	_update_state_labels(snapshot)
	return runtime_accessibility_report()


func render_damage_events(events: Array) -> void:
	var damage_events: Array[BattleEvent] = []
	for value: Variant in events:
		var event := value as BattleEvent
		if (
			event != null
			and event.type == &"damage"
			and event.payload is DamageEventPayload
		):
			damage_events.append(event.deep_clone())
	var host := get_node_or_null(^"DamageEvents")
	if host == null:
		return
	var labels: Array[Label] = []
	for child: Node in host.get_children():
		if child is Label:
			labels.append(child as Label)
	for index: int in labels.size():
		var label := labels[index]
		if index >= damage_events.size():
			label.set_meta(&"semantic_kind", &"damage")
			label.set_meta(&"typed_data_id", &"")
			label.set_meta(&"semantic_pattern", &"")
			continue
		var event := damage_events[index]
		var payload := event.payload as DamageEventPayload
		var pattern := _damage_pattern(payload.damage_type)
		var target_id := (
			event.target_instance_ids[0]
			if not event.target_instance_ids.is_empty()
			else &"target.unknown"
		)
		var damage_text := _localization.resolve(
			_locale,
			ProductionAccessibilityLocalization.DAMAGE_EVENT_KEY
		)
		label.text = damage_text % [
			String(pattern),
			String(payload.damage_type),
			payload.health_damage,
			String(target_id),
		]
		label.set_meta(&"semantic_kind", &"damage")
		label.set_meta(
			&"typed_data_id",
			StringName("damage.%s" % String(payload.damage_type))
		)
		label.set_meta(&"semantic_pattern", pattern)
		label.set_meta(&"accessible_text", label.text)


func _damage_pattern(damage_type: StringName) -> StringName:
	return {
		&"physical": &"impact-lines",
		&"magic": &"magic-spark",
		&"true": &"true-diamond",
	}.get(damage_type, &"damage-pulse")


func open_tooltip(depth: int) -> AccessibilityTooltipResult:
	var renderer_result := _renderer.open_tooltip(self, depth)
	if not _ok(renderer_result):
		return AccessibilityTooltipResult.failure(
			StringName(renderer_result.get(
				"error",
				&"ACCESSIBILITY_TOOLTIP_FAILED"
			))
		)
	_last_tooltip_report = (
		_renderer.tooltip_report(self) as Dictionary
	).duplicate(true)
	var result := AccessibilityTooltipResult.new()
	result.ok = true
	result.accepted = true
	result.opened_depth = int(renderer_result.get("opened_depth", 0))
	return result


func runtime_accessibility_report() -> AccessibilityRuntimeReport:
	if _last_effect_report.is_empty():
		return AccessibilityRuntimeReport.failure(
			&"ACCESSIBILITY_SETTINGS_NOT_APPLIED"
		)
	var report := AccessibilityRuntimeReport.new()
	report.ok = true
	report.error = StringName(_last_effect_report.get("error", &""))
	report.motion_effects_enabled = bool(
		_last_effect_report.get("motion_effects_enabled", false)
	)
	report.flash_effects_enabled = bool(
		_last_effect_report.get("flash_effects_enabled", false)
	)
	report.particle_effects_enabled = bool(
		_last_effect_report.get("particle_effects_enabled", false)
	)
	report.damage_number_density = StringName(
		_last_effect_report.get("damage_number_density", &"")
	)
	report.damage_event_budget = int(
		_last_effect_report.get("damage_event_budget", -1)
	)
	report.visible_damage_samples = int(
		_last_effect_report.get("visible_damage_samples", -1)
	)
	report.rule_information_visible = bool(
		_last_effect_report.get("rule_information_visible", false)
	)
	report.tooltip_opened_depth = int(
		_last_tooltip_report.get("opened_depth", 0)
	)
	report.tooltip_visible_layers = int(
		_last_tooltip_report.get("visible_layers", 0)
	)
	report.tooltip_maximum_depth = int(
		_last_tooltip_report.get("maximum_depth", 2)
	)
	report.cjk_ok = bool(_last_cjk_report.get("ok", false))
	report.cjk_locale = StringName(_last_cjk_report.get("locale", &""))
	report.cjk_font_source = StringName(
		_last_cjk_report.get("font_source", &"")
	)
	report.cjk_readable = bool(
		_last_cjk_report.get("readable", false)
	)
	report.cjk_required_glyph_count = int(
		_last_cjk_report.get("required_glyph_count", 0)
	)
	for value: Variant in _last_cjk_report.get("missing_glyphs", []):
		report.cjk_missing_glyphs.append(int(value))
	report.production_host = _stable_binding_identity()
	report.capabilities.assign(CAPABILITIES)
	return report


func _update_state_labels(snapshot: SettingsSnapshot) -> void:
	var full := _localization.resolve(
		snapshot.locale,
		ProductionAccessibilityLocalization.STATE_FULL_KEY
	)
	var reduced := _localization.resolve(
		snapshot.locale,
		ProductionAccessibilityLocalization.STATE_REDUCED_KEY
	)
	var summary := get_node_or_null(^"StateSummary") as Label
	if summary != null:
		summary.text = _localization.resolve(
			snapshot.locale,
			ProductionAccessibilityLocalization.SUMMARY_KEY
		) % [
			reduced if snapshot.reduced_motion else full,
			reduced if snapshot.reduced_flash else full,
			reduced if snapshot.reduced_particles else full,
			_localized_density(snapshot),
		]
	_set_label(
		^"MotionProbe/Label",
		_localization.resolve(
			snapshot.locale,
			ProductionAccessibilityLocalization.MOTION_KEY
		)
	)
	_set_label(
		^"FlashProbe/Label",
		_localization.resolve(
			snapshot.locale,
			ProductionAccessibilityLocalization.FLASH_KEY
		)
	)
	_set_label(
		^"ParticleProbe/Label",
		_localization.resolve(
			snapshot.locale,
			ProductionAccessibilityLocalization.PARTICLES_KEY
		)
	)
	_set_label(
		^"RuleInformation",
		_localization.resolve(
			snapshot.locale,
			ProductionAccessibilityLocalization.RULE_INFORMATION_KEY
		)
	)
	_set_label(
		^"SemanticPatternCue",
		_localization.resolve(
			snapshot.locale,
			ProductionAccessibilityLocalization.PATTERN_CUE_KEY
		)
	)
	for index: int in ProductionAccessibilityLocalization.DAMAGE_SAMPLE_KEYS.size():
		_set_label(
			NodePath("DamageEvents/DamageSample%d" % (index + 1)),
			_localization.resolve(
				snapshot.locale,
				ProductionAccessibilityLocalization.DAMAGE_SAMPLE_KEYS[index]
			)
		)


func _localized_density(snapshot: SettingsSnapshot) -> String:
	var key := StringName(
		"settings.value.damage_number_density.%s"
		% String(snapshot.damage_number_density)
	)
	var resolved := LocalizationCatalog.new().resolve(snapshot.locale, key)
	return resolved.value if resolved.ok else String(snapshot.damage_number_density)


func _set_label(path: NodePath, text: String) -> void:
	var label := get_node_or_null(path) as Label
	if label != null:
		label.text = text


func _stable_binding_identity() -> String:
	var parent := get_parent()
	return "%s/%s" % [
		String(parent.name) if parent != null else "DETACHED",
		String(name),
	]


func _ok(value: Variant) -> bool:
	return value is Dictionary and bool((value as Dictionary).get("ok", false))


func _make_mouse_passthrough(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_make_mouse_passthrough(child)
