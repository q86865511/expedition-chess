class_name ResolveOverflowCommand
extends RunCommand

## T05 / S4-AC-008 (specs/build-systems/design.md §5.4): resolves one entry of
## the one-shot pending_item_overflow tray with an explicit disposition -- never
## a silent discard. The tray is emptied one instance at a time, each via one of
## three named factories:
##   .equip()   -- binds the overflow item onto a roster unit under an
##                 independently transcribed copy of EquipItemCommand's equip
##                 rules (< 3 slots, no unique_group conflict, def_id must
##                 resolve to a BattleEquipmentRule so a component can never be
##                 equipped). This command does not delegate to EquipItemCommand
##                 (the source item lives in the overflow tray, not inventory),
##                 so the two rule sets are kept in lock-step by hand -- see the
##                 sync note on _apply_equip below.
##   .forge()   -- treats the overflow item as a component and consumes it with a
##                 second component (sourced from either the tray or inventory,
##                 per §5.4) against the pinned ForgeRecipeTable, minting one
##                 complete equipment into inventory (or back into overflow when
##                 inventory is full); a pair with no registered recipe is
##                 rejected by name.
##   .abandon() -- an explicit true discard: the instance is removed everywhere.
## The pinned catalog/table generation is checked against the draft's
## content_snapshot first (mirrors equip_item_command.gd:39-43 /
## forge_equipment_command.gd:44-48). Any rejection leaves `draft` untouched --
## the tray and all binding/inventory state are preserved -- and returns a named
## "source_code" diagnostic (see commit_board_layout_command.gd's `_rejected`
## convention, read via EquipDismantleTestFixture.error_source_code()).

const EQUIPMENT_CAPACITY: int = 3
const INVENTORY_CAPACITY: int = 16

enum Disposition { EQUIP, FORGE, ABANDON }

var _disposition: Disposition
var _overflow_item_instance_id: String
var _target_unit_instance_id: String
var _other_component_instance_id: String
var _catalog: BattleRuleCatalog
var _forge_table: ForgeRecipeTable

func _init(
	p_disposition: Disposition,
	p_overflow_item_instance_id: String,
	p_target_unit_instance_id: String,
	p_other_component_instance_id: String,
	p_catalog: BattleRuleCatalog,
	p_forge_table: ForgeRecipeTable
) -> void:
	_disposition = p_disposition
	_overflow_item_instance_id = p_overflow_item_instance_id
	_target_unit_instance_id = p_target_unit_instance_id
	_other_component_instance_id = p_other_component_instance_id
	_catalog = p_catalog.deep_clone() if p_catalog != null else null
	_forge_table = p_forge_table.deep_clone() if p_forge_table != null else null

static func equip(
	overflow_item_instance_id: String,
	target_unit_instance_id: String,
	catalog: BattleRuleCatalog
) -> ResolveOverflowCommand:
	return ResolveOverflowCommand.new(
		Disposition.EQUIP, overflow_item_instance_id, target_unit_instance_id, "", catalog, null
	)

static func forge(
	overflow_item_instance_id: String,
	other_component_instance_id: String,
	forge_table: ForgeRecipeTable
) -> ResolveOverflowCommand:
	return ResolveOverflowCommand.new(
		Disposition.FORGE, overflow_item_instance_id, "", other_component_instance_id, null, forge_table
	)

static func abandon(overflow_item_instance_id: String) -> ResolveOverflowCommand:
	return ResolveOverflowCommand.new(
		Disposition.ABANDON, overflow_item_instance_id, "", "", null, null
	)

