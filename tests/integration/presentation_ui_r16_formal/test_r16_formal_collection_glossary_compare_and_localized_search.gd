extends GutTest

## G2 wave2-B M7 regression (fix/g2-ui-review-findings): the formal COLLECTION
## composition (a) always populated the glossary category's CompareSelector
## even though CollectionBrowserViewModel.compare_for_presentation() rejects
## every glossary comparison with CATEGORY_NOT_COMPARABLE, and (b) matched
## search against the raw entry id instead of the resolved zh_TW/en display
## text, making search unusable for CJK players. This locks both fixes.

const Support = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)
const SCENE_PATH := "res://scenes/production/collection.tscn"


func test_collection_search_matches_localized_display_text() -> void:
	var composition := _compose(_localized_text())
	if composition == null:
		return
	var entries := composition.get_node_or_null(^"EntrySelector") as ItemList
	var search := composition.get_node_or_null(^"SearchInput") as LineEdit
	assert_not_null(entries)
	assert_not_null(search)
	if entries == null or search == null:
		return

	# Content category defaults selected; two content entries were seeded,
	# only one of which resolves to a localized name containing "艾法".
	assert_eq(entries.item_count, 2)
	search.text = "艾法"
	search.text_changed.emit("艾法")
	assert_eq(
		entries.item_count,
		1,
		"search must match the resolved display text, not the raw entry id"
	)
	assert_string_contains(entries.get_item_text(0), "測試內容艾法")


func test_collection_glossary_category_withdraws_the_compare_entry_point() -> void:
	var composition := _compose(_localized_text())
	if composition == null:
		return
	var category := composition.get_node_or_null(^"CategorySelector") as OptionButton
	var compare := composition.get_node_or_null(^"CompareSelector") as ItemList
	var result_label := composition.get_node_or_null(^"CompareResult") as Label
	assert_not_null(category)
	assert_not_null(compare)
	assert_not_null(result_label)
	if category == null or compare == null or result_label == null:
		return

	# Index 0/1/2 follow CollectionScreen.CATEGORY_ORDER: content, recipe, glossary.
	assert_eq(compare.item_count, 2, "content category must still offer compare entries")
	assert_eq(compare.focus_mode, Control.FOCUS_ALL)

	category.select(2)
	category.item_selected.emit(2)
	assert_eq(
		compare.item_count,
		0,
		"glossary must not populate a compare entry point that always fails"
	)
	assert_eq(
		compare.focus_mode,
		Control.FOCUS_NONE,
		"glossary compare selector must drop out of the focus/interaction order"
	)
	assert_eq(result_label.text, "此分類不支援比較")

	category.select(0)
	category.item_selected.emit(0)
	assert_eq(
		compare.item_count,
		2,
		"switching back to a comparable category must restore the compare entry point"
	)
	assert_eq(compare.focus_mode, Control.FOCUS_ALL)


func _compose(localized_text: Dictionary) -> CollectionScreen:
	var packed := load(SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var screen := packed.instantiate() as ProductionScreen
	assert_not_null(screen)
	if screen == null:
		return null
	autofree(screen)
	var composition := screen.get_node_or_null(^"Composition") as CollectionScreen
	assert_not_null(composition)
	if composition == null:
		return null

	var projection := CollectionBrowserSnapshot.new()
	projection.content_ids.assign([&"content.test_alpha", &"content.test_beta"])
	projection.glossary_ids.assign([&"rule.test_gamma"])

	assert_eq(
		composition.compose_collection(
			Support.profile_fixture(),
			LiveScreenNavigationPort.new(),
			projection,
			localized_text
		),
		&""
	)
	return composition


func _localized_text() -> Dictionary:
	return {
		&"loc.content_test_alpha": "測試內容艾法",
		&"loc.content_test_beta": "測試內容布拉沃",
		&"collection.category.content": "內容",
		&"collection.category.recipe": "配方",
		&"collection.category.glossary": "規則辭典",
		&"collection.compare.empty": "選擇兩個項目進行比較",
		&"error.collection_category_not_comparable": "此分類不支援比較",
	}
