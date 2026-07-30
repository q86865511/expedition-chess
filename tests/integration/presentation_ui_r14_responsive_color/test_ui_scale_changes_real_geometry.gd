extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_responsive_color/"
	+ "r14_responsive_color_test_support.gd"
)


func test_ui_100_125_150_change_meaningful_production_geometry() -> void:
	var signatures: Dictionary[int, String] = {}
	for percent: int in [100, 125, 150]:
		var screen := Support.instantiate_combat(self, Vector2(1280, 720))
		if screen == null:
			return
		var snapshot := SettingsSnapshot.new()
		snapshot.ui_scale_percent = percent
		Support.activate(self, Support.consumer(screen), snapshot)
		signatures[percent] = Support.visual_signature(screen)
		var runtime := Support.accessibility_runtime(screen)
		assert_not_null(runtime)
		if runtime != null:
			assert_eq(
				int(runtime.get_meta(&"effective_ui_scale_percent", -1)),
				percent,
				"runtime must report the scale actually applied to visible nodes"
			)
	assert_ne(signatures[100], signatures[125])
	assert_ne(signatures[125], signatures[150])
	assert_ne(signatures[100], signatures[150])


func test_scaled_layout_remains_inside_4_3_safe_area() -> void:
	var safe_size := Vector2(1024, 768)
	for percent: int in [100, 125, 150]:
		var screen := Support.instantiate_combat(self, safe_size)
		if screen == null:
			return
		var snapshot := SettingsSnapshot.new()
		snapshot.ui_scale_percent = percent
		Support.activate(self, Support.consumer(screen), snapshot)
		var runtime := Support.accessibility_runtime(screen)
		for node_path: NodePath in [
			^"StateSummary",
			^"DamageEvents",
			^"CjkBody",
		]:
			assert_true(
				Support.rect_inside(
					runtime.get_node_or_null(node_path) as Control,
					safe_size
				),
				"%s clips at ui%d" % [node_path, percent]
			)
