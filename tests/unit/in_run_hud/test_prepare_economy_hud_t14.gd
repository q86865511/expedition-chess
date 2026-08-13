extends GutTest

## IRH-REQ-011／T14：正式 HUD 只消費 bind-time typed quote/economy clone；
## 費率是 pinned basis-points 的文字格式化，按鈕可用性與停用原因只由 quote 決定。

const MESSAGE_KEYS := {
	&"prepare.resource.hp": "HP",
	&"prepare.resource.gold": "Gold",
	&"prepare.resource.level_xp": "Level / XP",
	&"prepare.resource.level_xp_max": "Max",
	&"prepare.resource.capacity": "Population",
	&"prepare.resource.win_streak": "Win Streak",
	&"prepare.resource.loss_streak": "Loss Streak",
	&"prepare.resource.shop_odds": "Shop Odds",
	&"prepare.refresh": "Refresh",
	&"prepare.xp": "Buy XP",
	&"prepare.panel.synergies": "Traits",
	&"prepare.panel.inventory": "Inventory",
	&"prepare.panel.units": "Units",
	&"prepare.panel.expedition": "Expedition",
	&"combat.inspection.none": "None",
	&"error.shop.gold_insufficient": "Not enough gold",
	&"error.shop.level_max": "Level is already at maximum",
	&"error.shop.input_invalid": "This shop action is not available right now",
}

const ZH_KEYS := {
	&"screen.run_prepare.title": "備戰",
	&"screen.run_container.title": "系統",
	&"prepare.resource.hp": "遠征生命",
	&"prepare.resource.gold": "金幣",
	&"prepare.resource.level_xp": "等級／經驗",
	&"prepare.resource.level_xp_max": "已達上限",
	&"prepare.resource.capacity": "人口",
	&"prepare.resource.win_streak": "連勝",
	&"prepare.resource.loss_streak": "連敗",
	&"prepare.resource.shop_odds": "費用機率",
	&"prepare.refresh": "刷新商店",
	&"prepare.xp": "購買經驗",
	&"prepare.panel.synergies": "羈絆",
	&"prepare.panel.inventory": "裝備庫",
	&"prepare.panel.units": "單位",
	&"prepare.panel.expedition": "遠征",
	&"combat.inspection.none": "無",
	&"error.shop.gold_insufficient": "金幣不足",
	&"error.shop.level_max": "等級已達上限",
	&"error.shop.input_invalid": "目前無法進行這項商店操作",
}


class ShopSupplySession:
	extends RunPresentationSession

	var status := ShopEconomySnapshot.new()

	func _init() -> void:
		status.gold = 17
		status.level = 9
		status.xp = 0
		status.xp_required_for_next_level = -1
		status.at_max_level = true
		status.win_streak = 4
		status.loss_streak = 1
		status.odds_level = 9
		status.odds_tier_basis_points = [3333, 1250, 1, 0, 5416]

	func shop_economy_status() -> ShopEconomySnapshot:
		return status.deep_clone()

	func shop_refresh_quote() -> ShopQuoteSnapshot:
		var quote := ShopQuoteSnapshot.new()
		quote.action = &"refresh"
		quote.quotable = true
		quote.gold_cost = 2
		quote.rejection_code = &"SHOP_GOLD_INSUFFICIENT"
		return quote

	func shop_buy_xp_quote() -> ShopXpQuoteSnapshot:
		var quote := ShopXpQuoteSnapshot.new()
		quote.at_max_level = true
		quote.rejection_code = &"SHOP_LEVEL_MAX"
		return quote


