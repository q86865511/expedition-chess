extends GutTest

## R16 審查缺口 3（2026-07-30 補洞）：test_r16_formal_screen_contract.gd 裡
## test_results_and_fallback_render_the_sealed_settlement_pair 只驗 RewardValue／
## ProfileValue 這些節點「存在」,全 repo 沒有其他測試讀過 ReceiptValue 系節點的實際
## text——results_screen_composition.gd:29-38 若把 RewardValue／ProfileValue 兩個
## _set_value() 呼叫的來源欄位對調(receipt.currency_delta <-> profile.meta_currency),
## 全測試仍綠。本測試對兩個欄位餵入彼此不相等的具體數值,直接讀 Label.text 斷言各自
## 綁到正確的來源欄位。


func test_reward_value_and_profile_value_render_their_own_source_field_not_swapped() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	# Distinct from the receipt's currency_delta below so a field swap is observable.
	profile.meta_currency = 17
	var run_id: StringName = &"run.r16_results_field_swap_fixture"
	var receipt_key_result := RuntimeKeySchemaRegistry.new().build_settlement_receipt(run_id)
	assert_true(receipt_key_result.ok)
	if not receipt_key_result.ok:
		return
	var receipt := SettlementReceiptState.new(
		receipt_key_result.key_state as SettlementReceiptKeyState,
		SettlementReceiptState.Outcome.COMPLETED,
		42,
		"receipt.payload.r16_results_field_swap_fixture"
	)
	profile.settlement_receipts.append(receipt)
	var snapshot := ResultsPresentationSnapshot.capture(
		profile, receipt, run_id, "a".repeat(64), true
	)
	assert_true(
		snapshot.has_authoritative_pair(),
		"test setup: the receipt/profile pair must be authoritative before composing"
	)
	if not snapshot.has_authoritative_pair():
		return

	var screen := ProductionSceneCatalog.new().instantiate(&"RESULTS")
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)
	var composition := screen.get_node_or_null(^"Composition") as ResultsScreenComposition
	assert_not_null(composition)
	if composition == null:
		return
	assert_eq(composition.compose(snapshot), &"")

	var reward_label := composition.get_node_or_null(^"RewardValue") as Label
	var profile_label := composition.get_node_or_null(^"ProfileValue") as Label
	assert_not_null(reward_label)
	assert_not_null(profile_label)
	if reward_label == null or profile_label == null:
		return
	assert_eq(
		reward_label.text, "42",
		"RewardValue must render receipt.currency_delta (42), not profile.meta_currency (17)"
	)
	assert_eq(
		profile_label.text, "17",
		"ProfileValue must render profile.meta_currency (17), not receipt.currency_delta (42)"
	)
