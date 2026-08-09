extends GutTest

## T01 / IRH-REQ-016（specs/in-run-hud/requirements.md、design.md §7）--
## UnitStatsPreviewViewModel 與 BattleSetupSourceCompiler.try_compile_unit_stats()。
##
## 契約：備戰期單位屬性預覽必須與實戰同源 -- 走 compile() 用的同一條星級縮放路徑
## （_apply_stats／_find_scaling），不得在呈現層另生算法。因此本 suite 對「已上場」
## 單位斷言「預覽逐欄位等於直接呼叫 compile() 的 player_units」，而不只是「有回值」。
##
## compile() 只收棋盤上的單位（_collect_on_field 走 board.placements），板凳單位不在
## bundle 內；try_compile_unit_stats() 的存在理由就是讓板凳單位也能取得同源屬性。

const UNIT_BOARD: StringName = &"unit.preview_board"
const UNIT_BENCH: StringName = &"unit.preview_bench"
const BOARD_INSTANCE: String = "u_0000000000000011"
const BENCH_INSTANCE: String = "u_0000000000000012"
const EQUIP_INSTANCE: String = "i_0000000000000021"


func test_board_unit_preview_matches_direct_compile_field_by_field() -> void:
	var run := _preview_run()
	var catalog := _preview_catalog(run.content_snapshot.manifest_digest_value())
	var view_model := UnitStatsPreviewViewModel.new(_controller_for(run, catalog), catalog)

	var preview := view_model.try_stats_for(BOARD_INSTANCE)
	assert_not_null(preview, "已上場單位必須取得屬性預覽")
	if preview == null:
		return

	var direct := BattleSetupSourceCompiler.new().compile(run.roster_state, catalog)
	assert_eq(direct.player_units.size(), 1, "只有一個單位在棋盤上")
	if direct.player_units.size() != 1:
		return
	var compiled: UnitBattleSnapshot = direct.player_units[0]
	assert_eq(preview.unit_id, compiled.unit_id)
	assert_eq(preview.star, compiled.star)
	assert_eq(preview.health, compiled.health)
	assert_eq(preview.attack, compiled.attack)
	assert_eq(preview.armor, compiled.armor)
	assert_eq(preview.magic_resist, compiled.magic_resist)
	assert_eq(preview.attack_speed_milli, compiled.attack_speed_milli)
	assert_eq(preview.attack_range_cells, compiled.attack_range_cells)
	assert_eq(preview.start_mana, compiled.start_mana)
	assert_eq(preview.max_mana, compiled.max_mana)
	assert_eq(preview.move_speed_milli, compiled.move_speed_milli)
	assert_eq(preview.basic_attack_profile, compiled.basic_attack_profile)


func test_bench_unit_gets_star_scaled_preview_although_compile_excludes_it() -> void:
	var run := _preview_run()
	var catalog := _preview_catalog(run.content_snapshot.manifest_digest_value())
	var view_model := UnitStatsPreviewViewModel.new(_controller_for(run, catalog), catalog)

	# 前提確認：板凳單位確實不在 compile() 的產物內。
	var direct := BattleSetupSourceCompiler.new().compile(run.roster_state, catalog)
	assert_eq(direct.player_units.size(), 1, "compile() 只收棋盤單位")

	var preview := view_model.try_stats_for(BENCH_INSTANCE)
	assert_not_null(preview, "板凳單位仍須取得屬性預覽")
	if preview == null:
		return
	assert_eq(preview.unit_id, UNIT_BENCH)
	assert_eq(preview.star, 2)
	# 星級 2 的 bps：attack 15000、health 18000，其餘 10000（見 _preview_catalog）。
	# _scaled 為整數除法：10*15000/10000=15、100*18000/10000=180。
	assert_eq(preview.attack, 15, "星級縮放必須套用在 attack 上")
	assert_eq(preview.health, 180, "星級縮放必須套用在 health 上")
	assert_eq(preview.armor, 0, "bps 10000 的欄位維持基礎值")
	assert_eq(preview.attack_speed_milli, 1000)


func test_preview_reports_equipped_instance_ids_without_folding_effects_into_stats() -> void:
	# 裝備在實戰是經 effect 解算成 BattleTimedState 後由 BattleCombatMath 疊加的；
	# 預覽不重現 effect 解算（§10.3），只回報配戴中的 instance id 供面板列出來源。
	var run := _preview_run()
	var catalog := _preview_catalog(run.content_snapshot.manifest_digest_value())
	var view_model := UnitStatsPreviewViewModel.new(_controller_for(run, catalog), catalog)

	var preview := view_model.try_stats_for(BOARD_INSTANCE)
	assert_not_null(preview)
	if preview == null:
		return
	assert_eq(preview.equipment_instance_ids.size(), 1)
	assert_eq(preview.equipment_instance_ids[0], EQUIP_INSTANCE)
	assert_eq(preview.attack, 10, "未套用星級加成的基礎攻擊；裝備不得被摺進屬性數值")


