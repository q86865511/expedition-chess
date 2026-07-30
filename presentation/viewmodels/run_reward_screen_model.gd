class_name RunRewardScreenModel
extends RefCounted

const SNAPSHOT_INVALID: StringName = &"REWARD_SNAPSHOT_INVALID"

var _snapshot: RunPresentationSnapshot


func compose(snapshot: RunPresentationSnapshot) -> StringName:
	if (
		snapshot == null
		or snapshot.app_phase != &"REWARD"
		or snapshot.pending_reward == null
	):
		_snapshot = null
		return SNAPSHOT_INVALID
	_snapshot = snapshot.deep_clone()
	return &""


func reward_identity() -> String:
	if _snapshot == null or _snapshot.pending_reward == null:
		return ""
	var transaction_digest: StringName = &""
	if _snapshot.pending_reward.transaction_id != null:
		transaction_digest = _snapshot.pending_reward.transaction_id.digest
	return "%s|%s|%s" % [
		String(_snapshot.run_id),
		_snapshot.pending_reward.node_id,
		String(transaction_digest),
	]


func stage_id() -> int:
	return (
		_snapshot.pending_reward.stage_id
		if _snapshot != null and _snapshot.pending_reward != null
		else -1
	)


func phase_id() -> int:
	return (
		_snapshot.pending_reward.phase
		if _snapshot != null and _snapshot.pending_reward != null
		else -1
	)


func offer_ids() -> Array[String]:
	var result: Array[String] = []
	if _snapshot == null or _snapshot.pending_reward == null:
		return result
	for offer: RewardOfferState in _snapshot.pending_reward.offers:
		result.append(offer.choice_id)
	return result


func available_action_kinds() -> Array[int]:
	var result: Array[int] = []
	match phase_id():
		PendingRewardState.Phase.CHOOSING:
			result.append(RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD)
		PendingRewardState.Phase.UNIT_RESOLUTION:
			result.append(RunPresentationIntent.Kind.RESOLVE_UNIT_REWARD)
		PendingRewardState.Phase.ITEM_RESOLUTION:
			result.append(RunPresentationIntent.Kind.RESOLVE_ITEM_REWARD)
			result.append(RunPresentationIntent.Kind.RESOLVE_ITEM_OVERFLOW)
		PendingRewardState.Phase.RELIC_RESOLUTION:
			result.append(RunPresentationIntent.Kind.RESOLVE_RELIC_REWARD)
			result.append(RunPresentationIntent.Kind.REPLACE_RELIC)
			result.append(RunPresentationIntent.Kind.ABANDON_RELIC)
		PendingRewardState.Phase.READY_TO_ADVANCE:
			result.append(RunPresentationIntent.Kind.ADVANCE_REWARD)
	return result


func overflow_ids() -> Array[String]:
	var result: Array[String] = []
	if _snapshot != null and _snapshot.roster != null:
		result.assign(_snapshot.roster.pending_item_overflow)
	return result


func shop_retained_visible() -> bool:
	return (
		_snapshot != null
		and _snapshot.economy != null
		and not _snapshot.economy.shop_offers.is_empty()
	)


func allows(kind: RunPresentationIntent.Kind) -> bool:
	return available_action_kinds().has(kind)


func snapshot_clone() -> RunPresentationSnapshot:
	return _snapshot.deep_clone() if _snapshot != null else null
