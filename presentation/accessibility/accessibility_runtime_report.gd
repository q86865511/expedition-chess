class_name AccessibilityRuntimeReport
extends RefCounted

var ok: bool
var error: StringName
var motion_effects_enabled: bool
var flash_effects_enabled: bool
var particle_effects_enabled: bool
var damage_number_density: StringName
var damage_event_budget: int
var visible_damage_samples: int
var rule_information_visible: bool
var tooltip_opened_depth: int
var tooltip_visible_layers: int
var tooltip_maximum_depth: int
var cjk_ok: bool
var cjk_locale: StringName
var cjk_font_source: StringName
var cjk_fallback_used: bool
var cjk_readable: bool
var cjk_required_glyph_count: int
var cjk_missing_glyphs: Array[int] = []
var production_host: String
var capabilities: Array[StringName] = []


func deep_clone() -> AccessibilityRuntimeReport:
	var clone := AccessibilityRuntimeReport.new()
	clone.ok = ok
	clone.error = error
	clone.motion_effects_enabled = motion_effects_enabled
	clone.flash_effects_enabled = flash_effects_enabled
	clone.particle_effects_enabled = particle_effects_enabled
	clone.damage_number_density = damage_number_density
	clone.damage_event_budget = damage_event_budget
	clone.visible_damage_samples = visible_damage_samples
	clone.rule_information_visible = rule_information_visible
	clone.tooltip_opened_depth = tooltip_opened_depth
	clone.tooltip_visible_layers = tooltip_visible_layers
	clone.tooltip_maximum_depth = tooltip_maximum_depth
	clone.cjk_ok = cjk_ok
	clone.cjk_locale = cjk_locale
	clone.cjk_font_source = cjk_font_source
	clone.cjk_fallback_used = cjk_fallback_used
	clone.cjk_readable = cjk_readable
	clone.cjk_required_glyph_count = cjk_required_glyph_count
	clone.cjk_missing_glyphs.assign(cjk_missing_glyphs)
	clone.production_host = production_host
	clone.capabilities.assign(capabilities)
	return clone


static func failure(code: StringName) -> AccessibilityRuntimeReport:
	var report := AccessibilityRuntimeReport.new()
	report.error = code
	return report
