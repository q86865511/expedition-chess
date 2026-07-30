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
const _VALUES: Dictionary = {
	&"zh_TW": {
		COMBAT_RULE_KEY: "戰鬥規則：護盾破裂後，敵方會進入第二階段。",
		SUMMARY_KEY: "動態：%s　閃光：%s　粒子：%s　傷害數字：%s",
		RULE_INFORMATION_KEY: "規則資訊會同時使用文字、圖示與圖樣提示。",
		PATTERN_CUE_KEY: "[///] 傷害　[!] 危險",
		MOTION_KEY: "動態效果",
		FLASH_KEY: "閃光效果",
		PARTICLES_KEY: "粒子效果",
		DAMAGE_EVENT_KEY: "[傷害|%s] %s %d → %s",
		DAMAGE_SAMPLE_KEYS[0]: "[DMG] 128",
		DAMAGE_SAMPLE_KEYS[1]: "[DMG] 64",
		DAMAGE_SAMPLE_KEYS[2]: "[DMG] 32",
		STATE_FULL_KEY: "完整",
		STATE_REDUCED_KEY: "減少",
		SEMANTIC_KEYS[&"ally"]: "[A] 我方",
		SEMANTIC_KEYS[&"enemy"]: "[E] 敵方",
		SEMANTIC_KEYS[&"trait"]: "[T] 特性",
		SEMANTIC_KEYS[&"rarity"]: "[*] 稀有度",
		SEMANTIC_KEYS[&"danger"]: "[!] 危險",
		SEMANTIC_KEYS[&"damage"]: "[DMG] 傷害",
	},
	&"en": {
		COMBAT_RULE_KEY: (
			"Battle rule: after the shield breaks, the enemy enters phase two."
		),
		SUMMARY_KEY: "Motion: %s  Flash: %s  Particles: %s  Damage numbers: %s",
		RULE_INFORMATION_KEY: "Rules use text, icons, and pattern cues together.",
		PATTERN_CUE_KEY: "[///] Damage  [!] Danger",
		MOTION_KEY: "Motion effects",
		FLASH_KEY: "Flash effects",
		PARTICLES_KEY: "Particle effects",
		DAMAGE_EVENT_KEY: "[Damage|%s] %s %d -> %s",
		DAMAGE_SAMPLE_KEYS[0]: "[DMG] 128",
		DAMAGE_SAMPLE_KEYS[1]: "[DMG] 64",
		DAMAGE_SAMPLE_KEYS[2]: "[DMG] 32",
		STATE_FULL_KEY: "Full",
		STATE_REDUCED_KEY: "Reduced",
		SEMANTIC_KEYS[&"ally"]: "[A] Ally",
		SEMANTIC_KEYS[&"enemy"]: "[E] Enemy",
		SEMANTIC_KEYS[&"trait"]: "[T] Trait",
		SEMANTIC_KEYS[&"rarity"]: "[*] Rarity",
		SEMANTIC_KEYS[&"danger"]: "[!] Danger",
		SEMANTIC_KEYS[&"damage"]: "[DMG] Damage",
	},
}


func resolve(locale: StringName, key: StringName) -> String:
	var values: Variant = _VALUES.get(locale)
	if not values is Dictionary:
		return ""
	return String((values as Dictionary).get(key, ""))


func semantic(locale: StringName, semantic: StringName) -> String:
	var key: Variant = SEMANTIC_KEYS.get(semantic)
	return resolve(locale, StringName(key)) if key != null else ""
