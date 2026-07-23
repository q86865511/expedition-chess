class_name IncomeService
extends RefCounted

func quote(request: IncomeQuoteRequest) -> IncomeQuoteResult:
	if request == null or request.run_id.is_empty() or request.node_id.is_empty() \
		or request.layer_index < 0 or request.economy_state == null \
		or request.next_transaction_serial == null or request.catalog == null:
		return IncomeQuoteResult.failure(ShopError.INPUT_INVALID, &"request")
	if request.next_transaction_serial.equals(U64Bits.max_value()):
		return IncomeQuoteResult.failure(ShopError.SERIAL_EXHAUSTED, &"next_transaction_serial")
	var config := request.catalog.config()
	var economy := request.economy_state.deep_clone()
	var pre_gold := economy.gold
	var base := config.base_income_for_layer(request.layer_index)
	var interest_steps := pre_gold / config.interest_step_gold
	var interest := mini(interest_steps * config.interest_per_step, config.max_interest)
	var streak := config.streak_reward(economy.win_streak)
	var relic_bonus := 0
	if request.relic_table != null:
		relic_bonus = request.relic_table.sum_operation_amount(
			request.active_relic_ids, &"economy", &"add_gold"
		)
	economy.gold = mini(config.gold_cap, pre_gold + base + interest + streak + relic_bonus)
	var key_result := RuntimeKeySchemaRegistry.new().build_transaction(
		request.run_id, request.node_id, &"node_income", request.next_transaction_serial
	)
	if not key_result.ok:
		return IncomeQuoteResult.failure(ShopError.KEY_FAILED, key_result.error.field_path)
	var payload := EconomyPayloadDigest.sha256([
		"INC1", String(key_result.key_state.digest), str(pre_gold), str(base),
		str(interest), str(streak), str(economy.gold)
	])
	if payload.is_empty():
		return IncomeQuoteResult.failure(ShopError.DIGEST_FAILED, &"payload_digest")
	var receipt := TransactionReceiptState.new(key_result.key_state as TransactionKeyState, payload)
	return IncomeQuoteResult.success(IncomeTransaction.new(
		economy, request.next_transaction_serial.add(U64Bits.one()), receipt,
		base, interest, streak
	))
