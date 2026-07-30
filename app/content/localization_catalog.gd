class_name LocalizationCatalog
extends RefCounted

const DEFAULT_LOCALE: StringName = &"zh_TW"
const SUPPORTED_LOCALES: Array[StringName] = [&"zh_TW", &"en"]

const ELEMENTS: Array[String] = [
	"arcane", "ember", "frost", "iron", "shadow", "verdant",
]
const ROLES: Array[String] = [
	"marksman", "mystic", "sentinel", "trickster", "vanguard", "warden",
]
const RELICS: Array[String] = [
	"arbiter_seal", "ember_ward", "emberheart_pact", "frost_edge",
	"frostbound_oath", "golden_ledger", "interest_token", "iron_will",
	"merchant_seal", "pathfinder_boots", "scout_lantern", "shadow_veil",
	"thrifty_charm", "tide_compass", "verdant_accord", "wanderer_map",
]

var _values: Dictionary = {
	&"zh_TW": {},
	&"en": {},
}


func _init() -> void:
	_register_fixed_keys()
	_register_generated_keys()


func default_locale() -> StringName:
	return DEFAULT_LOCALE


func supported_locales() -> Array[StringName]:
	return SUPPORTED_LOCALES.duplicate()


func keys_for_locale(locale: StringName) -> Array[StringName]:
	if not _values.has(locale):
		return []
	var result: Array[StringName] = []
	for key: Variant in (_values[locale] as Dictionary).keys():
		result.append(StringName(key))
	result.sort_custom(_name_less)
	return result


func resolve(locale: StringName, key: StringName) -> LocalizationResolveResult:
	if not _values.has(locale):
		return LocalizationResolveResult.failure(&"UNSUPPORTED_LOCALE")
	var locale_values := _values[locale] as Dictionary
	if not locale_values.has(key):
		return LocalizationResolveResult.failure(&"LOCALIZATION_KEY_MISSING")
	return LocalizationResolveResult.success(String(locale_values[key]))


