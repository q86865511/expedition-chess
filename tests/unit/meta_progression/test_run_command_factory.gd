extends GutTest

## T11 (specs/meta-progression/design.md §3, §4.4; requirements.md S5-AC-014; tasks.md T11;
## design.md §12 test case 014 "test_run_command_factory_injects_non_null_relic_table") —
## RunCommandFactory is the sole construction point for GenerateExpeditionMapCommand /
## RefreshShopCommand / SettleBattleResultCommand / EnterNodeEvent, always injecting a
## non-null RunRelicTable (HANDOFF.md §3's "S5 接手檢查項": these four commands' relic_table
## params are currently optional/default-null and nothing but tests/soak passes them --
## RunCommandFactory is design.md §4.4's named fix for that silent-skip regression).
##
## 假設聲明（design.md 未釘死 RunCommandFactory 的確切簽章，以下為 test-author 的 binding
## decision，比照 tests/fixtures/camp/start_expedition_test_fixture.gd 開頭的既定慣例）：
## 1. 新型別 RunCommandFactory（RefCounted），路徑 domain/run/controller/run_command_factory.gd
##    （與它建構的四個 command 同目錄 domain/run/controller/{,commands/,events/}，比照既有
##    RunSaveRootFactory／RunSessionFactory 的「同目錄 production builder」慣例）。
## 2. _init(catalog: EconomyExpeditionCatalog, relic_table: RunRelicTable,
##    battle_catalog: BattleRuleCatalog = null,
##    challenge_affix_effect_ids: Array[StringName] = [])：relic_table 為必要參數（無預設
##    值、不可省略）——這是 S5-AC-014「一律注入非 null relic_table」在型別層面能做到的最強
##    保證；battle_catalog 只有 enter_node_event() 需要，故給預設值 null，讓
##    generate_expedition_map_command()/refresh_shop_command()/
##    settle_battle_result_command() 三者不必為了不相關的欄位被迫傳 battle_catalog。
## 3. 四個建構方法，皆把建構子收到的 catalog/relic_table（及 enter_node_event 額外收到的
##    battle_catalog/challenge_affix_effect_ids）原樣轉呈給對應 command 的既有建構子：
##      generate_expedition_map_command() -> GenerateExpeditionMapCommand
##      refresh_shop_command() -> RefreshShopCommand
##      settle_battle_result_command() -> SettleBattleResultCommand
##      enter_node_event(target_node_id: String) -> EnterNodeEvent
##
## GUT 陷阱：RunCommandFactory 目前不存在，直接以 class_name 頂層引用會讓整檔 parse error
## 被 GUT 靜默排除（不計入失敗數）。比照 tests/unit/meta_progression/
## test_collection_view_model.gd 的 load() 動態載入寫法：本檔對 RunCommandFactory 一律經
## script.new(...)／.call(...) 間接呼叫；四個既有 command 類別（GenerateExpeditionMapCommand
## 等）本身已存在，可直接以型別名稱使用、做 `is` 型別檢查。

const SCRIPT_PATH := "res://domain/run/controller/run_command_factory.gd"


func test_factory_builds_all_four_command_types_and_each_is_concrete() -> void:
	var script := _load_script()
	if script == null:
		return
	var catalog := EconomyTestFixture.catalog(SaveRootFixture.MANIFEST_DIGEST)
	var battle_catalog := EconomyTestFixture.battle_catalog(SaveRootFixture.MANIFEST_DIGEST)
	var table := _table_with_rule(&"commander.fixture", &"commander", &"rule", &"heal_expedition_hp", 1)
	var factory: Object = script.new(catalog, table, battle_catalog)

	var map_command: Object = factory.call("generate_expedition_map_command")
	assert_true(map_command is GenerateExpeditionMapCommand)
	assert_true((map_command as GenerateExpeditionMapCommand).is_concrete())

	var shop_command: Object = factory.call("refresh_shop_command")
	assert_true(shop_command is RefreshShopCommand)
	assert_true((shop_command as RefreshShopCommand).is_concrete())

	var settle_command: Object = factory.call("settle_battle_result_command")
	assert_true(settle_command is SettleBattleResultCommand)
	assert_true((settle_command as SettleBattleResultCommand).is_concrete())

	var enter_event: Object = factory.call("enter_node_event", "node_fixture")
	assert_true(enter_event is EnterNodeEvent)
	assert_true((enter_event as EnterNodeEvent).is_concrete())


