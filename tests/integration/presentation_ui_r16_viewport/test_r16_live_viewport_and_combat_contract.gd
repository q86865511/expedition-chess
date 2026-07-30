extends GutTest


func test_main_world_viewport_owns_live_targets_and_receives_pointer_input() -> void:
	var packed := load("res://app/main.tscn") as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var main := packed.instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	var viewport := main.find_child("WorldViewport", true, false) as SubViewport
	var host := main.find_child("ProductionWorld", true, false)
	assert_not_null(viewport)
	assert_not_null(
		host,
		"the 640x360 framebuffer must contain a real production world host"
	)
	if viewport == null or host == null:
		return
	assert_true(viewport.is_ancestor_of(host))
	assert_not_null(host.find_child("BoardTileTarget", true, false))
	assert_not_null(host.find_child("CampHotspotTarget", true, false))
	assert_true(
		host.has_signal(&"target_activated"),
		"world target evidence must come from a real viewport input receiver"
	)
	if not host.has_signal(&"target_activated"):
		return
	var hits: Array[StringName] = []
	host.connect(&"target_activated", func(target_id: StringName) -> void:
		hits.append(target_id)
	)
	var event := InputEventMouseButton.new()
	event.position = Vector2(160.0, 90.0)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	viewport.push_input(event)
	await wait_process_frames(2)
	assert_eq(hits, [&"world.board_tile"])


func test_ui_mapper_matches_the_live_canvas_transform_not_reflow_scale() -> void:
	var layout := WorldViewportPolicy.new().layout_for_window(
		Vector2i(1920, 1080)
	)
	var at_100 := WindowCoordinateMapper.new()
	var at_150 := WindowCoordinateMapper.new()
	assert_eq(at_100.configure(layout, 100), &"")
	assert_eq(at_150.configure(layout, 150), &"")
	var reference_point := Vector2(900.0, 420.0)
	assert_eq(
		at_150.ui_to_screen(reference_point),
		at_100.ui_to_screen(reference_point),
		"UI percentage is reflow inside a fixed CanvasLayer, not a second canvas transform"
	)


## R16 審查缺口 1（2026-07-30 補洞）：上面「matches the live canvas transform」測試只驗
## WindowCoordinateMapper 這個獨立類別,從未實例化 ProductionViewportCoordinator——把
## coordinator.gd :88-93 的 fit_scale 改回再乘一次 UI 百分比(雙重縮放 bug)全測試仍綠。
## 本測試直接組裝真 coordinator 需要的五個子節點(型別與 main.tscn 的
## WorldViewportContainer/WorldViewport/UiLayer/UiRoot/PresentationHost 一致),用
## 「UiLayer 實際套用的 CanvasLayer.transform」與「pointer_to_ui() 背後
## WindowCoordinateMapper 的映射」互相 round-trip 回原始視窗座標,確保兩者對同一次
## synchronize() 用的是同一個 fit_scale——這是唯一能同時涵蓋 coordinator 自己那段
## 重複運算與 mapper 運算的斷言方式。
func test_ui_layer_transform_round_trips_pointer_to_ui_without_double_scaling_at_125_and_150_percent() -> void:
	var coordinator := ProductionViewportCoordinator.new()
	var world_container := SubViewportContainer.new()
	var world_viewport := SubViewport.new()
	var ui_layer := CanvasLayer.new()
	var ui_root := Control.new()
	var presentation_host := Control.new()
	coordinator.add_child(world_container)
	coordinator.add_child(world_viewport)
	coordinator.add_child(ui_layer)
	coordinator.add_child(ui_root)
	coordinator.add_child(presentation_host)
	coordinator.world_container_path = coordinator.get_path_to(world_container)
	coordinator.world_viewport_path = coordinator.get_path_to(world_viewport)
	coordinator.ui_layer_path = coordinator.get_path_to(ui_layer)
	coordinator.ui_root_path = coordinator.get_path_to(ui_root)
	coordinator.presentation_host_path = coordinator.get_path_to(presentation_host)
	add_child_autofree(coordinator)
	await wait_process_frames(2)

	var window_size := Vector2i(1920, 1080)
	for scale_percent: int in [125, 150]:
		assert_eq(coordinator.apply_ui_scale(scale_percent), &"")
		# apply_ui_scale() re-syncs against the real (headless-runner) visible rect,
		# which is out of this test's control; re-run with a fixed window size so the
		# assertion below is deterministic while still exercising the real
		# synchronize()/pointer_to_ui() code path at the just-applied UI scale.
		assert_eq(coordinator.synchronize(window_size), &"")
		# The window's own bottom-right corner is never at the letterbox origin,
		# so a stray "* ui_scale_percent / 100.0" factor on either side of the
		# round trip cannot cancel out by coincidence.
		var window_point := Vector2(window_size)
		var ui_point := coordinator.pointer_to_ui(window_point)
		var round_tripped: Vector2 = ui_layer.transform * ui_point
		assert_true(
			round_tripped.is_equal_approx(window_point),
			(
				"at %d%% UI scale the live CanvasLayer transform (%s) must invert " +
				"pointer_to_ui()'s mapping (%s -> %s) exactly, not be scaled again by " +
				"the UI percent"
			) % [scale_percent, ui_layer.transform, window_point, ui_point]
		)


