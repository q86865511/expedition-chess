class_name ForgeEquipmentCommand
extends RunCommand

## T03 / S4-AC-004/005 (specs/build-systems/design.md §5.1): consumes two
## inventory component instances -- looked up as an unordered component-pair
## (including a self-pair of the same def_id) -- to forge exactly one complete
## equipment instance in the same transaction. The pair resolves against the
## pinned ForgeRecipeTable (21-closed): a pair with no registered recipe is
## rejected by name, never silently no-op crafted. On success both components
## are removed from item_instances and inventory, and one new equipment
## instance is minted from RunState.next_item_serial (advancing it by one) into
## inventory (or pending_item_overflow when inventory is already full). The
## pinned catalog generation is checked against the draft's content_snapshot
## first (see equip_item_command.gd:39-43), so a stale table can never author a
## commit against a newer pinned run. Any rejection leaves `draft` untouched and
## returns a named "source_code" diagnostic (see commit_board_layout_command.gd's
## `_rejected` convention). Components are never directly equippable -- this
## command is their only synthesis path (EquipItemCommand rejects them).

const INVENTORY_CAPACITY: int = 16

var _component_instance_id_a: String
var _component_instance_id_b: String
var _forge_table: ForgeRecipeTable

func _init(
	p_component_instance_id_a: String,
	p_component_instance_id_b: String,
	p_forge_table: ForgeRecipeTable
) -> void:
	_component_instance_id_a = p_component_instance_id_a
	_component_instance_id_b = p_component_instance_id_b
	_forge_table = p_forge_table.deep_clone() if p_forge_table != null else null

func is_concrete() -> bool:
	return not _component_instance_id_a.is_empty() \
		and not _component_instance_id_b.is_empty() \
		and _forge_table != null

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.roster_state == null \
		or draft.content_snapshot == null or draft.next_item_serial == null:
		return _rejected(&"run.roster_state", &"FORGE_EQUIPMENT_DRAFT_INVALID")
	if _forge_table.manifest_digest_value() != draft.content_snapshot.manifest_digest_value():
		return _rejected(
			&"run.content_snapshot.manifest_digest",
			&"FORGE_EQUIPMENT_CATALOG_GENERATION_MISMATCH"
		)
	# A single inventory item can never be consumed twice, even when its def_id
	# would otherwise satisfy a self-pair recipe: the two slots must reference
	# two distinct instances.
	if _component_instance_id_a == _component_instance_id_b:
		return _rejected(
			&"run.roster_state.inventory_item_instance_ids", &"FORGE_EQUIPMENT_DUPLICATE_INSTANCE"
		)
	var component_a := _find_available_component(draft, _component_instance_id_a)
	var component_b := _find_available_component(draft, _component_instance_id_b)
	if component_a == null or component_b == null:
		return _rejected(
			&"run.roster_state.item_instances", &"FORGE_EQUIPMENT_COMPONENT_NOT_IN_INVENTORY"
		)
	var recipe := _forge_table.try_recipe(component_a.def_id, component_b.def_id)
	if recipe == null:
		return _rejected(
			&"run.roster_state.item_instances.def_id", &"FORGE_EQUIPMENT_RECIPE_NOT_FOUND"
		)
	var created := InstanceIdFactory.new().create(&"it", draft.next_item_serial)
	if not created.ok:
		return _rejected(&"run.next_item_serial", &"FORGE_EQUIPMENT_SERIAL_EXHAUSTED")

	# Single atomic draft mutation -- only reached once every guard has passed,
	# so a rejection above always leaves item_instances/inventory/next_item_serial
	# untouched.
	draft.roster_state.inventory_item_instance_ids.erase(_component_instance_id_a)
	draft.roster_state.inventory_item_instance_ids.erase(_component_instance_id_b)
	draft.roster_state.item_instances.erase(component_a)
	draft.roster_state.item_instances.erase(component_b)
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
	# T09 / S5-AC-012 (design.md §8): 取得裝備 -> discover the forged equipment in
	# the same copy-validate-save-swap transaction.
	RunDiscoveryLog.mark(draft, recipe.equipment_id)
	return CommandApplyResult.success(draft)

## An eligible forge input is an inventory item that exists in item_instances,
## is unbound (not equipped on a unit), and is actually sitting in
## inventory_item_instance_ids -- an item bound elsewhere or absent from
## inventory is never an available component.
func _find_available_component(draft: RunState, item_instance_id: String) -> ItemInstanceState:
	if not draft.roster_state.inventory_item_instance_ids.has(item_instance_id):
		return null
	var item := _find_item(draft, item_instance_id)
	if item == null or item.bound_unit_instance_id != null:
		return null
	return item

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
