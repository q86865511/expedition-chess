class_name BalanceBotCaseResult
extends RefCounted

var strategy_id: StringName
var seed_index: int
var run_id: StringName
var world_digest: String
var terminal: bool
var won: bool
var act_reached: int
var build_id: StringName
var selected_ids: Array[StringName] = []
var route_ids: Array[StringName] = []
var ending_gold: int
var ending_hp: int
var battle_wins: int
var battle_losses: int
var buy_unit_count: int
var buy_xp_count: int
var reroll_count: int
var sell_unit_count: int
var boss_retry_count: int
var completed_node_count: int
var reload_count: int
var act_snapshots: Array[BalanceBotActSnapshot] = []
var final_phase: StringName = &"UNSET"
var settlement_receipt_digests: Array[String] = []
var reward_receipt_digests: Array[String] = []
var failure_codes: Array[StringName] = []
var replay_digest: String
## Shop offers skipped because the catalog had no BattleUnitRule for their
## unit_def_id (see F08). Diagnostic only: distinguishes "content-catalog
## gap" from "legitimately rare per drop rate" when attributing selection counts.
var null_offer_rule_count: int = 0


func is_valid() -> bool:
	if not BalanceBotStrategy.IDS.has(strategy_id) or seed_index < 0 \
		or run_id.is_empty() or world_digest.length() != 64 \
		or act_reached < 0 or act_reached > 3 or build_id.is_empty() \
		or replay_digest.is_empty():
		return false
	if buy_unit_count < 0 or buy_xp_count < 0 or reroll_count < 0 \
		or sell_unit_count < 0 or boss_retry_count < 0 or null_offer_rule_count < 0:
		return false
	var seen_acts: Dictionary = {}
	for snapshot: BalanceBotActSnapshot in act_snapshots:
		if snapshot == null or not snapshot.is_valid() or seen_acts.has(snapshot.act_index):
			return false
		seen_acts[snapshot.act_index] = true
	return true
