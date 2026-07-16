class_name EffectSourceState
extends RefCounted

var priority: int = 0
var source_category: StringName = &""
var source_side: StringName = &""
var source_stable_id: StringName = &""
var source_instance_id: OptionalStringNameValue = null
var source_slot: int = 0
var effect_index: int = 0
var effect_id: StringName = &""
var proposal_source_token: String = ""
var instantiated_y: int = 0
var instantiated_x: int = 0

static func from_assignment(value: BattleEffectSnapshot) -> EffectSourceState:
	var state := EffectSourceState.new()
	state.priority = value.priority
	state.source_category = value.source_category
	state.source_side = value.source_side
	state.source_stable_id = value.source_stable_id
	state.source_instance_id = value.source_instance_id.deep_clone() if value.source_instance_id != null else null
	state.source_slot = value.source_slot
	state.effect_index = value.effect_index
	state.effect_id = value.effect_id
	return state

func deep_clone() -> EffectSourceState:
	var copied := EffectSourceState.new()
	copied.priority = priority
	copied.source_category = source_category
	copied.source_side = source_side
	copied.source_stable_id = source_stable_id
	copied.source_instance_id = source_instance_id.deep_clone() if source_instance_id != null else null
	copied.source_slot = source_slot
	copied.effect_index = effect_index
	copied.effect_id = effect_id
	copied.proposal_source_token = proposal_source_token
	copied.instantiated_y = instantiated_y
	copied.instantiated_x = instantiated_x
	return copied
