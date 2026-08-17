extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)
const THEME_PATH := "res://theme/expedition_theme.tres"
const COLLECTION_SCENE_PATH := "res://scenes/production/collection.tscn"
const FACILITY_ROUTES: Array[StringName] = [
	&"FACILITY_EXPEDITION_GATE",
	&"FACILITY_COMMANDER_HALL",
	&"COLLECTION",
	&"FACILITY_UNLOCK_WORKSHOP",
	&"FACILITY_CHALLENGE_MONUMENT",
]


func test_five_facilities_use_route_local_shell_geometry() -> void:
	for route: StringName in FACILITY_ROUTES:
		var shell := ProductionLayoutShell.new()
		shell.build(route)
		assert_eq(
			shell.current_region_rect(
				ProductionLayoutShell.REGION_TOP
			).size.y,
			ProductionLayoutShell.FACILITY_TOP_HEIGHT,
			"%s must use the compact facility top bar" % route
		)
		assert_eq(
			shell.current_region_rect(
				ProductionLayoutShell.REGION_BOTTOM
			).size.y,
			ProductionLayoutShell.FACILITY_BOTTOM_HEIGHT,
			"%s must use the compact facility action band" % route
		)
		assert_eq(
			shell.current_region_rect(
				ProductionLayoutShell.REGION_LEFT
			).size.x,
			0.0,
			"%s must not retain an empty left panel" % route
		)
		var expected_right := (
			ProductionLayoutShell.COLLECTION_RIGHT_WIDTH
			if route == &"COLLECTION"
			else 0.0
		)
		assert_eq(
			shell.current_region_rect(
				ProductionLayoutShell.REGION_RIGHT
			).size.x,
			expected_right,
			"only Collection reserves a comparison region"
		)
		shell.free()

	var map := ProductionLayoutShell.new()
	map.build(&"RUN_MAP")
	assert_eq(
		map.current_region_rect(ProductionLayoutShell.REGION_LEFT).size.x,
		ProductionLayoutShell.SIDE_WIDTH
	)
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
	map.free()


func test_camp_shell_yields_the_only_visible_frame_to_environment_view() -> void:
	var shell := ProductionLayoutShell.new()
	shell.build(&"CAMP_WORLD")
	var center := shell.find_child("CenterRegion", true, false) as PanelContainer
	assert_not_null(center)
	if center != null:
		assert_eq(center.self_modulate.a, 0.0)
	var top := shell.find_child("TopRegion", true, false) as PanelContainer
	assert_not_null(top)
	if top != null:
		assert_eq(top.self_modulate.a, 1.0)
	shell.free()


func test_production_portrait_catalog_resolves_adopted_unit_portraits() -> void:
	var catalog := ProductionUnitVisualCatalog.new()
	assert_eq(catalog.load_error(), &"")
	for unit_id: StringName in [
		&"unit.slice_player_00",
		&"unit.slice_player_31",
		&"unit.slice_monster_00",
		&"unit.slice_monster_11",
	]:
		var portrait := catalog.try_portrait(unit_id)
		assert_not_null(portrait, "%s must resolve from production inventory" % unit_id)
		if portrait != null:
			assert_gt(portrait.get_size().x, 0.0)
			assert_gt(portrait.get_size().y, 0.0)
	assert_null(
		catalog.try_portrait(&"commander.slice_c0"),
		"presentation must not invent a commander-to-unit portrait mapping"
	)


func test_collection_content_entries_become_portrait_cards_without_node_drift() -> void:
	var packed := load(COLLECTION_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var screen := packed.instantiate() as ProductionScreen
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)
	var collection := screen.get_node_or_null(^"Composition") as CollectionScreen
	assert_not_null(collection)
	if collection == null:
		return
	var projection := CollectionBrowserSnapshot.new()
	projection.content_ids.assign([
		&"unit.slice_player_00",
		&"unit.slice_player_01",
	])
	assert_eq(
		collection.compose_collection(
			Support.profile_fixture(),
			LiveScreenNavigationPort.new(),
			projection,
			{
				&"loc.unit_slice_player_00": "測試先鋒零",
				&"loc.unit_slice_player_01": "測試先鋒一",
				&"collection.category.content": "內容",
				&"collection.category.recipe": "配方",
				&"collection.category.glossary": "規則辭典",
				&"collection.compare.empty": "選擇兩個項目進行比較",
			}
		),
		&""
	)
	var category := collection.get_node_or_null(^"CategorySelector") as OptionButton
	var search := collection.get_node_or_null(^"SearchInput") as LineEdit
	var entries := collection.get_node_or_null(^"EntrySelector") as ItemList
	var compare := collection.get_node_or_null(^"CompareSelector") as ItemList
	var result := collection.get_node_or_null(^"CompareResult") as Label
	assert_not_null(category)
	assert_not_null(search)
	assert_not_null(entries)
	assert_not_null(compare)
	assert_not_null(result)
	if entries == null or compare == null:
		return
	assert_eq(entries.item_count, 2)
	assert_eq(compare.item_count, 2)
	assert_eq(entries.icon_mode, ItemList.ICON_MODE_TOP)
	assert_eq(entries.theme_type_variation, &"ExpeditionCollectionCardGrid")
	assert_eq(compare.theme_type_variation, &"ExpeditionCollectionCompareList")
	assert_not_null(entries.get_item_icon(0))
	assert_not_null(entries.get_item_icon(1))
	assert_not_null(compare.get_item_icon(0))
	assert_eq(
		StringName(entries.get_item_metadata(0)),
		&"unit.slice_player_00"
	)
	collection.apply_theme_scale_layout(150)
	assert_eq(entries.fixed_column_width, 285)
	var shell := ProductionLayoutShell.new()
	shell.build(&"COLLECTION")
	var available_width := shell.current_content_rect(
		ProductionLayoutShell.REGION_CENTER
	).size.x
	var four_card_width := entries.fixed_column_width * 4 + roundi(18.0 * 1.5) * 3
	assert_lte(
		four_card_width,
		roundi(available_width),
		"commander data plus three portrait cards must stay on one row at 150%"
	)
	shell.free()


func test_b_out_2_theme_variations_keep_expedition_contracts() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_not_null(theme)
	if theme == null:
		return
	var type_names := theme.get_type_list()
	for variation: StringName in [
		&"ExpeditionCampFooterContext",
		&"ExpeditionFacilityCardGrid",
		&"ExpeditionCollectionCategory",
		&"ExpeditionCollectionSearch",
		&"ExpeditionCollectionCardGrid",
		&"ExpeditionCollectionCompareList",
		&"ExpeditionCollectionCompareResult",
	]:
		assert_true(String(variation).begins_with("Expedition"))
		assert_true(
			type_names.has(String(variation)),
			"missing theme variation: %s" % variation
		)
	for item_list_variation: StringName in [
		&"ExpeditionFacilityCardGrid",
		&"ExpeditionCollectionCardGrid",
		&"ExpeditionCollectionCompareList",
	]:
		assert_eq(
			theme.get_type_variation_base(item_list_variation),
			&"ItemList"
		)
		assert_not_null(theme.get_stylebox(&"focus", item_list_variation))
