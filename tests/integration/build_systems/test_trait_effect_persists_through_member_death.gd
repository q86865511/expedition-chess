extends GutTest

## T12（specs/build-systems）— S4-AC-003 子句：「戰鬥中構成羈絆的單位死亡 -> 已啟動羈絆效果
## 持續到戰鬥結束」的整合案例，經 BattleSimulation 實跑（非 mock）。
## Covers：REQ-TRAIT-002、S4-AC-003（tasks.md T12 補充：本子句 T02 單元層無法表達，
## 需在 T12 補整合測試；BattleSetupSourceCompiler 的 compile() 正確性與 preview/combat 同源
## 已由 test_battle_setup_source_compiler.gd 鎖定，本檔不重測 compiler，只鎖定 BattleSimulation
## 消費 player_active_traits 的既有行為：羈絆效果在 initialize() 時一次性登記進
## state.effect_sources（見 battle_simulation.gd:41-42），之後每 tick 的排程觸發
## （_resolve_scheduled_triggers）不檢查任何「trait 成員是否仍存活」，故羈絆成員戰鬥中死亡
## 不會使已啟動的羈絆效果失效——這是既有架構的不變式，本測試把它鎖成迴歸案例）。
##
## 範圍聲明：本檔直接手建 BattleSetupInputs（不經 BattleSetupSourceCompiler.compile()），
## 因為要鎖定的行為屬於 BattleSimulation 消費 player_active_traits 的既有邏輯，與 compiler
## 如何產出該欄位無關（compiler 的正確性已由 T02 測試獨立覆蓋）。
##
## 場景設計：2 名玩家棋同屬一個羈絆（trait.test，沿用 BattleSimulationFixture 既有的
## 合法 trait_id，只替換其 member_instance_ids 與 effect_assignments）：
## - UNIT_A：hp=1，與敵人相鄰（distance=1），敵人一擊必殺 -> 第 1 tick 死亡。
## - UNIT_B：hp=100000、attack=100、attack_range_cells=7（battle_setup_inputs_validator.gd:208
##   的上限；涵蓋起始距離，免除路徑規劃），
##   持續對敵人造成傷害直到擊殺（敵人 hp=300，需 3 個 tick），故戰鬥必然在 UNIT_A 死亡後
##   還會再跑至少 1 個 tick。
## 羈絆效果為 periodic（每 tick 觸發一次）、grant_mana operation、target=all_allies，
## source_category=&"trait"（design.md §4/§6 的 GLOBAL_CATEGORIES 慣例：無 source_instance_id、
## 無成員存活檢查）。若戰鬥結束時的 global_effect_use_count 等於最終 tick 數，即證明此羈絆
## 效果從 tick 1 到戰鬥結束每 tick 都被觸發——涵蓋 UNIT_A 死亡之後的所有 tick。

const _ENEMY_HEALTH: int = 300
const _UNIT_B_ATTACK: int = 100
const _MAX_STEPS: int = 50

func test_trait_effect_keeps_firing_periodically_after_a_member_dies_mid_combat() -> void:
	var inputs := _build_inputs()
	var simulation := BattleSimulation.new()
	var setup := BattleSimulationFixture.build_setup(inputs)
	assert_not_null(setup)
	if setup == null:
		return
	assert_true(simulation.initialize(setup).ok)

	var death_tick_for_unit_a := -1
	var final_tick := -1
	for _step_index: int in range(_MAX_STEPS):
		var stepped := simulation.step()
		assert_true(stepped.ok, "%s" % [String(stepped.error.code) if not stepped.ok and stepped.error != null else "ok"])
		if not stepped.ok:
			return
		if death_tick_for_unit_a < 0:
			for event: BattleEvent in stepped.events:
				if event.type == &"death" and event.source_instance_id != null \
					and event.source_instance_id.value == &"u_0000000000000001":
					death_tick_for_unit_a = stepped.tick
		if stepped.finished:
			final_tick = stepped.tick
			break
	assert_ne(death_tick_for_unit_a, -1, "UNIT_A (trait member) must actually die mid-combat for this regression to be meaningful")
	assert_ne(final_tick, -1, "simulation must finish within _MAX_STEPS")
	assert_gt(final_tick, death_tick_for_unit_a, "battle must keep running for at least one more tick after the trait member dies")

	var result := simulation.result()
	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.result.outcome, &"player_win", "UNIT_B alone must be able to finish the encounter after UNIT_A dies")

	var final_state := simulation.state_snapshot()
	var token := "trait/player/trait.test/0000000000/0000000000"
	assert_eq(
		final_state.global_effect_use_count(token, &"effect.trait_periodic"), final_tick,
		"the trait-sourced periodic effect must have fired on every tick through the end of combat, including every tick after UNIT_A's death"
	)

func _build_inputs() -> BattleSetupInputs:
	var inputs := BattleSimulationFixture.create_inputs()
	var unit_a := inputs.player_units[0]
	unit_a.logical_y = 1
	unit_a.logical_x = 3
	unit_a.health = 1
	unit_a.attack = 0
	unit_a.max_mana = 0

	var unit_b := unit_a.deep_clone()
	unit_b.instance_id = &"u_0000000000000002"
	unit_b.logical_y = 5
	unit_b.logical_x = 3
	unit_b.health = 100000
	unit_b.attack = _UNIT_B_ATTACK
	unit_b.attack_range_cells = 7
	unit_b.max_mana = 0
	unit_b.ability_id = null
	unit_b.effect_ids.clear()
	unit_b.effect_assignments.clear()
	inputs.player_units.append(unit_b)

	var enemy := inputs.encounter_snapshot.enemy_units[0]
	enemy.logical_y = 0
	enemy.logical_x = 3
	enemy.health = _ENEMY_HEALTH
	enemy.attack = 999
	enemy.attack_range_cells = 1
	enemy.max_mana = 0

	var trait_snapshot := inputs.player_active_traits[0]
	trait_snapshot.member_instance_ids = [unit_a.instance_id, unit_b.instance_id]
	var assignment := BattleEffectSnapshot.new()
	assignment.priority = 0
	assignment.source_category = &"trait"
	assignment.source_side = &"player"
	assignment.source_stable_id = trait_snapshot.trait_id
	assignment.source_instance_id = null
	assignment.source_slot = 0
	assignment.effect_index = 0
	assignment.effect_id = &"effect.trait_periodic"
	trait_snapshot.effect_assignments = [assignment]

	var effect_rule := BattleEffectRuleSnapshot.new()
	effect_rule.effect_id = &"effect.trait_periodic"
	effect_rule.trigger = &"periodic"
	effect_rule.periodic_interval_ticks = 1
	effect_rule.stacking = &"replace"
	effect_rule.max_stacks = 1
	effect_rule.duration_ticks = 1
	var operation := BattleOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"grant_mana"
	operation.amount = 1
	operation.target = &"all_allies"
	effect_rule.battle_operations.append(operation)
	inputs.battle_rules.effect_rules.append(effect_rule)

	return inputs
