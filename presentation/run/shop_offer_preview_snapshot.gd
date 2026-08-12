class_name ShopOfferPreviewSnapshot
extends RefCounted

var offer_id: StringName
var slot_index: int
var unit_def_id: StringName
var cost: int
var cost_tier: int
var trait_ids: Array[StringName] = []
var owned_unit_count: int
var star_up_after_purchase: bool


func deep_clone() -> ShopOfferPreviewSnapshot:
	var clone := ShopOfferPreviewSnapshot.new()
	clone.offer_id = offer_id
	clone.slot_index = slot_index
	clone.unit_def_id = unit_def_id
	clone.cost = cost
	clone.cost_tier = cost_tier
	clone.trait_ids.assign(trait_ids)
	clone.owned_unit_count = owned_unit_count
	clone.star_up_after_purchase = star_up_after_purchase
	return clone
