class_name CollectionScreen
extends Control

const COMPOSE_INVALID: StringName = &"COLLECTION_COMPOSE_INVALID"
const CATEGORY_ORDER: Array[StringName] = [
	CollectionBrowserViewModel.KIND_CONTENT,
	CollectionBrowserViewModel.KIND_RECIPE,
	CollectionBrowserViewModel.KIND_GLOSSARY,
]
const TOOLBAR_HEIGHT: float = 72.0
const TOOLBAR_GAP: float = 18.0
const CATEGORY_WIDTH: float = 300.0
# Collection 的 content 列含一張無 portrait 的指揮官資料卡與三張單位卡；190 在
# 150% 時仍能讓四欄留在同列，同時容納 168px 圖像與 icon margin。
const CARD_WIDTH: float = 190.0
const CARD_ICON_SIZE: float = 168.0
const COMPARE_RESULT_HEIGHT: float = 144.0

var _view_model: CollectionBrowserViewModel
var _navigation_port: LiveScreenNavigationPort
var _localized_text: Dictionary[StringName, String] = {}
var _signals_bound: bool = false
var _visuals := ProductionUnitVisualCatalog.new()
var _ui_scale_percent: int = 100


func compose_collection(
	profile: ProfileState,
	navigation_port: LiveScreenNavigationPort,
	projection: CollectionBrowserSnapshot = null,
	localized_text: Dictionary = {}
) -> StringName:
	if profile == null or navigation_port == null:
		return COMPOSE_INVALID
	_navigation_port = navigation_port
	_set_localized_text(localized_text)
	var owned_projection := (
		projection.deep_clone()
		if projection != null
		else _minimal_profile_projection(profile.deep_clone())
	)
	_view_model = CollectionBrowserViewModel.new(owned_projection)
	_configure_visual_controls()
	_bind_controls()
	_populate_categories()
	_refresh_entries()
	refresh_layout_rects()
	return &""


func return_to_camp() -> AppActionResult:
	if _navigation_port == null:
		return AppActionResult.failure(
			DiagnosticError.new(
				COMPOSE_INVALID,
				&"error.presentation.collection_compose_invalid"
			)
		)
	return _navigation_port.navigate(&"CAMP_WORLD")


func _minimal_profile_projection(
	profile: ProfileState
) -> CollectionBrowserSnapshot:
	var projection := CollectionBrowserSnapshot.new()
	var content_ids: Array[StringName] = []
	for content_id: StringName in profile.discovered_content_ids:
		if not content_ids.has(content_id):
			content_ids.append(content_id)
	for content_id: StringName in profile.unlocked_content_ids:
		if not content_ids.has(content_id):
			content_ids.append(content_id)
	content_ids.sort_custom(_name_less)
	projection.content_ids.assign(content_ids)
	return projection


func _bind_controls() -> void:
	if _signals_bound:
		return
	var category := get_node_or_null(^"CategorySelector") as OptionButton
	var search := get_node_or_null(^"SearchInput") as LineEdit
	var entries := get_node_or_null(^"EntrySelector") as ItemList
	var compare := get_node_or_null(^"CompareSelector") as ItemList
	if category != null:
		category.item_selected.connect(_on_category_selected)
	if search != null:
		search.text_changed.connect(_on_search_changed)
	if entries != null:
		entries.item_selected.connect(_on_entry_selected)
	if compare != null:
		compare.item_selected.connect(_on_compare_selected)
	_signals_bound = true


func _populate_categories() -> void:
	var category := get_node_or_null(^"CategorySelector") as OptionButton
	if category == null:
		return
	category.clear()
	for kind: StringName in CATEGORY_ORDER:
		category.add_item(_text(_category_key(kind)))
		category.set_item_metadata(category.item_count - 1, kind)
	category.select(0)


