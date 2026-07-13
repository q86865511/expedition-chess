extends RefCounted

const GOLDEN_SIZE: int = 1559
const GOLDEN_SHA256: String = "e92f72d4c752b240aa7203c7e3899c07cfe113c4d05f5240c0e384398bcd0922"

static func create_inputs() -> BattleSetupInputs:
	var enemy := UnitBattleSnapshot.new()
	enemy.instance_id = &"e_0000000000000001"
	enemy.unit_id = &"unit.foe"
	enemy.side = &"enemy"
	enemy.logical_y = 5
	enemy.logical_x = 3
	enemy.star = 1
	enemy.health = 100
	enemy.attack = 10
	enemy.armor = 0
	enemy.magic_resist = 0
	enemy.attack_speed_milli = 1000
	enemy.attack_range_cells = 1
	enemy.start_mana = 0
	enemy.max_mana = 50
	enemy.move_speed_milli = 1000

	var encounter := EncounterPreviewSnapshot.new()
	encounter.preview_schema_version = 1
	encounter.encounter_id = &"encounter.test"
	encounter.manifest_digest = &"0000000000000000000000000000000000000000000000000000000000000000"
	encounter.enemy_units.append(enemy)

	var player := UnitBattleSnapshot.new()
	player.instance_id = &"u_0000000000000001"
	player.unit_id = &"unit.hero"
	player.side = &"player"
	player.logical_y = 2
	player.logical_x = 4
	player.star = 1
	player.health = 120
	player.attack = 12
	player.armor = 0
	player.magic_resist = 0
	player.attack_speed_milli = 1000
	player.attack_range_cells = 1
	player.start_mana = 0
	player.max_mana = 50
	player.move_speed_milli = 1000
	player.ability_id = OptionalStringNameValue.of(&"ability.test")

	var active_trait := TraitBattleSnapshot.new()
	active_trait.trait_id = &"trait.test"
	active_trait.tier = 1
	active_trait.member_instance_ids = [&"u_0000000000000001"]

	var parameter := BattleIntParam.new()
	parameter.key = &"amount"
	parameter.value = 5

	var equipment_effect := BattleEffectSnapshot.new()
	equipment_effect.priority = 0
	equipment_effect.source_stable_id = &"equipment.test"
	equipment_effect.source_instance_id = OptionalStringNameValue.of(&"it_0000000000000001")
	equipment_effect.effect_index = 0
	equipment_effect.effect_id = &"effect.test"
	equipment_effect.target_ids = [&"u_0000000000000001"]
	equipment_effect.integer_params.append(parameter)

	var inputs := BattleSetupInputs.new()
	inputs.setup_schema_version = 1
	inputs.content_version = "fixture.1"
	inputs.manifest_digest = &"0000000000000000000000000000000000000000000000000000000000000000"
	inputs.encounter_snapshot = encounter
	inputs.player_units.append(player)
	inputs.player_active_traits.append(active_trait)
	inputs.player_equipment_effects.append(equipment_effect)
	inputs.battle_rules = BattleRulesSnapshot.new()
	return inputs
