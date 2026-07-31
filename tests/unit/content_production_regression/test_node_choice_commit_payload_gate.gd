extends GutTest

## T25 review M1／M2 回歸：CommitNodeChoiceService.commit 必須逐欄比對
## design.md §5:174-178 的 exact payload，並以 :179-182 的十一個具名碼拒絕；
## begin／commit 兩個入口都要有 catalog↔pinned snapshot 的世代守衛。


func test_matching_payload_commits_and_repeat_commit_is_already_committed() -> void:
	var run := NodeChoiceServiceFixture.prepared_run()
	var catalog := NodeChoiceServiceFixture.catalog_for(run)
	var rule := NodeChoiceServiceFixture.choice_set()
	var begun := NodeChoiceServiceFixture.begun_run(run, rule, catalog)
	var payload := NodeChoiceServiceFixture.payload_for(
		begun, &"choice.fixture.plain"
	)
	var service := CommitNodeChoiceService.new()
	var committed := service.commit(begun, payload, rule, catalog)
	assert_true(
		committed.ok, NodeChoiceServiceFixture.error_code(committed)
	)
	if not committed.ok:
		return
	assert_eq(committed.run_state.node_choice_receipts.size(), 1)
	# design :204-205：commit 成功後 pending 已不存在，repeat confirm 仍必須由
	# ledger 回 ALREADY_COMMITTED（不是 RESOLUTION_INVALID／RESULT_INVALID）。
	var repeated := service.commit(
		committed.run_state, payload, rule, catalog
	)
	assert_false(repeated.ok)
	assert_eq(
		NodeChoiceServiceFixture.error_code(repeated),
		String(NodeChoiceRejection.ALREADY_COMMITTED)
	)
	assert_eq(committed.run_state.node_choice_receipts.size(), 1)


func test_every_payload_field_has_its_own_named_rejection() -> void:
	var run := NodeChoiceServiceFixture.prepared_run()
	var catalog := NodeChoiceServiceFixture.catalog_for(run)
	var rule := NodeChoiceServiceFixture.choice_set()
	var begun := NodeChoiceServiceFixture.begun_run(run, rule, catalog)
	var service := CommitNodeChoiceService.new()
	var cases: Array[Array] = [
		["expected_run_id", "run_deadbeef", NodeChoiceRejection.RUN_MISMATCH],
		[
			"node_id",
			StringName("node_%s" % "a".repeat(64)),
			NodeChoiceRejection.NODE_MISMATCH,
		],
		[
			"choice_set_id",
			&"choice_set.other",
			NodeChoiceRejection.CHOICE_SET_MISMATCH,
		],
		[
			"content_version",
			"fixture.other",
			NodeChoiceRejection.CONTENT_VERSION_MISMATCH,
		],
		[
			"catalog_schema_version",
			1,
			NodeChoiceRejection.CATALOG_SCHEMA_MISMATCH,
		],
		["content_codec_version", 2, NodeChoiceRejection.CODEC_MISMATCH],
		[
			"manifest_digest",
			"7".repeat(64),
			NodeChoiceRejection.MANIFEST_MISMATCH,
		],
		[
			"pending_digest",
			"8".repeat(64),
			NodeChoiceRejection.PENDING_DIGEST_MISMATCH,
		],
		["lifecycle_nonce", "00000000deadbeef", NodeChoiceRejection.NONCE_MISMATCH],
		["choice_id", &"choice.fixture.absent", NodeChoiceRejection.CHOICE_UNKNOWN],
	]
	for entry: Array in cases:
		var field: String = entry[0]
		var payload := NodeChoiceServiceFixture.payload_for(
			begun, &"choice.fixture.plain"
		)
		payload.set(field, entry[1])
		var rejected := service.commit(begun, payload, rule, catalog)
		assert_false(rejected.ok, "%s must be rejected" % field)
		assert_eq(
			NodeChoiceServiceFixture.error_code(rejected),
			String(entry[2]),
			"tampered %s" % field
		)
		assert_true(
			begun.resolution_state is NodeChoicePendingState,
			"rejection must leave the canonical pending untouched"
		)
		assert_true(begun.node_choice_receipts.is_empty())


func test_stale_payload_from_a_cancelled_lifecycle_is_rejected() -> void:
	var run := NodeChoiceServiceFixture.prepared_run()
	var catalog := NodeChoiceServiceFixture.catalog_for(run)
	var rule := NodeChoiceServiceFixture.choice_set()
	var service := CommitNodeChoiceService.new()
	var first := NodeChoiceServiceFixture.begun_run(run, rule, catalog)
	var stale := NodeChoiceServiceFixture.payload_for(
		first, &"choice.fixture.plain"
	)
	var cancelled := service.cancel(first)
	assert_true(cancelled.ok)
	if not cancelled.ok:
		return
	var second := NodeChoiceServiceFixture.begun_run(
		cancelled.run_state, rule, catalog
	)
	# 第一次生命週期留在 UI 手上的 payload 不得被第二次 pending 接受。
	var rejected := service.commit(second, stale, rule, catalog)
	assert_false(rejected.ok)
	assert_eq(
		NodeChoiceServiceFixture.error_code(rejected),
		String(NodeChoiceRejection.PENDING_DIGEST_MISMATCH)
	)


func test_begin_and_commit_reject_a_catalog_from_another_generation() -> void:
	var run := NodeChoiceServiceFixture.prepared_run()
	var catalog := NodeChoiceServiceFixture.catalog_for(run)
	var foreign := EconomyTestFixture.settlement_catalog("5".repeat(64))
	var rule := NodeChoiceServiceFixture.choice_set()
	var service := CommitNodeChoiceService.new()
	var begun_foreign := service.begin(
		run, NodeChoiceServiceFixture.current_node_id(run), rule, foreign
	)
	assert_false(begun_foreign.ok)
	assert_eq(
		NodeChoiceServiceFixture.error_code(begun_foreign),
		String(ExpeditionActionError.GENERATION_MISMATCH)
	)
	var begun := NodeChoiceServiceFixture.begun_run(run, rule, catalog)
	var payload := NodeChoiceServiceFixture.payload_for(
		begun, &"choice.fixture.plain"
	)
	var committed_foreign := service.commit(begun, payload, rule, foreign)
	assert_false(committed_foreign.ok)
	assert_eq(
		NodeChoiceServiceFixture.error_code(committed_foreign),
		String(ExpeditionActionError.GENERATION_MISMATCH)
	)


func test_command_requires_a_concrete_payload_and_pinned_catalog() -> void:
	var run := NodeChoiceServiceFixture.prepared_run()
	var catalog := NodeChoiceServiceFixture.catalog_for(run)
	var rule := NodeChoiceServiceFixture.choice_set()
	var begun := NodeChoiceServiceFixture.begun_run(run, rule, catalog)
	var payload := NodeChoiceServiceFixture.payload_for(
		begun, &"choice.fixture.plain"
	)
	assert_false(
		CommitNodeChoiceCommand.new(null, rule, catalog).is_concrete(),
		"payload is not optional"
	)
	assert_false(
		CommitNodeChoiceCommand.new(payload, rule, null).is_concrete(),
		"catalog pin is not optional"
	)
	var command := CommitNodeChoiceCommand.new(payload, rule, catalog)
	assert_true(command.is_concrete())
	var applied := command.apply_to(begun)
	assert_true(
		applied.ok, NodeChoiceServiceFixture.command_error_code(applied)
	)
