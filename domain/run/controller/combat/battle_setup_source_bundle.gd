class_name BattleSetupSourceBundle
extends RefCounted

var manifest_digest: String
var player_units: Array[UnitBattleSnapshot] = []
var player_active_traits: Array[TraitBattleSnapshot] = []
var player_equipment_effects: Array[BattleEffectSnapshot] = []
var player_relic_effects: Array[BattleEffectSnapshot] = []
var commander_effects: Array[BattleEffectSnapshot] = []
var challenge_modifiers: Array[BattleEffectSnapshot] = []
var unit_sources_resolved: bool
var trait_sources_resolved: bool
var equipment_sources_resolved: bool
var relic_sources_resolved: bool
var commander_sources_resolved: bool
var challenge_sources_resolved: bool

func _init(
	p_manifest_digest: String,
	p_player_units: Array[UnitBattleSnapshot],
	p_player_active_traits: Array[TraitBattleSnapshot],
	p_player_equipment_effects: Array[BattleEffectSnapshot],
	p_player_relic_effects: Array[BattleEffectSnapshot],
	p_commander_effects: Array[BattleEffectSnapshot],
	p_challenge_modifiers: Array[BattleEffectSnapshot],
	p_unit_sources_resolved: bool = false,
	p_trait_sources_resolved: bool = false,
	p_equipment_sources_resolved: bool = false,
	p_relic_sources_resolved: bool = false,
	p_commander_sources_resolved: bool = false,
	p_challenge_sources_resolved: bool = false
) -> void:
	manifest_digest = p_manifest_digest
	for unit: UnitBattleSnapshot in p_player_units:
		player_units.append(unit.deep_clone() if unit != null else null)
	for trait_snapshot: TraitBattleSnapshot in p_player_active_traits:
		player_active_traits.append(
			trait_snapshot.deep_clone() if trait_snapshot != null else null
		)
	_append_effect_copies(player_equipment_effects, p_player_equipment_effects)
	_append_effect_copies(player_relic_effects, p_player_relic_effects)
	_append_effect_copies(commander_effects, p_commander_effects)
	_append_effect_copies(challenge_modifiers, p_challenge_modifiers)
	unit_sources_resolved = p_unit_sources_resolved
	trait_sources_resolved = p_trait_sources_resolved
	equipment_sources_resolved = p_equipment_sources_resolved
	relic_sources_resolved = p_relic_sources_resolved
	commander_sources_resolved = p_commander_sources_resolved
	challenge_sources_resolved = p_challenge_sources_resolved

func all_sources_resolved() -> bool:
	return unit_sources_resolved \
		and trait_sources_resolved \
		and equipment_sources_resolved \
		and relic_sources_resolved \
		and commander_sources_resolved \
		and challenge_sources_resolved

func deep_clone() -> BattleSetupSourceBundle:
	return BattleSetupSourceBundle.new(
		manifest_digest,
		player_units,
		player_active_traits,
		player_equipment_effects,
		player_relic_effects,
		commander_effects,
		challenge_modifiers,
		unit_sources_resolved,
		trait_sources_resolved,
		equipment_sources_resolved,
		relic_sources_resolved,
		commander_sources_resolved,
		challenge_sources_resolved
	)

func _append_effect_copies(
	target: Array[BattleEffectSnapshot],
	source: Array[BattleEffectSnapshot]
) -> void:
	for effect: BattleEffectSnapshot in source:
		target.append(effect.deep_clone() if effect != null else null)
