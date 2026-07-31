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


func _init(p_validated_values: Dictionary = {}) -> void:
	if p_validated_values.is_empty():
		_register_fixed_keys()
		_register_generated_keys()
	else:
		_values = {
			&"zh_TW": (p_validated_values.get(&"zh_TW", {}) as Dictionary).duplicate(true),
			&"en": (p_validated_values.get(&"en", {}) as Dictionary).duplicate(true),
		}


# loader-private factory(design §L10N):production 只能經 LocalizationCatalogLoader
static func _from_validated_values(values: Dictionary) -> LocalizationCatalog:
	return LocalizationCatalog.new(values)


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
	_register(&"screen.run_route_fallback.title", "路線顯示修復", "Route Recovery")
	_register(&"screen.results.title", "遠征結算", "Results")
	_register(&"screen.results_fallback.title", "結算顯示修復", "Results Recovery")
	_register(&"screen.app_route_fallback.title", "畫面修復", "Screen Recovery")
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
	_register(&"app.retry_route", "重新載入畫面", "Reload Screen")
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
	_register(&"service.dismantle", "拆解所選裝備（節點服務）", "Dismantle Selected Equipment (Node Service)")
	_register(&"service.exit", "離開節點服務", "Exit Node Service")
	_register(&"prepare.move_board", "移至戰場", "Move to Board")
	_register(&"prepare.move_bench", "移至備戰區", "Move to Bench")
	_register(&"prepare.start", "開始戰鬥", "Start Combat")
	_register(&"choice.begin", "確認所選事件", "Confirm Selected Choice")
	_register(&"choice.confirm", "確認選擇", "Confirm Choice")
	_register(&"choice.cancel", "取消選擇", "Cancel Choice")
	_register(&"choice.ack", "確認事件結果", "Acknowledge Choice Result")
	_register(&"tooltip.cost", "花費", "Cost")
	_register(&"tooltip.star", "星級", "Star")
	_register(&"tooltip.reward_amount", "獎勵數量", "Reward Amount")
	_register(&"tooltip.collection_order", "圖鑑順序", "Collection Order")
	_register(&"combat.pause", "暫停", "Pause")
	_register(&"combat.inspect", "檢視單位", "Inspect Unit")
	_register(&"combat.speed", "戰鬥速度", "Battle Speed")
	_register(&"combat.inspection.none", "無", "None")
	_register(&"combat.stat.star", "星級", "Star")
	_register(&"combat.stat.health", "生命", "Health")
	_register(&"combat.stat.attack", "攻擊", "Attack")
	_register(&"combat.stat.armor", "護甲", "Armor")
	_register(&"combat.stat.magic_resist", "魔抗", "Magic Resist")
	_register(&"combat.stat.attack_speed_milli", "攻速（千分比）", "Attack Speed (milli)")
	_register(&"combat.stat.attack_range_cells", "攻擊距離（格）", "Attack Range (cells)")
	_register(&"combat.stat.start_mana", "初始法力", "Starting Mana")
	_register(&"combat.stat.max_mana", "法力上限", "Max Mana")
	_register(&"combat.stat.move_speed_milli", "移速（千分比）", "Move Speed (milli)")
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
	# wave2-B
	_register(&"error.board.bench_empty_slot", "備戰區有空位未填", "Bench has an empty slot")
	_register(&"error.board.bench_too_large", "備戰區超過上限", "Bench exceeds capacity")
	_register(&"error.board.board_cell_overlap", "棋盤格重疊", "Board cells overlap")
	_register(
		&"error.board.board_out_of_bounds",
		"棋子超出棋盤範圍",
		"Unit is out of board bounds"
	)
	_register(
		&"error.board.board_over_capacity",
		"戰場超出人口上限",
		"Board exceeds population capacity"
	)
	_register(
		&"error.board.board_physical_limit",
		"棋盤超出實體格數上限",
		"Board exceeds physical cell limit"
	)
	_register(&"error.board.board_request_invalid", "佈局請求無效", "Layout request is invalid")
	_register(
		&"error.board.board_unit_duplicate",
		"同一單位重複佈署",
		"A unit is deployed more than once"
	)
	_register(
		&"error.board.board_unit_reference_missing",
		"找不到對應單位",
		"Referenced unit could not be found"
	)
	_register(
		&"error.board.board_unit_unassigned",
		"有單位未分配位置",
		"A unit has not been assigned a position"
	)
	_register(
		&"error.board.board_wrong_half",
		"單位佈署在錯誤半場",
		"Unit is deployed on the wrong half"
	)
	_register(
		&"error.board.population_invalid",
		"人口上限數值無效",
		"Population capacity value is invalid"
	)
	_register(&"map.node_kind.normal", "一般戰鬥", "Battle")
	_register(&"map.node_kind.elite", "菁英戰鬥", "Elite Battle")
	_register(&"map.node_kind.merchant", "商人", "Merchant")
	_register(&"map.node_kind.event", "事件", "Event")
	_register(&"map.node_kind.rest", "休息", "Rest")
	_register(&"map.node_kind.treasure", "寶藏", "Treasure")
	_register(&"map.node_kind.boss", "首領", "Boss")
	# wave2-C
	_register(
		&"error.status.pre_commit",
		"操作未生效（尚未變更，可重試）：",
		"Action did not apply (nothing changed, retry): "
	)
	_register(
		&"error.status.post_commit",
		"已生效但畫面未更新（顯示已回退）：",
		"Applied, but the screen fell back: "
	)
	_register(&"error.presentation.failure", "操作失敗", "The action failed")
	_register(&"error.presentation.app_action", "操作失敗", "The action failed")
	_register(
		&"error.presentation.action_not_available",
		"目前無法執行這個操作",
		"That action is not available right now"
	)
	_register(
		&"error.presentation.screen_not_active",
		"畫面尚未啟用，請稍候再試",
		"The screen is not active yet"
	)
	_register(
		&"error.presentation.camp_selection_required",
		"請先選擇指揮官與挑戰等級",
		"Select a commander and challenge level first"
	)
	_register(
		&"error.presentation.retained_run_exists",
		"已有保留的遠征，請先處理",
		"A saved run is still retained"
	)
	_register(
		&"error.presentation.prepared_run_stale",
		"遠征存檔已過期，請重新載入",
		"The saved run is stale; reload it"
	)
	_register(
		&"error.presentation.exit_already_pending",
		"離開請求已在處理中",
		"An exit request is already pending"
	)
	_register(
		&"error.presentation.results_action_in_progress",
		"結算操作進行中",
		"A results action is already running"
	)
	_register(
		&"error.presentation.route_prepare_invalid",
		"無法準備下一個畫面",
		"The next screen could not be prepared"
	)
	_register(
		&"error.presentation.route_commit_failed",
		"畫面切換失敗",
		"The screen could not be switched"
	)
	_register(
		&"error.presentation.route_bind_failed",
		"畫面繫結失敗",
		"The screen could not be bound"
	)
	_register(
		&"error.presentation.scene_bind_failed",
		"場景繫結失敗",
		"The scene could not be bound"
	)
	_register(&"error.presentation.render_failed", "畫面繪製失敗", "Rendering failed")
	_register(
		&"error.presentation.run_session_unavailable",
		"目前沒有可用的遠征",
		"No expedition session is available"
	)
	_register(
		&"error.presentation.start_postcommit",
		"遠征已開始，但畫面未能切換",
		"The run started, but the screen could not follow"
	)
	_register(
		&"error.presentation.recovery_postcommit",
		"保留遠征已處理，但畫面未能更新",
		"The retained run was handled, but the screen could not follow"
	)
	_register(
		&"error.presentation.results_fallback",
		"結算畫面已退回備援顯示",
		"Results fell back to the recovery screen"
	)
	_register(
		&"error.presentation.run_route_fallback",
		"遠征畫面已退回備援顯示",
		"The run screen fell back to the recovery screen"
	)
	_register(
		&"error.presentation.terminal_handoff",
		"結算交接失敗",
		"The results handoff failed"
	)
	_register(
		&"error.presentation.save_unavailable",
		"存檔無法讀取",
		"The save file could not be read"
	)
	_register(
		&"error.presentation.run_unavailable",
		"遠征資料無法讀取",
		"The run data could not be read"
	)
	_register(
		&"error.presentation.run_recovery",
		"有一個無法載入的遠征待處理",
		"A run that cannot be loaded is waiting"
	)
	_register(
		&"error.presentation.run_incompatible",
		"保留的遠征與目前版本不相容",
		"The retained run is incompatible with this version"
	)
	_register(&"error.save.io_failure", "存檔寫入失敗", "Saving failed")
	_register(
		&"error.settings.apply_failed",
		"設定套用失敗",
		"The settings could not be applied"
	)
	_register(&"error.settings.draft_invalid", "設定草稿無效", "The settings draft is invalid")
	_register(&"error.settings.invalid_enum", "設定選項無效", "That setting option is invalid")
	_register(
		&"error.settings.field_out_of_range",
		"設定數值超出範圍",
		"That setting value is out of range"
	)
	_register(
		&"error.settings.runtime_missing",
		"設定執行環境未就緒",
		"The settings runtime is not ready"
	)
	_register(
		&"error.settings.rebuild_failed",
		"設定重建失敗",
		"The settings could not be rebuilt"
	)
	_register(
		&"error.settings.port_invalid",
		"設定通道無效",
		"The settings port is invalid"
	)
	_register(
		&"error.settings.application_invalid_result",
		"設定套用回應無效",
		"The settings application returned an invalid result"
	)
	_register(
		&"error.settings.application_failed",
		"設定套用失敗",
		"The settings could not be applied"
	)
	_register(
		&"run.menu.status",
		"遠征仍在進行中，確定要返回主選單？",
		"The expedition is still in progress. Return to the main menu?"
	)
	_register(&"run.menu.confirm", "確認返回", "Confirm")
	_register(&"run.menu.cancel", "繼續遠征", "Keep Playing")
	_register(&"menu.exit.status", "確定要離開遊戲？", "Exit the game?")
	_register(&"menu.exit.confirm", "確認離開", "Confirm Exit")
	_register(&"menu.exit.cancel", "取消", "Cancel")


