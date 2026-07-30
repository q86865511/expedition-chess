extends GutTest

const Support := preload(
	"res://tests/integration/presentation_ui_r12_accessibility/"
	+ "r12_accessibility_test_support.gd"
)

const EFFECT_CASES: Array[Dictionary] = [
	{
		"setting": &"reduced_motion",
		"report_flag": &"motion_effects_enabled",
		"node": ^"MotionProbe",
	},
	{
		"setting": &"reduced_flash",
		"report_flag": &"flash_effects_enabled",
		"node": ^"FlashProbe",
	},
	{
		"setting": &"reduced_particles",
		"report_flag": &"particle_effects_enabled",
		"node": ^"ParticleProbe",
	},
]


func test_each_reduced_toggle_changes_its_runtime_effect_only_and_keeps_rules() -> void:
	var renderer: Variant = _renderer()
	var fixture := Support.instantiate_fixture(self)
	if renderer == null or fixture == null:
		return
	if not Support.require_methods(
		self,
		renderer,
		[&"apply_settings", &"runtime_effect_report"],
		"R12-B02 accessibility runtime effects"
	):
		return

	var baseline := SettingsSnapshot.new()
	assert_true(Support.ok(renderer.call(&"apply_settings", fixture, baseline)))
	var baseline_report: Variant = renderer.call(&"runtime_effect_report", fixture)
	assert_true(Support.ok(baseline_report))
	if not Support.ok(baseline_report):
		return
	for flag: StringName in [
		&"motion_effects_enabled",
		&"flash_effects_enabled",
		&"particle_effects_enabled",
	]:
		assert_true(bool(baseline_report.get(flag, false)), String(flag))
	assert_true(bool(baseline_report.get("rule_information_visible", false)))

	for effect_case: Dictionary in EFFECT_CASES:
		var candidate := SettingsSnapshot.new()
		candidate.set(effect_case["setting"], true)
		var applied: Variant = renderer.call(
			&"apply_settings",
			fixture,
			candidate
		)
		assert_true(Support.ok(applied), String(effect_case["setting"]))
		var report: Variant = renderer.call(&"runtime_effect_report", fixture)
		assert_true(Support.ok(report))
		if not Support.ok(report):
			continue
		assert_false(
			bool(report.get(effect_case["report_flag"], true)),
			"%s must change its production runtime flag" % effect_case["setting"]
		)
		for other_case: Dictionary in EFFECT_CASES:
			if other_case["report_flag"] != effect_case["report_flag"]:
				assert_true(bool(report.get(other_case["report_flag"], false)))
		assert_true(
			bool(report.get("rule_information_visible", false)),
			"reduced effects must never hide rule information"
		)
		var probe := fixture.get_node(effect_case["node"])
		if probe is CanvasItem:
			assert_false((probe as CanvasItem).visible)
		elif probe is Node:
			assert_eq(
				(probe as Node).process_mode,
				Node.PROCESS_MODE_DISABLED
			)
		assert_true((fixture.get_node(^"RuleInformation") as CanvasItem).visible)


func test_damage_density_has_three_distinct_runtime_event_budgets() -> void:
	var renderer: Variant = _renderer()
	var fixture := Support.instantiate_fixture(self)
	if renderer == null or fixture == null:
		return
	if not Support.require_methods(
		self,
		renderer,
		[&"apply_settings", &"runtime_effect_report"],
		"R12-B02 damage-number density runtime"
	):
		return

	var budgets: Dictionary = {}
	var visible_counts: Dictionary = {}
	for density: StringName in [&"off", &"reduced", &"full"]:
		var candidate := SettingsSnapshot.new()
		candidate.damage_number_density = density
		assert_true(Support.ok(
			renderer.call(&"apply_settings", fixture, candidate)
		))
		var report: Variant = renderer.call(&"runtime_effect_report", fixture)
		assert_true(Support.ok(report), String(density))
		if not Support.ok(report):
			continue
		assert_eq(report.get("damage_number_density"), density)
		assert_true(bool(report.get("rule_information_visible", false)))
		budgets[density] = int(report.get("damage_event_budget", -1))
		visible_counts[density] = int(
			report.get("visible_damage_samples", -1)
		)
		var damage_host := fixture.get_node(^"DamageEvents")
		assert_eq(
			int(damage_host.get_meta(&"event_budget", -1)),
			budgets[density]
		)

	assert_eq(budgets.get(&"off"), 0)
	assert_gt(int(budgets.get(&"reduced", -1)), 0)
	assert_gt(
		int(budgets.get(&"full", -1)),
		int(budgets.get(&"reduced", -1))
	)
	assert_eq(visible_counts.get(&"off"), 0)
	assert_gt(int(visible_counts.get(&"reduced", -1)), 0)
	assert_gt(
		int(visible_counts.get(&"full", -1)),
		int(visible_counts.get(&"reduced", -1))
	)


func _renderer() -> Variant:
	var script := Support.load_script(
		self,
		Support.RENDERER_PATH,
		"R12-B02 accessibility runtime renderer"
	)
	return script.new() if script != null else null
