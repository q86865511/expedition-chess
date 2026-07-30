extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_responsive_color/"
	+ "r14_responsive_color_test_support.gd"
)


func test_real_combat_information_stays_inside_1024x768_safe_area() -> void:
	var safe_size := Vector2(1024, 768)
	var screen := Support.instantiate_combat(self, safe_size)
	var runtime := Support.accessibility_runtime(screen)
	assert_not_null(runtime)
	if runtime == null:
		return
	var snapshot := SettingsSnapshot.new()
	snapshot.ui_scale_percent = 100
	Support.activate(self, Support.consumer(screen), snapshot)
	for node_path: NodePath in [
		^"StateSummary",
		^"DamageEvents",
		^"CjkBody",
	]:
		var control := runtime.get_node_or_null(node_path) as Control
		assert_not_null(control, "missing required production node %s" % node_path)
		assert_true(
			Support.rect_inside(control, safe_size),
			"%s must remain fully inside the 4:3 safe area" % node_path
		)


func test_four_three_layout_preserves_non_color_decision_information() -> void:
	var safe_size := Vector2(1024, 768)
	var screen := Support.instantiate_combat(self, safe_size)
	var runtime := Support.accessibility_runtime(screen)
	if runtime == null:
		return
	var snapshot := SettingsSnapshot.new()
	snapshot.color_vision_mode = &"deuteranopia"
	Support.activate(self, Support.consumer(screen), snapshot)
	for node_path: NodePath in [
		^"RuleInformation",
		^"DamageEvents",
		^"TooltipStack",
		^"CjkBody",
	]:
		var control := runtime.get_node_or_null(node_path) as Control
		assert_not_null(control)
		if control != null:
			assert_true(control.visible)
			assert_true(Support.rect_inside(control, safe_size))
