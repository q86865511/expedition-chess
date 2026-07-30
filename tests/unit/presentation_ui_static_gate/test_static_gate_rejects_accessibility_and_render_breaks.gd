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


func test_wrong_world_viewport_contract_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	var policy: Dictionary = candidate["render_policy"]
	policy["world_size"] = Vector2i(800, 450)
	policy["integer_scale"] = false

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
