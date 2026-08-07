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
	assert_eq(theme.default_font.resource_path, "res://assets/fonts/noto-sans-tc/NotoSansTC-wght.ttf")
	assert_eq(theme.default_font_size, 18)
	for token: StringName in PALETTE_TOKENS:
		assert_true(theme.has_color(token, &"ExpeditionPalette"), "missing %s" % token)
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
	for region: StringName in [
		ProductionLayoutShell.REGION_TOP,
		ProductionLayoutShell.REGION_LEFT,
		ProductionLayoutShell.REGION_CENTER,
		ProductionLayoutShell.REGION_RIGHT,
		ProductionLayoutShell.REGION_BOTTOM,
		ProductionLayoutShell.REGION_STATUS,
	]:
		var rect := ProductionLayoutShell.region_rect(region)
		assert_true(safe.encloses(rect), "%s must stay in the 1280x720 UI canvas" % region)
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
