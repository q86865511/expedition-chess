class_name BattleRuleCatalog
extends RefCounted

var _manifest_digest: String
var _units: Array[BattleUnitRule] = []
var _traits: Array[BattleTraitRule] = []
var _abilities: Array[BattleAbilityRule] = []
var _effects: Array[BattleEffectRule] = []
var _encounters: Array[BattleEncounterRule] = []
var _equipment: Array[BattleEquipmentRule] = []
var _configs: Array[BattleCombatConfigRule] = []
var _relics: Array[BattleRelicRule] = []

func _init(
	manifest_digest: String,
	units: Array[BattleUnitRule],
	traits: Array[BattleTraitRule],
	abilities: Array[BattleAbilityRule],
	effects: Array[BattleEffectRule],
	encounters: Array[BattleEncounterRule],
	equipment: Array[BattleEquipmentRule],
	configs: Array[BattleCombatConfigRule],
	relics: Array[BattleRelicRule] = [] as Array[BattleRelicRule]
) -> void:
	_manifest_digest = manifest_digest
	for value: BattleUnitRule in units: _units.append(value.deep_clone())
	for value: BattleTraitRule in traits: _traits.append(value.deep_clone())
	for value: BattleAbilityRule in abilities: _abilities.append(value.deep_clone())
	for value: BattleEffectRule in effects: _effects.append(value.deep_clone())
	for value: BattleEncounterRule in encounters: _encounters.append(value.deep_clone())
	for value: BattleEquipmentRule in equipment: _equipment.append(value.deep_clone())
	for value: BattleCombatConfigRule in configs: _configs.append(value.deep_clone())
	for value: BattleRelicRule in relics: _relics.append(value.deep_clone())

func manifest_digest_value() -> String:
	return _manifest_digest

func unit_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []
	for value: BattleUnitRule in _units: result.append(value.unit_id)
	return result

func try_unit_rule(content_id: StringName) -> BattleUnitRule:
	for value: BattleUnitRule in _units:
		if value.unit_id == content_id: return value.deep_clone()
	return null

## 全 pinned 羈絆 id（比照 unit_ids_copy）。羈絆進度面板要列出「場上 0 隻」的 inactive 列，
## 必須能列舉 catalog 的全部 trait rule，而不只是 roster 命中的那些（IRH-REQ-013）。
func trait_ids_copy() -> Array[StringName]:
	var result: Array[StringName] = []
	for value: BattleTraitRule in _traits: result.append(value.trait_id)
	return result

func try_trait_rule(content_id: StringName) -> BattleTraitRule:
	for value: BattleTraitRule in _traits:
		if value.trait_id == content_id: return value.deep_clone()
	return null

func try_ability_rule(content_id: StringName) -> BattleAbilityRule:
	for value: BattleAbilityRule in _abilities:
		if value.ability_id == content_id: return value.deep_clone()
	return null

func try_effect_rule(content_id: StringName) -> BattleEffectRule:
	for value: BattleEffectRule in _effects:
		if value.effect_id == content_id: return value.deep_clone()
	return null

func try_encounter_rule(content_id: StringName) -> BattleEncounterRule:
	for value: BattleEncounterRule in _encounters:
		if value.encounter_id == content_id: return value.deep_clone()
	return null

func try_equipment_rule(content_id: StringName) -> BattleEquipmentRule:
	for value: BattleEquipmentRule in _equipment:
		if value.equipment_id == content_id: return value.deep_clone()
	return null

func try_combat_config_rule(content_id: StringName) -> BattleCombatConfigRule:
	for value: BattleCombatConfigRule in _configs:
		if value.config_id == content_id: return value.deep_clone()
	return null

func try_relic_rule(content_id: StringName) -> BattleRelicRule:
	for value: BattleRelicRule in _relics:
		if value.relic_id == content_id: return value.deep_clone()
	return null

func deep_clone() -> BattleRuleCatalog:
	return BattleRuleCatalog.new(
		_manifest_digest,
		_units,
		_traits,
		_abilities,
		_effects,
		_encounters,
		_equipment,
		_configs,
		_relics
	)
