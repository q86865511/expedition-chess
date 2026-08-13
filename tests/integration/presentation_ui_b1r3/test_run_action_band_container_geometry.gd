extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_functional_controls/"
	+ "r14_functional_controls_test_support.gd"
)

const REFERENCE_SIZE := Vector2(1920.0, 1080.0)
const SCALES: Array[int] = [100, 125, 150]


func test_map_and_reward_actions_are_enclosed_by_bottom_content_at_all_scales() -> void:
	for route_kind: StringName in [&"RUN_MAP", &"RUN_REWARD"]:
		var screen := _run_screen(route_kind)
		assert_not_null(screen, "%s must compose" % String(route_kind))
		if screen == null:
			continue
		var runtime := ExpeditionThemeRuntime.new()
		for scale_percent: int in SCALES:
			assert_true(
				runtime.apply(screen, scale_percent),
				"%s@ui%d theme must apply" % [route_kind, scale_percent]
			)
			screen.apply_theme_scale_layout(scale_percent)
			await wait_process_frames(4)
			_assert_actions_enclosed(screen, route_kind, scale_percent)


func test_service_dismantle_keeps_full_accessible_copy_with_compact_visual_key() -> void:
	var screen := _run_screen(&"RUN_PREPARE")
	assert_not_null(screen, "RUN_PREPARE must compose")
	if screen == null:
		return
	var runtime := ExpeditionThemeRuntime.new()
	for scale_percent: int in SCALES:
		assert_true(runtime.apply(screen, scale_percent))
		screen.apply_theme_scale_layout(scale_percent)
		for locale_fixture: Dictionary in [
			{
				"locale": &"zh_TW",
				"visual": "拆解所選裝備",
				"full": "拆解所選裝備（節點服務）",
			},
			{
				"locale": &"en",
				"visual": "Dismantle Selected Equipment",
				"full": "Dismantle Selected Equipment (Node Service)",
			},
		]:
			screen.relocalize(
				StringName(locale_fixture["locale"]),
				{
					&"prepare.dismantle": String(locale_fixture["visual"]),
					&"service.dismantle": String(locale_fixture["full"]),
				}
			)
			await wait_process_frames(3)
			var button := Support.button(
				self, screen, &"service.dismantle"
			)
			assert_not_null(button)
			if button == null:
				continue
			assert_eq(
				StringName(button.get_meta(&"action_id")),
				&"service.dismantle"
			)
			assert_eq(
				StringName(button.get_meta(&"visual_localization_key")),
				&"prepare.dismantle"
			)
			assert_eq(button.text, String(locale_fixture["visual"]))
			assert_eq(button.tooltip_text, String(locale_fixture["full"]))
			assert_eq(
				String(button.get_meta(&"accessible_text")),
				String(locale_fixture["full"])
			)
			_assert_visible_text_fits(button, scale_percent)


func _run_screen(route_kind: StringName) -> ProductionScreen:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot: RunPresentationSnapshot
	match route_kind:
		&"RUN_MAP":
			snapshot = RunPresentationSnapshot.new()
			snapshot.run_id = &"run.b1r3.map.actions"
			snapshot.app_phase = &"MAP"
			snapshot.manifest_digest = "manifest.b1r3.map.actions"
		&"RUN_REWARD":
			snapshot = Support.CompositionSupport.reward_snapshot(
				PendingRewardState.Phase.CHOOSING
			)
		&"RUN_PREPARE":
			snapshot = Support.CompositionSupport.prepare_snapshot()
		_:
			return null
	session.current_snapshot = snapshot
	var screen := Support.live_run_screen(
		self, route_kind, snapshot, session
	)
	if screen != null:
		# ProductionScreen scenes use full-rect anchors under the real viewport.
		# This isolated fixture assigns an explicit reference rect, so normalize
		# anchors first; assigning `size` while opposite anchors differ emits an
		# engine warning (correctly treated as a test failure by GUT).
		screen.anchor_left = 0.0
		screen.anchor_top = 0.0
		screen.anchor_right = 0.0
		screen.anchor_bottom = 0.0
		screen.position = Vector2.ZERO
		screen.size = REFERENCE_SIZE
	return screen


func _assert_actions_enclosed(
	screen: ProductionScreen,
	route_kind: StringName,
	scale_percent: int
) -> void:
	var bottom := screen.layout_content(
		ProductionLayoutShell.REGION_BOTTOM
	)
	var actions := screen.find_child("Actions", true, false) as Control
	assert_not_null(bottom)
	assert_not_null(actions)
	if bottom == null or actions == null:
		return
	assert_eq(
		actions.get_parent(),
		bottom,
		"%s@ui%d Actions geometry must be container-owned" % [
			route_kind, scale_percent,
		]
	)
	assert_eq(
		bottom.get_child_count(),
		1,
		"%s@ui%d Bottom Content must have one expanding child" % [
			route_kind, scale_percent,
		]
	)
	var bottom_rect := bottom.get_global_rect()
	var actions_rect := actions.get_global_rect()
	assert_true(actions_rect.size.x > 0.0 and actions_rect.size.y > 0.0)
	assert_true(
		bottom_rect.encloses(actions_rect),
		"%s@ui%d Actions %s must be enclosed by Bottom Content %s" % [
			route_kind, scale_percent, actions_rect, bottom_rect,
		]
	)


func _assert_visible_text_fits(button: Button, scale_percent: int) -> void:
	var font := button.get_theme_font(&"font")
	var font_size := button.get_theme_font_size(&"font_size")
	var text_width := font.get_string_size(
		button.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	).x
	var style := button.get_theme_stylebox(&"normal")
	var combined_width := text_width
	if style != null:
		combined_width += (
			style.get_content_margin(SIDE_LEFT)
			+ style.get_content_margin(SIDE_RIGHT)
		)
	assert_true(
		combined_width <= button.get_global_rect().size.x + 0.5,
		"ui%d service.dismantle visual text needs %.1fpx but has %.1fpx" % [
			scale_percent,
			combined_width,
			button.get_global_rect().size.x,
		]
	)
