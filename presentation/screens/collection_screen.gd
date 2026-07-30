class_name CollectionScreen
extends Control

const COMPOSE_INVALID: StringName = &"COLLECTION_COMPOSE_INVALID"
const CATEGORY_ORDER: Array[StringName] = [
	CollectionBrowserViewModel.KIND_CONTENT,
	CollectionBrowserViewModel.KIND_RECIPE,
	CollectionBrowserViewModel.KIND_GLOSSARY,
]

var _view_model: CollectionBrowserViewModel
var _navigation_port: LiveScreenNavigationPort
var _localized_text: Dictionary[StringName, String] = {}
var _signals_bound: bool = false


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
	_bind_controls()
	_populate_categories()
	_refresh_entries()
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
	var search := get_node_or_null(^"SearchInput") as LineEdit
	var query := search.text if search != null else ""
	for entry_id: StringName in _view_model.filter_and_search(kind, query):
		var label := _entry_text(entry_id)
		entries.add_item(label)
		entries.set_item_metadata(entries.item_count - 1, entry_id)
		compare.add_item(label)
		compare.set_item_metadata(compare.item_count - 1, entry_id)
	_set_compare_result(&"collection.compare.empty")


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


func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
