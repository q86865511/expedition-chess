extends GutTest

## T25 review M3／M4 回歸：
## - design.md §5:186／:201-203：commit 交易一律留 result_acknowledged=false，
##   只有 AcknowledgeNodeChoiceResultCommand 在另一筆交易翻 true；reward 出口也不例外，
##   否則 reload 後 UI 不會重播結果。
## - design.md §5:161-165：lifecycle_nonce 是 pending 生命週期的唯一性來源，
##   cancel→re-begin 必須換一組 nonce／pending_digest（不得是 run/node/世代的純函數）。


func test_reward_outcome_leaves_the_receipt_unacknowledged() -> void:
	var committed := _committed_reward_run()
	assert_eq(committed.node_choice_receipts.size(), 1)
	assert_false(committed.node_choice_receipts[0].result_acknowledged)
	assert_true(committed.resolution_state is RewardPendingResolutionState)


func test_acknowledge_command_flips_only_the_wrapper_flag() -> void:
	var committed := _committed_reward_run()
	var receipt := committed.node_choice_receipts[0].receipt
	var before_digest := receipt.receipt_digest
	var applied := AcknowledgeNodeChoiceResultCommand.new(
		committed.run_id, before_digest
	).apply_to(committed)
	assert_true(applied.ok, NodeChoiceServiceFixture.command_error_code(applied))
	if not applied.ok:
		return
	var entry := applied.draft.node_choice_receipts[0]
	assert_true(entry.result_acknowledged)
	assert_eq(entry.receipt.receipt_digest, before_digest)
	assert_true(entry.receipt.is_valid())
	assert_eq(applied.draft.node_choice_receipts.size(), 1)
	# 不碰 resolution／phase：ack 只是「結果已播完」的旗標。
	assert_true(applied.draft.resolution_state is RewardPendingResolutionState)
	assert_eq(applied.draft.run_phase, committed.run_phase)


func test_acknowledge_rejects_foreign_run_and_unknown_receipt() -> void:
	var committed := _committed_reward_run()
	var digest := committed.node_choice_receipts[0].receipt.receipt_digest
	var foreign := AcknowledgeNodeChoiceResultCommand.new(
		"run_deadbeef", digest
	).apply_to(committed)
	assert_false(foreign.ok)
	assert_eq(
		NodeChoiceServiceFixture.command_error_code(foreign),
		String(NodeChoiceRejection.RUN_MISMATCH)
	)
	var unknown := AcknowledgeNodeChoiceResultCommand.new(
		committed.run_id, "d".repeat(64)
	).apply_to(committed)
	assert_false(unknown.ok)
	assert_eq(
		NodeChoiceServiceFixture.command_error_code(unknown),
		String(ExpeditionActionError.RESULT_INVALID)
	)
	assert_false(committed.node_choice_receipts[0].result_acknowledged)


func test_repeat_commit_after_acknowledge_still_returns_already_committed() -> void:
	var run := NodeChoiceServiceFixture.prepared_run()
	var catalog := NodeChoiceServiceFixture.catalog_for(run)
	var rule := NodeChoiceServiceFixture.choice_set(
		NodeChoiceRule.OUTCOME_OPEN_REWARD_STAGE
	)
	var begun := NodeChoiceServiceFixture.begun_run(run, rule, catalog)
	var payload := NodeChoiceServiceFixture.payload_for(
		begun, &"choice.fixture.reward"
	)
	var service := CommitNodeChoiceService.new()
	var committed := service.commit(begun, payload, rule, catalog)
	assert_true(committed.ok, NodeChoiceServiceFixture.error_code(committed))
	if not committed.ok:
		return
	var acknowledged := service.acknowledge(
		committed.run_state,
		committed.run_state.run_id,
		committed.run_state.node_choice_receipts[0].receipt.receipt_digest
	)
	assert_true(acknowledged.ok)
	if not acknowledged.ok:
		return
	# design :204-205「repeat confirm 不論 ack 狀態都由 ledger 回 ALREADY_COMMITTED」。
	var repeated := service.commit(
		acknowledged.run_state, payload, rule, catalog
	)
	assert_false(repeated.ok)
	assert_eq(
		NodeChoiceServiceFixture.error_code(repeated),
		String(NodeChoiceRejection.ALREADY_COMMITTED)
	)
	assert_eq(acknowledged.run_state.node_choice_receipts.size(), 1)


func test_re_begin_after_cancel_draws_a_fresh_nonce_and_pending_digest() -> void:
	var run := NodeChoiceServiceFixture.prepared_run()
	var catalog := NodeChoiceServiceFixture.catalog_for(run)
	var rule := NodeChoiceServiceFixture.choice_set()
	var service := CommitNodeChoiceService.new()
	var first := NodeChoiceServiceFixture.begun_run(run, rule, catalog)
	var first_pending := NodeChoiceServiceFixture.pending_of(first)
	var cancelled := service.cancel(first)
	assert_true(cancelled.ok)
	if not cancelled.ok:
		return
	var second := NodeChoiceServiceFixture.begun_run(
		cancelled.run_state, rule, catalog
	)
	var second_pending := NodeChoiceServiceFixture.pending_of(second)
	assert_ne(
		second_pending.lifecycle_nonce,
		first_pending.lifecycle_nonce,
		"nonce must not be reproducible for the same (run, node, generation)"
	)
	assert_ne(second_pending.pending_digest, first_pending.pending_digest)
	assert_true(second_pending.is_valid())
	for nonce: String in [
		first_pending.lifecycle_nonce, second_pending.lifecycle_nonce
	]:
		assert_eq(nonce.length(), 16)
		assert_eq(nonce, nonce.to_lower())
		assert_eq(nonce.hex_decode().size(), 8)
		assert_ne(nonce, "0000000000000000")
	# entropy 來自 run 的具名 rng stream，且推進後的 snapshot 已落回 draft。
	assert_false(
		_map_rng(first).equals(_map_rng(run)),
		"begin() must persist the advanced rng snapshot"
	)
	assert_false(_map_rng(second).equals(_map_rng(first)))


func _map_rng(run: RunState) -> RngSnapshot:
	return EconomyCommandSupport.try_named_rng(
		run, CommitNodeChoiceService.LIFECYCLE_NONCE_STREAM
	)


func _committed_reward_run() -> RunState:
	var run := NodeChoiceServiceFixture.prepared_run()
	var catalog := NodeChoiceServiceFixture.catalog_for(run)
	var rule := NodeChoiceServiceFixture.choice_set(
		NodeChoiceRule.OUTCOME_OPEN_REWARD_STAGE
	)
	var begun := NodeChoiceServiceFixture.begun_run(run, rule, catalog)
	var committed := CommitNodeChoiceService.new().commit(
		begun,
		NodeChoiceServiceFixture.payload_for(begun, &"choice.fixture.reward"),
		rule,
		catalog
	)
	assert_true(committed.ok, NodeChoiceServiceFixture.error_code(committed))
	return committed.run_state
