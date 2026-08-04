class_name BalanceBotReport
extends RefCounted

const SCHEMA_VERSION: int = 1
const DOMINANCE_BPS: int = 2000
const FINAL_CASE_COUNT: int = 30000
const MIN_TERMINAL_PER_STRATEGY: int = 500
const MIN_WINS_PER_STRATEGY: int = 50
const REPLAY_SAMPLE_MODULUS: int = 20
const REPLAY_SAMPLE_RATE_BPS: int = 500

var candidate: BalanceCandidateDescriptor
var cases: Array[BalanceBotCaseResult] = []
var cohort_seed_count: int
var failures: Array[StringName] = []
var primary_elapsed_ms_total: int = 0
var primary_timed_case_count: int = 0
var replay_elapsed_ms_total: int = 0
var replay_sampled_case_ids: Array[String] = []
var replay_drift_case_ids: Array[String] = []


func _init(p_candidate: BalanceCandidateDescriptor, p_cohort_seed_count: int) -> void:
	candidate = p_candidate.deep_clone() if p_candidate != null else null
	cohort_seed_count = p_cohort_seed_count


func append(value: BalanceBotCaseResult) -> void:
	if value == null or not value.is_valid():
		failures.append(&"BALANCE_CASE_INVALID")
		return
	cases.append(value)


func record_primary_elapsed_ms(elapsed_ms: int) -> void:
	if elapsed_ms < 0:
		failures.append(&"BALANCE_PRIMARY_ELAPSED_INVALID")
		return
	primary_elapsed_ms_total += elapsed_ms
	primary_timed_case_count += 1


func record_replay_sample(
	strategy_id: StringName, seed_index: int, elapsed_ms: int, matched: bool
) -> void:
	if not BalanceBotStrategy.IDS.has(strategy_id) or seed_index < 0 or elapsed_ms < 0:
		failures.append(&"BALANCE_REPLAY_SAMPLE_INVALID")
		return
	var case_id := "%s:%d" % [String(strategy_id), seed_index]
	if replay_sampled_case_ids.has(case_id):
		failures.append(&"BALANCE_REPLAY_SAMPLE_DUPLICATE")
		return
	replay_sampled_case_ids.append(case_id)
	replay_sampled_case_ids.sort()
	replay_elapsed_ms_total += elapsed_ms
	if not matched:
		replay_drift_case_ids.append(case_id)
		replay_drift_case_ids.sort()


static func replay_selected(seed_index: int) -> bool:
	return seed_index >= 0 and seed_index % REPLAY_SAMPLE_MODULUS == 0


func gate_reasons(
	final_gate: bool, enforce_sample_minimums: bool = false
) -> Array[StringName]:
	var reasons: Array[StringName] = failures.duplicate()
	for value: BalanceBotCaseResult in cases:
		for code: StringName in value.failure_codes:
			if not reasons.has(code):
				reasons.append(code)
	if final_gate and cases.size() != FINAL_CASE_COUNT:
		reasons.append(&"BALANCE_FINAL_CASE_COUNT_MISMATCH")
	if cases.size() != cohort_seed_count * BalanceBotStrategy.IDS.size():
		reasons.append(&"BALANCE_COHORT_CASE_COUNT_MISMATCH")
	if _cohort_world_mismatch():
		reasons.append(&"BALANCE_COHORT_WORLD_MISMATCH")
	for strategy_id: StringName in BalanceBotStrategy.IDS:
		var terminal := _count(strategy_id, true, false)
		var wins := _count(strategy_id, true, true)
		if (final_gate or enforce_sample_minimums) \
			and terminal < MIN_TERMINAL_PER_STRATEGY:
			reasons.append(StringName("BALANCE_%s_TERMINAL_SAMPLE_LOW" % String(strategy_id).to_upper()))
		if (final_gate or enforce_sample_minimums) \
			and wins < MIN_WINS_PER_STRATEGY:
			reasons.append(StringName("BALANCE_%s_WIN_SAMPLE_LOW" % String(strategy_id).to_upper()))
	if _dominance_exceeds_limit(true):
		reasons.append(&"BALANCE_BUILD_WIN_RATE_DOMINANCE")
	if _dominance_exceeds_limit(false):
		reasons.append(&"BALANCE_BUILD_SELECTION_DOMINANCE")
	if _all_strategies_have_perfect_win_rate():
		reasons.append(&"BALANCE_ALL_STRATEGIES_PERFECT_WIN_RATE")
	if not cases.is_empty() and _fallback_build_count() == cases.size():
		reasons.append(&"BALANCE_BUILD_ID_ALL_FALLBACK")
	if not cases.is_empty() and _unique_ending_gold().size() == 1:
		reasons.append(&"BALANCE_ENDING_GOLD_CONSTANT")
	return reasons


