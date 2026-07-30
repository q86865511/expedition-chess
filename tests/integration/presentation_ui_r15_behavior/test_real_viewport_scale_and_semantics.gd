extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r15_behavior/"
	+ "r15_behavior_test_support.gd"
)
const AccessibilitySupport = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)


func test_main_scene_owns_real_world_viewport_and_ui_reference_layer() -> void:
	var packed := load("res://app/main.tscn") as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var main := packed.instantiate()
	assert_not_null(main)
	if main == null:
		return
	autofree(main)
	var world_container := main.find_child(
		"WorldViewportContainer",
		true,
		false
	) as SubViewportContainer
	var world := main.find_child("WorldViewport", true, false) as SubViewport
	var ui_layer := main.find_child("UiLayer", true, false) as CanvasLayer
	var ui_root := main.find_child("UiRoot", true, false) as Control
	assert_not_null(
		world_container,
		"production tree must own the world texture/input target"
	)
	assert_not_null(world, "production tree must own a real SubViewport")
	assert_not_null(ui_layer, "UI must live in an independent CanvasLayer")
	assert_not_null(ui_root, "CanvasLayer must own a 1280x720 UI root")
	if (
		world_container == null
		or world == null
		or ui_layer == null
		or ui_root == null
	):
		return
	assert_true(world_container.is_ancestor_of(world))
	assert_eq(world.size, Vector2i(640, 360))
	assert_eq(
		world_container.texture_filter,
		CanvasItem.TEXTURE_FILTER_NEAREST
	)
	assert_eq(ui_root.size, Vector2(1280, 720))
	assert_true(ui_layer.is_ancestor_of(ui_root))
	var presentation_host := ui_root.find_child(
		"PresentationHost",
		true,
		false
	) as Control
	assert_not_null(
		presentation_host,
		"SceneRouter must mount formal screens under the scaled UI root"
	)


func test_app_root_ui_scale_changes_real_menu_action_rect_and_font() -> void:
	var harness := AccessibilitySupport.boot(self)
	assert_eq(harness.settings_bind_error, &"")
	assert_true(harness.root.is_booted())
	if not harness.root.is_booted():
		return
	await wait_process_frames(2)
	var menu := AccessibilitySupport.active_screen(harness)
	var start := Support.action_button(menu, &"menu.start")
	assert_not_null(start)
	var port := harness.root.settings_application_port()
	assert_not_null(port)
	if start == null or port == null:
		return
	var at_100 := SettingsSnapshot.new()
	at_100.ui_scale_percent = 100
	assert_true(port.apply(at_100).ok)
	await wait_process_frames(2)
	var rect_100 := start.get_global_rect()
	var font_100 := start.get_theme_font_size(&"font_size")

	var at_150 := at_100.deep_clone()
	at_150.ui_scale_percent = 150
	assert_true(port.apply(at_150).ok)
	await wait_process_frames(2)
	var rect_150 := start.get_global_rect()
	var font_150 := start.get_theme_font_size(&"font_size")
	assert_gt(
		rect_150.size.x,
		rect_100.size.x * 1.4,
		"150% must change the real action hit rect, not host metadata"
	)
	assert_gt(
		rect_150.size.y,
		rect_100.size.y * 1.4,
		"150% must change the real action hit rect, not host metadata"
	)
	assert_gt(
		float(font_150),
		float(font_100) * 1.4,
		"150% must change the real action font"
	)


func test_combat_semantic_cues_are_bound_to_authoritative_typed_data() -> void:
	var session := Support.SpyTypedSession.new()
	session.current_snapshot = Support.CompositionSupport.combat_snapshot()
	var playback := Support.FunctionalSupport.playback_fixture(self)
	var screen := Support.FunctionalSupport.live_run_screen(
		self,
		&"RUN_COMBAT",
		session.snapshot(),
		session,
		playback.get("port") as LiveScreenPlaybackPort
	)
	if screen == null:
		return
	var snapshot := SettingsSnapshot.new()
	snapshot.color_vision_mode = &"deuteranopia"
	snapshot.ui_scale_percent = 150
	var consumer := PresentationSettingsRuntimeConsumer.new(screen)
	assert_eq(consumer.activate(&"theme", snapshot), &"")
	assert_eq(consumer.activate(&"viewport", snapshot), &"")
	await wait_process_frames(2)
	for expected: Dictionary in [
		{
			"semantic": &"enemy",
			"id": &"unit.enemy.alpha",
		},
		{
			"semantic": &"trait",
			"id": &"trait.enemy.arcane",
		},
		{
			"semantic": &"danger",
			"id": &"elite.node",
		},
	]:
		var control := Support.semantic_control(
			screen,
			StringName(expected["semantic"]),
			StringName(expected["id"])
		)
		assert_not_null(
			control,
			"%s cue must be attached to real typed data %s"
			% [expected["semantic"], expected["id"]]
		)
		if control != null:
			assert_true(control.visible)
			assert_false(Support.visible_text(control).strip_edges().is_empty())
			assert_false(
				String(control.get_meta(&"semantic_pattern", "")).is_empty(),
				"non-color meaning must survive every color mode"
			)
