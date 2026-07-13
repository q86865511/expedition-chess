class_name BattleSetupInputs
extends RefCounted

var setup_schema_version: int = 1
var content_version: String = ""
var manifest_digest: StringName = &""
var encounter_snapshot: EncounterPreviewSnapshot = null
var player_units: Array[UnitBattleSnapshot] = []
var player_active_traits: Array[TraitBattleSnapshot] = []
var player_equipment_effects: Array[BattleEffectSnapshot] = []
var player_relic_effects: Array[BattleEffectSnapshot] = []
var commander_effects: Array[BattleEffectSnapshot] = []
var challenge_modifiers: Array[BattleEffectSnapshot] = []
var battle_rules: BattleRulesSnapshot = null

func deep_clone() -> BattleSetupInputs:
	var copied := BattleSetupInputs.new()
	copied.setup_schema_version = setup_schema_version
	copied.content_version = content_version
	copied.manifest_digest = manifest_digest
	copied.encounter_snapshot = encounter_snapshot.deep_clone() if encounter_snapshot != null else null
	for unit: UnitBattleSnapshot in player_units:
		copied.player_units.append(unit.deep_clone())
	for trait_snapshot: TraitBattleSnapshot in player_active_traits:
		copied.player_active_traits.append(trait_snapshot.deep_clone())
	for effect: BattleEffectSnapshot in player_equipment_effects:
		copied.player_equipment_effects.append(effect.deep_clone())
	for effect: BattleEffectSnapshot in player_relic_effects:
		copied.player_relic_effects.append(effect.deep_clone())
	for effect: BattleEffectSnapshot in commander_effects:
		copied.commander_effects.append(effect.deep_clone())
	for effect: BattleEffectSnapshot in challenge_modifiers:
		copied.challenge_modifiers.append(effect.deep_clone())
	copied.battle_rules = battle_rules.deep_clone() if battle_rules != null else null
	return copied
