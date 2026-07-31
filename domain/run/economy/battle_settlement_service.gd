class_name BattleSettlementService
extends RefCounted

const EXPEDITION_HP_CAP: int = 100

## on_first_clear 的 run 級 sentinel node_id（design §6.4）：全 run 同一 claim key，首次消費後
## 恰一次、不因換節點重觸發。須為 stable-ascii 且不會與真實 node digest（64 lower-hex）相撞。
const FIRST_CLEAR_CLAIM_NODE: StringName = &"run_first_clear"

var _reward_service: RewardService

func _init(p_reward_service: RewardService = null) -> void:
	_reward_service = p_reward_service if p_reward_service != null else RewardService.new()

func settle(
	source: RunState,
	catalog: EconomyExpeditionCatalog,
	relic_table: RunRelicTable = null,
	active_relic_ids: Array[StringName] = []
) -> ExpeditionActionResult:
	var input_error := _validate(source, catalog)
	if input_error != null:
		return ExpeditionActionResult.failure(input_error.code, input_error.field_path)
	# W3-F7 世代守衛：遺物表若釘在與 run content_snapshot 不符的 manifest 世代，絕不得授權結算
	# （與既有 catalog vs content_snapshot 檢查同一份 digest，見 _validate）。
	if relic_table != null \
		and relic_table.manifest_digest_value() != source.content_snapshot.manifest_digest_value():
		return ExpeditionActionResult.failure(
			ExpeditionActionError.GENERATION_MISMATCH, &"relic_table.manifest_digest"
		)
	var draft := source.deep_clone()
	var pending := draft.resolution_state as BattleResultPendingResolutionState
	var result := pending.battle_result
	var node := _current_node(draft)
	if node == null or not node.node_kind in [
		MapNodeState.NodeKind.NORMAL,
		MapNodeState.NodeKind.ELITE,
		MapNodeState.NodeKind.BOSS,
	]:
		return ExpeditionActionResult.failure(
			ExpeditionActionError.NODE_INVALID, &"current_node_id"
		)
	# 規則型遺物的遠征 HP 修正（不經 EffectResolver；EffectResolver 專用於戰鬥）。
	# claim_scope=always（rule 規則本身、以及指揮官/挑戰 always-active 貢獻）無條件加總、
	# 勝負皆適用，維持既有逐節點語意（design §6.1/§6.4、S5-AC-003/013）。once_per_node／
	# on_first_clear 的 claim 建立與消費延後到確認勝利之後才進行——2026-07-25 裁決：
	# 戰敗不得建立/消耗 claim、不套 bonus，避免首戰落敗即燒掉「首次通關」等效果。
	# design §6.3 軌 B：挑戰詞綴（及指揮官被動）的 drain 貢獻只在戰敗路徑加深損失，勝利不生效。
	# W4-F3 修正（2026-07-25）：drain 比照 heal，同時讀 slot-gated（一般 rule 類遺物，經
	# _sum_always_rule_drain_bonus）與 always-active（commander/challenge 來源）兩路——修正前
	# 只讀後者，slot-gated drain 遺物會建表成功卻結算時靜默零效果。
	var relic_always_bonus := 0
	var challenge_drain := 0
	if relic_table != null:
		relic_always_bonus = _sum_always_rule_heal_bonus(relic_table, active_relic_ids)
		relic_always_bonus += relic_table.sum_always_active(&"rule", &"heal_expedition_hp")
		challenge_drain = _sum_always_rule_drain_bonus(relic_table, active_relic_ids)
		challenge_drain += relic_table.sum_always_active(&"rule", &"drain_expedition_hp")
	if result.outcome == &"player_loss":
		return _settle_loss(
			draft, node, result, catalog, relic_always_bonus, challenge_drain
		)
	if result.outcome != &"player_win":
		return ExpeditionActionResult.failure(
			ExpeditionActionError.RESULT_INVALID, &"battle_result.outcome"
		)
	var relic_heal_bonus := relic_always_bonus
	if relic_table != null:
		var claim_result := _consume_claimed_rule_heal_bonus(draft, relic_table, active_relic_ids)
		if claim_result.error != null:
			return ExpeditionActionResult.failure(claim_result.error.code, claim_result.error.field_path)
		relic_heal_bonus += claim_result.bonus
	var proposal_error := _apply_proposals(draft, result, catalog.config())
	if proposal_error != null:
		return ExpeditionActionResult.failure(
			proposal_error.code, proposal_error.field_path
		)
	# 勝利：既有 proposals 之後、產生獎勵之前，套用規則遺物的遠征 HP 修正（受 cap 夾限）。
	draft.expedition_hp = mini(EXPEDITION_HP_CAP, draft.expedition_hp + relic_heal_bonus)
	draft.economy_state.win_streak += 1
	draft.economy_state.loss_streak = 0
	match node.node_kind:
		MapNodeState.NodeKind.NORMAL:
			draft.cleared_normal_count += 1
		MapNodeState.NodeKind.ELITE:
			draft.cleared_elite_count += 1
		MapNodeState.NodeKind.BOSS:
			draft.defeated_boss_count += 1
	var receipt_error := _append_settlement_receipt(
		draft, &"battle_settle_win", result.result_hash
	)
	if receipt_error != null:
		return ExpeditionActionResult.failure(
			receipt_error.code, receipt_error.field_path
		)
	var stage := PendingRewardState.StageId.RELIC \
		if node.node_kind == MapNodeState.NodeKind.BOSS \
		else PendingRewardState.StageId.STANDARD
	return _reward_service.generate_stage(draft, stage, catalog)