## design.md §6.1 消費端支援集合之一：BattleSettlementService 對 rule×heal_expedition_hp 的
## always-active 貢獻（既有機制，見 battle_settlement_service.gd:52-58）。用一個非空
## relic_table 建構出的 SettleBattleResultCommand，套用到一場勝利戰鬥草稿上，遠征 HP 必須
## 反映 commander 來源的 always-active 加成——若 factory 忘傳 relic_table（等同 HANDOFF §3
## 描述的既有回歸），這個加成不會出現，pre-battle 80 + bonus 5 就不會是 85。
func test_settle_battle_result_command_relic_table_bonus_is_observable() -> void:
	var script := _load_script()
	if script == null:
		return
	var root := _win_root(80, 0)
	var digest := root.run.content_snapshot.manifest_digest_value()
	var catalog := EconomyTestFixture.settlement_catalog(digest)
	var table := _table_with_rule(&"commander.fixture", &"commander", &"rule", &"heal_expedition_hp", 5)
	var factory: Object = script.new(catalog, table)

	var command: SettleBattleResultCommand = factory.call("settle_battle_result_command")
	var applied := command.apply_to(root.run.deep_clone())
	assert_true(applied.ok, String(applied.error.code) if not applied.ok else "ok")
	if not applied.ok:
		return
	assert_eq(
		applied.draft.expedition_hp, 85,
		"factory-built SettleBattleResultCommand must carry the non-null relic_table's" +
		" +5 commander always-active heal bonus through to the settled run"
	)


## 對照組：同一場景，factory 若被誤用成「不傳 relic_table 效果」（本測試以手動建構、
## relic_table=null 的 SettleBattleResultCommand 模擬 HANDOFF §3 描述的既有回歸樣式）必須
## 得到不同（較低）的結果，證明上一條測試量到的 +5 確實來自 relic_table 而非其他因素。
func test_settle_battle_result_command_without_relic_table_has_no_bonus() -> void:
	var root := _win_root(80, 0)
	var digest := root.run.content_snapshot.manifest_digest_value()
	var catalog := EconomyTestFixture.settlement_catalog(digest)
	var command_without_table := SettleBattleResultCommand.new(catalog, null, null)
	var applied := command_without_table.apply_to(root.run.deep_clone())
	assert_true(applied.ok, String(applied.error.code) if not applied.ok else "ok")
	if not applied.ok:
		return
	assert_eq(applied.draft.expedition_hp, 80, "no relic_table means no always-active bonus at all")


## design §6.3 軌 B：ShopSurchargeOperationDef 的 always-active 貢獻只作用在 quote_refresh()
## 的 reroll 定額費用上（shop_service.gd:38，「只套 surcharge、不套 discount」）——factory 建構
## 的 RefreshShopCommand 若忘傳 relic_table，reroll 恰好可負擔的金額就不會被 surcharge 推過
## 門檻。
func test_refresh_shop_command_surcharge_raises_the_reroll_price() -> void:
	var script := _load_script()
	if script == null:
		return
	var digest := SaveRootFixture.MANIFEST_DIGEST
	var catalog := EconomyTestFixture.catalog(digest)
	var base_reroll_cost := catalog.config().reroll_cost
	# 金額恰好夠付「無 surcharge」的 reroll 價，但不夠付「+4 surcharge」後的價。
	var draft_without := _prepare_shop_draft(digest, base_reroll_cost)
	var draft_with := _prepare_shop_draft(digest, base_reroll_cost)

	var table := _table_with_rule(&"commander.fixture", &"commander", &"economy", &"shop_surcharge", 4)
	var factory: Object = script.new(catalog, table)
	var with_surcharge_command: RefreshShopCommand = factory.call("refresh_shop_command")
	var with_result := with_surcharge_command.apply_to(draft_with)
	assert_false(
		with_result.ok,
		"reroll must be rejected once the factory-injected +4 surcharge exceeds the available gold"
	)
	if with_result.ok:
		return
	assert_eq(_diagnostic_source_code(with_result.error), String(ShopError.GOLD_INSUFFICIENT))

	var without_surcharge_command := RefreshShopCommand.new(catalog, null, null)
	var without_result := without_surcharge_command.apply_to(draft_without)
	assert_false(
		not without_result.ok
			and _diagnostic_source_code(without_result.error) == String(ShopError.GOLD_INSUFFICIENT),
		"without the surcharge, the same gold amount must not fail with GOLD_INSUFFICIENT"
	)


