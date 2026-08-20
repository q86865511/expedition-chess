class_name ProductionAccessibilityLocalization
extends RefCounted

const COMBAT_RULE_KEY: StringName = &"accessibility.combat.rule_probe"
const SUMMARY_KEY: StringName = &"accessibility.combat.state_summary"
const RULE_INFORMATION_KEY: StringName = &"accessibility.combat.rule_information"
const PATTERN_CUE_KEY: StringName = &"accessibility.combat.pattern_cue"
const MOTION_KEY: StringName = &"accessibility.combat.motion"
const FLASH_KEY: StringName = &"accessibility.combat.flash"
const PARTICLES_KEY: StringName = &"accessibility.combat.particles"
const DAMAGE_EVENT_KEY: StringName = &"accessibility.combat.damage_event"
const DAMAGE_SAMPLE_KEYS: Array[StringName] = [
	&"accessibility.combat.damage_sample_1",
	&"accessibility.combat.damage_sample_2",
	&"accessibility.combat.damage_sample_3",
]
const STATE_FULL_KEY: StringName = &"accessibility.state.full"
const STATE_REDUCED_KEY: StringName = &"accessibility.state.reduced"
const SEMANTIC_KEYS: Dictionary = {
	&"ally": &"accessibility.semantic.ally",
	&"enemy": &"accessibility.semantic.enemy",
	&"trait": &"accessibility.semantic.trait",
	&"rarity": &"accessibility.semantic.rarity",
	&"danger": &"accessibility.semantic.danger",
	&"damage": &"accessibility.semantic.damage",
}

var _catalog: LocalizationCatalog


func _init(catalog: LocalizationCatalog = null) -> void:
	bind_catalog(catalog)


func bind_catalog(catalog: LocalizationCatalog) -> void:
	_catalog = (
		catalog
		if catalog != null
		else LocalizationCatalog.restricted_emergency_catalog()
	)


func resolve(locale: StringName, key: StringName) -> String:
	var resolved := _catalog.resolve(locale, key)
	return resolved.value if resolved.ok else ""


func semantic(locale: StringName, semantic: StringName) -> String:
	var key: Variant = SEMANTIC_KEYS.get(semantic)
	return resolve(locale, StringName(key)) if key != null else ""
