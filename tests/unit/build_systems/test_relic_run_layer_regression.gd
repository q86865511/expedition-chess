extends GutTest

## T06 (specs/build-systems) — 遺物 run-layer 效果集合的替換正確性與存檔重載不變。
## Covers：REQ-RELIC-001、S4-AC-010/011（第六件替換後效果集合正確且重載不變，回歸 S3
## 替換流程；同時觸發依 slot_index 升序）。
##
## 範圍聲明：S3 既有的第六件原子替換機制本身（ResolveRelicRewardCommand /
## RewardService.resolve_relic）已由 test_battle_settlement_and_rewards.gd 等既有測試覆蓋，
## 本檔不重測該機制。本檔鎖定的是 T06 新增的「效果推導」邏輯本身的正確性與重載穩定性：
## 給定 RosterState.active_relic_slots 在替換前後的兩種狀態（不論該狀態是如何產生的），
## RunRelicActivation.active_ids_in_slot_order() + RunRelicTable.ordered_rules() 推導出的
## 有效效果集合必須正確反映「當下」槽位內容（不可停留在替換前的舊值），且此推導結果在
## RunState 經 SaveJsonCodec 編碼/解碼一輪（模擬存檔重載）後必須逐位元不變。

func test_replacing_a_relic_slot_updates_the_derived_effect_set_not_stale() -> void:
	var root := SaveRootFixture.create_valid_root()
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [
		_economy_rule(&"relic.economy_old", 3),
		_economy_rule(&"relic.economy_new", 9),
	])
	root.run.roster_state.active_relic_slots[2].relic_id = OptionalStringNameValue.of(&"relic.economy_old")

	var ids_before := RunRelicActivation.active_ids_in_slot_order(root.run.roster_state.active_relic_slots)
	assert_eq(ids_before, [&"relic.economy_old"])
	var bonus_before := _sum_add_gold(table.ordered_rules(ids_before))
	assert_eq(bonus_before, 3)

	# 模擬 S3 第六件替換流程執行完畢後的槽位狀態（替換機制本身不在本檔重測）。
	root.run.roster_state.active_relic_slots[2].relic_id = OptionalStringNameValue.of(&"relic.economy_new")

	var ids_after := RunRelicActivation.active_ids_in_slot_order(root.run.roster_state.active_relic_slots)
	assert_eq(ids_after, [&"relic.economy_new"])
	var bonus_after := _sum_add_gold(table.ordered_rules(ids_after))
	assert_eq(bonus_after, 9, "effect set must reflect the replacement, not the stale pre-replacement relic")
	assert_ne(bonus_after, bonus_before)

func test_derived_effect_set_survives_a_save_reload_round_trip() -> void:
	# SaveRootFixture.create_receipt() 的 active_entry_ids 未包含本檔測試用的 relic id，
	# S1 遷移語意（save_json_codec.gd _migrate_required_id）會把不在 active_entry_ids
	# 內的 relic_id 判定為 MIGRATION_TOMBSTONE_REQUIRED，decode 回 ok=true/root=null——
	# 故比照 EquipDismantleTestFixture.equipment_receipt() 的模式，建自訂 receipt 把本測試
	# 用到的 relic id 加入 active_entry_ids，root.content_snapshot 與 codec 用同一份 receipt。
	var fixture := _root_with_relic_ids([&"relic.economy_new"])
	var root: SaveRoot = fixture["root"]
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [_economy_rule(&"relic.economy_new", 9)])
	root.run.roster_state.active_relic_slots[2].relic_id = OptionalStringNameValue.of(&"relic.economy_new")

	var codec: SaveJsonCodec = fixture["codec"]
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var decoded := codec.decode_bytes(encoded.bytes.value)
	assert_true(decoded.ok, String(decoded.error.field_path) if decoded.error != null else "decode failed")
	if not decoded.ok:
		return

	var ids_before_reload := RunRelicActivation.active_ids_in_slot_order(root.run.roster_state.active_relic_slots)
	var ids_after_reload := RunRelicActivation.active_ids_in_slot_order(decoded.root.run.roster_state.active_relic_slots)
	assert_eq(ids_after_reload, ids_before_reload)
	assert_eq(_sum_add_gold(table.ordered_rules(ids_after_reload)), 9)