func is_concrete() -> bool:
	if _overflow_item_instance_id.is_empty():
		return false
	match _disposition:
		Disposition.EQUIP:
			return not _target_unit_instance_id.is_empty() and _catalog != null
		Disposition.FORGE:
			return not _other_component_instance_id.is_empty() and _forge_table != null
		Disposition.ABANDON:
			return true
	return false

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.roster_state == null:
		return _rejected(&"run.roster_state", &"RESOLVE_OVERFLOW_DRAFT_INVALID")
	# Every disposition operates only on an item that is genuinely sitting in the
	# one-shot tray as an unbound instance -- an item elsewhere (inventory, bound
	# on a unit, or absent) is never a tray entry and can never be silently
	# dispositioned.
	if not draft.roster_state.pending_item_overflow.has(_overflow_item_instance_id):
		return _rejected(
			&"run.roster_state.pending_item_overflow", &"RESOLVE_OVERFLOW_ITEM_NOT_IN_TRAY"
		)
	var overflow_item := _find_item(draft, _overflow_item_instance_id)
	if overflow_item == null or overflow_item.bound_unit_instance_id != null:
		return _rejected(
			&"run.roster_state.item_instances", &"RESOLVE_OVERFLOW_ITEM_NOT_IN_TRAY"
		)
	match _disposition:
		Disposition.EQUIP:
			return _apply_equip(draft, overflow_item)
		Disposition.FORGE:
			return _apply_forge(draft, overflow_item)
		Disposition.ABANDON:
			return _apply_abandon(draft, overflow_item)
	return _rejected(&"run.roster_state", &"RESOLVE_OVERFLOW_DRAFT_INVALID")

func _apply_equip(draft: RunState, overflow_item: ItemInstanceState) -> CommandApplyResult:
	if draft.content_snapshot == null:
		return _rejected(&"run.content_snapshot", &"RESOLVE_OVERFLOW_DRAFT_INVALID")
	if _catalog.manifest_digest_value() != draft.content_snapshot.manifest_digest_value():
		return _rejected(
			&"run.content_snapshot.manifest_digest", &"RESOLVE_OVERFLOW_CATALOG_GENERATION_MISMATCH"
		)
	var unit := _find_unit(draft, _target_unit_instance_id)
	if unit == null:
		return _rejected(&"run.roster_state.unit_instances", &"RESOLVE_OVERFLOW_UNIT_NOT_FOUND")
	# SYNC: the three equip rules below (equipment-rule resolves, slots < capacity,
	# no unique_group conflict) are a hand-kept copy of equip_item_command.gd:51-63
	# -- any change to that check logic must be mirrored here (and vice versa).
	var rule := _catalog.try_equipment_rule(overflow_item.def_id)
	if rule == null:
		return _rejected(
			&"run.roster_state.item_instances.def_id", &"RESOLVE_OVERFLOW_NOT_EQUIPMENT"
		)
	if unit.equipment_instance_ids.size() >= EQUIPMENT_CAPACITY:
		return _rejected(
			&"run.roster_state.unit_instances.equipment_instance_ids", &"RESOLVE_OVERFLOW_SLOTS_FULL"
		)
	if rule.unique_group != null \
		and _has_unique_conflict(draft, unit, rule.unique_group.value):
		return _rejected(
			&"run.roster_state.unit_instances.equipment_instance_ids",
			&"RESOLVE_OVERFLOW_UNIQUE_GROUP_CONFLICT"
		)
	# Single atomic mutation -- only reached once every guard has passed.
	overflow_item.bound_unit_instance_id = OptionalStringValue.new(_target_unit_instance_id)
	unit.equipment_instance_ids.append(_overflow_item_instance_id)
	draft.roster_state.pending_item_overflow.erase(_overflow_item_instance_id)
	return CommandApplyResult.success(draft)