func abandon_boss_retry(
	source: RunState,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	if source == null or catalog == null or source.content_snapshot == null \
		or source.run_phase != RunState.RunPhase.PREPARE \
		or not source.resolution_state is IdleResolutionState \
		or catalog.manifest_digest_value() != source.content_snapshot.manifest_digest_value():
		return ExpeditionActionResult.failure(
			ExpeditionActionError.PHASE_INVALID, &"run_phase"
		)
	var draft := source.deep_clone()
	var node := _current_node(draft)
	if node == null or node.node_kind != MapNodeState.NodeKind.BOSS \
		or not draft.income_claimed_node_ids.has(node.node_id):
		return ExpeditionActionResult.failure(
			ExpeditionActionError.NODE_INVALID, &"current_node_id"
		)
	draft.expedition_hp = 0
	var release_error := _reward_service.try_release_shop_offers(draft)
	if release_error != null:
		return ExpeditionActionResult.failure(release_error.code, release_error.field_path)
	_mark_node_complete(draft, node)
	draft.run_phase = RunState.RunPhase.RESULTS
	EconomyCommandSupport.clear_node_choice_receipts(draft)
	draft.resolution_state = IdleResolutionState.new()
	var receipt_error := _append_settlement_receipt(
		draft, &"expedition_abandon", &"abandoned"
	)
	if receipt_error != null:
		return ExpeditionActionResult.failure(receipt_error.code, receipt_error.field_path)
	return ExpeditionActionResult.success(draft)

func _settle_loss(
	draft: RunState,
	node: MapNodeState,
	result: BattleResult,
	catalog: EconomyExpeditionCatalog,
	relic_damage_reduction: int = 0,
	challenge_extra_damage: int = 0
) -> ExpeditionActionResult:
	# 規則型遺物把遠征 HP 修正值視為傷害減免（下限 0，不得反向治療）。
	# design §6.3 軌 B（S5-AC-010）：挑戰詞綴的遠征傷害以 drain_expedition_hp 表達（amount≥0＝
	# 額外損失幅度），是獨立加項——先讓 heal 把傷害砍到不低於 0，drain 再對這個已砍過的值疊加，
	# 兩者不合併成單一淨值（否則 drain 會被 heal 的下限 clamp 吸收）。
	var reduced_damage := maxi(0, result.expedition_damage - relic_damage_reduction)
	draft.expedition_hp = maxi(
		0, draft.expedition_hp - (reduced_damage + challenge_extra_damage)
	)
	draft.economy_state.loss_streak += 1
	draft.economy_state.win_streak = 0
	if draft.economy_state.loss_streak >= 2 \
		and not draft.loss_stipend_claimed_act_ids.has(draft.act_index):
		var stipend := catalog.config().loss_stipend(draft.economy_state.loss_streak)
		if stipend > 0:
			draft.economy_state.gold = mini(
				catalog.config().gold_cap,
				draft.economy_state.gold + stipend
			)
			draft.loss_stipend_claimed_act_ids.append(draft.act_index)
			draft.loss_stipend_claimed_act_ids.sort()
	var receipt_error := _append_settlement_receipt(
		draft, &"battle_settle_loss", result.result_hash
	)
	if receipt_error != null:
		return ExpeditionActionResult.failure(
			receipt_error.code, receipt_error.field_path
		)
	draft.resolution_state = IdleResolutionState.new()
	if node.node_kind == MapNodeState.NodeKind.BOSS and draft.expedition_hp > 0:
		draft.run_phase = RunState.RunPhase.PREPARE
		return ExpeditionActionResult.success(draft)
	var release_error := _reward_service.try_release_shop_offers(draft)
	if release_error != null:
		return ExpeditionActionResult.failure(
			release_error.code, release_error.field_path
		)
	_mark_node_complete(draft, node)
	draft.run_phase = RunState.RunPhase.RESULTS \
		if draft.expedition_hp == 0 else RunState.RunPhase.MAP
	if draft.run_phase == RunState.RunPhase.RESULTS:
		EconomyCommandSupport.clear_node_choice_receipts(draft)
	return ExpeditionActionResult.success(draft)

## 規則遺物 (rule, heal_expedition_hp) 的 claim_scope=always 加總（design §6.4、S5-AC-013）。
## 無條件加總、不設 claim（維持 S4 逐節點語意，claim_receipts 不動），勝負皆呼叫——
## 與 once_per_node/on_first_clear 的 claim 消費（僅勝利呼叫）分離，見 _consume_claimed_rule_heal_bonus。
func _sum_always_rule_heal_bonus(
	relic_table: RunRelicTable, active_relic_ids: Array[StringName]
) -> int:
	var bonus := 0
	for rule: RunRelicRule in relic_table.ordered_rules(active_relic_ids):
		if rule.category != &"rule":
			continue
		for operation: RunRelicOperationRule in rule.run_operations:
			if operation.kind == &"heal_expedition_hp" and operation.claim_scope == &"always":
				bonus += operation.amount
	return bonus

## 規則遺物 (rule, drain_expedition_hp) 的 claim_scope=always 加總（design §6.3 軌 B、
## W4-F3 修正）。與 _sum_always_rule_heal_bonus 同構，但 drain 沒有對應的 claim-aware 消費
## 版本——RunRelicTableBuilder._scope_supported 只對 (rule, heal_expedition_hp) 開放
## once_per_node/on_first_clear，drain 的 claim_scope 只可能是 always（否則 build 階段已被
## UNSUPPORTED_INTENT 拒絕），故本函式已涵蓋 drain 的完整 slot-gated 貢獻，不需額外的
## claim 消費函式。勝負皆呼叫（維持既有逐節點語意），drain 本身只在 _settle_loss 分支生效。
func _sum_always_rule_drain_bonus(
	relic_table: RunRelicTable, active_relic_ids: Array[StringName]
) -> int:
	var bonus := 0
	for rule: RunRelicRule in relic_table.ordered_rules(active_relic_ids):
		if rule.category != &"rule":
			continue
		for operation: RunRelicOperationRule in rule.run_operations:
			if operation.kind == &"drain_expedition_hp" and operation.claim_scope == &"always":
				bonus += operation.amount
	return bonus

## 規則遺物 (rule, heal_expedition_hp) 的 claim-aware 消費（design §6.4、S5-AC-013）。
## 只呼叫於已確認勝利的結算路徑（2026-07-25 裁決：戰敗不得建立/消耗 claim、不套 bonus，
## 避免首戰落敗即燒掉「首次通關」等效果——claim_scope=always 不在此列，由
## _sum_always_rule_heal_bonus 於勝負分流前無條件處理）。依 slot 序（ordered_rules）逐一
## 處理作用中規則遺物的遠征 HP 修正：
## - once_per_node：claim key 的 node_id 用當前節點 → 同節點恰一次、跨節點重觸發。
## - on_first_clear：claim key 的 node_id 用 run 級 sentinel → 全 run 首次消費恰一次、換節點不重觸發。
## 已存在的 claim 命中時比對 payload_digest（與 _apply_proposals:262-268 同調，W3-F5 修正）：
## digest 相符（重載/重放）→ 略過、不重複加成；不符（竄改或未來調整）→ 具名拒絕
## （RESULT_INVALID／claim_receipts.payload_digest），不得靜默放行。新 claim 以 build_effect_claim
## 編碼並記入 draft.claim_receipts（依 key.digest 升序，符合 RunStateValidator 的唯一/排序不變量）。
## claim key 的 source 用 rule.relic_id（合法 single-dot stable id）、effect_id 改用
## operation.effect_id（builder 解碼時回攜真正來源，W3-F4 修正）：operation_index 只在單一
## effect 內唯一（content_validator.gd:691-693），若沿用 relic_id 頂替 effect_id，同遺物跨
## effect_refs 而 index 相同的第二筆操作會與第一筆撞成同一把 key、遭誤判已 claim。
func _consume_claimed_rule_heal_bonus(
	draft: RunState, relic_table: RunRelicTable, active_relic_ids: Array[StringName]
) -> RuleHealClaimResult:
	var claim := RuleHealClaimResult.new()
	var appended := false
	for rule: RunRelicRule in relic_table.ordered_rules(active_relic_ids):
		if rule.category != &"rule":
			continue
		for operation: RunRelicOperationRule in rule.run_operations:
			if operation.kind != &"heal_expedition_hp":
				continue
			if operation.claim_scope == &"always":
				continue
			var node_token := EconomyCommandSupport.current_node_id(draft) \
				if operation.claim_scope == &"once_per_node" else FIRST_CLEAR_CLAIM_NODE
			var key_result := RuntimeKeySchemaRegistry.new().build_effect_claim(
				StringName(draft.run_id), node_token, operation.claim_scope,
				rule.relic_id, operation.effect_id, operation.operation_index
			)
			if not key_result.ok:
				claim.error = ExpeditionActionError.new(
					ExpeditionActionError.KEY_FAILED, key_result.error.field_path
				)
				return claim
			var payload := EconomyPayloadDigest.sha256([
				"RRHP", String(rule.relic_id), String(operation.effect_id),
				str(operation.operation_index), str(operation.amount), String(operation.claim_scope)
			])
			if payload.is_empty():
				claim.error = ExpeditionActionError.new(
					ExpeditionActionError.DIGEST_FAILED, &"claim_receipts.payload_digest"
				)
				return claim
			var existing := _find_claim(draft.claim_receipts, key_result.key_state.digest)
			if existing != null:
				if existing.payload_digest != payload:
					claim.error = ExpeditionActionError.new(
						ExpeditionActionError.RESULT_INVALID,
						&"claim_receipts.payload_digest"
					)
					return claim
				continue
			claim.bonus += operation.amount
			draft.claim_receipts.append(ClaimReceiptState.new(
				key_result.key_state as EffectClaimKeyState, payload
			))
			appended = true
	if appended:
		draft.claim_receipts.sort_custom(func(
			left: ClaimReceiptState, right: ClaimReceiptState
		) -> bool:
			return String(left.key.digest) < String(right.key.digest)
		)
	return claim

class RuleHealClaimResult:
	extends RefCounted
	var bonus: int = 0
	var error: ExpeditionActionError = null

func _apply_proposals(
	draft: RunState,
	result: BattleResult,
	config: EconomyConfigRule
) -> ExpeditionActionError:
	for proposal: RunMutationProposal in result.run_mutation_proposals:
		var key_result := RuntimeKeySchemaRegistry.new().build_effect_claim(
			StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft),
			proposal.claim_scope, StringName(proposal.source_instance_or_slot),
			proposal.effect_id, proposal.operation_index
		)
		if not key_result.ok:
			return ExpeditionActionError.new(
				ExpeditionActionError.KEY_FAILED, key_result.error.field_path
			)
		var existing := _find_claim(draft.claim_receipts, key_result.key_state.digest)
		if existing != null:
			if existing.payload_digest != proposal.payload_digest:
				return ExpeditionActionError.new(
					ExpeditionActionError.RESULT_INVALID,
					&"claim_receipts.payload_digest"
				)
			continue
		match proposal.operation_kind:
			&"add_gold":
				draft.economy_state.gold = mini(
					config.gold_cap,
					draft.economy_state.gold + proposal.amount
				)
			&"add_xp":
				var xp_error := _add_xp(draft.economy_state, proposal.amount, config)
				if xp_error != null:
					return xp_error
			&"heal_expedition_hp":
				draft.expedition_hp = mini(
					EXPEDITION_HP_CAP,
					draft.expedition_hp + proposal.amount
				)
			_:
				return ExpeditionActionError.new(
					ExpeditionActionError.RESULT_INVALID,
					&"run_mutation_proposals.operation_kind"
				)
		draft.claim_receipts.append(ClaimReceiptState.new(
			key_result.key_state as EffectClaimKeyState,
			proposal.payload_digest
		))
	draft.claim_receipts.sort_custom(func(
		left: ClaimReceiptState,
		right: ClaimReceiptState
	) -> bool:
		return String(left.key.digest) < String(right.key.digest)
	)
	return null