## RefreshShopCommand/EnterNodeEvent/GenerateExpeditionMapCommand/SettleBattleResultCommand
## all funnel their underlying named error (e.g. ShopError.GOLD_INSUFFICIENT) through
## CommandApplyError.diagnostic_values as a DiagnosticValue.from_string(&"source_code", ...)
## entry (see refresh_shop_command.gd's _failure()) -- the top-level .code is always the
## generic CommandApplyError.APPLY_REJECTED, so tests must read the diagnostic to see WHICH
## named error actually fired (HANDOFF.md §2 point 6's "具名原因的讀法").
func _diagnostic_source_code(error: CommandApplyError) -> String:
	if error == null or error.diagnostic_values.is_empty():
		return ""
	var value := error.diagnostic_values[0]
	return value.string_value.value if value.string_value != null else ""


## design §6.1 消費端支援集合之一：IncomeService 對 economy×add_gold 的 always-active 貢獻
## （income_service.gd:23-29），由 node_entry_service.gd:80-84 的 income quote 呼叫端消費。
## factory 建構的 EnterNodeEvent 進一個尚未請領過收入的非戰鬥節點，必須把 relic_table 的
## always-active add_gold 貢獻實際加進 economy_state.gold。
func test_enter_node_event_relic_table_income_bonus_is_observable() -> void:
	var script := _load_script()
	if script == null:
		return
	var digest := SaveRootFixture.MANIFEST_DIGEST
	var catalog := EconomyTestFixture.catalog(digest)
	var base_income := catalog.config().base_income_for_layer(0)
	# w5 仲裁（2026-07-25）：起始金 9（低於 interest_step_gold=10）確保利息項為 0——原案起始 11
	# 會多拿 1 利息（income_service.gd 公式含 interest 項），期望值漏算而恆差 1。
	# MERCHANT:EVENT/REST/TREASURE 進入後會轉 NodeChoicePending,與本測試要觀察的
	# income quote 無關;income 對所有 kind 一視同仁,測試意圖不變
	var draft := _map_draft_with_reachable_node(digest, MapNodeState.NodeKind.MERCHANT, 9)

	var table := _table_with_rule(&"commander.fixture", &"commander", &"economy", &"add_gold", 9)
	var factory: Object = script.new(catalog, table)
	var node_id: String = draft.map_state.nodes[0].node_id
	var event: EnterNodeEvent = factory.call("enter_node_event", node_id)
	var applied := event.apply_to(draft)
	assert_true(applied.ok, String(applied.error.code) if not applied.ok else "ok")
	if not applied.ok:
		return
	assert_eq(
		applied.draft.economy_state.gold, 9 + base_income + 9,
		"factory-built EnterNodeEvent must carry the +9 commander always-active add_gold" +
		" bonus into the node's income quote"
	)


## design §6.1 註解（route 佔用由 MapService 對規則計數、無對應 scalar run kind，本波
## RunModifierTableBuilder 不產出 route always-active 規則）：GenerateExpeditionMapCommand
## 這一波沒有 always-active 差異可觀察，故本測試只鎖「factory 產出正確型別、is_concrete()
## 為真、且 relic_table 不是 null 導致的立即結構性拒絕（成功產生地圖）」這一層——與其餘三個
## command 的「數值差異可觀察」證明不同層級，範圍差異已在檔頭假設聲明說明。
func test_generate_expedition_map_command_accepts_a_non_empty_relic_table() -> void:
	var script := _load_script()
	if script == null:
		return
	var digest := SaveRootFixture.MANIFEST_DIGEST
	var catalog := EconomyTestFixture.save_fixture_catalog(digest)
	var table := _table_with_rule(&"commander.fixture", &"commander", &"rule", &"heal_expedition_hp", 1)
	var factory: Object = script.new(catalog, table)
	var command: GenerateExpeditionMapCommand = factory.call("generate_expedition_map_command")
	var draft := _map_generation_ready_draft(digest)
	var applied := command.apply_to(draft)
	assert_true(applied.ok, String(applied.error.code) if not applied.ok else "ok")
	if not applied.ok:
		return
	assert_false(applied.draft.map_state.nodes.is_empty())


func _table_with_rule(
	source_id: StringName, source: StringName, category: StringName, kind: StringName, amount: int
) -> RunRelicTable:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = kind
	operation.amount = amount
	operation.claim_scope = &"always"
	var rule := RunRelicRule.new()
	rule.relic_id = source_id
	rule.category = category
	rule.source = source
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return RunRelicTable.new(SaveRootFixture.MANIFEST_DIGEST, [rule])