func passed(final_gate: bool, enforce_sample_minimums: bool = false) -> bool:
	return candidate != null and candidate.is_valid() \
		and gate_reasons(final_gate, enforce_sample_minimums).is_empty()


func to_json(final_gate: bool, enforce_sample_minimums: bool = false) -> String:
	var strategy_rows: Array[Dictionary] = []
	for strategy_id: StringName in BalanceBotStrategy.IDS:
		strategy_rows.append({
			"strategy_id": String(strategy_id),
			"cases": _strategy_total(strategy_id),
			"terminal": _count(strategy_id, true, false),
			"wins": _count(strategy_id, true, true),
			"act1_reached": _act_count(strategy_id, 1),
			"act2_reached": _act_count(strategy_id, 2),
			"act3_reached": _act_count(strategy_id, 3),
			"buy_unit_count": _action_count(strategy_id, &"buy_unit"),
			"buy_xp_count": _action_count(strategy_id, &"buy_xp"),
			"reroll_count": _action_count(strategy_id, &"reroll"),
			"sell_unit_count": _action_count(strategy_id, &"sell_unit"),
			"boss_retry_count": _action_count(strategy_id, &"boss_retry"),
		})
	var build_rows: Array[Dictionary] = []
	for build_id: StringName in _build_ids():
		var selected := 0
		var wins := 0
		for value: BalanceBotCaseResult in cases:
			if value.build_id == build_id:
				selected += 1
				if value.won:
					wins += 1
		build_rows.append({
			"build_id": String(build_id), "selected": selected, "wins": wins,
			"selection_rate_bps": _rate_bps(selected, cases.size()),
			"win_rate_bps": _rate_bps(wins, selected),
		})
	var reason_text: Array[String] = []
	for reason: StringName in gate_reasons(final_gate, enforce_sample_minimums):
		reason_text.append(String(reason))
	var failed_seeds: Array[Dictionary] = []
	var case_proofs: Array[Dictionary] = []
	var route_counts: Dictionary = {}
	var selected_counts: Dictionary = {}
	var ending_gold_total := 0
	var ending_hp_total := 0
	var battle_wins := 0
	var battle_losses := 0
	var replay_parts: Array[String] = ["BALANCE-BOT-REPORT-V1"]
	for value: BalanceBotCaseResult in cases:
		ending_gold_total += value.ending_gold
		ending_hp_total += value.ending_hp
		battle_wins += value.battle_wins
		battle_losses += value.battle_losses
		replay_parts.append("%s:%d:%s" % [
			String(value.strategy_id), value.seed_index, value.replay_digest
		])
		var selected_ids: Array[String] = []
		for selected_id: StringName in value.selected_ids:
			selected_ids.append(String(selected_id))
		var route_ids: Array[String] = []
		for route_id: StringName in value.route_ids:
			route_ids.append(String(route_id))
		var failure_codes: Array[String] = []
		for failure_code: StringName in value.failure_codes:
			failure_codes.append(String(failure_code))
		var act_snapshots: Array[Dictionary] = []
		for act_snapshot: BalanceBotActSnapshot in value.act_snapshots:
			var stable_unit_ids: Array[String] = []
			for unit_id: StringName in act_snapshot.stable_unit_ids:
				stable_unit_ids.append(String(unit_id))
			act_snapshots.append({
				"act_index": act_snapshot.act_index,
				"gold": act_snapshot.gold,
				"expedition_hp": act_snapshot.expedition_hp,
				"roster_unit_count": act_snapshot.roster_unit_count,
				"board_unit_count": act_snapshot.board_unit_count,
				"stable_unit_ids": stable_unit_ids,
			})
		case_proofs.append({
			"strategy_id": String(value.strategy_id),
			"seed_index": value.seed_index,
			"run_id": String(value.run_id),
			"world_digest": value.world_digest,
			"terminal": value.terminal,
			"won": value.won,
			"act_reached": value.act_reached,
			"build_id": String(value.build_id),
			"selected_ids": selected_ids,
			"route_ids": route_ids,
			"ending_gold": value.ending_gold,
			"ending_hp": value.ending_hp,
			"battle_wins": value.battle_wins,
			"battle_losses": value.battle_losses,
			"buy_unit_count": value.buy_unit_count,
			"buy_xp_count": value.buy_xp_count,
			"reroll_count": value.reroll_count,
			"sell_unit_count": value.sell_unit_count,
			"boss_retry_count": value.boss_retry_count,
			"completed_node_count": value.completed_node_count,
			"reload_count": value.reload_count,
			"null_offer_rule_count": value.null_offer_rule_count,
			"act_snapshots": act_snapshots,
			"final_phase": String(value.final_phase),
			"settlement_receipt_count": value.settlement_receipt_digests.size(),
			"settlement_receipt_digests": value.settlement_receipt_digests.duplicate(),
			"reward_receipt_count": value.reward_receipt_digests.size(),
			"reward_receipt_digests": value.reward_receipt_digests.duplicate(),
			"failure_codes": failure_codes,
			"replay_digest": value.replay_digest,
		})
		for route_id: StringName in value.route_ids:
			var route_key := String(route_id)
			route_counts[route_key] = int(route_counts.get(route_key, 0)) + 1
		for selected_id: StringName in value.selected_ids:
			var selected_key := String(selected_id)
			selected_counts[selected_key] = int(selected_counts.get(selected_key, 0)) + 1
		if not value.failure_codes.is_empty():
			var codes: Array[String] = []
			for code: StringName in value.failure_codes:
				codes.append(String(code))
			failed_seeds.append({
				"strategy_id": String(value.strategy_id),
				"seed_index": value.seed_index,
				"failure_codes": codes,
				"replay_digest": value.replay_digest,
			})
	var replay_sample_rows: Array[Dictionary] = []
	for case_id: String in replay_sampled_case_ids:
		replay_sample_rows.append({
			"strategy_id": case_id.get_slice(":", 0),
			"seed_index": int(case_id.get_slice(":", 1)),
		})
	return JSON.stringify({
		"artifact_schema_version": SCHEMA_VERSION,
		"runner": "balance-playtest",
		"candidate_id": String(candidate.candidate_id) if candidate != null else "",
		"content_version": candidate.content_version if candidate != null else "",
		"manifest_digest": candidate.manifest_digest if candidate != null else "",
		"tune_digest": candidate.tune_digest if candidate != null else "",
		"cohort_seed_count": cohort_seed_count,
		"strategy_seed_case_count": cases.size(),
		"strategies": strategy_rows,
		"builds": build_rows,
		"content_selection_counts": selected_counts,
		"stable_id_observability": {
			"selected_id_count": _selected_id_count(),
			"opaque_selected_id_count": _opaque_selected_id_count(),
		},
		"node_route_counts": route_counts,
		"resource_curve": {
			"mean_terminal_gold": _rate_bps(ending_gold_total, cases.size()) / 10000.0,
			"mean_terminal_hp": _rate_bps(ending_hp_total, cases.size()) / 10000.0,
		},
		"battle_outcomes": {"wins": battle_wins, "losses": battle_losses},
		"case_proofs": case_proofs,
		"failed_seeds": failed_seeds,
		"regression_proof": {
			"all_strategies_perfect_win_rate": _all_strategies_have_perfect_win_rate(),
			"fallback_build_count": _fallback_build_count(),
			"unique_ending_gold": _unique_ending_gold(),
		},
		"canonical_replay_digest": EconomyPayloadDigest.sha256(replay_parts),
		"replay_validation": {
			"mode": "deterministic_sample",
			"sample_rate_bps": REPLAY_SAMPLE_RATE_BPS,
			"selection_rule": "seed_index % 20 == 0",
			"sampled_case_count": replay_sample_rows.size(),
			"sampled_cases": replay_sample_rows,
			"drift_case_ids": replay_drift_case_ids.duplicate(),
		},
		"execution_metrics": {
			"primary_case_count": primary_timed_case_count,
			"primary_elapsed_ms_total": primary_elapsed_ms_total,
			"primary_mean_elapsed_ms": _mean_ms(
				primary_elapsed_ms_total, primary_timed_case_count
			),
			"replay_sample_count": replay_sampled_case_ids.size(),
			"replay_elapsed_ms_total": replay_elapsed_ms_total,
			"replay_mean_elapsed_ms": _mean_ms(
				replay_elapsed_ms_total, replay_sampled_case_ids.size()
			),
			"effective_mean_elapsed_ms": _mean_ms(
				primary_elapsed_ms_total + replay_elapsed_ms_total,
				primary_timed_case_count
			),
		},
		"gate": "PASS" if passed(final_gate, enforce_sample_minimums) else "FAIL",
		"gate_reasons": reason_text,
		"ac_032": "PENDING_EXTERNAL",
	})


