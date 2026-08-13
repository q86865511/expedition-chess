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
	assert_eq(theme.default_font_size, 27)
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
	assert_eq(theme.get_font_size(&"title", &"ExpeditionTypeScale"), 48)
	assert_eq(theme.get_font_size(&"heading", &"ExpeditionTypeScale"), 36)
	assert_eq(theme.get_font_size(&"body", &"ExpeditionTypeScale"), 27)
	assert_eq(theme.get_font_size(&"auxiliary", &"ExpeditionTypeScale"), 24)
	assert_eq(theme.get_constant(&"safe_margin", &"ExpeditionSpacing"), 36)
	assert_eq(theme.get_constant(&"gutter", &"ExpeditionSpacing"), 24)
	assert_eq(
		theme.get_constant(&"min_button_height", &"ExpeditionSpacing"),
		72
	)
	assert_not_null(theme.get_stylebox(&"panel", &"ExpeditionPanel"))
	assert_not_null(theme.get_stylebox(&"focus", &"Button"))


func test_shop_cost_tiers_have_five_distinct_authored_border_variations() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return
	var border_colors := PackedStringArray()
	for tier: int in range(1, 6):
		var variation := StringName("ExpeditionShopCardTier%d" % tier)
		var style := theme.get_stylebox(&"normal", variation) as StyleBoxFlat
		assert_not_null(style, "missing authored shop cost tier %d" % tier)
		if style == null:
			continue
		assert_eq(style.border_width_top, 3)
		border_colors.append(style.border_color.to_html(false))
	assert_eq(border_colors.size(), 5)
	var unique_colors: Dictionary = {}
	for color: String in border_colors:
		unique_colors[color] = true
	assert_eq(
		unique_colors.size(),
		5,
		"tiers 1..5 must not collapse to the same color treatment"
	)


func test_compact_action_bar_reuses_panel_texture_with_small_vertical_margin() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return
	var regular := theme.get_stylebox(
		&"panel", &"ExpeditionActionBar"
	) as StyleBoxTexture
	var compact := theme.get_stylebox(
		&"panel", &"ExpeditionActionBarCompact"
	) as StyleBoxTexture
	assert_not_null(regular)
	assert_not_null(compact)
	if regular == null or compact == null:
		return
	assert_eq(compact.texture, regular.texture)
	assert_eq(compact.get_content_margin(SIDE_LEFT), 24.0)
	assert_eq(compact.get_content_margin(SIDE_TOP), 6.0)
	assert_eq(compact.get_content_margin(SIDE_RIGHT), 24.0)
	assert_eq(compact.get_content_margin(SIDE_BOTTOM), 6.0)

	var host := Control.new()
	autofree(host)
	assert_true(ExpeditionThemeRuntime.new().apply(host, 150))
	var scaled := host.theme.get_stylebox(
		&"panel", &"ExpeditionActionBarCompact"
	) as StyleBoxTexture
	assert_not_null(scaled)
	if scaled != null:
		assert_eq(scaled.get_content_margin(SIDE_TOP), 9.0)
		assert_eq(scaled.get_content_margin(SIDE_BOTTOM), 9.0)


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
				"%s/%s must stay in the 1920x1080 UI canvas" % [bottom_height, region]
			)
			assert_gt(rect.size.x, 0.0)
			assert_gt(rect.size.y, 0.0)


func test_b1_layout_constants_match_the_1920_reference() -> void:
	assert_eq(ProductionLayoutShell.REFERENCE_SIZE, Vector2(1920, 1080))
	assert_eq(ProductionLayoutShell.SAFE_MARGIN, 36.0)
	assert_eq(ProductionLayoutShell.GUTTER, 24.0)
	assert_eq(ProductionLayoutShell.TOP_HEIGHT, 126.0)
	assert_eq(ProductionLayoutShell.BOTTOM_HEIGHT, 204.0)
	assert_eq(ProductionLayoutShell.PREPARE_BOTTOM_HEIGHT, 210.0)
	assert_eq(ProductionLayoutShell.SIDE_WIDTH, 420.0)
	assert_eq(ProductionLayoutShell.STATUS_HEIGHT, 66.0)
	assert_eq(ProductionLayoutShell.STATUS_GUTTER, 12.0)
	assert_eq(ProductionLayoutShell.PANEL_CONTENT_MARGIN, Vector2(24, 18))
	assert_eq(ProductionLayoutShell.TITLE_INSET, 12.0)
	assert_eq(ProductionLayoutShell.TITLE_WIDTH, 450.0)


func test_layout_metrics_accept_explicit_1920_reference_values() -> void:
	var control := Control.new()
	autofree(control)
	ExpeditionLayoutMetrics.set_min(control, 270.0, 72.0)
	assert_eq(control.custom_minimum_size, Vector2(270, 72))
	assert_eq(
		control.get_meta(ExpeditionLayoutMetrics.META_BASE_MINIMUM),
		Vector2(270, 72)
	)


func test_runtime_scaling_is_centralized_on_a_theme_copy() -> void:
	var host := Control.new()
	autofree(host)
	var runtime := ExpeditionThemeRuntime.new()
	assert_true(runtime.apply(host, 150))
	assert_not_null(host.theme)
	assert_eq(host.theme.default_font_size, 41)
	assert_eq(host.theme.get_font_size(&"font_size", &"ExpeditionTitle"), 72)
	assert_eq(host.get_meta(&"effective_theme_scale_percent"), 150)


func test_scale_rebuild_does_not_capture_scaled_combined_minimum() -> void:
	var base_theme := load(THEME_PATH) as Theme
	var recorded_100 := Button.new()
	autofree(recorded_100)
	recorded_100.text = "開始遊戲"
	recorded_100.theme = base_theme
	var recorded_100_minimum := recorded_100.get_combined_minimum_size()
	recorded_100_minimum.y = maxf(recorded_100_minimum.y, 72.0)
	assert_gt(recorded_100_minimum.x, 8.0)
	var host := Control.new()
	autofree(host)
	var runtime := ExpeditionThemeRuntime.new()
	assert_true(runtime.apply(host, 150))
	var rebuilt_button := Button.new()
	ExpeditionLayoutMetrics.set_min(rebuilt_button, 270.0, 72.0)
	host.add_child(rebuilt_button)
	assert_true(runtime.apply(host, 150))
	# B1R3 契約：寬度屬版面欄位預算（reference 空間不縮），高度 ×factor。
	assert_eq(rebuilt_button.custom_minimum_size, Vector2(270.0, 108.0))
	assert_true(runtime.apply(host, 100))
	assert_eq(
		rebuilt_button.custom_minimum_size,
		Vector2(270.0, 72.0),
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
		recorded_100_minimum.x,
		"width floors stay in reference space; only heights scale"
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
	# B1R3 P11：只禁止「ViewportCoordinator 節點區塊」帶 node_paths
	#（原始違規情境：相對路徑賦值被 Godot 4.7 靜默丟棄）；其他節點日後
	# 合法使用 node_paths 不在此限。
	for block: String in scene_source.split("[node"):
		if (
			block.contains("ViewportCoordinator")
			and block.contains("node_paths=PackedStringArray")
		):
			assert_true(
				false,
				"Godot 4.7 silently discards the coordinator's relative scene assignments"
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