func _refresh_entries() -> void:
	var entries := get_node_or_null(^"EntrySelector") as ItemList
	var compare := get_node_or_null(^"CompareSelector") as ItemList
	if entries == null or compare == null or _view_model == null:
		return
	entries.clear()
	compare.clear()
	var kind := _selected_category()
	# Glossary entries never resolve to a supported comparison (the view model
	# always rejects them with CATEGORY_NOT_COMPARABLE), so the compare entry
	# point is withdrawn instead of staying interactive and always failing.
	var comparable := kind != CollectionBrowserViewModel.KIND_GLOSSARY
	var search := get_node_or_null(^"SearchInput") as LineEdit
	var query := search.text if search != null else ""
	var matches := _search_matches(kind, query)
	for entry_index: int in matches.size():
		var entry_id := StringName(matches[entry_index])
		var label := _entry_text(entry_id)
		var portrait := _entry_portrait(kind, entry_id)
		entries.add_item(label, portrait)
		var visible_index := entries.item_count - 1
		entries.set_item_metadata(visible_index, entry_id)
		entries.set_item_tooltip(
			visible_index,
			_tooltip_text(&"tooltip.collection_order", entry_index + 1)
		)
		if comparable:
			compare.add_item(label, portrait)
			var compare_index := compare.item_count - 1
			compare.set_item_metadata(compare_index, entry_id)
			compare.set_item_tooltip(
				compare_index,
				_tooltip_text(&"tooltip.collection_order", entry_index + 1)
			)
	compare.focus_mode = Control.FOCUS_ALL if comparable else Control.FOCUS_NONE
	_set_compare_result(
		&"collection.compare.empty"
		if comparable
		else CollectionBrowserViewModel.CATEGORY_NOT_COMPARABLE
	)


func apply_theme_scale_layout(scale_percent: int) -> void:
	_ui_scale_percent = clampi(scale_percent, 100, 150)
	_apply_card_metrics()
	refresh_layout_rects()


func refresh_layout_rects() -> void:
	var parent_screen := get_parent() as ProductionScreen
	if parent_screen == null:
		return
	var center := parent_screen.layout_region_content_rect(
		ProductionLayoutShell.REGION_CENTER
	)
	var right := parent_screen.layout_region_content_rect(
		ProductionLayoutShell.REGION_RIGHT
	)
	if center.size.x <= 0.0 or center.size.y <= 0.0:
		return
	var factor := float(_ui_scale_percent) / 100.0
	var toolbar_height := ceilf(TOOLBAR_HEIGHT * factor)
	var toolbar_gap := ceilf(TOOLBAR_GAP * factor)
	var category_width := roundf(CATEGORY_WIDTH * factor)
	var category := get_node_or_null(^"CategorySelector") as OptionButton
	var search := get_node_or_null(^"SearchInput") as LineEdit
	var entries := get_node_or_null(^"EntrySelector") as ItemList
	var compare := get_node_or_null(^"CompareSelector") as ItemList
	var result := get_node_or_null(^"CompareResult") as Label
	if category != null:
		category.position = center.position
		category.size = Vector2(category_width, toolbar_height)
	if search != null:
		search.position = Vector2(
			center.position.x + category_width + toolbar_gap,
			center.position.y
		)
		search.size = Vector2(
			maxf(0.0, center.size.x - category_width - toolbar_gap),
			toolbar_height
		)
	if entries != null:
		entries.position = Vector2(
			center.position.x,
			center.position.y + toolbar_height + toolbar_gap
		)
		entries.size = Vector2(
			center.size.x,
			maxf(0.0, center.size.y - toolbar_height - toolbar_gap)
		)
	if right.size.x <= 0.0 or right.size.y <= 0.0:
		return
	var result_height := ceilf(COMPARE_RESULT_HEIGHT * factor)
	if compare != null:
		compare.position = right.position
		compare.size = Vector2(
			right.size.x,
			maxf(0.0, right.size.y - result_height - toolbar_gap)
		)
	if result != null:
		result.position = Vector2(
			right.position.x,
			right.end.y - result_height
		)
		result.size = Vector2(right.size.x, result_height)


func _configure_visual_controls() -> void:
	var category := get_node_or_null(^"CategorySelector") as OptionButton
	var search := get_node_or_null(^"SearchInput") as LineEdit
	var entries := get_node_or_null(^"EntrySelector") as ItemList
	var compare := get_node_or_null(^"CompareSelector") as ItemList
	var result := get_node_or_null(^"CompareResult") as Label
	if category != null:
		category.theme_type_variation = &"ExpeditionCollectionCategory"
	if search != null:
		search.theme_type_variation = &"ExpeditionCollectionSearch"
	if entries != null:
		entries.theme_type_variation = &"ExpeditionCollectionCardGrid"
		entries.icon_mode = ItemList.ICON_MODE_TOP
		entries.same_column_width = true
		entries.max_columns = 0
		entries.allow_reselect = true
		entries.set_meta(&"portrait_catalog_error", _visuals.load_error())
	if compare != null:
		compare.theme_type_variation = &"ExpeditionCollectionCompareList"
		compare.icon_mode = ItemList.ICON_MODE_LEFT
		compare.allow_reselect = true
	if result != null:
		result.theme_type_variation = &"ExpeditionCollectionCompareResult"
		result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_card_metrics()


