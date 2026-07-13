class_name TestMutationCommand
extends RunCommand

enum Kind { SET_HP, INVALID_COMMANDER, REJECT, REPLACE_CONTENT_DIGEST }

var kind: Kind
var hp_value: int

func _init(p_kind: Kind, p_hp_value: int = 100) -> void:
	kind = p_kind
	hp_value = p_hp_value

func is_concrete() -> bool:
	return true

func apply_to(draft: RunState) -> CommandApplyResult:
	match kind:
		Kind.SET_HP:
			draft.expedition_hp = hp_value
			return CommandApplyResult.success(draft)
		Kind.INVALID_COMMANDER:
			draft.commander_id = &"INVALID"
			return CommandApplyResult.success(draft)
		Kind.REJECT:
			return CommandApplyResult.failure(
				CommandApplyError.new(CommandApplyError.APPLY_REJECTED, &"test.command")
			)
		Kind.REPLACE_CONTENT_DIGEST:
			var snapshot := draft.content_snapshot
			draft.content_snapshot = ContentSnapshotState.new(
				snapshot.content_version_value(),
				snapshot.enabled_content_ids_copy(),
				snapshot.economy_config_id_value(),
				snapshot.reward_table_ids_copy(),
				snapshot.map_node_def_ids_copy(),
				snapshot.challenge_unlock_def_ids_copy(),
				snapshot.meta_reward_table_id_value(),
				"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
			)
			return CommandApplyResult.success(draft)
	return CommandApplyResult.failure(
		CommandApplyError.new(CommandApplyError.APPLY_REJECTED, &"test.command.kind")
	)
