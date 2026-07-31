extends GutTest

const CONSUMER_PATHS: Array[String] = [
	"res://presentation/screens/run_prepare_screen.gd",
	"res://presentation/screens/run_reward_screen.gd",
	"res://presentation/screens/collection_screen.gd",
	"res://presentation/screens/run_combat_screen.gd",
]


func test_tooltip_formatter_rejects_nesting_beyond_two() -> void:
	var result := ContentTooltipFormatter.new().format_value(
		&"tooltip.cost",
		"Cost",
		3,
		&"en",
		0,
		3
	)
	assert_false(result.ok)
	assert_eq(result.error_code, &"TOOLTIP_DEPTH_EXCEEDED")


func test_formal_screens_consume_snapshot_tooltip_port() -> void:
	var production_source := FileAccess.get_file_as_string(
		"res://presentation/screens/production_screen.gd"
	)
	assert_true(
		production_source.contains("func content_tooltip_text("),
		"ProductionScreen must own the localized tooltip formatting port"
	)
	for path: String in CONSUMER_PATHS:
		var source := FileAccess.get_file_as_string(path)
		assert_true(
			source.contains("content_tooltip_text("),
			"%s must consume the shared tooltip port" % path
		)
		assert_true(
			source.contains("set_item_tooltip("),
			"%s must expose tooltips on visible typed items" % path
		)
		assert_false(
			source.contains("load(\"res://content/"),
			"%s must not bypass pinned snapshots with direct content loads" % path
		)


func test_tooltip_keys_exist_in_both_locales() -> void:
	var catalog := LocalizationCatalog.restricted_emergency_catalog()
	for key: StringName in [
		&"tooltip.cost",
		&"tooltip.star",
		&"tooltip.reward_amount",
		&"tooltip.collection_order",
	]:
		assert_true(catalog.resolve(&"zh_TW", key).ok, "missing zh_TW %s" % key)
		assert_true(catalog.resolve(&"en", key).ok, "missing en %s" % key)
