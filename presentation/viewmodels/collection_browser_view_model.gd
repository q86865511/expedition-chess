class_name CollectionBrowserViewModel
extends RefCounted

const KIND_CONTENT: StringName = &"content"
const KIND_RECIPE: StringName = &"recipe"
const KIND_GLOSSARY: StringName = &"glossary"

const INVALID_KIND: StringName = &"COLLECTION_KIND_INVALID"
const ENTRY_NOT_FOUND: StringName = &"COLLECTION_ENTRY_NOT_FOUND"
const COMPARE_KIND_MISMATCH: StringName = &"COLLECTION_COMPARE_KIND_MISMATCH"
const COMPARE_UNSUPPORTED: StringName = &"COLLECTION_COMPARE_UNSUPPORTED"
const CATEGORY_NOT_COMPARABLE: StringName = \
	&"COLLECTION_CATEGORY_NOT_COMPARABLE"

var _snapshot: CollectionBrowserSnapshot
var _selected_kind: StringName = &""
var _selected_id: StringName = &""


func _init(snapshot: CollectionBrowserSnapshot = null) -> void:
	_snapshot = (
		snapshot.deep_clone()
		if snapshot != null
		else CollectionBrowserSnapshot.new()
	)


func entries(kind: StringName) -> Array:
	var source := _entries_for_kind(kind)
	var clone: Array = []
	clone.assign(source)
	return clone


func filter_and_search(kind: StringName, query: String) -> Array:
	var matches: Array = []
	var normalized_query := query.strip_edges().to_lower()
	for entry_id: StringName in _entries_for_kind(kind):
		if normalized_query.is_empty() or String(entry_id).to_lower().contains(normalized_query):
			matches.append(entry_id)
	return matches


func select(kind: StringName, entry_id: StringName) -> StringName:
	if not _is_known_kind(kind):
		return INVALID_KIND
	if not _entries_for_kind(kind).has(entry_id):
		return ENTRY_NOT_FOUND
	_selected_kind = kind
	_selected_id = entry_id
	return &""


func move_focus(offset: int) -> StringName:
	if _selected_kind.is_empty():
		return &""
	var available := _entries_for_kind(_selected_kind)
	if available.is_empty():
		_selected_id = &""
		return &""
	var current_index := available.find(_selected_id)
	if current_index < 0:
		current_index = 0
	else:
		current_index = wrapi(current_index + offset, 0, available.size())
	_selected_id = available[current_index]
	return _selected_id


func selected_id() -> StringName:
	return _selected_id


func compare_selected_with(
	other_kind: StringName,
	other_id: StringName
) -> Dictionary:
	if _selected_kind.is_empty() or not _entries_for_kind(other_kind).has(other_id):
		return _compare_failure(ENTRY_NOT_FOUND)
	if _selected_kind == KIND_GLOSSARY or other_kind == KIND_GLOSSARY:
		return _compare_failure(COMPARE_UNSUPPORTED)
	if other_kind != _selected_kind:
		return _compare_failure(COMPARE_KIND_MISMATCH)
	return {
		"ok": true,
		"error_code": &"",
		"left_id": _selected_id,
		"right_id": other_id,
		"kind": _selected_kind,
	}


func compare_for_presentation(
	other_kind: StringName,
	other_id: StringName
) -> Dictionary:
	if _selected_kind.is_empty() or not _entries_for_kind(other_kind).has(
		other_id
	):
		return _compare_failure(ENTRY_NOT_FOUND)
	if (
		_selected_kind == KIND_GLOSSARY
		or other_kind == KIND_GLOSSARY
		or other_kind != _selected_kind
	):
		return _compare_failure(CATEGORY_NOT_COMPARABLE)
	return {
		"ok": true,
		"error_code": &"",
		"left_id": _selected_id,
		"right_id": other_id,
		"kind": _selected_kind,
	}


func _entries_for_kind(kind: StringName) -> Array:
	match kind:
		KIND_CONTENT:
			return _snapshot.content_ids
		KIND_RECIPE:
			return _snapshot.recipe_ids
		KIND_GLOSSARY:
			return _snapshot.glossary_ids
		_:
			var empty: Array = []
			return empty


func _is_known_kind(kind: StringName) -> bool:
	return kind in [KIND_CONTENT, KIND_RECIPE, KIND_GLOSSARY]


func _compare_failure(error_code: StringName) -> Dictionary:
	return {
		"ok": false,
		"error_code": error_code,
	}