func _apply_card_metrics() -> void:
	var factor := float(_ui_scale_percent) / 100.0
	var entries := get_node_or_null(^"EntrySelector") as ItemList
	var compare := get_node_or_null(^"CompareSelector") as ItemList
	if entries != null:
		entries.fixed_column_width = roundi(CARD_WIDTH * factor)
		entries.fixed_icon_size = Vector2i.ONE * roundi(
			CARD_ICON_SIZE * factor
		)
	if compare != null:
		compare.fixed_icon_size = Vector2i.ONE * roundi(48.0 * factor)


func _entry_portrait(kind: StringName, entry_id: StringName) -> Texture2D:
	if kind != CollectionBrowserViewModel.KIND_CONTENT:
		return null
	return _visuals.try_portrait(entry_id)


## Matches against the resolved display name (current locale) rather than the
## raw entry id, so search is usable for zh_TW/en players. The view model's
## own filter_and_search() keeps matching raw ids for its own clone-only
## contract (see CollectionBrowserViewModel); this stays screen-local because
## localized text belongs to the screen, not the view model.
func _search_matches(kind: StringName, query: String) -> Array:
	var normalized_query := query.strip_edges().to_lower()
	var matches: Array = []
	for entry_id: StringName in _view_model.entries(kind):
		if (
			normalized_query.is_empty()
			or _entry_text(entry_id).to_lower().contains(normalized_query)
		):
			matches.append(entry_id)
	return matches


func _on_category_selected(_index: int) -> void:
	_refresh_entries()


func _on_search_changed(_query: String) -> void:
	_refresh_entries()


func _on_entry_selected(index: int) -> void:
	var entries := get_node_or_null(^"EntrySelector") as ItemList
	if entries == null or index < 0 or index >= entries.item_count:
		return
	var error := _view_model.select(
		_selected_category(),
		StringName(entries.get_item_metadata(index))
	)
	_set_compare_result(
		&"collection.compare.ready"
		if error.is_empty()
		else error
	)


func _on_compare_selected(index: int) -> void:
	var compare := get_node_or_null(^"CompareSelector") as ItemList
	if compare == null or index < 0 or index >= compare.item_count:
		return
	var result := _view_model.compare_for_presentation(
		_selected_category(),
		StringName(compare.get_item_metadata(index))
	)
	var result_label := get_node_or_null(^"CompareResult") as Label
	if result_label == null:
		return
	if not bool(result.get("ok", false)):
		var error_code := StringName(
			result.get("error_code", &"COLLECTION_ENTRY_NOT_FOUND")
		)
		_set_compare_result(error_code)
		return
	result_label.text = _text(&"collection.compare.format") % [
		_entry_text(StringName(result.get("left_id", &""))),
		_entry_text(StringName(result.get("right_id", &""))),
	]
	result_label.set_meta(&"comparison_result", result.duplicate(true))


func _selected_category() -> StringName:
	var category := get_node_or_null(^"CategorySelector") as OptionButton
	if (
		category == null
		or category.selected < 0
		or category.selected >= category.item_count
	):
		return CollectionBrowserViewModel.KIND_CONTENT
	return StringName(category.get_item_metadata(category.selected))


func _set_compare_result(code: StringName) -> void:
	var result := get_node_or_null(^"CompareResult") as Label
	if result == null:
		return
	var key := (
		StringName("error.%s" % String(code).to_lower())
		if String(code).begins_with("COLLECTION_")
		else code
	)
	result.text = _text(key)
	result.set_meta(&"status_code", code)
	result.set_meta(&"accessible_text", result.text)


func _entry_text(entry_id: StringName) -> String:
	var key := StringName("loc.%s" % String(entry_id).replace(".", "_"))
	return _localized_text.get(key, String(entry_id))


func _category_key(kind: StringName) -> StringName:
	return StringName("collection.category.%s" % String(kind))


func _set_localized_text(values: Dictionary) -> void:
	_localized_text.clear()
	for key: Variant in values.keys():
		_localized_text[StringName(key)] = String(values[key])


func _text(key: StringName) -> String:
	return _localized_text.get(key, String(key))


func _tooltip_text(
	label_key: StringName,
	numeric_value: int,
	depth: int = 1
) -> String:
	var parent_screen := get_parent() as ProductionScreen
	return (
		parent_screen.content_tooltip_text(
			label_key, numeric_value, depth
		)
		if parent_screen != null
		else ""
	)


func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
