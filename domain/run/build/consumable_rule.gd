class_name ConsumableRule
extends RefCounted

## Pinned-manifest summary of one ConsumableDef (consumable_def.gd:
## use_timing/run_operations), mirroring RunRelicRule. `is_dismantle()` encodes
## the dismantle semantics enforced by content_validator.gd rule (d): a valid
## dismantle consumable has use_timing == &"dismantle" (and no run_operations).

var consumable_id: StringName
var use_timing: StringName
var has_run_operations: bool = false

func is_dismantle() -> bool:
	return use_timing == &"dismantle" and not has_run_operations

func deep_clone() -> ConsumableRule:
	var copied := ConsumableRule.new()
	copied.consumable_id = consumable_id
	copied.use_timing = use_timing
	copied.has_run_operations = has_run_operations
	return copied