func _apply_forge(draft: RunState, overflow_item: ItemInstanceState) -> CommandApplyResult:
	if draft.content_snapshot == null or draft.next_item_serial == null:
		return _rejected(&"run.roster_state", &"RESOLVE_OVERFLOW_DRAFT_INVALID")
	if _forge_table.manifest_digest_value() != draft.content_snapshot.manifest_digest_value():
		return _rejected(
			&"run.content_snapshot.manifest_digest", &"RESOLVE_OVERFLOW_CATALOG_GENERATION_MISMATCH"
		)
	# The second component must be a distinct, unbound instance available in the
	# tray or in inventory (§5.4). The overflow instance itself can never double
	# as the partner.
	var partner := _find_forge_partner(draft, _other_component_instance_id)
	if partner == null or _other_component_instance_id == _overflow_item_instance_id:
		return _rejected(
			&"run.roster_state.item_instances", &"RESOLVE_OVERFLOW_COMPONENT_NOT_AVAILABLE"
		)
	var recipe := _forge_table.try_recipe(overflow_item.def_id, partner.def_id)
	if recipe == null:
		return _rejected(
			&"run.roster_state.item_instances.def_id", &"RESOLVE_OVERFLOW_RECIPE_NOT_FOUND"
		)
	var created := InstanceIdFactory.new().create(&"it", draft.next_item_serial)
	if not created.ok:
		return _rejected(&"run.next_item_serial", &"RESOLVE_OVERFLOW_SERIAL_EXHAUSTED")
	# Single atomic mutation -- only reached once every guard has passed, so a
	# rejection above always leaves tray/inventory/item_instances untouched.
	draft.roster_state.pending_item_overflow.erase(_overflow_item_instance_id)
	draft.roster_state.pending_item_overflow.erase(_other_component_instance_id)
	draft.roster_state.inventory_item_instance_ids.erase(_other_component_instance_id)
	draft.roster_state.item_instances.erase(overflow_item)
	draft.roster_state.item_instances.erase(partner)
	var forged_id := String(created.instance_id)
	draft.roster_state.item_instances.append(ItemInstanceState.new(
		forged_id, recipe.equipment_id, null, draft.next_item_serial
	))
	if draft.roster_state.inventory_item_instance_ids.size() < INVENTORY_CAPACITY:
		draft.roster_state.inventory_item_instance_ids.append(forged_id)
		draft.roster_state.inventory_item_instance_ids.sort()
	else:
		draft.roster_state.pending_item_overflow.append(forged_id)
		draft.roster_state.pending_item_overflow.sort()
	draft.next_item_serial = created.next_serial.deep_clone()
	return CommandApplyResult.success(draft)

func _apply_abandon(draft: RunState, overflow_item: ItemInstanceState) -> CommandApplyResult:
	draft.roster_state.pending_item_overflow.erase(_overflow_item_instance_id)
	draft.roster_state.item_instances.erase(overflow_item)
	draft.roster_state.inventory_item_instance_ids.erase(_overflow_item_instance_id)
	return CommandApplyResult.success(draft)

## An eligible forge partner is an unbound item instance that exists in
## item_instances and is currently held in either the overflow tray or
## inventory -- a bound item, or one absent from both holding lists, is never
## available.
func _find_forge_partner(draft: RunState, item_instance_id: String) -> ItemInstanceState:
	var in_inventory := draft.roster_state.inventory_item_instance_ids.has(item_instance_id)
	var in_tray := draft.roster_state.pending_item_overflow.has(item_instance_id)
	if not in_inventory and not in_tray:
		return null
	var item := _find_item(draft, item_instance_id)
	if item == null or item.bound_unit_instance_id != null:
		return null
	return item

func _has_unique_conflict(
	draft: RunState,
	unit: UnitInstance,
	unique_group: StringName
) -> bool:
	for equipped_id: String in unit.equipment_instance_ids:
		var equipped_item := _find_item(draft, equipped_id)
		if equipped_item == null:
			continue
		var equipped_rule := _catalog.try_equipment_rule(equipped_item.def_id)
		if equipped_rule != null and equipped_rule.unique_group != null \
			and equipped_rule.unique_group.value == unique_group:
			return true
	return false

func _find_unit(draft: RunState, unit_instance_id: String) -> UnitInstance:
	for unit: UnitInstance in draft.roster_state.unit_instances:
		if unit.instance_id == unit_instance_id:
			return unit
	return null

func _find_item(draft: RunState, item_instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in draft.roster_state.item_instances:
		if item.instance_id == item_instance_id:
			return item
	return null

func _rejected(field_path: StringName, source_code: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(source_code)),
	]
	return CommandApplyResult.failure(
		CommandApplyError.new(CommandApplyError.APPLY_REJECTED, field_path, null, diagnostics)
	)
