extends GutTest

const Support := preload(
	"res://tests/integration/"
	+ "presentation_ui_r13_accessibility_production/"
	+ "r13_accessibility_production_test_support.gd"
)

const EFFECT_CASES: Array[Dictionary] = [
	{
		"field": &"reduced_motion",
		"node": &"motion",
		"report": &"motion_effects_enabled",
	},
	{
		"field": &"reduced_flash",
		"node": &"flash",
		"report": &"flash_effects_enabled",
	},
	{
		"field": &"reduced_particles",
		"node": &"particles",
		"report": &"particle_effects_enabled",
	},
]


func test_committed_reduced_flags_drive_distinct_production_effect_hosts() -> void:
	var root := Support.instantiate_run_combat(self)
	if root == null:
		return
	var nodes_complete := Support.require_runtime_nodes(self, root)
	var consumer := Support.load_consumer(self, root)
	var coordinator := Support.coordinator(self, consumer)
	if consumer == null or coordinator == null:
		return
	assert_true(
		consumer.has_method(&"runtime_accessibility_report"),
		"production consumer must expose concrete runtime evidence"
	)
	if not nodes_complete \
		or not consumer.has_method(&"runtime_accessibility_report"):
		return

	for effect_case: Dictionary in EFFECT_CASES:
		var candidate := SettingsSnapshot.new()
		candidate.set(effect_case["field"], true)
		var applied := coordinator.apply(candidate)
		assert_true(
			applied.ok,
			"committed setting must activate through SettingsApplicationCoordinator"
		)
		assert_true(applied.committed)
		if not applied.ok:
			continue
		var report := consumer.call(
			&"runtime_accessibility_report"
		) as AccessibilityRuntimeReport
		assert_not_null(report, String(effect_case["field"]))
		if report == null:
			continue
		assert_true(report.ok, report.error)
		assert_false(
			_effect_is_enabled(report, effect_case["report"]),
			"%s must disable only its production effect host"
			% effect_case["field"]
		)
		for other_case: Dictionary in EFFECT_CASES:
			if other_case["report"] != effect_case["report"]:
				assert_true(
					_effect_is_enabled(report, other_case["report"])
				)
		var effect_node := root.get_node(
			Support.NODE_PATHS[effect_case["node"]]
		) as CanvasItem
		assert_false(effect_node.visible)
		if effect_node is CPUParticles2D:
			assert_false((effect_node as CPUParticles2D).emitting)
		assert_true(
			(root.get_node(Support.NODE_PATHS[&"rules"]) as CanvasItem).visible,
			"reduced effects must preserve readable rule information"
		)
		var independent_clone := consumer.call(
			&"runtime_accessibility_report"
		) as AccessibilityRuntimeReport
		assert_not_null(independent_clone)
		if independent_clone == null:
			continue
		assert_ne(
			report,
			independent_clone,
			"public runtime report must be clone-only"
		)
		report.capabilities.clear()
		var read_back_clone := consumer.call(
			&"runtime_accessibility_report"
		) as AccessibilityRuntimeReport
		assert_not_null(read_back_clone)
		if read_back_clone == null:
			continue
		assert_eq(
			read_back_clone.capabilities.size(),
			6,
			"caller mutation must not reach production runtime evidence"
		)


func test_committed_density_controls_real_production_damage_emitters() -> void:
	var root := Support.instantiate_run_combat(self)
	if root == null:
		return
	var nodes_complete := Support.require_runtime_nodes(self, root)
	var consumer := Support.load_consumer(self, root)
	var coordinator := Support.coordinator(self, consumer)
	if consumer == null or coordinator == null:
		return
	if not nodes_complete \
		or not consumer.has_method(&"runtime_accessibility_report"):
		assert_true(
			consumer.has_method(&"runtime_accessibility_report"),
			"production consumer must expose density evidence"
		)
		return

	var visible_by_density: Dictionary = {}
	var budget_by_density: Dictionary = {}
	for density: StringName in [&"off", &"reduced", &"full"]:
		var candidate := SettingsSnapshot.new()
		candidate.damage_number_density = density
		var applied := coordinator.apply(candidate)
		assert_true(applied.ok, "density %s must commit" % density)
		if not applied.ok:
			continue
		var report := consumer.call(
			&"runtime_accessibility_report"
		) as AccessibilityRuntimeReport
		assert_not_null(report, String(density))
		if report == null:
			continue
		assert_true(report.ok, report.error)
		assert_eq(report.damage_number_density, density)
		visible_by_density[density] = report.visible_damage_samples
		budget_by_density[density] = report.damage_event_budget

	assert_eq(visible_by_density.get(&"off"), 0)
	assert_gt(int(visible_by_density.get(&"reduced", -1)), 0)
	assert_gt(
		int(visible_by_density.get(&"full", -1)),
		int(visible_by_density.get(&"reduced", -1))
	)
	assert_eq(budget_by_density.get(&"off"), 0)
	assert_gt(int(budget_by_density.get(&"reduced", -1)), 0)
	assert_gt(
		int(budget_by_density.get(&"full", -1)),
		int(budget_by_density.get(&"reduced", -1))
	)


func _effect_is_enabled(
	report: AccessibilityRuntimeReport,
	field: StringName
) -> bool:
	match field:
		&"motion_effects_enabled":
			return report.motion_effects_enabled
		&"flash_effects_enabled":
			return report.flash_effects_enabled
		&"particle_effects_enabled":
			return report.particle_effects_enabled
	return false