func _count(strategy_id: StringName, require_terminal: bool, require_win: bool) -> int:
	var result := 0
	for value: BalanceBotCaseResult in cases:
		if value.strategy_id != strategy_id:
			continue
		if require_terminal and not value.terminal:
			continue
		if require_win and not value.won:
			continue
		result += 1
	return result


func _strategy_total(strategy_id: StringName) -> int:
	var result := 0
	for value: BalanceBotCaseResult in cases:
		if value.strategy_id == strategy_id:
			result += 1
	return result


func _act_count(strategy_id: StringName, act: int) -> int:
	var result := 0
	for value: BalanceBotCaseResult in cases:
		if value.strategy_id == strategy_id and value.act_reached >= act:
			result += 1
	return result


func _action_count(strategy_id: StringName, kind: StringName) -> int:
	var result := 0
	for value: BalanceBotCaseResult in cases:
		if value.strategy_id != strategy_id:
			continue
		match kind:
			&"buy_unit": result += value.buy_unit_count
			&"buy_xp": result += value.buy_xp_count
			&"reroll": result += value.reroll_count
			&"sell_unit": result += value.sell_unit_count
			&"boss_retry": result += value.boss_retry_count
	return result


func _build_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for value: BalanceBotCaseResult in cases:
		if not result.has(value.build_id):
			result.append(value.build_id)
	result.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return result


