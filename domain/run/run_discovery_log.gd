class_name RunDiscoveryLog
extends RefCounted

## T09 / S5-AC-012 (specs/meta-progression/design.md §8): shared helper for the
## four in-run discovery events (上場/購得棋子、商店出現、遭遇敵人、取得裝備/遺物).
## Each event's owning command calls mark() inside its apply_to(draft) so the
## discovery lands in the same copy-validate-save-swap transaction as the action
## that revealed the content. Marking is a pure, monotonic union: it never
## removes, never reorders existing entries out of canonical order, and consumes
## no RNG (design §8: "純 append 不消耗 RNG、不改 draw 序").
##
## The ledger stays sorted+unique by String(content_id) -- StringName's own `<`
## compares by hash/pointer in Godot 4, so canonical order must be derived from
## the String form, matching run_state_validator.gd `_sorted_unique_names`
## (which rejects duplicate or out-of-canonical-order discovered_content_ids on
## both run.discovered_content_ids and profile.discovered_content_ids).

## Unions a single content_id into draft.discovered_content_ids in place
## (idempotent when already present). Called by discovery commands/events.
static func mark(draft: RunState, content_id: StringName) -> void:
	_insert_sorted_unique(draft.discovered_content_ids, content_id)

## Commit-time fold used by RunController._commit_draft: unions the run-scoped
## discovery ledger into the profile's cross-run ledger (profile' per design §8).
## Idempotent -- re-applying an already-discovered id leaves the profile
## unchanged, so reload/replay never duplicates an entry.
static func union_into_profile(profile: ProfileState, draft: RunState) -> void:
	for content_id: StringName in draft.discovered_content_ids:
		_insert_sorted_unique(profile.discovered_content_ids, content_id)

## Inserts content_id into a StringName ledger keeping it sorted+unique by
## String order. Empty ids are ignored so a caller can mark unconditionally
## without risking a validator-rejecting blank entry.
static func _insert_sorted_unique(ids: Array[StringName], content_id: StringName) -> void:
	var text := String(content_id)
	if text.is_empty():
		return
	var index := 0
	while index < ids.size():
		var existing := String(ids[index])
		if existing == text:
			return
		if existing > text:
			break
		index += 1
	ids.insert(index, content_id)
