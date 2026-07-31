class_name NodeChoiceDef
extends Resource

enum OutcomeKind {
	APPLY_AND_COMPLETE = 1,
	OPEN_DISMANTLE_SERVICE = 2,
	OPEN_REWARD_STAGE = 3,
}

@export var choice_id: StringName
@export var sort_order: int
@export var title_key: StringName
@export var description_key: StringName
@export var preview_key: StringName
@export var result_key: StringName
@export var operations: Array[RunOperationDef] = []
@export var has_reward_table_ref: bool
@export var reward_table_ref: StringName
@export var outcome_kind: OutcomeKind = OutcomeKind.APPLY_AND_COMPLETE
@export var confirmation_required: bool = true
