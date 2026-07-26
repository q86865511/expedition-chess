extends GutTest

## W5 R2 #7 / REQ-DATA-008：AppRoot 不得取得 authoring .tres 的共享
## MetaRewardTableDef。MetaRewardTableReader 必須只從 pinned registry canonical
## payload 重建完整純值 clone；消費端改動 clone 不得改變 registry view 或 digest。

const READER_PATH: String = "res://app/content/meta_reward_table_reader.gd"


func test_reader_rebuilds_every_meta_reward_field_from_pinned_canonical_payload() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var content := BuildLabContentBootstrap.new().run(registry)
	assert_true(content.ok, content.error_message)
	if not content.ok:
		return
	var reader := _reader()
	if reader == null:
		return

	var table: MetaRewardTableDef = reader.call(
		"try_read", registry, content.manifest_digest, content.meta_reward_table_id
	)
	assert_not_null(table)
	if table == null:
		return
	assert_eq(table.id, content.meta_reward_table_id)
	assert_eq(table.completion_reward, 10)
	assert_eq(table.failure_reward, 0)
	var expected_scores := {
		&"normal": 1,
		&"elite": 3,
		&"merchant": 0,
		&"event": 0,
		&"rest": 0,
		&"treasure": 0,
		&"boss": 5,
	}
	assert_eq(table.node_scores.size(), expected_scores.size())
	for score: EnumIntPairDef in table.node_scores:
		assert_true(expected_scores.has(score.enum_key))
		if expected_scores.has(score.enum_key):
			assert_eq(score.value_i32, int(expected_scores[score.enum_key]))
	assert_eq(table.challenge_multiplier_bps.size(), 6)
	for level: int in range(6):
		var entry: ChallengeMultiplierDef = table.challenge_multiplier_bps[level]
		assert_eq(entry.challenge_level, level)
		assert_eq(entry.basis_points, 10000 + level * 1000)


func test_mutating_reader_clone_does_not_change_registry_view_digest_or_next_read() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var content := BuildLabContentBootstrap.new().run(registry)
	assert_true(content.ok, content.error_message)
	if not content.ok:
		return
	var reader := _reader()
	if reader == null:
		return
	var before_view := registry.resolve(ContentRef.new(
		content.manifest_digest, content.meta_reward_table_id
	))
	assert_true(before_view.ok)
	var handle_before := registry.latest_catalog_handle()
	assert_true(handle_before.ok)
	if not before_view.ok or not handle_before.ok:
		return

	var first: MetaRewardTableDef = reader.call(
		"try_read", registry, content.manifest_digest, content.meta_reward_table_id
	)
	assert_not_null(first)
	if first == null:
		return
	first.completion_reward = 999999
	first.node_scores[0].value_i32 = 999999
	first.challenge_multiplier_bps[0].basis_points = 1

	var after_view := registry.resolve(ContentRef.new(
		content.manifest_digest, content.meta_reward_table_id
	))
	var handle_after := registry.latest_catalog_handle()
	var second: MetaRewardTableDef = reader.call(
		"try_read", registry, content.manifest_digest, content.meta_reward_table_id
	)
	assert_true(after_view.ok)
	assert_true(handle_after.ok)
	assert_not_null(second)
	if not after_view.ok or not handle_after.ok or second == null:
		return
	assert_eq(
		handle_after.value.manifest_digest, handle_before.value.manifest_digest,
		"mutating a consumer clone must not publish a new or silent registry generation"
	)
	assert_eq(
		after_view.value.payload.value_equals(before_view.value.payload), true,
		"registry canonical payload must remain unchanged"
	)
	assert_eq(second.completion_reward, 10)
	assert_eq(_score_value(second, &"normal"), 1)
	assert_eq(second.challenge_multiplier_bps[0].basis_points, 10000)


func _reader() -> RefCounted:
	if not ResourceLoader.exists(READER_PATH):
		assert_true(
			false,
			"MetaRewardTableReader script/API must exist at the canonical app/content path"
		)
		return null
	var script := load(READER_PATH) as Script
	assert_not_null(script, "MetaRewardTableReader script/API must exist at the canonical app/content path")
	if script == null:
		return null
	var reader := script.new() as RefCounted
	assert_not_null(reader)
	assert_true(reader.has_method("try_read"))
	return reader


func _score_value(table: MetaRewardTableDef, key: StringName) -> int:
	for score: EnumIntPairDef in table.node_scores:
		if score.enum_key == key:
			return score.value_i32
	return -1
