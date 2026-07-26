class_name PopulationSourceSnapshot
extends RefCounted

## COMMANDER (S5, design.md SS4.2) is appended last so the existing kinds keep
## their wire ordinals and their position in PopulationCalculator's identity sort.
enum SourceKind {
	EVENT = 0,
	RELIC = 1,
	TRAIT = 2,
	COMMANDER = 3,
}

var source_kind: SourceKind
var source_id: StringName
var source_instance_or_slot: String
var amount: int

func _init(
	p_source_kind: SourceKind,
	p_source_id: StringName,
	p_source_instance_or_slot: String,
	p_amount: int
) -> void:
	source_kind = p_source_kind
	source_id = p_source_id
	source_instance_or_slot = p_source_instance_or_slot
	amount = p_amount

func deep_clone() -> PopulationSourceSnapshot:
	return PopulationSourceSnapshot.new(
		source_kind,
		source_id,
		source_instance_or_slot,
		amount
	)
