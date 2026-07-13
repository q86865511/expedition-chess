class_name ContentCategory
extends RefCounted

const UNIT := 0x1001
const TRAIT := 0x1002
const ABILITY := 0x1003
const EFFECT := 0x1004
const ITEM_COMPONENT := 0x1005
const EQUIPMENT := 0x1006
const CONSUMABLE := 0x1007
const RELIC := 0x1008
const COMMANDER := 0x1009
const ENCOUNTER := 0x100a
const REWARD_TABLE := 0x100b
const MAP_NODE := 0x100c
const UNLOCK := 0x100d
const ECONOMY_CONFIG := 0x100e
const META_REWARD_TABLE := 0x100f

static func code_for_name(value: StringName) -> int:
	match value:
		&"unit": return UNIT
		&"trait": return TRAIT
		&"ability": return ABILITY
		&"effect": return EFFECT
		&"item_component": return ITEM_COMPONENT
		&"equipment": return EQUIPMENT
		&"consumable": return CONSUMABLE
		&"relic": return RELIC
		&"commander": return COMMANDER
		&"encounter": return ENCOUNTER
		&"reward_table": return REWARD_TABLE
		&"map_node": return MAP_NODE
		&"unlock": return UNLOCK
		&"economy_config": return ECONOMY_CONFIG
		&"meta_reward_table": return META_REWARD_TABLE
	return 0

static func name_for_code(value: int) -> StringName:
	match value:
		UNIT: return &"unit"
		TRAIT: return &"trait"
		ABILITY: return &"ability"
		EFFECT: return &"effect"
		ITEM_COMPONENT: return &"item_component"
		EQUIPMENT: return &"equipment"
		CONSUMABLE: return &"consumable"
		RELIC: return &"relic"
		COMMANDER: return &"commander"
		ENCOUNTER: return &"encounter"
		REWARD_TABLE: return &"reward_table"
		MAP_NODE: return &"map_node"
		UNLOCK: return &"unlock"
		ECONOMY_CONFIG: return &"economy_config"
		META_REWARD_TABLE: return &"meta_reward_table"
	return &""
