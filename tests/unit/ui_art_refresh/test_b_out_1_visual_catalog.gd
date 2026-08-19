extends GutTest

const MANIFEST_PATH := \
	"res://assets/production/environment/inventory.json"
const THEME_PATH := "res://theme/expedition_theme.tres"


func test_catalog_loads_the_adopted_environment_visuals() -> void:
	var catalog := ProductionEnvironmentVisualCatalog.new()
	assert_eq(catalog.load_error(), &"")
	assert_eq(
		catalog.visual_ids(),
		[&"environment.camp", &"key_art.menu_main", &"environment.run_map"]
	)
	var camp := catalog.try_texture(&"environment.camp")
	var menu := catalog.try_texture(&"key_art.menu_main")
	var run_map := catalog.try_texture(&"environment.run_map")
	assert_not_null(camp)
	assert_not_null(menu)
	assert_not_null(run_map)
	if camp != null:
		assert_eq(camp.get_size(), Vector2(1280.0, 720.0))
	if menu != null:
		assert_eq(menu.get_size(), Vector2(1672.0, 941.0))
	if run_map != null:
		assert_eq(run_map.get_size(), Vector2(1672.0, 941.0))


func test_environment_manifest_paths_and_hashes_match_disk() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(MANIFEST_PATH)
	)
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return
	var visuals: Array = (parsed as Dictionary).get("visuals", [])
	assert_eq(visuals.size(), 3)
	for entry_value: Variant in visuals:
		assert_true(entry_value is Dictionary)
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		assert_eq(String(entry.get("status", "")), "adopted")
		var path := String(entry.get("path", ""))
		var resource_path := path if path.begins_with("res://") else "res://%s" % path
		assert_true(FileAccess.file_exists(resource_path))
		assert_eq(
			FileAccess.get_sha256(resource_path),
			String(entry.get("sha256", ""))
		)


func test_new_theme_variations_keep_the_expedition_prefix() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return
	var type_names := theme.get_type_list()
	for variation: StringName in [
		&"ExpeditionMenuAction",
		&"ExpeditionCampMapFrame",
		&"ExpeditionCampFacilityMarker",
		&"ExpeditionCampMetrics",
		&"ExpeditionCampMetric",
		&"ExpeditionCampExpeditionPanel",
		&"ExpeditionCampCardHeading",
		&"ExpeditionCampCardLabel",
		&"ExpeditionCampCompactChoice",
		&"ExpeditionCampCompactSpinBox",
		&"ExpeditionCampCompactInput",
		&"ExpeditionCampStartAction",
		&"ExpeditionCampSecondaryAction",
	]:
		assert_true(String(variation).begins_with("Expedition"))
		assert_true(
			type_names.has(String(variation)),
			"missing theme variation: %s" % variation
		)
	assert_false(
		type_names.has("ExpeditionMenuPanel"),
		"MENU_MAIN revision must not retain a full-height backing panel"
	)
	assert_not_null(theme.get_stylebox(&"focus", &"ExpeditionMenuAction"))
	var menu_normal := theme.get_stylebox(&"normal", &"ExpeditionMenuAction")
	var menu_hover := theme.get_stylebox(&"hover", &"ExpeditionMenuAction")
	assert_not_null(menu_normal)
	assert_not_null(menu_hover)
	if menu_normal is StyleBoxFlat and menu_hover is StyleBoxFlat:
		assert_ne(
			(menu_normal as StyleBoxFlat).border_width_left,
			(menu_hover as StyleBoxFlat).border_width_left,
			"MENU_MAIN hover must retain a non-color border-width cue"
		)
	assert_eq(
		theme.get_type_variation_base(&"ExpeditionCampFacilityMarker"),
		&"Button"
	)
	assert_not_null(
		theme.get_stylebox(&"focus", &"ExpeditionCampFacilityMarker")
	)
	var marker_normal := theme.get_stylebox(
		&"normal", &"ExpeditionCampFacilityMarker"
	)
	var marker_hover := theme.get_stylebox(
		&"hover", &"ExpeditionCampFacilityMarker"
	)
	assert_not_null(marker_normal)
	assert_not_null(marker_hover)
	if marker_normal is StyleBoxFlat and marker_hover is StyleBoxFlat:
		assert_ne(
			(marker_normal as StyleBoxFlat).border_width_left,
			(marker_hover as StyleBoxFlat).border_width_left,
			"hover must retain a non-color border-width cue"
		)


func test_camp_shell_uses_a_route_local_main_visual_geometry() -> void:
	var camp := ProductionLayoutShell.new()
	camp.build(&"CAMP_WORLD")
	assert_eq(
		camp.current_region_rect(ProductionLayoutShell.REGION_LEFT).size.x,
		0.0
	)
	assert_eq(
		camp.current_region_rect(ProductionLayoutShell.REGION_RIGHT).size.x,
		ProductionLayoutShell.SIDE_WIDTH * 0.5
	)
	assert_gte(
		camp.current_region_rect(ProductionLayoutShell.REGION_CENTER).size.x,
		1200.0
	)
	assert_eq(
		camp.current_region_rect(ProductionLayoutShell.REGION_TOP).size.y,
		ProductionLayoutShell.CAMP_TOP_HEIGHT
	)
	assert_eq(
		camp.current_region_rect(ProductionLayoutShell.REGION_BOTTOM).size.y,
		ProductionLayoutShell.CAMP_BOTTOM_HEIGHT
	)
	var map := ProductionLayoutShell.new()
	map.build(&"RUN_MAP")
	assert_eq(
		map.current_region_rect(ProductionLayoutShell.REGION_RIGHT).size.x,
		ProductionLayoutShell.SIDE_WIDTH
	)
	assert_eq(
		map.current_region_rect(ProductionLayoutShell.REGION_TOP).size.y,
		ProductionLayoutShell.TOP_HEIGHT
	)
	assert_eq(
		map.current_region_rect(ProductionLayoutShell.REGION_BOTTOM).size.y,
		ProductionLayoutShell.BOTTOM_HEIGHT
	)
	camp.free()
	map.free()


func test_read_only_focus_graph_already_names_all_scene_facilities() -> void:
	var order := KeyboardFocusGraph.new().focus_order(&"CAMP_WORLD", 150, [])
	for action_id: StringName in [
		&"camp.expedition_gate",
		&"camp.commander_hall",
		&"camp.collection",
		&"camp.forge",
		&"camp.challenge_monument",
	]:
		assert_has(order, action_id)
