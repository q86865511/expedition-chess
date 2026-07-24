class_name UnlockPurchaseService
extends RefCounted

## T04 (design.md §4.3; requirements.md S5-AC-011): the sole place the three
## named purchase-rejection errors are computed. Pure, deterministic, no RNG
## (design.md §13). A rejected call leaves the CALLER's original profile
## argument completely untouched ("零變更"); success returns a freshly-cloned
## profile (never the same instance passed in). Validation clause order follows
## design.md §4.3 literally, each clause independently observable.

func purchase(profile: ProfileState, unlock_def: UnlockDef) -> UnlockPurchaseResult:
	if profile == null or unlock_def == null:
		return UnlockPurchaseResult.failure(
			UnlockPurchaseError.new(UnlockPurchaseError.INPUT_INVALID, &"unlock_def")
		)
	# a. insufficient currency
	if unlock_def.currency_cost > profile.meta_currency:
		return UnlockPurchaseResult.failure(
			UnlockPurchaseError.new(
				UnlockPurchaseError.UNLOCK_INSUFFICIENT_CURRENCY,
				&"profile.meta_currency"
			)
		)
	# b. already owned -- any id this unlock would grant is already held
	# (design.md §4.3: unlocked_content_ids IS the purchase record).
	for granted: StringName in unlock_def.unlocked_content_refs:
		if profile.unlocked_content_ids.has(granted):
			return UnlockPurchaseResult.failure(
				UnlockPurchaseError.new(
					UnlockPurchaseError.UNLOCK_ALREADY_OWNED,
					&"profile.unlocked_content_ids"
				)
			)
	# c. prerequisite unmet -- any required id not yet held
	for prerequisite: StringName in unlock_def.prerequisite_refs:
		if not profile.unlocked_content_ids.has(prerequisite):
			return UnlockPurchaseResult.failure(
				UnlockPurchaseError.new(
					UnlockPurchaseError.UNLOCK_PREREQUISITE_UNMET,
					&"profile.unlocked_content_ids"
				)
			)
	# d. success: deduct cost, merge grants into canonical sorted/unique order
	# (matches ContentSnapshotState._canonicalize_ids /
	# RunStateValidator._sorted_unique_names: ascending by String()).
	var draft := profile.deep_clone()
	draft.meta_currency -= unlock_def.currency_cost
	var merged: Array[StringName] = []
	merged.assign(draft.unlocked_content_ids)
	for granted: StringName in unlock_def.unlocked_content_refs:
		if not merged.has(granted):
			merged.append(granted)
	merged.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	draft.unlocked_content_ids = merged
	return UnlockPurchaseResult.success(draft)