func _win_root(expedition_hp: int, damage: int) -> SaveRoot:
	var root := ResolutionFixtureFactory.create_root(ResolutionState.Kind.BATTLE_RESULT_PENDING)
	root.run.run_phase = RunState.RunPhase.COMBAT
	root.run.expedition_hp = expedition_hp
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	var previous := root.run.resolution_state as BattleResultPendingResolutionState
	var result := BattleResult.new()
	result.battle_setup_hash = StringName(previous.battle_setup_hash)
	result.outcome = &"player_win"
	result.final_tick = 20
	result.survivor_instance_ids = [&"u_0000000000000001"]
	result.expedition_damage = damage
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert_true(sealed.ok)
	root.run.resolution_state = BattleResultPendingResolutionState.new(
		previous.battle_setup_hash, BattleResult.from_record(sealed.record)
	)
	return root


## A PREPARE-phase draft with a current node, empty shop_offers, and a real unit pool --
## the minimum RefreshShopCommand.apply_to() needs to reach quote_refresh()'s affordability
## gate (shop_service.gd:29-40) with a legitimate, non-degenerate economy/pool shape.
func _prepare_shop_draft(digest: String, gold: int) -> RunState:
	var root := SaveRootFixture.create_valid_root()
	var run := root.run
	var catalog := EconomyTestFixture.catalog(digest)
	run.run_phase = RunState.RunPhase.PREPARE
	var node_id := "node_shop_fixture"
	run.current_node_id = OptionalStringValue.new(node_id)
	run.map_state.current_node_id = OptionalStringValue.new(node_id)
	run.economy_state = EconomyState.new(gold, 3, 0, 0, 0, 0, [])
	run.unit_pool_state = catalog.create_initial_pool()
	return run


## A MAP-phase draft with exactly one reachable, uncompleted, non-combat node -- enough for
## EnterNodeEvent.apply_to() to reach IncomeService.quote() without needing a battle_catalog.
func _map_draft_with_reachable_node(digest: String, kind: MapNodeState.NodeKind, gold: int) -> RunState:
	var root := SaveRootFixture.create_valid_root()
	var run := root.run
	var catalog := EconomyTestFixture.catalog(digest)
	run.run_phase = RunState.RunPhase.MAP
	run.current_node_id = null
	var registry := RuntimeKeySchemaRegistry.new()
	var node_result := registry.build_node(StringName(run.run_id), 1, MapNodeState.node_kind_to_token(kind), 0, 0)
	var node_key := node_result.key_state as NodeKeyState
	var node := MapNodeState.new(
		String(node_key.digest), node_key, &"mapnode.fixture", 1, 0, 0,
		kind, "a".repeat(64), null, false
	)
	var empty_edges: Array[MapEdgeState] = []
	var empty_completed: Array[String] = []
	run.map_state = MapState.new([node], empty_edges, null, empty_completed)
	run.economy_state = EconomyState.new(gold, 3, 0, 0, 0, 0, [])
	run.unit_pool_state = catalog.create_initial_pool()
	run.income_claimed_node_ids = []
	return run


## A MAP-phase draft ready for GenerateExpeditionMapCommand.apply_to(): empty map/current
## node/IDLE resolution, matching that command's own preflight (generate_expedition_map_
## command.gd:20-25).
func _map_generation_ready_draft(digest: String) -> RunState:
	var root := SaveRootFixture.create_valid_root()
	var run := root.run
	run.run_phase = RunState.RunPhase.MAP
	run.current_node_id = null
	var empty_nodes: Array[MapNodeState] = []
	var empty_edges: Array[MapEdgeState] = []
	var empty_completed: Array[String] = []
	run.map_state = MapState.new(empty_nodes, empty_edges, null, empty_completed)
	run.resolution_state = IdleResolutionState.new()
	return run


func _load_script() -> GDScript:
	var script := load(SCRIPT_PATH) as GDScript
	assert_not_null(
		script,
		(
			"RunCommandFactory (%s) must exist: _init(catalog, relic_table, battle_catalog" +
			" = null, challenge_affix_effect_ids = []) and generate_expedition_map_command()" +
			"/refresh_shop_command()/settle_battle_result_command()/enter_node_event(node_id)"
		) % SCRIPT_PATH
	)
	return script
