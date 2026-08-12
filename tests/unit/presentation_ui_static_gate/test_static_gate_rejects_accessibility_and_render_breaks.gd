extends GutTest

const Candidate := preload(
	"res://tests/unit/presentation_ui_static_gate/fixtures/minimal_static_gate_candidate.gd"
)
const Support := preload(
	"res://tests/unit/presentation_ui_static_gate/static_gate_test_support.gd"
)


func test_unreachable_required_focus_action_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	var focus_graphs: Array = candidate["focus_graphs"]
	var menu_graph: Dictionary = focus_graphs[0]
	menu_graph["required_actions"] = PackedStringArray([
		"start",
		"settings",
		"exit",
		"hidden_confirm",
	])

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_FOCUS_GRAPH_INVALID")


func test_missing_system_menu_focus_trap_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	var contract: Dictionary = candidate["system_menu_contract"]
	contract["focus_trap"] = false

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_FOCUS_GRAPH_INVALID")


func test_resident_run_menu_contract_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	var contract: Dictionary = candidate["system_menu_contract"]
	contract["no_resident_run_menu"] = false

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_FOCUS_GRAPH_INVALID")


func test_wrong_world_viewport_contract_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	var policy: Dictionary = candidate["render_policy"]
	policy["world_size"] = Vector2i(800, 450)
	policy["integer_scale"] = false

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_VIEWPORT_POLICY_INVALID")


func test_legacy_1280_ui_reference_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	var policy: Dictionary = candidate["render_policy"]
	policy["ui_reference_size"] = Vector2i(1280, 720)

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_VIEWPORT_POLICY_INVALID")


func test_non_nearest_world_filter_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	var policy: Dictionary = candidate["render_policy"]
	policy["world_texture_filter"] = "linear"

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_FILTER_POLICY_INVALID")


func test_missing_required_theme_tokens_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	var theme: Dictionary = candidate["theme_policy"]
	theme["ui_scale_tokens"] = PackedFloat32Array([1.0, 1.25])
	theme["non_color_cues"] = false

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_THEME_TOKEN_INVALID")


func test_direct_custom_minimum_size_assignment_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	var sources: Dictionary = candidate["sources"]
	sources["res://presentation/screens/direct_layout_break.gd"] = (
		"extends Control\n"
		+ "func resize(control: Control) -> void:\n"
		+ "\tcontrol.custom_minimum_size = Vector2(20.0, 20.0)\n"
	)

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(
		self, report, &"PUI_LAYOUT_METRIC_ASSIGNMENT"
	)


func test_layout_assignment_scanner_ignores_comments_strings_and_only_allows_helper() -> void:
	var candidate := Candidate.build()
	var sources: Dictionary = candidate["sources"]
	sources["res://presentation/screens/layout_scanner_fixture.gd"] = (
		"extends Control\n"
		+ "# control.custom_minimum_size = Vector2.ONE\n"
		+ "const NOTE := \"control.custom_minimum_size = Vector2.ONE\"\n"
		+ "const MULTILINE := '''custom_minimum_size = Vector2.ONE'''\n"
		+ "func read(control: Control) -> Vector2:\n"
		+ "\treturn control.custom_minimum_size\n"
	)
	sources[
		"res://presentation/theme/expedition_layout_metrics.gd"
	] = (
		"extends RefCounted\n"
		+ "static func apply(control: Control) -> void:\n"
		+ "\tcontrol.custom_minimum_size = Vector2.ONE\n"
	)

	Support.assert_clean(self, Support.validate(self, candidate))
