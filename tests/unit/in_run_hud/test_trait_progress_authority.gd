extends GutTest

## IRH-REQ-013（specs/in-run-hud）-- BattleSetupSourceCompiler.compile_trait_progress()
## 與 TraitPreviewViewModel.trait_progress()。
##
## 契約：羈絆進度（含「場上 0 隻」的 inactive 列、不同 def_id 計數、下一門檻）必須由
## domain 產出，且與 compile() 的 player_active_traits 同源——因此本 suite 對已達門檻的列
## 斷言「逐欄位等於 compile() 的產物」，而不只是「有回值」。

const TRAIT_ALPHA: StringName = &"trait.alpha"
const TRAIT_BETA: StringName = &"trait.beta"
const TRAIT_GAMMA: StringName = &"trait.gamma"
const UNIT_A: StringName = &"unit.alpha_a"
const UNIT_B: StringName = &"unit.alpha_b"
const UNIT_C: StringName = &"unit.alpha_c"
const UNIT_D: StringName = &"unit.alpha_d"
const UNIT_BENCH: StringName = &"unit.beta_bench"
const INSTANCE_A: String = "u_0000000000000101"
const INSTANCE_B: String = "u_0000000000000102"
const INSTANCE_C: String = "u_0000000000000103"
const INSTANCE_D: String = "u_0000000000000104"
const INSTANCE_BENCH: String = "u_0000000000000105"


func test_active_rows_match_compile_player_active_traits_field_by_field() -> void:
	var run := _progress_run(2)
	var catalog := _progress_catalog(run.content_snapshot.manifest_digest_value())
	var compiler := BattleSetupSourceCompiler.new()

	var bundle := compiler.compile(run.roster_state, catalog)
	assert_eq(bundle.player_active_traits.size(), 1, "只有 trait.alpha 達到門檻")
	if bundle.player_active_traits.size() != 1:
		return
	var active: TraitBattleSnapshot = bundle.player_active_traits[0]

	var progress := compiler.compile_trait_progress(run.roster_state, catalog)
	var alpha := _row(progress, TRAIT_ALPHA)
	assert_not_null(alpha, "trait.alpha 必須出現在進度列")
	if alpha == null:
		return
	assert_eq(alpha.trait_id, active.trait_id)
	assert_eq(alpha.active_tier, active.tier, "階序必須與實戰同源")
	assert_eq(alpha.member_instance_ids, active.member_instance_ids, "成員清單必須同源")
	assert_eq(alpha.distinct_count, 2, "不同 def_id 數決定 tier")
	assert_eq(alpha.next_required_count, 4, "下一階門檻取自 authored 階梯")
	assert_eq(alpha.thresholds.size(), 2)
	assert_eq(alpha.thresholds[0].tier, 1)
	assert_eq(alpha.thresholds[0].required_count, 2)
	assert_eq(alpha.thresholds[1].tier, 2)
	assert_eq(alpha.thresholds[1].required_count, 4)


func test_inactive_traits_are_listed_with_zero_count_and_next_threshold() -> void:
	var run := _progress_run(2)
	var catalog := _progress_catalog(run.content_snapshot.manifest_digest_value())
	var progress := BattleSetupSourceCompiler.new().compile_trait_progress(
		run.roster_state, catalog
	)

	assert_eq(progress.size(), 3, "pinned catalog 的三個羈絆都要有進度列")
	if progress.size() != 3:
		return
	assert_eq(progress[0].trait_id, TRAIT_ALPHA, "列序必須依 trait_id 字典序")
	assert_eq(progress[1].trait_id, TRAIT_BETA)
	assert_eq(progress[2].trait_id, TRAIT_GAMMA)

	# trait.beta 只有板凳單位帶，trait.gamma 連持有都沒有 -- 兩者都必須是 0 隻的 inactive 列。
	var beta := _row(progress, TRAIT_BETA)
	assert_eq(beta.distinct_count, 0, "板凳單位不計入上場計數")
	assert_eq(beta.active_tier, 0)
	assert_eq(beta.next_required_count, 2)
	assert_true(beta.member_instance_ids.is_empty())
	var gamma := _row(progress, TRAIT_GAMMA)
	assert_eq(gamma.distinct_count, 0)
	assert_eq(gamma.active_tier, 0)
	assert_eq(gamma.next_required_count, 3)


