class_name LiveScreenSupplyPort
extends RefCounted

## Lease-protected, read-only bridge for on-demand run presentation supplies.
## The screen never receives the underlying RunPresentationSession; every
## successful read is cloned again at this boundary so callers cannot retain a
## mutable object owned by either the session or another screen generation.

const SCREEN_NOT_ACTIVE: StringName = &"SCREEN_NOT_ACTIVE"

var _lease: LiveScreenLease
var _registry: LiveScreenLeaseRegistry
var _session: RunPresentationSession


func _init(
	p_lease: LiveScreenLease = null,
	p_registry: LiveScreenLeaseRegistry = null,
	p_session: RunPresentationSession = null
) -> void:
	_lease = p_lease.deep_clone() if p_lease != null else null
	_registry = p_registry
	_session = p_session


func forge_inventory_components() -> Array[ItemInstanceState]:
	var result: Array[ItemInstanceState] = []
	if not _is_active():
		return result
	for item: ItemInstanceState in _session.forge_inventory_components():
		result.append(item.deep_clone() if item != null else null)
	return result


func forge_recipes_containing(
	component_def_id: StringName
) -> Array[ForgeRecipeRule]:
	var result: Array[ForgeRecipeRule] = []
	if not _is_active():
		return result
	for recipe: ForgeRecipeRule in _session.forge_recipes_containing(
		component_def_id
	):
		result.append(recipe.deep_clone() if recipe != null else null)
	return result


func try_forge_pair_recipe(
	component_instance_id_a: String,
	component_instance_id_b: String
) -> ForgeRecipeRule:
	if not _is_active():
		return null
	var recipe := _session.try_forge_pair_recipe(
		component_instance_id_a,
		component_instance_id_b
	)
	return recipe.deep_clone() if recipe != null else null


func shop_economy_status() -> ShopEconomySnapshot:
	if not _is_active():
		return ShopEconomySnapshot.new()
	var snapshot := _session.shop_economy_status()
	return snapshot.deep_clone() if snapshot != null else ShopEconomySnapshot.new()


func shop_refresh_quote() -> ShopQuoteSnapshot:
	if not _is_active():
		return _inactive_shop_quote(&"refresh")
	var snapshot := _session.shop_refresh_quote()
	return snapshot.deep_clone() if snapshot != null else _inactive_shop_quote(&"refresh")


func shop_buy_xp_quote() -> ShopXpQuoteSnapshot:
	if not _is_active():
		return _inactive_xp_quote()
	var snapshot := _session.shop_buy_xp_quote()
	return snapshot.deep_clone() if snapshot != null else _inactive_xp_quote()


func shop_sell_quote(unit_instance_id: String) -> ShopQuoteSnapshot:
	if not _is_active():
		return _inactive_shop_quote(&"sell")
	var snapshot := _session.shop_sell_quote(unit_instance_id)
	return snapshot.deep_clone() if snapshot != null else _inactive_shop_quote(&"sell")


func try_board_draft_preview(
	draft_placements: Array[BoardPlacementState],
	draft_bench_unit_instance_ids: Array[String]
) -> BoardDraftPreviewSnapshot:
	if not _is_active():
		return null
	var preview := _session.try_board_draft_preview(
		draft_placements,
		draft_bench_unit_instance_ids
	)
	return preview.deep_clone() if preview != null else null


func try_committed_board_preview() -> BoardDraftPreviewSnapshot:
	if not _is_active():
		return null
	var preview := _session.try_committed_board_preview()
	return preview.deep_clone() if preview != null else null


func trait_progress() -> Array[TraitProgressSnapshot]:
	var result: Array[TraitProgressSnapshot] = []
	if not _is_active():
		return result
	for progress: TraitProgressSnapshot in _session.trait_progress():
		result.append(progress.deep_clone() if progress != null else null)
	return result


func _is_active() -> bool:
	return (
		_session != null
		and _registry != null
		and _registry.is_active(_lease)
	)


func _inactive_shop_quote(action: StringName) -> ShopQuoteSnapshot:
	var result := ShopQuoteSnapshot.new()
	result.action = action
	result.rejection_code = SCREEN_NOT_ACTIVE
	return result


func _inactive_xp_quote() -> ShopXpQuoteSnapshot:
	var result := ShopXpQuoteSnapshot.new()
	result.rejection_code = SCREEN_NOT_ACTIVE
	return result