func _register_fixed_keys() -> void:
	_register(&"screen.menu_main.title", "遠征主選單", "Expedition Menu")
	_register(&"screen.settings.title", "設定", "Settings")
	_register(&"screen.camp_world.title", "遠征營地", "Expedition Camp")
	_register(&"screen.facility_expedition_gate.title", "遠征之門", "Expedition Gate")
	_register(&"screen.facility_commander_hall.title", "指揮官大廳", "Commander Hall")
	_register(&"screen.collection.title", "圖鑑", "Collection")
	_register(&"screen.facility_unlock_workshop.title", "解鎖工坊", "Unlock Workshop")
	_register(&"screen.facility_challenge_monument.title", "挑戰紀念碑", "Challenge Monument")
	_register(&"screen.run_container.title", "遠征", "Expedition")
	_register(&"screen.run_map.title", "遠征地圖", "Expedition Map")
	_register(&"screen.run_prepare.title", "備戰", "Prepare")
	_register(&"screen.run_combat.title", "戰鬥", "Combat")
	_register(&"screen.run_reward.title", "獎勵", "Reward")
	_register(&"screen.results.title", "遠征結算", "Results")
	_register(&"screen.results_fallback.title", "結算顯示修復", "Results Recovery")
	_register(&"menu.continue", "繼續遠征", "Continue")
	_register(&"menu.start", "開始", "Start")
	_register(&"menu.settings", "設定", "Settings")
	_register(&"menu.exit", "離開", "Exit")
	_register(&"menu.recovery", "處理保留遠征", "Recover Saved Run")
	_register(&"menu.recovery.status", "是否棄置無法載入的遠征？", "Discard the unloadable run?")
	_register(&"menu.recovery.confirm", "確認棄置", "Confirm Discard")
	_register(&"menu.recovery.cancel", "取消", "Cancel")
	_register(&"settings.apply", "套用", "Apply")
	_register(&"settings.back", "返回", "Back")
	_register(&"settings.field.locale", "語言", "Language")
	_register(&"settings.field.ui_scale_percent", "介面縮放", "UI Scale")
	_register(&"settings.field.color_vision_mode", "色覺模式", "Color Vision Mode")
	_register(&"settings.field.reduced_motion", "減少動態效果", "Reduced Motion")
	_register(&"settings.field.reduced_flash", "減少閃光", "Reduced Flash")
	_register(&"settings.field.reduced_particles", "減少粒子", "Reduced Particles")
	_register(&"settings.field.damage_number_density", "傷害數字密度", "Damage Number Density")
	_register(&"settings.field.master_volume", "主音量", "Master Volume")
	_register(&"settings.field.master_mute", "主音量靜音", "Mute Master")
	_register(&"settings.field.music_volume", "音樂音量", "Music Volume")
	_register(&"settings.field.music_mute", "音樂靜音", "Mute Music")
	_register(&"settings.field.sfx_volume", "音效音量", "SFX Volume")
	_register(&"settings.field.sfx_mute", "音效靜音", "Mute SFX")
	_register(&"settings.field.ui_volume", "介面音效音量", "UI Volume")
	_register(&"settings.field.ui_mute", "介面音效靜音", "Mute UI")
	_register(&"settings.value.locale.zh_TW", "繁體中文（台灣）", "Traditional Chinese (Taiwan)")
	_register(&"settings.value.locale.en", "英文", "English")
	_register(&"settings.value.ui_scale_percent.100", "100%", "100%")
	_register(&"settings.value.ui_scale_percent.125", "125%", "125%")
	_register(&"settings.value.ui_scale_percent.150", "150%", "150%")
	_register(&"settings.value.color_vision_mode.default", "預設", "Default")
	_register(&"settings.value.color_vision_mode.protanopia", "紅色辨識輔助", "Protanopia")
	_register(&"settings.value.color_vision_mode.deuteranopia", "綠色辨識輔助", "Deuteranopia")
	_register(&"settings.value.color_vision_mode.tritanopia", "藍色辨識輔助", "Tritanopia")
	_register(&"settings.value.damage_number_density.off", "關閉", "Off")
	_register(&"settings.value.damage_number_density.reduced", "減少", "Reduced")
	_register(&"settings.value.damage_number_density.full", "完整", "Full")
	_register(&"camp.collection", "圖鑑", "Collection")
	_register(&"camp.forge", "工坊", "Workshop")
	_register(&"camp.expedition_gate", "遠征之門", "Expedition Gate")
	_register(&"camp.commander_hall", "指揮官大廳", "Commander Hall")
	_register(&"camp.challenge_monument", "挑戰紀念碑", "Challenge Monument")
	_register(&"run.retry_route", "重試畫面", "Retry Screen")
	_register(&"camp.settings", "設定", "Settings")
	_register(&"camp.start", "開始遠征", "Start Expedition")
	_register(&"camp.menu", "返回主選單", "Main Menu")
	_register(&"camp.back", "返回營地", "Back to Camp")
	_register(&"map.select", "選擇節點", "Select Node")
	_register(&"map.confirm", "確認前進", "Confirm Route")
	_register(&"prepare.unit", "調整隊伍", "Manage Party")
	_register(&"prepare.refresh", "重新整理商店", "Refresh Shop")
	_register(&"prepare.buy", "購買所選單位", "Buy Selected Unit")
	_register(&"prepare.xp", "購買經驗值", "Buy XP")
	_register(&"prepare.sell", "出售所選單位", "Sell Selected Unit")
	_register(&"prepare.forge", "鍛造所選物品", "Forge Selected Items")
	_register(&"prepare.forge.confirm", "確認鍛造", "Confirm Forge")
	_register(&"prepare.forge.cancel", "取消鍛造", "Cancel Forge")
	_register(&"prepare.equip", "裝備所選物品", "Equip Selected Item")
	_register(&"prepare.dismantle", "拆解所選裝備", "Dismantle Selected Equipment")
	_register(&"prepare.move_board", "移至戰場", "Move to Board")
	_register(&"prepare.move_bench", "移至備戰區", "Move to Bench")
	_register(&"prepare.start", "開始戰鬥", "Start Combat")
	_register(&"combat.pause", "暫停", "Pause")
	_register(&"combat.inspect", "檢視單位", "Inspect Unit")
	_register(&"combat.speed", "戰鬥速度", "Battle Speed")
	_register(&"reward.select", "選擇獎勵", "Select Reward")
	_register(&"reward.confirm", "確認獎勵", "Confirm Reward")
	_register(&"run.menu", "返回主選單", "Main Menu")
	_register(&"results.retry", "重試顯示", "Retry Display")
	_register(&"results.camp", "返回營地", "Return to Camp")
	_register(&"results.menu", "返回主選單", "Return to Menu")
	_register(&"collection.category.content", "內容", "Content")
	_register(&"collection.category.recipe", "配方", "Recipes")
	_register(&"collection.category.glossary", "規則辭典", "Glossary")
	_register(&"collection.compare.empty", "選擇兩個項目進行比較", "Select two entries to compare")
	_register(&"collection.compare.ready", "請選擇比較項目", "Select an entry to compare")
	_register(&"collection.compare.format", "%s 與 %s", "%s vs %s")
	_register(
		&"error.collection_category_not_comparable",
		"此分類不支援比較",
		"This category cannot be compared"
	)
	_register(
		&"error.collection_entry_not_found",
		"找不到收藏項目",
		"Collection entry not found"
	)
	_register(&"results.outcome.completed", "遠征完成", "Expedition Completed")
	_register(&"results.outcome.failed", "遠征失敗", "Expedition Failed")
	_register(&"results.outcome.abandoned", "已放棄遠征", "Expedition Abandoned")
	_register(&"results.outcome.unknown", "未知結果", "Unknown Outcome")
	_register(
		&"error.presentation.prepare_selection_required",
		"請先選擇有效項目",
		"Select a valid item first"
	)
	_register(
		&"error.presentation.prepare_board_full",
		"戰場沒有可用位置",
		"No board cell is available"
	)
	_register(
		&"error.presentation.prepare_bench_full",
		"備戰區已滿",
		"The bench is full"
	)
	_register(&"loc.config_combat_default", "預設戰鬥規則", "Default Combat Rules")
	_register(&"loc.consumable_dismantle_kit", "拆卸工具", "Dismantle Kit")
	_register(&"loc.economy_slice_default", "預設遠征經濟", "Default Expedition Economy")
	_register(&"loc.meta_reward_table_slice_default", "預設局外獎勵", "Default Meta Rewards")
	_register(&"loc.reward_table_slice_relic", "遺物獎勵", "Relic Rewards")
	_register(&"loc.reward_table_slice_standard", "標準獎勵", "Standard Rewards")
	_register(&"loc.map_node_slice_boss", "首領節點", "Boss Node")
	_register(&"loc.map_node_slice_elite", "菁英節點", "Elite Node")
	_register(&"loc.map_node_slice_merchant", "商人節點", "Merchant Node")
	_register(&"loc.map_node_slice_normal", "一般戰鬥", "Battle Node")
	_register(&"loc.map_node_slice_rest", "休息節點", "Rest Node")
	_register(&"loc.map_node_slice_treasure", "寶藏節點", "Treasure Node")
	_register(&"loc.encounter_slice_boss_0", "第一幕首領", "Act I Boss")
	_register(&"loc.encounter_slice_boss_1", "第二幕首領", "Act II Boss")
	_register(&"loc.encounter_slice_boss_2", "第三幕首領", "Act III Boss")
	_register(&"loc.encounter_slice_elite", "菁英遭遇", "Elite Encounter")
	_register(&"loc.encounter_slice_normal", "一般遭遇", "Normal Encounter")
	_register(&"loc.unlock_slice_base_profile", "基礎解鎖", "Base Unlocks")


