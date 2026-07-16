extends GutTest

func test_integer_resistance_true_damage_and_minimum_damage_vectors() -> void:
	var rules := BattleRulesSnapshot.new()
	assert_eq(BattleCombatMath.post_resistance(100, 100, &"physical", rules), 50)
	assert_eq(BattleCombatMath.post_resistance(100, -100, &"magical", rules), 150)
	assert_eq(BattleCombatMath.post_resistance(1, 1000000, &"physical", rules), 1)
	assert_eq(BattleCombatMath.post_resistance(37, 1000000, &"true", rules), 37)
	assert_eq(BattleCombatMath.post_resistance(0, -100, &"physical", rules), 0)

func test_progress_damage_mana_and_overtime_use_fixed_integer_thresholds() -> void:
	var rules := BattleRulesSnapshot.new()
	assert_eq(BattleCombatMath.threshold(rules), 20000)
	assert_eq(BattleCombatMath.initial_progress(1000, rules), 19000)
	assert_eq(BattleCombatMath.advance_progress(19000, 1000, rules), 20000)
	assert_eq(BattleCombatMath.damage_mana(1, 1000, rules), 1)
	assert_eq(BattleCombatMath.damage_mana(1000, 1000, rules), 10)
	assert_eq(BattleCombatMath.overtime_damage(101, 1, rules), 3)
	assert_eq(BattleCombatMath.overtime_damage(101, 100, rules), 21)

func test_modifier_recompute_is_sorted_and_clamped_without_float_math() -> void:
	var entity := BattleEntityState.new()
	entity.base_attack = 100
	entity.base_armor = -20
	entity.base_magic_resist = 10
	entity.base_attack_speed_milli = 1000
	entity.base_move_speed_milli = 1000
	var additive := BattleTimedState.new()
	additive.kind = &"modifier"
	additive.state_id = &"effect.add"
	additive.stat = &"attack"
	additive.mode = &"add"
	additive.amount = 20
	var multiplier := BattleTimedState.new()
	multiplier.kind = &"modifier"
	multiplier.state_id = &"effect.multiply"
	multiplier.stat = &"attack"
	multiplier.mode = &"multiply_bps"
	multiplier.amount = 15000
	entity.modifiers = [multiplier, additive]
	BattleCombatMath.recompute_effective_stats(entity, BattleRulesSnapshot.new())
	assert_eq(entity.attack, 180)
	assert_eq(entity.armor, -20)