func test_max_tier_row_reports_next_required_as_minus_one() -> void:
	var run := _progress_run(4)
	var catalog := _progress_catalog(run.content_snapshot.manifest_digest_value())
	var compiler := BattleSetupSourceCompiler.new()
	var progress := compiler.compile_trait_progress(run.roster_state, catalog)

	var alpha := _row(progress, TRAIT_ALPHA)
	assert_eq(alpha.distinct_count, 4)
	assert_eq(alpha.active_tier, 2, "四個不同 def_id 達到第二階")
	assert_eq(alpha.next_required_count, -1, "已滿階必須明示沒有下一門檻")
	var bundle := compiler.compile(run.roster_state, catalog)
	assert_eq(bundle.player_active_traits[0].tier, 2, "compile() 必須給出同一階序")


func test_view_model_forwards_progress_and_returned_rows_are_isolated() -> void:
	var run := _progress_run(2)
	var catalog := _progress_catalog(run.content_snapshot.manifest_digest_value())
	var controller := _controller_for(run, catalog)
	var view_model := TraitPreviewViewModel.new(controller, catalog)

	var first := view_model.trait_progress()
	assert_eq(first.size(), 3, "ViewModel 必須轉發完整進度列")
	if first.size() != 3:
		return
	first[0].distinct_count = 99
	first[0].thresholds[0].required_count = 99
	first[0].member_instance_ids.append(&"injected")
	first.clear()

	var second := view_model.trait_progress()
	assert_eq(second.size(), 3, "改動先前回傳的清單不應影響之後的讀取")
	assert_eq(second[0].distinct_count, 2)
	assert_eq(second[0].thresholds[0].required_count, 2)
	assert_false(second[0].member_instance_ids.has(&"injected"))
	assert_eq(
		controller.roster_snapshot().board.placements.size(), 2,
		"讀取不得污染 domain roster"
	)
	# 同一份 roster 下，ViewModel 的產物與直接呼叫 compiler 相同。
	var direct := BattleSetupSourceCompiler.new().compile_trait_progress(
		controller.roster_snapshot(), catalog
	)
	assert_eq(second.size(), direct.size())
	assert_eq(second[0].active_tier, direct[0].active_tier)


func test_empty_board_and_missing_catalog_behave_explicitly() -> void:
	var run := _progress_run(0)
	var catalog := _progress_catalog(run.content_snapshot.manifest_digest_value())
	var compiler := BattleSetupSourceCompiler.new()

	var empty_board := compiler.compile_trait_progress(run.roster_state, catalog)
	assert_eq(empty_board.size(), 3, "沒有上場棋時仍要列出全部 authored 羈絆")
	for progress: TraitProgressSnapshot in empty_board:
		assert_eq(progress.distinct_count, 0)
		assert_eq(progress.active_tier, 0)

	var no_catalog := compiler.compile_trait_progress(run.roster_state, null)
	assert_true(no_catalog.is_empty(), "沒有 pinned catalog 時回空陣列而非 null")
	var no_roster := compiler.compile_trait_progress(null, catalog)
	assert_eq(no_roster.size(), 3, "沒有 roster 時仍列出羈絆，計數為 0")
	assert_eq(no_roster[0].distinct_count, 0)


# ---------------------------------------------------------------------------
# fixtures：trait.alpha 門檻 2/4；trait.beta 門檻 2（只有板凳單位帶）；
# trait.gamma 門檻 3（沒有任何單位帶）。on_board_count 決定上場的 alpha 單位數。
# ---------------------------------------------------------------------------

