extends GutTest

const THEME_PATH := "res://theme/expedition_theme.tres"
const PALETTE_TOKENS: Array[StringName] = [
	&"navy_950", &"navy_800", &"parchment_300", &"off_white",
	&"amber_500", &"teal_500", &"crimson_500", &"violet_500",
	&"stone_500", &"focus_high",
]


func test_project_uses_single_theme_with_font_tokens_and_focus_style() -> void:
	assert_eq(ProjectSettings.get_setting("gui/theme/custom"), THEME_PATH)
	var theme := load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return
	assert_not_null(theme.default_font)
	assert_true(theme.default_font is FontVariation)
	var variation := theme.default_font as FontVariation
	assert_not_null(variation.base_font)
	assert_eq(
		variation.base_font.resource_path,
		"res://assets/fonts/noto-sans-tc/NotoSansTC-wght.ttf"
	)
	assert_eq(float(variation.variation_opentype.get("wght", 0.0)), 400.0)
	assert_eq(theme.default_font_size, 18)
	for token: StringName in PALETTE_TOKENS:
		assert_true(theme.has_color(token, &"ExpeditionPalette"), "missing %s" % token)
	var palette_data := JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/pilot/palette.json")
	) as Dictionary
	assert_false(palette_data.is_empty())
	var palette_tokens := palette_data.get("tokens", {}) as Dictionary
	for token: StringName in PALETTE_TOKENS:
		assert_eq(
			theme.get_color(token, &"ExpeditionPalette").to_html(false),
			Color.from_string(String(palette_tokens.get(String(token), "")), Color.TRANSPARENT).to_html(false),
			"palette token drift: %s" % token
		)
	assert_eq(theme.get_font_size(&"title", &"ExpeditionTypeScale"), 32)
	assert_eq(theme.get_font_size(&"heading", &"ExpeditionTypeScale"), 24)
	assert_eq(theme.get_font_size(&"body", &"ExpeditionTypeScale"), 18)
	assert_eq(theme.get_font_size(&"auxiliary", &"ExpeditionTypeScale"), 16)
	assert_eq(theme.get_constant(&"safe_margin", &"ExpeditionSpacing"), 24)
	assert_eq(theme.get_constant(&"gutter", &"ExpeditionSpacing"), 16)
	assert_not_null(theme.get_stylebox(&"panel", &"ExpeditionPanel"))
	assert_not_null(theme.get_stylebox(&"focus", &"Button"))


func test_b1_layout_regions_stay_inside_reference_safe_area() -> void:
	var safe := Rect2(Vector2.ZERO, ProductionLayoutShell.REFERENCE_SIZE)
	for bottom_height: float in [
		ProductionLayoutShell.BOTTOM_HEIGHT,
		ProductionLayoutShell.PREPARE_BOTTOM_HEIGHT,
	]:
		for region: StringName in [
			ProductionLayoutShell.REGION_TOP,
			ProductionLayoutShell.REGION_LEFT,
			ProductionLayoutShell.REGION_CENTER,
			ProductionLayoutShell.REGION_RIGHT,
			ProductionLayoutShell.REGION_BOTTOM,
			ProductionLayoutShell.REGION_STATUS,
		]:
			var rect := ProductionLayoutShell.region_rect_for(region, bottom_height)
			assert_true(
				safe.encloses(rect),
				"%s/%s must stay in the 1280x720 UI canvas" % [bottom_height, region]
			)
			assert_gt(rect.size.x, 0.0)
			assert_gt(rect.size.y, 0.0)


func test_runtime_scaling_is_centralized_on_a_theme_copy() -> void:
	var host := Control.new()
	autofree(host)
	var runtime := ExpeditionThemeRuntime.new()
	assert_true(runtime.apply(host, 150))
	assert_not_null(host.theme)
	assert_eq(host.theme.default_font_size, 27)
	assert_eq(host.theme.get_font_size(&"font_size", &"ExpeditionTitle"), 48)
	assert_eq(host.get_meta(&"effective_theme_scale_percent"), 150)


func test_scale_rebuild_does_not_capture_scaled_combined_minimum() -> void:
	var base_theme := load(THEME_PATH) as Theme
	var recorded_100 := Button.new()
	autofree(recorded_100)
	recorded_100.text = "開始遊戲"
	recorded_100.theme = base_theme
	var recorded_100_minimum := recorded_100.get_combined_minimum_size()
	recorded_100_minimum.y = maxf(recorded_100_minimum.y, 48.0)
	assert_gt(recorded_100_minimum.x, 8.0)
	var host := Control.new()
	autofree(host)
	var runtime := ExpeditionThemeRuntime.new()
	assert_true(runtime.apply(host, 150))
	var rebuilt_button := Button.new()
	rebuilt_button.custom_minimum_size = Vector2(180.0, 48.0)
	host.add_child(rebuilt_button)
	assert_true(runtime.apply(host, 150))
	assert_eq(rebuilt_button.custom_minimum_size, Vector2(270.0, 72.0))
	assert_true(runtime.apply(host, 100))
	assert_eq(
		rebuilt_button.custom_minimum_size,
		Vector2(180.0, 48.0),
		"150% -> rebuild -> 100% must return to the authored baseline"
	)
	var inherited_button := Button.new()
	inherited_button.text = "開始遊戲"
	host.add_child(inherited_button)
	assert_true(runtime.apply(host, 150))
	assert_eq(
		inherited_button.get_meta(&"expedition_theme_base_minimum"),
		recorded_100_minimum,
		"the expected baseline must come from an independent 100% control"
	)
	assert_eq(
		inherited_button.custom_minimum_size.x,
		ceilf(recorded_100_minimum.x * 1.5)
	)
	assert_true(runtime.apply(host, 100))
	assert_eq(
		inherited_button.custom_minimum_size,
		recorded_100_minimum,
		"an un-authored child inherited at 150% must not pollute its 100% base"
	)


func test_button_text_contributes_to_combined_minimum_width() -> void:
	var button := Button.new()
	autofree(button)
	button.text = "鍛造所選物品"
	button.theme = load(THEME_PATH) as Theme
	button.clip_text = false
	var text_width := button.get_theme_font(&"font").get_string_size(
		button.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		button.get_theme_font_size(&"font_size")
	).x
	assert_gte(
		button.get_combined_minimum_size().x,
		text_width,
		"clip_text must not collapse an action below its rendered text width"
	)


func test_production_viewport_paths_have_resolving_defaults() -> void:
	var scene_source := FileAccess.get_file_as_string("res://app/main.tscn")
	assert_false(
		scene_source.contains("node_paths=PackedStringArray"),
		"Godot 4.7 silently discards the five relative scene assignments"
	)
	for dead_assignment: String in [
		"world_container_path = NodePath",
		"world_viewport_path = NodePath",
		"ui_layer_path = NodePath",
		"ui_root_path = NodePath",
		"presentation_host_path = NodePath",
	]:
		assert_false(scene_source.contains(dead_assignment))
	var packed := load("res://app/main.tscn") as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var main: Node = autofree(packed.instantiate()) as Node
	var runtime: Node = main.get_node_or_null(^"AppRoot/ViewportCoordinator")
	assert_not_null(runtime)
	if runtime == null:
		return
	for property_name: StringName in [
		&"world_container_path", &"world_viewport_path", &"ui_layer_path",
		&"ui_root_path", &"presentation_host_path",
	]:
		var path: NodePath = runtime.get(property_name)
		assert_false(path.is_empty(), "%s must have a default" % property_name)
		assert_not_null(runtime.get_node_or_null(path), "%s must resolve" % property_name)
