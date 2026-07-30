extends RefCounted

const RUN_COMBAT_SCENE_PATH := "res://scenes/production/run_combat.tscn"
const SCREEN_SCRIPT_PATH := "res://presentation/screens/run_combat_screen.gd"
const CONSUMER_PATH := (
	"res://services/settings/adapters/"
	+ "presentation_settings_runtime_consumer.gd"
)
const RUNNER_PATH := (
	"res://tests/runners/"
	+ "presentation_r13_accessibility_production_runner.gd"
)
const STATIC_GATE_PATH := "res://tools/presentation_ui_static_gate.gd"
const REQUIRED_ZH_TW_TEXT := "戰鬥規則：護盾破裂後，敵方會進入第二階段。"
const ACCESSIBILITY_HOST_PATH := ^"AccessibilityRuntime"
const NODE_PATHS: Dictionary = {
	&"motion": ^"AccessibilityRuntime/MotionProbe",
	&"flash": ^"AccessibilityRuntime/FlashProbe",
	&"particles": ^"AccessibilityRuntime/ParticleProbe",
	&"rules": ^"AccessibilityRuntime/RuleInformation",
	&"damage": ^"AccessibilityRuntime/DamageEvents",
	&"tooltip_1": ^"AccessibilityRuntime/TooltipStack/TooltipDepth1",
	&"tooltip_2": ^"AccessibilityRuntime/TooltipStack/TooltipDepth2",
	&"tooltip_3": ^"AccessibilityRuntime/TooltipStack/TooltipDepth3",
	&"cjk": ^"AccessibilityRuntime/CjkBody",
}


class FakeRepository:
	extends RefCounted

	var committed: SettingsSnapshot = SettingsSnapshot.new()
	var save_count: int


	func save(snapshot: SettingsSnapshot) -> Dictionary:
		save_count += 1
		committed = snapshot.deep_clone()
		return {
			"ok": true,
			"snapshot": committed.deep_clone(),
		}


	func current_snapshot() -> SettingsSnapshot:
		return committed.deep_clone()


class NoopActivationToken:
	extends RefCounted

	var candidate_digest: String


	func _init(p_candidate_digest: String) -> void:
		candidate_digest = p_candidate_digest


	func activate() -> StringName:
		return &""


class NoopSettingsAdapter:
	extends RefCounted

	func preflight(
		_plan: SettingsSnapshot,
		candidate_digest: String
	) -> Dictionary:
		return {
			"ok": true,
			"token": NoopActivationToken.new(candidate_digest),
		}


	func activate_safe_fallback() -> void:
		pass


	func rebuild_from_committed(_snapshot: SettingsSnapshot) -> void:
		pass


static func instantiate_run_combat(test: GutTest) -> Control:
	var exists := ResourceLoader.exists(RUN_COMBAT_SCENE_PATH, "PackedScene")
	test.assert_true(
		exists,
		"R13-B02 must load the real production RUN_COMBAT scene"
	)
	if not exists:
		return null
	var packed := load(RUN_COMBAT_SCENE_PATH) as PackedScene
	test.assert_not_null(packed)
	if packed == null:
		return null
	var root := test.autofree(packed.instantiate()) as Control
	test.assert_not_null(root)
	if root == null:
		return null
	var composition := root.get_node_or_null(^"Composition")
	var expected_script := load(SCREEN_SCRIPT_PATH) as Script
	test.assert_not_null(composition)
	test.assert_not_null(expected_script)
	if composition != null and expected_script != null:
		test.assert_eq(
			composition.get_script(),
			expected_script,
			"evidence must exercise the production RunCombatScreen composition"
		)
	return root


static func load_consumer(test: GutTest, root: Control) -> Object:
	var script := load(CONSUMER_PATH) as Script
	test.assert_not_null(script, "production settings runtime consumer must load")
	if script == null:
		return null
	var consumer: Object = script.new(root)
	test.assert_not_null(consumer)
	return consumer


static func coordinator(
	test: GutTest,
	consumer: Object
) -> SettingsApplicationCoordinator:
	test.assert_not_null(consumer)
	if consumer == null:
		return null
	var noop := NoopSettingsAdapter.new()
	return SettingsApplicationCoordinator.new(
		FakeRepository.new(),
		ThemeSettingsAdapter.new(consumer),
		noop,
		noop,
		noop
	)


static func require_runtime_nodes(test: GutTest, root: Control) -> bool:
	var complete := true
	for key: StringName in NODE_PATHS:
		var path: NodePath = NODE_PATHS[key]
		var node := root.get_node_or_null(path)
		test.assert_not_null(
			node,
			"production RUN_COMBAT accessibility node missing: %s" % path
		)
		complete = complete and node != null
	if not complete:
		return false
	test.assert_true(
		root.get_node(NODE_PATHS[&"motion"]) is CanvasItem,
		"motion host must be a concrete CanvasItem"
	)
	test.assert_true(
		root.get_node(NODE_PATHS[&"flash"]) is CanvasItem,
		"flash host must be a concrete CanvasItem"
	)
	test.assert_true(
		root.get_node(NODE_PATHS[&"particles"]) is CPUParticles2D,
		"particle host must be a concrete CPUParticles2D emitter"
	)
	test.assert_true(
		root.get_node(NODE_PATHS[&"cjk"]) is Label,
		"CJK host must be a real production Label"
	)
	return true