func _progress_run(on_board_count: int) -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.run_phase = RunState.RunPhase.PREPARE
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		UnitInstance.new(INSTANCE_A, UNIT_A, 1, no_equipment, U64Bits.zero()),
		UnitInstance.new(INSTANCE_B, UNIT_B, 1, no_equipment, U64Bits.zero()),
		UnitInstance.new(INSTANCE_C, UNIT_C, 1, no_equipment, U64Bits.zero()),
		UnitInstance.new(INSTANCE_D, UNIT_D, 1, no_equipment, U64Bits.zero()),
		UnitInstance.new(INSTANCE_BENCH, UNIT_BENCH, 1, no_equipment, U64Bits.zero()),
	]
	var board_instances: Array[String] = [INSTANCE_A, INSTANCE_B, INSTANCE_C, INSTANCE_D]
	var placements: Array[BoardPlacementState] = []
	var bench: Array[String] = [INSTANCE_BENCH]
	for index: int in range(board_instances.size()):
		if index < on_board_count:
			placements.append(BoardPlacementState.new(0, index, board_instances[index]))
		else:
			bench.append(board_instances[index])
	var no_items: Array[ItemInstanceState] = []
	var no_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(placements), bench, units, no_items, no_ids, no_ids, relics
	)
	return run


func _progress_catalog(manifest_digest: String) -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = [
		_unit_rule(UNIT_A, [TRAIT_ALPHA]),
		_unit_rule(UNIT_B, [TRAIT_ALPHA]),
		_unit_rule(UNIT_C, [TRAIT_ALPHA]),
		_unit_rule(UNIT_D, [TRAIT_ALPHA]),
		_unit_rule(UNIT_BENCH, [TRAIT_BETA]),
	]
	# authored 順序刻意不是字典序，用來確認回傳列序由 compile_trait_progress 決定。
	var traits: Array[BattleTraitRule] = [
		_trait_rule(TRAIT_GAMMA, [3]),
		_trait_rule(TRAIT_ALPHA, [2, 4]),
		_trait_rule(TRAIT_BETA, [2]),
	]
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		manifest_digest, units, traits, abilities, effects, encounters, equipment, configs
	)


func _trait_rule(trait_id: StringName, required_counts: Array) -> BattleTraitRule:
	var rule := BattleTraitRule.new()
	rule.trait_id = trait_id
	rule.trait_kind = &"faction"
	rule.member_rule = &"unit"
	var thresholds: Array[BattleTraitThresholdRule] = []
	for index: int in range(required_counts.size()):
		var threshold := BattleTraitThresholdRule.new()
		threshold.required_count = required_counts[index] as int
		threshold.effect_ids = [
			StringName("effect.%s_t%d" % [String(trait_id), index + 1])
		] as Array[StringName]
		thresholds.append(threshold)
	rule.thresholds = thresholds
	return rule


func _unit_rule(unit_id: StringName, trait_ids: Array) -> BattleUnitRule:
	var rule := BattleUnitRule.new()
	rule.unit_id = unit_id
	var typed_traits: Array[StringName] = []
	for value: Variant in trait_ids:
		typed_traits.append(value as StringName)
	rule.trait_ids = typed_traits
	rule.base_stats = BattleUnitStatsRule.new()
	rule.base_stats.health = 100
	rule.base_stats.attack = 10
	rule.base_stats.armor = 0
	rule.base_stats.magic_resist = 0
	rule.base_stats.attack_speed_milli = 1000
	rule.base_stats.attack_range_cells = 1
	rule.base_stats.start_mana = 0
	rule.base_stats.max_mana = 50
	rule.base_stats.move_speed_milli = 1000
	rule.ai_profile = &"melee"
	rule.basic_attack_profile = &"melee"
	rule.availability = &"always"
	rule.shop_condition = &"none"
	return rule


func _row(rows: Array[TraitProgressSnapshot], trait_id: StringName) -> TraitProgressSnapshot:
	for progress: TraitProgressSnapshot in rows:
		if progress.trait_id == trait_id:
			return progress
	return null


func _controller_for(run: RunState, catalog: BattleRuleCatalog) -> RunController:
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(repository)
	return ViewModelTestFixture.controller_for(run, catalog, repository)