class IntegrationShopSession:
	extends RunPresentationSession

	var dispatched_kinds: Array[int] = []
	var projected_snapshot: RunPresentationSnapshot

	func _init(snapshot: RunPresentationSnapshot) -> void:
		projected_snapshot = snapshot.deep_clone()

	func snapshot() -> RunPresentationSnapshot:
		return projected_snapshot.deep_clone()

	func shop_economy_status() -> ShopEconomySnapshot:
		var status := ShopEconomySnapshot.new()
		status.gold = 10
		status.level = 3
		status.xp = 2
		status.xp_required_for_next_level = 4
		status.win_streak = 2
		status.loss_streak = 0
		status.odds_level = 3
		status.odds_tier_basis_points = [10000, 0, 0, 0, 0]
		return status

	func shop_refresh_quote() -> ShopQuoteSnapshot:
		var quote := ShopQuoteSnapshot.new()
		quote.action = &"refresh"
		quote.available = true
		quote.affordable = true
		quote.quotable = true
		quote.gold_before = 10
		quote.gold_cost = 2
		return quote

	func shop_buy_xp_quote() -> ShopXpQuoteSnapshot:
		var quote := ShopXpQuoteSnapshot.new()
		quote.quotable = true
		quote.gold_before = 1
		quote.gold_cost = 4
		quote.xp_gain = 4
		quote.rejection_code = &"SHOP_GOLD_INSUFFICIENT"
		return quote

	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		dispatched_kinds.append(intent.kind)
		return RunPresentationResult.success(projected_snapshot)


func test_mapper_contains_the_complete_shop_error_table() -> void:
	var expected := {
		&"SHOP_GOLD_INSUFFICIENT": &"error.shop.gold_insufficient",
		&"SHOP_LEVEL_MAX": &"error.shop.level_max",
		&"SHOP_OFFER_STALE": &"error.shop.offer_stale",
		&"SHOP_ROSTER_FULL": &"error.shop.roster_full",
		&"SHOP_UNIT_MISSING": &"error.shop.unit_missing",
		&"SHOP_UNIT_RULE_MISSING": &"error.shop.unit_rule_missing",
		&"SHOP_UNIT_POOL_INVALID": &"error.shop.unit_pool_invalid",
		&"SHOP_RESERVATION_INVALID": &"error.shop.reservation_invalid",
		&"SHOP_CATALOG_GENERATION_MISMATCH": &"error.shop.generation_mismatch",
		&"SHOP_INPUT_INVALID": &"error.shop.input_invalid",
		&"SHOP_RNG_FAILED": &"error.shop.internal_failure",
		&"SHOP_KEY_FAILED": &"error.shop.internal_failure",
		&"SHOP_DIGEST_FAILED": &"error.shop.internal_failure",
		&"SHOP_CONFIG_INVALID": &"error.shop.internal_failure",
		&"SHOP_SERIAL_EXHAUSTED": &"error.shop.internal_failure",
		&"SHOP_MERGE_FAILED": &"error.shop.internal_failure",
	}
	var mapper := PresentationErrorMapper.new()
	for source_code: StringName in expected:
		assert_eq(
			mapper.message_key_for(source_code),
			expected[source_code],
			String(source_code)
		)


func test_hud_renders_max_streaks_and_five_authored_odds_from_bind_clone() -> void:
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 1401)
	var supply_session := ShopSupplySession.new()
	var port := LiveScreenSupplyPort.new(lease, registry, supply_session)
	var shell := _bind_shell(port)
	autofree(shell)

	var level_xp := shell.find_child("LevelXpValue", true, false) as Label
	var win := shell.find_child("WinStreakValue", true, false) as Label
	var loss := shell.find_child("LossStreakValue", true, false) as Label
	var odds := shell.find_child("ShopOddsValue", true, false) as Label
	assert_not_null(level_xp)
	assert_not_null(win)
	assert_not_null(loss)
	assert_not_null(odds)
	if level_xp == null or win == null or loss == null or odds == null:
		return
	assert_eq(level_xp.text, "Level / XP  9 · Max")
	assert_eq(win.text, "Win Streak  4")
	assert_eq(loss.text, "Loss Streak  1")
	assert_eq(
		odds.text,
		"Shop Odds  ◆1 33.33% · ◆2 12.50% · ◆3 0.01% · ◆4 0% · ◆5 54.16%"
	)
	assert_eq(odds.get_meta(&"odds_tier_basis_points"), [3333, 1250, 1, 0, 5416])

	# bind 後改動供給端，既有 HUD 不得持有同一份 mutable snapshot。
	supply_session.status.win_streak = 99
	supply_session.status.odds_tier_basis_points[0] = 9999
	assert_eq(win.text, "Win Streak  4")
	assert_eq(odds.get_meta(&"odds_tier_basis_points")[0], 3333)