func test_mutating_returned_preview_does_not_affect_domain_or_later_reads() -> void:
	var run := _preview_run()
	var catalog := _preview_catalog(run.content_snapshot.manifest_digest_value())
	var controller := _controller_for(run, catalog)
	var view_model := UnitStatsPreviewViewModel.new(controller, catalog)

	var first := view_model.try_stats_for(BOARD_INSTANCE)
	assert_not_null(first)
	if first == null:
		return
	first.attack = 999
	first.equipment_instance_ids.append("i_injected")

	var second := view_model.try_stats_for(BOARD_INSTANCE)
	assert_not_null(second)
	if second == null:
		return
	assert_eq(second.attack, 10, "改動先前回傳的預覽不應影響之後的讀取結果")
	assert_false(
		second.equipment_instance_ids.has("i_injected"),
		"改動先前回傳的預覽不應污染之後的讀取結果"
	)
	var roster_after := controller.roster_snapshot()
	assert_eq(roster_after.unit_instances.size(), 2, "domain roster 不應被污染")


func test_unknown_instance_id_returns_null_and_all_stats_is_deterministic() -> void:
	var run := _preview_run()
	var catalog := _preview_catalog(run.content_snapshot.manifest_digest_value())
	var view_model := UnitStatsPreviewViewModel.new(_controller_for(run, catalog), catalog)

	assert_null(view_model.try_stats_for("u_does_not_exist"), "未知 instance id 應回 null")
	assert_null(view_model.try_stats_for(""), "空字串應回 null")

	var all_stats := view_model.all_stats()
	assert_eq(all_stats.size(), 2, "棋盤與板凳單位都應出現在 all_stats()")
	if all_stats.size() != 2:
		return
	assert_eq(all_stats[0].instance_id, StringName(BOARD_INSTANCE), "應依 instance id 排序")
	assert_eq(all_stats[1].instance_id, StringName(BENCH_INSTANCE))


# ---------------------------------------------------------------------------
# fixtures：一個上場（星 1、配一件裝備）＋一個板凳（星 2）
# ---------------------------------------------------------------------------

func _preview_run() -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.run_phase = RunState.RunPhase.PREPARE
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, BOARD_INSTANCE),
	]
	var board_equipment: Array[String] = [EQUIP_INSTANCE]
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		UnitInstance.new(BOARD_INSTANCE, UNIT_BOARD, 1, board_equipment, U64Bits.zero()),
		UnitInstance.new(BENCH_INSTANCE, UNIT_BENCH, 2, no_equipment, U64Bits.zero()),
	]
	var no_items: Array[ItemInstanceState] = []
	var bench_ids: Array[String] = [BENCH_INSTANCE]
	var no_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(placements), bench_ids, units, no_items, no_ids, no_ids, relics
	)
	return run


func _preview_catalog(manifest_digest: String) -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = [
		_unit_rule(UNIT_BOARD, 1, 10000, 10000),
		_unit_rule(UNIT_BENCH, 2, 15000, 18000),
	]
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		manifest_digest, units, traits, abilities, effects, encounters, equipment, configs
	)


func _unit_rule(
	unit_id: StringName,
	star: int,
	attack_bps: int,
	health_bps: int
) -> BattleUnitRule:
	var rule := BattleUnitRule.new()
	rule.unit_id = unit_id
	rule.trait_ids = [] as Array[StringName]
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
	var scaling := BattleStarScalingRule.new()
	scaling.star = star
	scaling.health_bps = health_bps
	scaling.attack_bps = attack_bps
	scaling.armor_bps = 10000
	scaling.magic_resist_bps = 10000
	scaling.attack_speed_bps = 10000
	scaling.attack_range_bps = 10000
	scaling.start_mana_bps = 10000
	scaling.max_mana_bps = 10000
	scaling.move_speed_bps = 10000
	rule.star_scalings = [scaling]
	rule.ai_profile = &"melee"
	rule.basic_attack_profile = &"melee"
	rule.availability = &"always"
	rule.shop_condition = &"none"
	return rule


func _controller_for(run: RunState, catalog: BattleRuleCatalog) -> RunController:
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(repository)
	return ViewModelTestFixture.controller_for(run, catalog, repository)
