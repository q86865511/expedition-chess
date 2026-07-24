class_name MetaSettlementService
extends RefCounted

## design.md §5.1 — 遠征 meta 結算的唯一 settlement receipt writer（純推導段；
## S5-AC-007／S5-AC-009／REQ-META-004／REQ-DATA-007）。給定 terminal RunState 與
## 已對齊的 MetaRewardTableDef，回傳結算後的 profile'（純函式，不變動輸入 profile／run）：
##   1. outcome：defeated_boss_count==3 → COMPLETED，其餘 → FAILED（含遠征 HP 歸零與
##      Boss 重戰放棄——S3 兩路徑終態同為 RESULTS＋hp0 不可區分；Outcome.ABANDONED
##      枚舉值保留不使用。w2 裁決 2026-07-24）。
##   2. currency_delta = MetaRewardComputeService.compute(...)（純函式，§9）。
##   3. 冪等守衛（design.md §5.1 point3）：profile.settlement_receipts 已含此 run_id 的
##      receipt key digest → 整個更新區塊原封不動跳過、回傳未變動的 profile' clone
##      （不重發 currency、不重複 append，維持 RunStateValidator 的唯一 digest 不變量）。
##   4. 否則：meta_currency += delta、append SettlementReceiptState(key, outcome, delta,
##      payload_digest)（key = build_settlement_receipt(run_id)、依 digest 遞增排序），
##      且 COMPLETED 時 highest_challenge_level = max(舊, challenge_level) 並更新該指揮官
##      commander_challenge_records（取 max，§7.4）。
## SaveRoot(profile', run=null)／存檔／AppStateMachine 轉場屬 MetaSettlementCommand（§5.1 point5）。
## 例外：settlement receipt key 建置失敗時回傳 null（不可達防禦路徑，見下方
## key_result.ok 檢查），由呼叫端（MetaSettlementCommand）轉具名 KEY_FAILED 錯誤。
static func settle(
	profile: ProfileState,
	terminal_run: RunState,
	meta_reward_table: MetaRewardTableDef
) -> ProfileState:
	var draft := profile.deep_clone()
	var key_result := RuntimeKeySchemaRegistry.new().build_settlement_receipt(
		StringName(terminal_run.run_id)
	)
	# 合法 run（run_id == run_key.digest，恆為 stable-ascii）必可編碼；防呆：無法產 key
	# 即回 null 讓命令層（MetaSettlementCommand）轉具名 KEY_FAILED 錯誤、不清 run
	# （不 crash、不部分變更、不靜默清局無 receipt——w2 review 修正，見
	# meta_settlement_command_error.gd 的 KEY_FAILED 說明）。
	if not key_result.ok:
		return null
	var key := key_result.key_state as SettlementReceiptKeyState
	# 冪等守衛：同 run_id 已結算過 → 原封不動跳過整個更新區塊。
	for receipt: SettlementReceiptState in draft.settlement_receipts:
		if receipt.key != null and receipt.key.digest == key.digest:
			return draft
	var outcome := _resolve_outcome(terminal_run)
	var currency_delta := MetaRewardComputeService.compute(
		terminal_run.cleared_normal_count,
		terminal_run.cleared_elite_count,
		terminal_run.defeated_boss_count,
		terminal_run.challenge_level,
		outcome,
		meta_reward_table
	)
	draft.meta_currency += currency_delta
	_append_receipt(draft, key, outcome, currency_delta, terminal_run)
	if outcome == SettlementReceiptState.Outcome.COMPLETED:
		draft.highest_challenge_level = maxi(
			draft.highest_challenge_level, terminal_run.challenge_level
		)
		_apply_commander_record(
			draft, terminal_run.commander_id, terminal_run.challenge_level
		)
	return draft

## design.md §5.1 point1：三幕通關（defeated_boss_count==3）→ COMPLETED，其餘皆 FAILED。
static func _resolve_outcome(run: RunState) -> SettlementReceiptState.Outcome:
	if run.defeated_boss_count == 3:
		return SettlementReceiptState.Outcome.COMPLETED
	return SettlementReceiptState.Outcome.FAILED

## payload_digest 涵蓋 run_id、outcome、cleared counts、challenge_level、delta，供載入
## 竄改偵測（對齊 battle_settlement_service.gd:246-250 的 EconomyPayloadDigest 慣例）。
## append 後依 key.digest 嚴格遞增排序，維持 RunStateValidator 的 canonical order 不變量。
static func _append_receipt(
	draft: ProfileState,
	key: SettlementReceiptKeyState,
	outcome: SettlementReceiptState.Outcome,
	currency_delta: int,
	terminal_run: RunState
) -> void:
	var payload_digest := EconomyPayloadDigest.sha256([
		"MSR1",
		terminal_run.run_id,
		_outcome_token(outcome),
		str(terminal_run.cleared_normal_count),
		str(terminal_run.cleared_elite_count),
		str(terminal_run.defeated_boss_count),
		str(terminal_run.challenge_level),
		str(currency_delta),
	])
	draft.settlement_receipts.append(
		SettlementReceiptState.new(key, outcome, currency_delta, payload_digest)
	)
	draft.settlement_receipts.sort_custom(func(
		left: SettlementReceiptState,
		right: SettlementReceiptState
	) -> bool:
		return String(left.key.digest) < String(right.key.digest)
	)

## COMPLETED 時更新該指揮官挑戰紀錄：已存在 → 取 max（不回退）；不存在 → 插入並依
## commander_id 字典序排序（維持 RunStateValidator 的 sorted-unique 不變量，§10）。
static func _apply_commander_record(
	draft: ProfileState,
	commander_id: StringName,
	cleared_level: int
) -> void:
	for record: CommanderChallengeRecordState in draft.commander_challenge_records:
		if record.commander_id == commander_id:
			record.highest_cleared_level = maxi(
				record.highest_cleared_level, cleared_level
			)
			return
	draft.commander_challenge_records.append(
		CommanderChallengeRecordState.new(commander_id, cleared_level)
	)
	draft.commander_challenge_records.sort_custom(func(
		left: CommanderChallengeRecordState,
		right: CommanderChallengeRecordState
	) -> bool:
		return String(left.commander_id) < String(right.commander_id)
	)

static func _outcome_token(outcome: SettlementReceiptState.Outcome) -> String:
	match outcome:
		SettlementReceiptState.Outcome.COMPLETED:
			return "completed"
		SettlementReceiptState.Outcome.FAILED:
			return "failed"
		SettlementReceiptState.Outcome.ABANDONED:
			return "abandoned"
	return "unknown"