func _register_generated_keys() -> void:
	for index: int in range(3):
		_register(
			StringName("loc.commander_slice_c%d" % index),
			"指揮官 %d" % (index + 1),
			"Commander %d" % (index + 1)
		)
	for index: int in range(6):
		_register_indexed("loc.effect_slice_affix_", index, "菁英詞綴", "Elite Affix")
	for index: int in range(5):
		_register_indexed(
			"loc.effect_slice_challenge_affix_", index, "挑戰詞綴", "Challenge Affix"
		)
	for index: int in range(3):
		var suffix := "" if index == 0 else "_%02d" % index
		_register(
			StringName("loc.effect_slice_commander_passive" + suffix),
			"指揮官被動 %02d" % (index + 1),
			"Commander Passive %02d" % (index + 1)
		)
	for index: int in range(12):
		_register_indexed("loc.effect_slice_event_gen_", index, "事件效果", "Event Effect")
		_register_indexed("loc.map_node_slice_event_", index, "事件節點", "Event Node")
		_register_indexed("loc.unit_slice_monster_", index, "怪物", "Monster")
	for index: int in range(32):
		_register_indexed("loc.unit_slice_player_", index, "遠征棋士", "Expedition Unit")
	for index: int in range(6):
		_register(
			StringName("loc.unlock_slice_challenge_%d" % index),
			"挑戰解鎖 %d" % (index + 1),
			"Challenge Unlock %d" % (index + 1)
		)
	for index: int in range(6):
		var element := ELEMENTS[index]
		_register_named_family(element, "faction", "陣營", "Faction")
		_register(
			StringName("loc.effect_equip_" + element),
			"裝備效果：%s" % _title(element),
			"Equipment Effect: %s" % _title(element)
		)
	for role: String in ROLES:
		_register_named_family(role, "role", "職業", "Role")
	for relic: String in RELICS:
		_register(
			StringName("loc.relic_" + relic),
			"遺物：%s" % _title(relic),
			"Relic: %s" % _title(relic)
		)
		_register(
			StringName("loc.effect_relic_" + relic),
			"遺物效果：%s" % _title(relic),
			"Relic Effect: %s" % _title(relic)
		)
	for left: int in range(ELEMENTS.size()):
		for right: int in range(left, ELEMENTS.size()):
			var pair := "%s_%s" % [ELEMENTS[left], ELEMENTS[right]]
			_register(
				StringName("loc.equipment_" + pair),
				"裝備：%s" % _title(pair),
				"Equipment: %s" % _title(pair)
			)
	var component_keys := {
		"arcane": "arcane_dust",
		"ember": "ember_shard",
		"frost": "frost_core",
		"iron": "iron_plate",
		"shadow": "shadow_thread",
		"verdant": "verdant_leaf",
	}
	for element: String in ELEMENTS:
		var component := String(component_keys[element])
		_register(
			StringName("loc.item_component_" + component),
			"零件：%s" % _title(component),
			"Component: %s" % _title(component)
		)


