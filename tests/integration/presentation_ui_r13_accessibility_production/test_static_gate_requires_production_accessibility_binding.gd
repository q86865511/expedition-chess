extends GutTest

const Candidate := preload(
	"res://tests/unit/presentation_ui_static_gate/fixtures/"
	+ "minimal_static_gate_candidate.gd"
)
const Support := preload(
	"res://tests/unit/presentation_ui_static_gate/static_gate_test_support.gd"
)


func test_missing_run_combat_accessibility_binding_is_named_and_rejected() -> void:
	var candidate := _candidate_with_binding()
	candidate["accessibility_bindings"] = []

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(
		self,
		report,
		&"PUI_ACCESSIBILITY_BINDING_INVALID"
	)


func test_incomplete_production_accessibility_capabilities_are_rejected() -> void:
	var candidate := _candidate_with_binding()
	var bindings: Array = candidate["accessibility_bindings"]
	var binding: Dictionary = bindings[0]
	binding["capabilities"] = PackedStringArray([
		"motion",
		"flash",
		"particles",
		"density",
		"tooltip",
	])

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(
		self,
		report,
		&"PUI_ACCESSIBILITY_BINDING_INVALID"
	)


func test_complete_run_combat_accessibility_binding_passes_static_gate() -> void:
	var candidate := _candidate_with_binding()

	var report := Support.validate(self, candidate)

	Support.assert_clean(self, report)
	assert_eq(report.get("accessibility_binding_count"), 1)


func _candidate_with_binding() -> Dictionary:
	var candidate := Candidate.build()
	var sources: Dictionary = candidate["sources"]
	sources["res://scenes/production/run_combat.tscn"] = (
		"[gd_scene load_steps=2 format=3]\n"
		+ "[ext_resource path=\"res://presentation/accessibility/"
		+ "production_accessibility_host.gd\" type=\"Script\" id=\"1\"]\n"
		+ "[node name=\"RunCombat\" type=\"Control\"]\n"
		+ "[node name=\"AccessibilityRuntime\" type=\"Control\" parent=\".\"]\n"
		+ "script = ExtResource(\"1\")\n"
	)
	sources[
		"res://presentation/accessibility/production_accessibility_host.gd"
	] = (
		"class_name ProductionAccessibilityHost\n"
		+ "extends Control\n"
		+ "const CAPABILITIES := [\"motion\", \"flash\", \"particles\", "
		+ "\"density\", \"tooltip\", \"cjk\"]\n"
	)
	candidate["accessibility_bindings"] = [
		{
			"scene_path": "res://scenes/production/run_combat.tscn",
			"host_path": "AccessibilityRuntime",
			"consumer": "PresentationSettingsRuntimeConsumer",
			"capabilities": PackedStringArray([
				"motion",
				"flash",
				"particles",
				"density",
				"tooltip",
				"cjk",
			]),
		},
	]
	return candidate
