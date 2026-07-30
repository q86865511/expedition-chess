class_name AccessibilitySemanticTokens
extends RefCounted

const _VALID_COLOR_MODES: Array[StringName] = [
	&"default",
	&"protanopia",
	&"deuteranopia",
	&"tritanopia",
]
const _VALID_DAMAGE_DENSITIES: Array[StringName] = [
	&"off",
	&"reduced",
	&"full",
]
const _SEMANTIC_CUES: Dictionary = {
	&"allegiance.enemy": {
		"icon_token": &"icon.allegiance.enemy",
		"pattern_token": &"pattern.allegiance.enemy",
		"text_key": &"accessibility.allegiance.enemy",
	},
	&"allegiance.ally": {
		"icon_token": &"icon.allegiance.ally",
		"pattern_token": &"pattern.allegiance.ally",
		"text_key": &"accessibility.allegiance.ally",
	},
	&"bond.active": {
		"icon_token": &"icon.bond.active",
		"pattern_token": &"pattern.bond.active",
		"text_key": &"accessibility.bond.active",
	},
	&"rarity.legendary": {
		"icon_token": &"icon.rarity.legendary",
		"pattern_token": &"pattern.rarity.legendary",
		"text_key": &"accessibility.rarity.legendary",
	},
	&"damage.arcane": {
		"icon_token": &"icon.damage.arcane",
		"pattern_token": &"pattern.damage.arcane",
		"text_key": &"accessibility.damage.arcane",
	},
	&"danger.lethal": {
		"icon_token": &"icon.danger.lethal",
		"pattern_token": &"pattern.danger.lethal",
		"text_key": &"accessibility.danger.lethal",
	},
}


func cue_for(color_mode: StringName, semantic: StringName) -> Dictionary:
	if color_mode not in _VALID_COLOR_MODES:
		return {}
	var cue: Variant = _SEMANTIC_CUES.get(semantic)
	if not cue is Dictionary:
		return {}
	var result: Dictionary = (cue as Dictionary).duplicate(true)
	result["color_mode"] = color_mode
	return result


func effects_for(snapshot: SettingsSnapshot) -> Dictionary:
	if snapshot == null:
		return {}
	var density: StringName = snapshot.damage_number_density
	if density not in _VALID_DAMAGE_DENSITIES:
		density = &"full"
	return {
		"motion_level": &"reduced" if snapshot.reduced_motion else &"full",
		"flash_level": &"reduced" if snapshot.reduced_flash else &"full",
		"particle_level": &"reduced" if snapshot.reduced_particles else &"full",
		"damage_number_density": density,
		"rule_information_visible": true,
	}


func tooltip_depth_allowed(depth: int) -> bool:
	return depth >= 0 and depth <= 2