func _add_xp(
	economy: EconomyState,
	amount: int,
	config: EconomyConfigRule
) -> ExpeditionActionError:
	economy.xp += amount
	while economy.level < 9:
		var threshold := config.value_for(config.xp_thresholds, economy.level, -1)
		if threshold < 1:
			return ExpeditionActionError.new(
				ExpeditionActionError.REWARD_CONFIG_INVALID, &"xp_thresholds"
			)
		if economy.xp < threshold:
			break
		economy.xp -= threshold
		economy.level += 1
	if economy.level == 9:
		economy.xp = 0
	return null

func _append_settlement_receipt(
	draft: RunState,
	kind: StringName,
	result_hash: StringName
) -> ExpeditionActionError:
	if draft.next_transaction_serial.equals(U64Bits.max_value()):
		return ExpeditionActionError.new(
			ExpeditionActionError.SERIAL_EXHAUSTED, &"next_transaction_serial"
		)
	var key_result := RuntimeKeySchemaRegistry.new().build_transaction(
		StringName(draft.run_id), EconomyCommandSupport.current_node_id(draft),
		kind, draft.next_transaction_serial
	)
	if not key_result.ok:
		return ExpeditionActionError.new(
			ExpeditionActionError.KEY_FAILED, key_result.error.field_path
		)
	var payload := EconomyPayloadDigest.sha256([
		"BSE1", String(key_result.key_state.digest), String(result_hash),
		str(draft.expedition_hp), str(draft.economy_state.win_streak),
		str(draft.economy_state.loss_streak)
	])
	if payload.is_empty():
		return ExpeditionActionError.new(
			ExpeditionActionError.DIGEST_FAILED, &"transaction.payload_digest"
		)
	EconomyCommandSupport.append_transaction_receipt(
		draft, TransactionReceiptState.new(
			key_result.key_state as TransactionKeyState, payload
		)
	)
	draft.next_transaction_serial = draft.next_transaction_serial.add(U64Bits.one())
	return null