func _register_generated_keys() -> void:
	for index: int in range(3):
		_register(
			StringName("loc.commander_slice_c%d" % index),
			"指揮官 %d" % (index + 1),
			"Commander %d" % (index + 1)
		)
	for index: int in range(6):
		_register_indexed("loc.effect_slice_affix_", index, "菁英詞綴", "Elite Affix")
		_register(
			StringName("loc.effect_slice_affix_%02d_description" % index),
			"戰鬥開始時套用的菁英效果。",
			"Elite effect applied at battle start."
		)
	for index: int in range(5):
		_register_indexed(
			"loc.effect_slice_challenge_affix_", index, "挑戰詞綴", "Challenge Affix"
		)
		_register(
			StringName("loc.effect_slice_challenge_affix_%02d_description" % index),
			"挑戰等級提供的遠征規則效果。",
			"Expedition rule effect supplied by challenge level."
		)
	for index: int in range(3):
		var suffix := "" if index == 0 else "_%02d" % index
		_register(
			StringName("loc.effect_slice_commander_passive" + suffix),
			"指揮官被動 %02d" % (index + 1),
			"Commander Passive %02d" % (index + 1)
		)
		_register(
			StringName("loc.effect_slice_commander_passive%s_description" % suffix),
			"指揮官的固定被動效果。",
			"Commander's persistent passive effect."
		)
	for index: int in range(12):
		_register_indexed("loc.effect_slice_event_gen_", index, "事件效果", "Event Effect")
		_register(
			StringName("loc.effect_slice_event_gen_%02d_description" % index),
			"事件節點的既有進入效果。",
			"Existing event-node entry effect."
		)
		_register_indexed("loc.map_node_slice_event_", index, "事件節點", "Event Node")
		_register_indexed("loc.unit_slice_monster_", index, "怪物", "Monster")
		_register_formal_unit_content(
			"slice_monster_%02d" % index, "怪物技能", "Monster Ability"
		)
	for index: int in range(32):
		_register_indexed("loc.unit_slice_player_", index, "遠征棋士", "Expedition Unit")
		_register_formal_unit_content(
			"slice_player_%02d" % index, "棋士技能", "Unit Ability"
		)
	for index: int in range(12):
		var event_suffix := "%02d" % index
		_register(
			StringName("loc.choice_set_event_" + event_suffix),
			"事件抉擇 %02d" % (index + 1),
			"Event Choice %02d" % (index + 1)
		)
		_register_event_choice(event_suffix, "safe", "穩健處理", "Safe Approach")
		_register_event_choice(event_suffix, "risk", "承擔風險", "Take the Risk")
	_register_choice_set_keys()
	var formal_audio_names: Array = [
		["menu", "主選單音樂", "Menu Music"],
		["camp", "營地音樂", "Camp Music"],
		["expedition", "遠征音樂", "Expedition Music"],
		["combat", "戰鬥音樂", "Combat Music"],
		["results", "結算音樂", "Results Music"],
		["ui_confirm", "介面確認", "UI Confirm"],
		["ui_cancel", "介面取消", "UI Cancel"],
		["ui_focus", "介面聚焦", "UI Focus"],
		["ui_error", "介面錯誤", "UI Error"],
		["shop_buy", "商店購買", "Shop Buy"],
		["shop_sell", "商店出售", "Shop Sell"],
		["shop_refresh", "商店刷新", "Shop Refresh"],
		["forge", "鍛造", "Forge"],
		["equip", "裝備", "Equip"],
		["reward_select", "獎勵選擇", "Reward Select"],
		["event_select", "事件選擇", "Event Select"],
		["combat_cast", "技能施放", "Combat Cast"],
		["combat_melee_hit", "近戰命中", "Melee Hit"],
		["combat_defeat", "戰敗", "Combat Defeat"],
		["combat_shield", "護盾格擋", "Shield Block"],
		["combat_heal", "戰鬥治療", "Combat Heal"],
		["combat_death", "戰鬥倒下", "Combat Death"],
		["combat_ranged_attack", "遠程攻擊", "Ranged Attack"],
		["combat_magic_hit", "法術命中", "Magic Hit"],
		["combat_boss_warning", "Boss 警示", "Boss Warning"],
		["combat_victory", "戰鬥勝利", "Combat Victory"],
	]
	for audio_name: Array in formal_audio_names:
		_register(
			StringName("loc.audio_" + String(audio_name[0])),
			String(audio_name[1]),
			String(audio_name[2])
		)
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
		_register(
			StringName("loc.effect_equip_%s_description" % element),
			"由裝備提供的戰鬥效果。",
			"Battle effect granted by equipment."
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
		_register(
			StringName("loc.effect_relic_%s_description" % relic),
			"由遺物提供的正式效果。",
			"Formal effect granted by this relic."
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
	_register(
		StringName("loc.effect_trait_%s_%s_description" % [family, token]),
		"%s「%s」的正式階段效果。" % [zh_family, _title(token)],
		"Formal tier effect for %s %s."
		% [en_family.to_lower(), _title(token)]
	)


func _register_formal_unit_content(
	token: String,
	zh_ability: String,
	en_ability: String
) -> void:
	_register(
		StringName("loc.ability_" + token),
		"%s：%s" % [zh_ability, _title(token)],
		"%s: %s" % [en_ability, _title(token)]
	)
	_register(
		StringName("loc.ability_%s_description" % token),
		"對主要敵人造成依攻擊力計算的傷害。",
		"Deals attack-scaled damage to the primary enemy."
	)
	_register(
		StringName("loc.effect_%s_primary" % token),
		"%s的主要技能效果" % _title(token),
		"%s Primary Ability Effect" % _title(token)
	)
	_register(
		StringName("loc.effect_%s_primary_description" % token),
		"此數值為功能用暫定基線，尚未進行平衡調校。",
		"This value is a functional provisional baseline and is not TUNE-balanced."
	)
	_register(
		StringName("loc.presentation_" + token),
		"%s的正式呈現" % _title(token),
		"%s Presentation" % _title(token)
	)


func _register_event_choice(
	suffix: String,
	choice_token: String,
	zh_title: String,
	en_title: String
) -> void:
	var prefix := "loc.choice_event_%s_%s_" % [suffix, choice_token]
	_register(StringName(prefix + "title"), zh_title, en_title)
	_register(
		StringName(prefix + "description"),
		"選擇一個有明確代價與結果的事件方案。",
		"Choose an event approach with an explicit cost and outcome."
	)
	_register(
		StringName(prefix + "preview"),
		"確認前可預覽金幣與遠征生命變化。",
		"Preview gold and expedition HP changes before confirming."
	)
	_register(
		StringName(prefix + "result"),
		"事件選擇已套用。",
		"Event choice applied."
	)


func _register_choice_set_keys() -> void:
	_register(&"loc.choice_set_rest", "休息點服務", "Rest Services")
	_register(&"loc.choice_set_treasure", "寶藏抉擇", "Treasure Choice")
	var choices: Array = [
		["rest_heal_20", "治療 20%", "Heal 20%", "恢復 20% 遠征生命。", "Restore 20% expedition HP."],
		["rest_dismantle", "拆解服務", "Dismantle Service", "開啟既有拆解服務。", "Open the existing dismantle service."],
		["treasure_standard", "標準寶箱", "Standard Cache", "進入標準獎勵流程。", "Open the standard reward flow."],
		["treasure_relic", "遺物寶箱", "Relic Cache", "進入遺物獎勵流程。", "Open the relic reward flow."],
		["treasure_gold", "金幣寶箱", "Gold Cache", "立即取得固定金幣。", "Gain a fixed amount of gold immediately."],
	]
	for value: Array in choices:
		var prefix := "loc.choice_%s_" % String(value[0])
		_register(StringName(prefix + "title"), String(value[1]), String(value[2]))
		_register(StringName(prefix + "description"), String(value[3]), String(value[4]))
		_register(StringName(prefix + "preview"), String(value[3]), String(value[4]))
		_register(StringName(prefix + "result"), "選擇已套用。", "Choice applied.")


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
