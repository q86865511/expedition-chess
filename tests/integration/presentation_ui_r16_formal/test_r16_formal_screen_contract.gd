extends GutTest

const RouteSupport = preload(
	"res://tests/integration/presentation_ui_r14_production_route/"
	+ "r14_production_route_test_support.gd"
)


func test_prepare_uses_authoritative_report_and_exposes_the_player_loop() -> void:
	var snapshot := RunPresentationSnapshot.new()
	assert_true(
		_has_property(snapshot, &"board_validation_report"),
		"RUN_PREPARE must receive the committed board validation projection"
	)
	if not _has_property(snapshot, &"board_validation_report"):
		return
	var issues: Array[BoardValidationIssue] = [
		BoardValidationIssue.new(BoardValidationIssue.OVER_CAPACITY),
	]
	snapshot.set(
		&"board_validation_report",
		BoardValidationReport.new(12, issues)
	)
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 1601)
	var session := RunPresentationSession.new()
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)
	var staged := StagedScreenContext.new(
		&"RUN_PREPARE",
		snapshot,
		null,
		&"zh_TW",
		{}
	)
	assert_eq(screen.bind(staged), &"")
	var live := ProductionLiveScreenContext.new(
		&"RUN_PREPARE",
		snapshot,
		null,
		ProductionScreenActionPort.new(lease, registry, {}),
		LiveScreenNavigationPort.new(),
		LiveScreenIntentPort.new(lease, registry, session)
	)
	assert_eq(screen.prepare_live_binding(live), &"")
	add_child_autofree(screen)
	screen.activate_live()
	var composition := screen.get_node_or_null(^"Composition") as RunPrepareScreen
	assert_not_null(composition)
	if composition == null:
		return
	assert_eq(composition.displayed_capacity(), 12)
	assert_false(composition.start_enabled())
	for control_name: StringName in [
		&"BoardSelector",
		&"BenchSelector",
		&"ShopSelector",
		&"InventorySelector",
		&"BuildUnitSelector",
	]:
		assert_not_null(
			composition.find_child(String(control_name), true, false),
			"formal prepare must expose %s" % control_name
		)
	for action_id: StringName in [
		&"prepare.refresh",
		&"prepare.buy",
		&"prepare.xp",
		&"prepare.sell",
		&"prepare.forge",
		&"prepare.equip",
		&"prepare.dismantle",
		&"prepare.move_board",
		&"prepare.move_bench",
	]:
		assert_not_null(_action_button(screen, action_id))


func test_collection_has_three_queryable_categories_and_typed_compare() -> void:
	var packed := load("res://scenes/production/collection.tscn") as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var screen := packed.instantiate() as ProductionScreen
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)
	var composition := screen.get_node_or_null(^"Composition")
	assert_not_null(composition)
	if composition == null:
		return
	assert_true(
		composition.has_method(&"compose_collection"),
		"COLLECTION must not reuse the one-list generic facility composition"
	)
	for control_name: StringName in [
		&"CategorySelector",
		&"SearchInput",
		&"EntrySelector",
		&"CompareSelector",
		&"CompareResult",
	]:
		assert_not_null(
			composition.find_child(String(control_name), true, false),
			"collection composition must expose %s" % control_name
		)


func test_live_collection_uses_authoritative_content_recipe_and_glossary_projection() -> void:
	var harness: Variant = RouteSupport.boot(self)
	assert_true(harness.root.open_camp().ok)
	var camp := RouteSupport.composition(harness) as CampWorldScreen
	assert_not_null(camp)
	if camp == null:
		return
	assert_true(camp.open_facility(&"COLLECTION").ok)
	var collection := RouteSupport.composition(harness) as CollectionScreen
	assert_not_null(collection)
	if collection == null:
		return
	var category := collection.get_node_or_null(^"CategorySelector") as OptionButton
	var entries := collection.get_node_or_null(^"EntrySelector") as ItemList
	assert_not_null(category)
	assert_not_null(entries)
	if category == null or entries == null:
		return
	assert_eq(category.item_count, 3)
	category.select(1)
	category.item_selected.emit(1)
	assert_gt(
		entries.item_count,
		0,
		"live COLLECTION recipe category must come from the pinned content projection"
	)
	category.select(2)
	category.item_selected.emit(2)
	assert_gt(
		entries.item_count,
		0,
		"live COLLECTION glossary must expose authoritative rule definitions"
	)


func test_results_and_fallback_render_the_sealed_settlement_pair() -> void:
	for route_kind: StringName in [&"RESULTS", &"RESULTS_FALLBACK"]:
		var screen := ProductionSceneCatalog.new().instantiate(route_kind)
		assert_not_null(screen)
		if screen == null:
			continue
		autofree(screen)
		assert_not_null(
			screen.get_node_or_null(^"Composition"),
			"%s must have a typed settlement composition" % route_kind
		)
		for control_name: StringName in [
			&"ReceiptValue",
			&"OutcomeValue",
			&"RewardValue",
			&"ProfileValue",
			&"DigestValue",
		]:
			assert_not_null(
				screen.find_child(String(control_name), true, false),
				"%s must render %s" % [route_kind, control_name]
			)


func test_settings_focus_cycle_contains_every_visible_editor() -> void:
	var screen := ProductionSceneCatalog.new().instantiate(&"SETTINGS")
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)
	var snapshot := SettingsSnapshot.new()
	assert_eq(
		screen.bind(StagedScreenContext.new(
			&"SETTINGS",
			snapshot,
			null,
			&"zh_TW",
			{}
		)),
		&""
	)
	add_child_autofree(screen)
	var ordered: Array = screen.call(&"_ordered_focus_controls")
	var setting_ids: Array[StringName] = []
	for control: Control in ordered:
		if control.has_meta(&"setting_id"):
			setting_ids.append(StringName(control.get_meta(&"setting_id")))
	assert_eq(
		setting_ids.size(),
		15,
		"OptionButton, CheckButton and HSlider editors must all be keyboard reachable"
	)


func _action_button(screen: ProductionScreen, action_id: StringName) -> Button:
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			return button
	return null


func _has_property(target: Object, property_name: StringName) -> bool:
	for property: Dictionary in target.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false
