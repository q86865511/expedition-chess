class_name CollectionViewModel
extends RefCounted

## T09 / S5-AC-012 (specs/meta-progression/design.md §8: "圖鑑館經
## CollectionViewModel 按類別讀出"): read-only projection over a ProfileState's
## discovery/unlock ledgers for the 圖鑑館 (collection) facility. Holds only a
## deep_clone of the profile and never a mutable reference back into live domain
## state (same convention as trait_preview_view_model.gd).
##
## Category is the segment before the first "." of a content id (the project-wide
## "<category>.<name>" convention: unit.fixture -> "unit", relic.alpha ->
## "relic"), so a facility tab can list only the ids belonging to its category
## while preserving the ledger's existing (canonical) order.

## Holds only the two ledgers this ViewModel actually reads (copied out of the
## profile up front), rather than the profile reference itself -- this keeps a
## null profile a valid, inert input (empty ledgers) instead of leaving a null
## `_profile` for every accessor below to separately guard against.
var _discovered_ids: Array[StringName] = []
var _unlocked_ids: Array[StringName] = []

func _init(profile: ProfileState) -> void:
	if profile != null:
		_discovered_ids.assign(profile.discovered_content_ids)
		_unlocked_ids.assign(profile.unlocked_content_ids)

## Discovered ids whose category matches, in ledger order (empty for a category
## with no discovered content).
func discovered_ids_for_category(category: StringName) -> Array[StringName]:
	return _filter_by_category(_discovered_ids, category)

## Unlocked ids whose category matches, in ledger order.
func unlocked_ids_for_category(category: StringName) -> Array[StringName]:
	return _filter_by_category(_unlocked_ids, category)

func is_discovered(content_id: StringName) -> bool:
	return _discovered_ids.has(content_id)

func is_unlocked(content_id: StringName) -> bool:
	return _unlocked_ids.has(content_id)

func _filter_by_category(ids: Array[StringName], category: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for content_id: StringName in ids:
		if _category_of(content_id) == category:
			result.append(content_id)
	return result

func _category_of(content_id: StringName) -> StringName:
	var text := String(content_id)
	var separator := text.find(".")
	return StringName(text.substr(0, separator)) if separator >= 0 else content_id