func test_combat_accessibility_runtime_does_not_cover_or_intercept_typed_controls() -> void:
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_COMBAT")
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)
	var composition := screen.get_node_or_null(^"Composition") as Control
	var runtime := screen.get_node_or_null(^"AccessibilityRuntime") as Control
	var background := screen.get_node_or_null(
		^"AccessibilityRuntime/Background"
	) as ColorRect
	assert_not_null(composition)
	assert_not_null(runtime)
	assert_not_null(background)
	if composition == null or runtime == null or background == null:
		return
	assert_eq(
		runtime.mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"QA probes must pass pointer input through to typed combat controls"
	)
	assert_false(
		background.visible,
		"the probe background must not paint over UnitSelector/InspectionPanel"
	)
	assert_gt(
		composition.z_index,
		runtime.z_index,
		"typed combat composition must be visually above the QA probe layer"
	)


func test_combat_semantics_bind_damage_events_and_color_mode_without_losing_patterns() -> void:
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_COMBAT")
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)
	var composition := screen.get_node_or_null(^"Composition") as RunCombatScreen
	var runtime := screen.get_node_or_null(
		^"AccessibilityRuntime"
	) as ProductionAccessibilityHost
	assert_not_null(composition)
	assert_not_null(runtime)
	if composition == null or runtime == null:
		return
	assert_true(runtime.has_method(&"render_damage_events"))
	assert_true(composition.has_method(&"apply_color_vision_mode"))
	if (
		not runtime.has_method(&"render_damage_events")
		or not composition.has_method(&"apply_color_vision_mode")
	):
		return
	var payload := DamageEventPayload.new()
	payload.damage_type = &"magic"
	payload.health_damage = 17
	var damage := BattleEvent.new()
	damage.type = &"damage"
	damage.sequence = 4
	damage.target_instance_ids.assign([&"enemy.r16"])
	damage.payload = payload
	runtime.call(&"render_damage_events", [damage])
	var damage_label := runtime.get_node_or_null(
		^"DamageEvents/DamageSample1"
	) as Label
	assert_not_null(damage_label)
	if damage_label == null:
		return
	assert_eq(damage_label.get_meta(&"typed_data_id"), &"damage.magic")
	assert_eq(damage_label.get_meta(&"semantic_pattern"), &"magic-spark")
	assert_true(damage_label.text.contains("17"))

	var semantic := composition.call(
		&"_semantic_label",
		&"enemy",
		&"unit.r16",
		&"cross-hatch"
	) as Label
	composition.add_child(semantic)
	var stable_text := semantic.text
	composition.call(&"apply_color_vision_mode", &"default")
	var default_color := semantic.get_theme_color(&"font_color")
	composition.call(&"apply_color_vision_mode", &"tritanopia")
	assert_ne(semantic.get_theme_color(&"font_color"), default_color)
	assert_eq(semantic.text, stable_text)
	assert_eq(semantic.get_meta(&"semantic_pattern"), &"cross-hatch")
