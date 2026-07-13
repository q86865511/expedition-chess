class_name EncounterPreviewSnapshot
extends RefCounted

var preview_schema_version: int = 1
var encounter_id: StringName = &""
var manifest_digest: StringName = &""
var enemy_units: Array[UnitBattleSnapshot] = []
var active_traits: Array[TraitBattleSnapshot] = []
var affix_effects: Array[BattleEffectSnapshot] = []
var boss_phases: Array[BossPhaseSnapshot] = []

func deep_clone() -> EncounterPreviewSnapshot:
	var copied := EncounterPreviewSnapshot.new()
	copied.preview_schema_version = preview_schema_version
	copied.encounter_id = encounter_id
	copied.manifest_digest = manifest_digest
	for unit: UnitBattleSnapshot in enemy_units:
		copied.enemy_units.append(unit.deep_clone())
	for trait_snapshot: TraitBattleSnapshot in active_traits:
		copied.active_traits.append(trait_snapshot.deep_clone())
	for effect: BattleEffectSnapshot in affix_effects:
		copied.affix_effects.append(effect.deep_clone())
	for phase: BossPhaseSnapshot in boss_phases:
		copied.boss_phases.append(phase.deep_clone())
	return copied