func _register_named_family(
	token: String,
	family: String,
	zh_family: String,
	en_family: String
) -> void:
	var key := StringName("loc.trait_%s_%s" % [family, token])
	_register(
		key,
		"%s：%s" % [zh_family, _title(token)],
		"%s: %s" % [en_family, _title(token)]
	)
	_register(
		StringName(String(key) + "_description"),
		"啟用%s「%s」的階段效果。" % [zh_family, _title(token)],
		"Activates tier effects for %s %s." % [en_family.to_lower(), _title(token)]
	)
	_register(
		StringName("loc.effect_trait_%s_%s" % [family, token]),
		"%s效果：%s" % [zh_family, _title(token)],
		"%s Effect: %s" % [en_family, _title(token)]
	)


func _register_indexed(
	prefix: String,
	index: int,
	zh_label: String,
	en_label: String
) -> void:
	var number := "%02d" % index
	_register(
		StringName(prefix + number),
		"%s %02d" % [zh_label, index + 1],
		"%s %02d" % [en_label, index + 1]
	)


func _register(key: StringName, zh_tw: String, en: String) -> void:
	(_values[&"zh_TW"] as Dictionary)[key] = zh_tw
	(_values[&"en"] as Dictionary)[key] = en


func _title(token: String) -> String:
	return token.replace("_", " ").capitalize()


func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