func test_multi_slot_ascending_order_survives_a_save_reload_round_trip() -> void:
	# 同上：relic.slot0/2/4 須先加入自訂 receipt 的 active_entry_ids，避免 S1 遷移語意
	# 把它們判定為 tombstone-required 而使 decode 回 root=null。
	var fixture := _root_with_relic_ids([&"relic.slot4", &"relic.slot0", &"relic.slot2"])
	var root: SaveRoot = fixture["root"]
	root.run.roster_state.active_relic_slots[4].relic_id = OptionalStringNameValue.of(&"relic.slot4")
	root.run.roster_state.active_relic_slots[0].relic_id = OptionalStringNameValue.of(&"relic.slot0")
	root.run.roster_state.active_relic_slots[2].relic_id = OptionalStringNameValue.of(&"relic.slot2")

	var codec: SaveJsonCodec = fixture["codec"]
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var decoded := codec.decode_bytes(encoded.bytes.value)
	assert_true(decoded.ok)
	if not decoded.ok:
		return

	var ids_after_reload := RunRelicActivation.active_ids_in_slot_order(decoded.root.run.roster_state.active_relic_slots)
	assert_eq(ids_after_reload, [&"relic.slot0", &"relic.slot2", &"relic.slot4"])

## 建自訂 PinnedCatalogBuildReceipt：以 SaveRootFixture.create_receipt() 為底，把
## extra_relic_ids 併入 active_entry_ids（模式沿用 EquipDismantleTestFixture.equipment_receipt()）。
func _receipt_with_relic_ids(extra_relic_ids: Array[StringName]) -> PinnedCatalogBuildReceipt:
	var base := SaveRootFixture.create_receipt()
	var active_ids: Array[StringName] = base.active_entry_ids.duplicate()
	for relic_id: StringName in extra_relic_ids:
		active_ids.append(relic_id)
	active_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return PinnedCatalogBuildReceipt.new(
		base.catalog_schema_version,
		base.content_codec_version,
		base.content_version,
		base.selection_digest,
		active_ids,
		base.economy_config_id,
		base.combat_config_id,
		base.reward_table_ids,
		base.map_node_def_ids,
		base.challenge_unlock_def_ids,
		base.meta_reward_table_id,
		base.manifest_digest
	)

## 回傳 {root, codec}：root.run.content_snapshot 與 codec 使用同一份含 extra_relic_ids
## 的自訂 receipt，讓存檔重載測試用的 relic id 不被 S1 遷移語意判定為 tombstone-required。
func _root_with_relic_ids(extra_relic_ids: Array[StringName]) -> Dictionary:
	var receipt := _receipt_with_relic_ids(extra_relic_ids)
	var root := SaveRootFixture.create_valid_root()
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(receipt)
	assert(snapshot_result.ok, "relic-id-extended receipt must build a valid content snapshot")
	root.run.content_snapshot = snapshot_result.snapshot
	var codec := SaveJsonCodec.new(
		FakePinnedCatalogReceiptPort.new(receipt),
		FakeContentIdMigrationPort.new()
	)
	return {"root": root, "codec": codec}

func _economy_rule(relic_id: StringName, add_gold_amount: int) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"add_gold"
	operation.amount = add_gold_amount
	operation.claim_scope = &"once_per_node"
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"economy"
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule

func _sum_add_gold(rules: Array[RunRelicRule]) -> int:
	var total := 0
	for rule: RunRelicRule in rules:
		for operation: RunRelicOperationRule in rule.run_operations:
			if operation.kind == &"add_gold":
				total += operation.amount
	return total