func _dominance_exceeds_limit(win_rate: bool) -> bool:
	var rates: Array[int] = []
	for build_id: StringName in _build_ids():
		if build_id == &"build.none":
			continue
		var selected := 0
		var wins := 0
		for value: BalanceBotCaseResult in cases:
			if value.build_id == build_id:
				selected += 1
				if value.won:
					wins += 1
		rates.append(_rate_bps(wins, selected) if win_rate else _rate_bps(selected, cases.size()))
	rates.sort()
	return rates.size() >= 2 and rates[-1] - rates[-2] >= DOMINANCE_BPS


func _cohort_world_mismatch() -> bool:
	var by_seed: Dictionary = {}
	for value: BalanceBotCaseResult in cases:
		if not by_seed.has(value.seed_index):
			by_seed[value.seed_index] = [] as Array[BalanceBotCaseResult]
		var group: Array[BalanceBotCaseResult] = by_seed[value.seed_index]
		group.append(value)
	for group_value: Variant in by_seed.values():
		var group: Array[BalanceBotCaseResult] = group_value
		var strategy_ids: Array[StringName] = []
		var run_id := ""
		var world_digest := ""
		for value: BalanceBotCaseResult in group:
			if strategy_ids.has(value.strategy_id):
				return true
			strategy_ids.append(value.strategy_id)
			if run_id.is_empty():
				run_id = String(value.run_id)
				world_digest = value.world_digest
			elif run_id != String(value.run_id) or world_digest != value.world_digest:
				return true
	return false


func _all_strategies_have_perfect_win_rate() -> bool:
	if cases.is_empty():
		return false
	for strategy_id: StringName in BalanceBotStrategy.IDS:
		var total := _strategy_total(strategy_id)
		if total == 0 or _count(strategy_id, false, true) != total:
			return false
	return true


func _fallback_build_count() -> int:
	var result := 0
	for value: BalanceBotCaseResult in cases:
		var build_id := String(value.build_id)
		if build_id in ["build.unresolved", "build.empty", "build.none"] \
			or build_id.begins_with("build.unit."):
			result += 1
	return result


func _selected_id_count() -> int:
	var result := 0
	for value: BalanceBotCaseResult in cases:
		result += value.selected_ids.size()
	return result


func _opaque_selected_id_count() -> int:
	var result := 0
	for value: BalanceBotCaseResult in cases:
		for selected_id: StringName in value.selected_ids:
			var token := String(selected_id)
			if token.begins_with("reservation_owner_") \
				or token.begins_with("offer_") or token.begins_with("choice_"):
				result += 1
	return result


func _unique_ending_gold() -> Array[int]:
	var result: Array[int] = []
	for value: BalanceBotCaseResult in cases:
		if not result.has(value.ending_gold):
			result.append(value.ending_gold)
	result.sort()
	return result


func _rate_bps(numerator: int, denominator: int) -> int:
	if denominator <= 0:
		return 0
	@warning_ignore("integer_division")
	return (numerator * 10000) / denominator


func _mean_ms(total: int, count: int) -> float:
	return float(total) / float(count) if count > 0 else 0.0