func test_revoked_supply_and_named_quotes_fail_closed_without_phase_guessing() -> void:
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 1402)
	var port := LiveScreenSupplyPort.new(lease, registry, ShopSupplySession.new())
	registry.revoke(lease)
	var shell := _bind_shell(port)
	autofree(shell)
	var unavailable := shell.find_child(
		"ShopEconomyUnavailable", true, false
	) as Label
	assert_not_null(unavailable)
	if unavailable != null:
		assert_true(bool(unavailable.get_meta(&"quote_fail_closed", false)))
		assert_string_contains(unavailable.text, MESSAGE_KEYS[&"error.shop.input_invalid"])

	var screen := ProductionScreen.new()
	screen.route_kind = &"RUN_PREPARE"
	screen._context = StagedScreenContext.new(
		&"RUN_PREPARE", RunPresentationSnapshot.new(), null, &"en", MESSAGE_KEYS
	)
	var refresh := Button.new()
	var insufficient := ShopQuoteSnapshot.new()
	insufficient.quotable = true
	insufficient.gold_cost = 2
	insufficient.rejection_code = &"SHOP_GOLD_INSUFFICIENT"
	screen._apply_shop_quote_button(
		refresh, &"prepare.refresh", insufficient
	)
	assert_true(refresh.disabled)
	assert_eq(refresh.text, "Refresh · 2")
	assert_eq(refresh.tooltip_text, "Refresh · Not enough gold")
	assert_eq(
		refresh.get_meta(&"shop_quote_message_key"),
		&"error.shop.gold_insufficient"
	)

	var xp_button := Button.new()
	var max_quote := ShopXpQuoteSnapshot.new()
	max_quote.at_max_level = true
	max_quote.rejection_code = &"SHOP_LEVEL_MAX"
	screen._apply_xp_quote_button(xp_button, max_quote)
	assert_true(xp_button.disabled)
	assert_eq(xp_button.text, "Buy XP · Max")
	assert_eq(xp_button.tooltip_text, "Buy XP · Level is already at maximum")

	var phase_neutral := ShopQuoteSnapshot.new()
	phase_neutral.rejection_code = &"SHOP_INPUT_INVALID"
	screen._apply_shop_quote_button(
		refresh, &"prepare.refresh", phase_neutral
	)
	assert_true(refresh.disabled)
	assert_eq(
		refresh.get_meta(&"shop_quote_message_key"),
		&"error.shop.input_invalid",
		"SHOP_INPUT_INVALID 只顯示中性文案，不推斷 phase"
	)
	refresh.free()
	xp_button.free()
	screen.free()