func _validate(
	source: RunState,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionError:
	if source == null or catalog == null or source.content_snapshot == null:
		return ExpeditionActionError.new(
			ExpeditionActionError.INPUT_INVALID, &"source"
		)
	if source.run_phase != RunState.RunPhase.COMBAT:
		return ExpeditionActionError.new(
			ExpeditionActionError.PHASE_INVALID, &"run_phase"
		)
	if not source.resolution_state is BattleResultPendingResolutionState:
		return ExpeditionActionError.new(
			ExpeditionActionError.RESOLUTION_INVALID, &"resolution_state"
		)
	if catalog.manifest_digest_value() != source.content_snapshot.manifest_digest_value():
		return ExpeditionActionError.new(
			ExpeditionActionError.GENERATION_MISMATCH,
			&"content_snapshot.manifest_digest"
		)
	var result := (source.resolution_state as BattleResultPendingResolutionState).battle_result
	if result == null or result.validate() != null:
		return ExpeditionActionError.new(
			ExpeditionActionError.RESULT_INVALID, &"battle_result"
		)
	return null

func _current_node(draft: RunState) -> MapNodeState:
	if draft.current_node_id == null:
		return null
	for node: MapNodeState in draft.map_state.nodes:
		if node.node_id == draft.current_node_id.value:
			return node
	return null

func _mark_node_complete(draft: RunState, node: MapNodeState) -> void:
	node.completed = true
	if not draft.map_state.completed_node_ids.has(node.node_id):
		draft.map_state.completed_node_ids.append(node.node_id)
		draft.map_state.completed_node_ids.sort()

func _find_claim(
	receipts: Array[ClaimReceiptState],
	digest: StringName
) -> ClaimReceiptState:
	for receipt: ClaimReceiptState in receipts:
		if receipt.key.digest == digest:
			return receipt
	return null
