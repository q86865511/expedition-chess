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
