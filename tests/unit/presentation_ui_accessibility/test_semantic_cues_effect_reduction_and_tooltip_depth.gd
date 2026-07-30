extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_accessibility/accessibility_test_support.gd"
)

const COLOR_MODES: Array[StringName] = [
	&"default",
	&"protanopia",
	&"deuteranopia",
	&"tritanopia",
]
const DECISION_SEMANTICS: Array[StringName] = [
	&"allegiance.enemy",
	&"allegiance.ally",
	&"bond.active",
	&"rarity.legendary",
	&"damage.arcane",
	&"danger.lethal",
]


# Coverage for R12-B02 is intentionally recorded here without claiming that the
# deferred review finding is resolved.
func test_every_color_mode_keeps_icon_pattern_and_text_decision_cues() -> void:
	var script := Support.load_script(self, Support.SEMANTIC_TOKENS_PATH)
	if script == null:
		return
	var tokens: Object = script.new()
	if not Support.require_methods(
		self,
		tokens,
		[&"cue_for"],
		Support.SEMANTIC_TOKENS_PATH
	):
		return

	for mode: StringName in COLOR_MODES:
		for semantic: StringName in DECISION_SEMANTICS:
			var cue: Variant = tokens.call(&"cue_for", mode, semantic)
			assert_true(
				cue is Dictionary,
				"%s/%s must expose a typed cue record" % [mode, semantic]
			)
			if not cue is Dictionary:
				continue
			for non_color_field: StringName in [
				&"icon_token",
				&"pattern_token",
				&"text_key",
			]:
				assert_true(
					cue.has(non_color_field),
					"%s/%s needs %s" % [mode, semantic, non_color_field]
				)
				assert_false(
					String(cue.get(non_color_field, "")).is_empty(),
					"%s/%s cannot encode meaning by color alone" % [mode, semantic]
				)


func test_reduced_effects_damage_density_and_tooltip_depth_are_explicit() -> void:
	var script := Support.load_script(self, Support.SEMANTIC_TOKENS_PATH)
	if script == null:
		return
	var tokens: Object = script.new()
	if not Support.require_methods(
		self,
		tokens,
		[&"effects_for", &"tooltip_depth_allowed"],
		Support.SEMANTIC_TOKENS_PATH
	):
		return

	var defaults := SettingsSnapshot.new()
	var default_effects: Variant = tokens.call(&"effects_for", defaults)
	assert_true(default_effects is Dictionary)
	if default_effects is Dictionary:
		assert_eq(default_effects.get("motion_level"), &"full")
		assert_eq(default_effects.get("flash_level"), &"full")
		assert_eq(default_effects.get("particle_level"), &"full")
		assert_eq(default_effects.get("damage_number_density"), &"full")
		assert_eq(default_effects.get("rule_information_visible"), true)

	var reduced := SettingsSnapshot.new()
	reduced.reduced_motion = true
	reduced.reduced_flash = true
	reduced.reduced_particles = true
	for density: StringName in [&"off", &"reduced", &"full"]:
		reduced.damage_number_density = density
		var policy: Variant = tokens.call(&"effects_for", reduced)
		assert_true(policy is Dictionary)
		if not policy is Dictionary:
			continue
		assert_eq(policy.get("motion_level"), &"reduced")
		assert_eq(policy.get("flash_level"), &"reduced")
		assert_eq(policy.get("particle_level"), &"reduced")
		assert_eq(policy.get("damage_number_density"), density)
		assert_eq(
			policy.get("rule_information_visible"),
			true,
			"reduced effects must not hide rules"
		)

	assert_true(bool(tokens.call(&"tooltip_depth_allowed", 0)))
	assert_true(bool(tokens.call(&"tooltip_depth_allowed", 1)))
	assert_true(bool(tokens.call(&"tooltip_depth_allowed", 2)))
	assert_false(bool(tokens.call(&"tooltip_depth_allowed", 3)))
	assert_false(bool(tokens.call(&"tooltip_depth_allowed", -1)))
