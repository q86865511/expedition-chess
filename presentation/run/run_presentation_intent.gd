class_name RunPresentationIntent
extends RefCounted

enum Kind {
	GENERATE_MAP,
	ENTER_NODE,
	REFRESH_SHOP,
	BUY_UNIT,
	BUY_XP,
	SELL_UNIT,
	COMMIT_BOARD_LAYOUT,
	FORGE_EQUIPMENT,
	EQUIP_ITEM,
	DISMANTLE_EQUIPMENT,
	START_OR_RESUME_COMBAT,
	SETTLE_BATTLE,
	RESOLVE_NON_COMBAT,
	CHOOSE_STANDARD_REWARD,
	RESOLVE_UNIT_REWARD,
	RESOLVE_ITEM_REWARD,
	RESOLVE_RELIC_REWARD,
	ADVANCE_REWARD,
	RESOLVE_UNIT_OVERFLOW,
	RESOLVE_ITEM_OVERFLOW,
	REPLACE_RELIC,
	ABANDON_RELIC,
	ABANDON_BOSS_RETRY,
	SETTLE_TERMINAL_RUN,
	COMMIT_NODE_CHOICE,
	ACKNOWLEDGE_NODE_CHOICE_RESULT,
	DISMANTLE_WITH_NODE_SERVICE,
	EXIT_NODE_SERVICE,
}

var kind: Kind
var target_node_id: String
var offer_id: String
var unit_instance_id: String
var item_instance_id: String
var secondary_item_instance_id: String
var target_unit_instance_id: String
var choice_id: String
var choice_set_id: StringName
## design.md §5:173-178：COMMIT_NODE_CHOICE 的 exact payload。intent 只搬運它，
## 不在 dispatch 時回頭讀 canonical state（見 node_choice_commit_payload.gd 檔頭）。
var node_choice_payload: NodeChoiceCommitPayload
## node service（design :208-214）與 ack（design :201-203）各自的 identity 欄位。
var expected_run_id: String
var node_id: StringName
var choice_receipt_digest: String
var receipt_digest: String
var accept: bool
var abandon: bool
var relic_slot_index: int = -1
var board: BoardState
var bench_unit_instance_ids: Array[String] = []
var battle_sources: BattleSetupSourceBundle


func _init(p_kind: Kind = Kind.GENERATE_MAP) -> void:
	kind = p_kind


func deep_clone() -> RunPresentationIntent:
	var clone := RunPresentationIntent.new(kind)
	clone.target_node_id = target_node_id
	clone.offer_id = offer_id
	clone.unit_instance_id = unit_instance_id
	clone.item_instance_id = item_instance_id
	clone.secondary_item_instance_id = secondary_item_instance_id
	clone.target_unit_instance_id = target_unit_instance_id
	clone.choice_id = choice_id
	clone.choice_set_id = choice_set_id
	clone.node_choice_payload = (
		node_choice_payload.deep_clone()
		if node_choice_payload != null
		else null
	)
	clone.expected_run_id = expected_run_id
	clone.node_id = node_id
	clone.choice_receipt_digest = choice_receipt_digest
	clone.receipt_digest = receipt_digest
	clone.accept = accept
	clone.abandon = abandon
	clone.relic_slot_index = relic_slot_index
	clone.board = board.deep_clone() if board != null else null
	clone.bench_unit_instance_ids.assign(bench_unit_instance_ids)
	clone.battle_sources = battle_sources.deep_clone() if battle_sources != null else null
	return clone