func test_formal_prepare_lifecycle_keeps_quotes_reasons_and_locale_coherent() -> void:
	var snapshot := _formal_snapshot()
	var session := IntegrationShopSession.new(snapshot)
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 1403)
	var intent := LiveScreenIntentPort.new(lease, registry, session)
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)
	assert_eq(screen.bind(StagedScreenContext.new(
		&"RUN_PREPARE", snapshot, null, &"zh_TW", ZH_KEYS
	)), &"")
	var live := ProductionLiveScreenContext.new(
		&"RUN_PREPARE",
		snapshot,
		null,
		ProductionScreenActionPort.new(lease, registry, {}),
		LiveScreenNavigationPort.new(),
		intent
	)
	assert_eq(screen.prepare_live_binding(live), &"")
	add_child_autofree(screen)
	screen.activate_live()

	var refresh := screen.find_child("PrepareRefreshButton", true, false) as Button
	var xp := screen.find_child("PrepareXpButton", true, false) as Button
	var xp_reason := screen.find_child("BuyXpReason", true, false) as Label
	assert_not_null(refresh)
	assert_not_null(xp)
	assert_not_null(xp_reason)
	if refresh == null or xp == null or xp_reason == null:
		return
	assert_false(refresh.disabled)
	assert_eq(refresh.text, "刷新商店 · 2")
	assert_true(xp.disabled)
	assert_eq(xp.text, "購買經驗 · 4")
	assert_true(xp_reason.visible, "disabled button 外必須有常駐可見的 reason surface")
	assert_eq(xp_reason.text, "金幣不足")
	assert_eq(xp_reason.focus_mode, Control.FOCUS_NONE, "reason 是 status，不是假按鈕")
	assert_eq(xp_reason.get_meta(&"accessibility_role"), &"status")
	assert_eq(xp_reason.get_meta(&"accessible_text"), "金幣不足")

	# generic state refresh 不得把 typed quote 停用的 XP 復活。
	screen.refresh_interaction_state()
	assert_false(refresh.disabled)
	assert_true(xp.disabled)

	var hud := screen.find_child("InRunHudShell", true, false) as InRunHudShell
	assert_not_null(hud)
	if hud != null:
		hud.show_prepare_unit("unit_t14")
	var inspector := screen.find_child("UnitInspector", true, false) as VBoxContainer
	assert_not_null(inspector)
	if inspector != null:
		assert_eq(inspector.get_meta(&"unit_instance_id"), &"unit_t14")

	var en := MESSAGE_KEYS.duplicate(true)
	en[&"screen.run_prepare.title"] = "Prepare"
	en[&"screen.run_container.title"] = "System"
	screen.relocalize(&"en", en)
	assert_eq(refresh.text, "Refresh · 2")
	assert_eq(xp.text, "Buy XP · 4")
	assert_eq(xp_reason.text, "Not enough gold")
	var win := screen.find_child("WinStreakValue", true, false) as Label
	assert_not_null(win)
	if win != null:
		assert_eq(win.text, "Win Streak  2", "HUD 用既有 economy clone 原地重畫")
	if inspector != null:
		assert_same(
			screen.find_child("UnitInspector", true, false), inspector,
			"relocalize 不可重建 T17 inspector"
		)
		assert_eq(inspector.get_meta(&"unit_instance_id"), &"unit_t14")

	refresh.pressed.emit()
	assert_eq(session.dispatched_kinds.size(), 1)
	assert_eq(
		session.dispatched_kinds[0],
		RunPresentationIntent.Kind.REFRESH_SHOP,
		"available quote 仍走正式 intent dispatch"
	)
	assert_true(xp.disabled)


func _bind_shell(port: LiveScreenSupplyPort) -> InRunHudShell:
	var snapshot := RunPresentationSnapshot.new()
	snapshot.economy = EconomyState.new(88, 3, 2, 0, 0, 0, [])
	snapshot.board_validation_report = BoardValidationReport.new(4, [])
	var shell := InRunHudShell.new()
	assert_eq(shell.bind(
		snapshot,
		&"RUN_PREPARE",
		func(_region: StringName) -> Rect2:
			return Rect2(Vector2.ZERO, Vector2(1600.0, 900.0)),
		func(key: StringName) -> String:
			return String(MESSAGE_KEYS.get(key, String(key))),
		func(key: StringName) -> String:
			return String(key),
		port
	), &"")
	return shell


func _formal_snapshot() -> RunPresentationSnapshot:
	var snapshot := RunPresentationSnapshot.new()
	snapshot.run_id = &"run_t14_formal"
	snapshot.app_phase = &"PREPARE"
	var unit := UnitInstance.new(
		"unit_t14", &"unit.test_t14", 1, [], U64Bits.one()
	)
	snapshot.roster = RosterState.new(
		BoardState.new([]), ["unit_t14"], [unit], [], [], [], []
	)
	snapshot.economy = EconomyState.new(10, 3, 2, 2, 0, 0, [])
	snapshot.board_validation_report = BoardValidationReport.new(3, [])
	var inspection := PrepareUnitInspectionSnapshot.new()
	inspection.unit_instance_id = &"unit_t14"
	inspection.unit_def_id = &"unit.test_t14"
	inspection.unit_id = &"unit.test_t14"
	inspection.star = 1
	inspection.cost_tier = 1
	snapshot.prepare_unit_inspections.append(inspection)
	return snapshot
