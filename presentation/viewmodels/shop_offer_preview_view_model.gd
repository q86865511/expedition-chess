class_name ShopOfferPreviewViewModel
extends RefCounted

## Shop metadata comes from the same pinned BattleRuleCatalog clone as combat.
## Star-up prediction delegates to UnitMergeService on a cloned roster.

var _roster: RosterState
var _catalog: BattleRuleCatalog


func _init(roster: RosterState, catalog: BattleRuleCatalog) -> void:
	_roster = roster.deep_clone() if roster != null else null
	_catalog = catalog.deep_clone() if catalog != null else null


func previews(economy: EconomyState) -> Array[ShopOfferPreviewSnapshot]:
	var result: Array[ShopOfferPreviewSnapshot] = []
	if economy == null or _roster == null or _catalog == null:
		return result
	for offer: ShopOffer in economy.shop_offers:
		if offer == null:
			continue
		var rule := _catalog.try_unit_rule(offer.unit_def_id)
		if rule == null:
			continue
		var preview := ShopOfferPreviewSnapshot.new()
		preview.offer_id = StringName(offer.offer_id)
		preview.slot_index = offer.slot_index
		preview.unit_def_id = offer.unit_def_id
		preview.cost = offer.cost
		preview.cost_tier = rule.cost_tier
		preview.trait_ids.assign(rule.trait_ids)
		preview.owned_unit_count = _owned_unit_count(offer.unit_def_id)
		preview.star_up_after_purchase = _would_star_up(offer)
		result.append(preview)
	result.sort_custom(
		func(left: ShopOfferPreviewSnapshot, right: ShopOfferPreviewSnapshot) -> bool:
			return left.slot_index < right.slot_index
	)
	return result


func _owned_unit_count(unit_def_id: StringName) -> int:
	var count := 0
	for unit: UnitInstance in _roster.unit_instances:
		if unit != null and unit.def_id == unit_def_id:
			count += 1
	return count


func _would_star_up(offer: ShopOffer) -> bool:
	var draft := _roster.deep_clone()
	var before_star := _highest_star(draft, offer.unit_def_id)
	var equipment: Array[String] = []
	var preview_id := "preview_%s" % offer.offer_id
	draft.unit_instances.append(UnitInstance.new(
		preview_id, offer.unit_def_id, 1, equipment, U64Bits.zero()
	))
	draft.bench_unit_instance_ids.append(preview_id)
	var merged := UnitMergeService.new().merge_all(draft, _catalog)
	return (
		merged.ok
		and merged.roster != null
		and _highest_star(merged.roster, offer.unit_def_id) > before_star
	)


func _highest_star(roster: RosterState, unit_def_id: StringName) -> int:
	var highest := 0
	for unit: UnitInstance in roster.unit_instances:
		if unit != null and unit.def_id == unit_def_id:
			highest = maxi(highest, unit.star)
	return highest
