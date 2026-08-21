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

## design.md §4(:147-149):constructor 需要 loader-private seal,production 不得直接 new。
## GDScript 沒有真正的私有 constructor,這裡用「必填的 seal 參數」把封印做成呼叫端可驗:
## 漏傳＝參數不足的解析錯誤(舊的 `LocalizationCatalog.new()` 一律編不過),
## 傳錯＝空 catalog(resolve 全部 LOCALIZATION_KEY_MISSING,fail-closed 而不是靜默
## 回內建文案)。合法建構點只有兩個:`_from_validated_values`(LocalizationCatalogLoader
## 驗過的正式 CSV)與 `restricted_emergency_catalog`(design :150-152 的 boot/recovery 退路)。
const _CONSTRUCTOR_SEAL: StringName = &"localization_catalog.loader_private"

var _values: Dictionary = {
	&"zh_TW": {},
	&"en": {},
}


func _init(p_seal: StringName, p_validated_values: Dictionary) -> void:
	if p_seal != _CONSTRUCTOR_SEAL:
		push_error(
			"LocalizationCatalog must be built through its sealed factories"
		)
		return
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
	return LocalizationCatalog.new(_CONSTRUCTOR_SEAL, values)


## restricted factory(design :150-152):不接受任意 bytes／path,只從本檔內建的具名
## key 表建構,供「正式 catalog 尚未載入或載入失敗」的 boot／recovery／工具路徑使用。
## 正式遊玩畫面的文案來源是 localization/catalog.v2.csv——由 ProjectContentBootstrap
## 經 typed load result 驗證後注入 AppRoot(review N3),不再由本目錄提供。
static func restricted_emergency_catalog() -> LocalizationCatalog:
	return LocalizationCatalog.new(_CONSTRUCTOR_SEAL, {})


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
	_register(&"screen.menu_main.title", "遠征棋", "Expedition Chess")
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
	_register(&"system_menu.open", "選單", "Menu")
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
	# Phase D：production accessibility 不再持有第二份雙語值表。這些 key
	# 與所有 production UI 文案一起由 sealed catalog／CSV 單一來源供應。
	_register(
		&"accessibility.combat.rule_probe",
		"戰鬥規則：護盾破裂後，敵方會進入第二階段。",
		"Battle rule: after the shield breaks, the enemy enters phase two."
	)
	_register(
		&"accessibility.combat.state_summary",
		"動態：%s　閃光：%s　粒子：%s　傷害數字：%s",
		"Motion: %s  Flash: %s  Particles: %s  Damage numbers: %s"
	)
	_register(
		&"accessibility.combat.rule_information",
		"規則資訊會同時使用文字、圖示與圖樣提示。",
		"Rules use text, icons, and pattern cues together."
	)
	_register(
		&"accessibility.combat.pattern_cue",
		"[///] 傷害　[!] 危險",
		"[///] Damage  [!] Danger"
	)
	_register(&"accessibility.combat.motion", "動態效果", "Motion effects")
	_register(&"accessibility.combat.flash", "閃光效果", "Flash effects")
	_register(&"accessibility.combat.particles", "粒子效果", "Particle effects")
	_register(
		&"accessibility.combat.damage_event",
		"[傷害|%s] %s %d → %s",
		"[Damage|%s] %s %d -> %s"
	)
	_register(&"accessibility.combat.damage_sample_1", "[DMG] 128", "[DMG] 128")
	_register(&"accessibility.combat.damage_sample_2", "[DMG] 64", "[DMG] 64")
	_register(&"accessibility.combat.damage_sample_3", "[DMG] 32", "[DMG] 32")
	_register(&"accessibility.state.full", "完整", "Full")
	_register(&"accessibility.state.reduced", "減少", "Reduced")
	_register(&"accessibility.semantic.ally", "[A] 我方", "[A] Ally")
	_register(&"accessibility.semantic.enemy", "[E] 敵方", "[E] Enemy")
	_register(&"accessibility.semantic.trait", "[T] 特性", "[T] Trait")
	_register(&"accessibility.semantic.rarity", "[*] 稀有度", "[*] Rarity")
	_register(&"accessibility.semantic.danger", "[!] 危險", "[!] Danger")
	_register(&"accessibility.semantic.damage", "[DMG] 傷害", "[DMG] Damage")
	# AccessibilitySemanticTokens 原有 text_key 沒有獨立值來源；機械沿用同類
	# semantic cue 的既有字串，避免在這次 reseal 順手創作文案。
	_register(&"accessibility.allegiance.ally", "[A] 我方", "[A] Ally")
	_register(&"accessibility.allegiance.enemy", "[E] 敵方", "[E] Enemy")
	_register(&"accessibility.bond.active", "[T] 特性", "[T] Trait")
	_register(&"accessibility.rarity.legendary", "[*] 稀有度", "[*] Rarity")
	_register(&"accessibility.damage.arcane", "[DMG] 傷害", "[DMG] Damage")
	_register(&"accessibility.danger.lethal", "[!] 危險", "[!] Danger")
	_register(&"camp.collection", "圖鑑", "Collection")
	_register(&"camp.forge", "工坊", "Workshop")
	_register(&"camp.expedition_gate", "遠征之門", "Expedition Gate")
	_register(&"camp.commander_hall", "指揮官大廳", "Commander Hall")
	_register(&"camp.challenge_monument", "挑戰紀念碑", "Challenge Monument")
	_register(&"camp.commander_selector", "指揮官", "Commander")
	_register(&"camp.challenge_selector", "挑戰等級", "Challenge Level")
	_register(&"camp.panel.expedition", "遠征資訊", "Expedition")
	_register(&"camp.resource.currency", "工坊貨幣", "Workshop Currency")
	_register(&"camp.resource.challenge", "最高挑戰", "Highest Challenge")
	_register(&"camp.resource.discovered", "已發現", "Discovered")
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
	_register(&"prepare.action_group_selector", "備戰動作分類", "Prepare Action Category")
	_register(&"prepare.group.advance", "推進", "Advance")
	_register(&"prepare.group.forge_equipment", "鍛造裝備", "Forge and Equipment")
	_register(&"prepare.group.party", "隊伍調整", "Party Setup")
	_register(&"prepare.group.shop", "商店", "Shop")
	_register(&"prepare.panel.board", "戰場", "Board")
	_register(&"prepare.panel.bench", "備戰區", "Bench")
	_register(&"prepare.panel.expedition", "遠征資訊", "Expedition")
	_register(&"prepare.panel.inventory", "裝備庫", "Inventory")
	_register(&"prepare.panel.issues", "部署問題", "Deployment Issues")
	_register(&"prepare.panel.overflow", "待處理裝備", "Overflow")
	_register(&"prepare.panel.party", "隊伍", "Party")
	_register(&"prepare.panel.shop", "商店", "Shop")
	_register(&"prepare.panel.synergies", "羈絆", "Synergies")
	_register(&"prepare.panel.units", "單位", "Units")
	_register(
		&"prepare.empty.expedition",
		"目前沒有待處理的遠征事件",
		"No expedition event is pending."
	)
	_register(&"prepare.empty.issues", "目前沒有部署問題", "No deployment issue.")
	_register(&"prepare.empty.overflow", "目前沒有待處理裝備", "No equipment overflow.")
	_register(
		&"prepare.empty.synergies",
		"部署單位後顯示羈絆摘要",
		"Deploy units to show synergy details."
	)
	_register(&"prepare.resource.capacity", "人口", "Capacity")
	_register(&"prepare.resource.gold", "金幣", "Gold")
	_register(&"prepare.resource.hp", "遠征生命", "Expedition HP")
	_register(&"prepare.resource.level_xp", "等級／經驗", "Level / XP")
	# in-run-hud T14（IRH-REQ-011）：經濟資訊列多出來的三個欄位標籤與一個值 token。
	# 命名沿用同一條資源列的 prepare.resource.*（gold／level_xp 就在上面兩行），
	# 語意對應 ShopEconomySnapshot 的 win_streak／loss_streak／odds_*／at_max_level；
	# 各費率的百分比數字由呈現層直接格式化 basis points，不進 catalog。
	_register(&"prepare.resource.win_streak", "連勝", "Win Streak")
	_register(&"prepare.resource.loss_streak", "連敗", "Loss Streak")
	_register(&"prepare.resource.shop_odds", "費用機率", "Shop Odds")
	_register(&"prepare.resource.level_xp_max", "已達上限", "Max")
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
	_register(&"results.metric.currency_delta", "本次貨幣獎勵", "Expedition Currency Reward")
	_register(&"results.metric.profile_currency", "目前持有貨幣", "Current Currency")
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
	# in-run-hud T14（IRH-REQ-011）：商店報價停用原因的文案。來源是
	# ShopQuoteSnapshot.rejection_code／CommandApplyError 診斷 key `source_code`
	# 的 ShopError 具名碼（HANDOFF §2 第 6 條）。命名比照 SETTINGS_*→error.settings.*
	# 的既有映射：去掉與 key 前綴重複的 SHOP_ 後轉小寫，即 error.shop.<code>。
	# 只收玩家在報價／購買路徑撞得到的碼；RNG／KEY／DIGEST／CONFIG／SERIAL／MERGE
	# 六個是不變量失效（玩家無從處置、也分辨不出差異），共用 internal_failure 一句，
	# 比照 error.settings.activation_diagnostic 的既有作法。
	_register(&"error.shop.gold_insufficient", "金幣不足", "Not enough gold")
	_register(&"error.shop.level_max", "等級已達上限", "Level is already at maximum")
	_register(&"error.shop.offer_stale", "這筆報價已失效", "That offer is no longer available")
	_register(&"error.shop.roster_full", "隊伍已滿", "The party is full")
	_register(&"error.shop.unit_missing", "找不到指定棋子", "That unit could not be found")
	_register(
		&"error.shop.unit_rule_missing",
		"這個棋子無法交易",
		"That unit cannot be traded"
	)
	_register(
		&"error.shop.unit_pool_invalid",
		"棋子牌庫狀態不符",
		"The unit pool is out of sync"
	)
	_register(
		&"error.shop.reservation_invalid",
		"商店保留狀態已失效",
		"The shop reservation is no longer valid"
	)
	_register(
		&"error.shop.generation_mismatch",
		"內容版本不符，商店暫停",
		"Content version mismatch; the shop is unavailable"
	)
	_register(
		&"error.shop.input_invalid",
		"目前無法進行這項商店操作",
		"This shop action is not available right now"
	)
	_register(
		&"error.shop.internal_failure",
		"商店運算失敗，請稍後再試",
		"The shop could not complete this action"
	)
	_register(&"map.node_kind.normal", "一般戰鬥", "Battle")
	_register(&"map.node_kind.elite", "菁英戰鬥", "Elite Battle")
	_register(&"map.node_kind.merchant", "商人", "Merchant")
	_register(&"map.node_kind.event", "事件", "Event")
	_register(&"map.node_kind.rest", "休息", "Rest")
	_register(&"map.node_kind.treasure", "寶藏", "Treasure")
	_register(&"map.node_kind.boss", "首領", "Boss")
	# in-run-hud：進度列每個節點的狀態文字。以前 accessible copy 只有符號＋節點種類，
	# 讀屏使用者聽不出「這一格是走過的、現在的、還是還沒到的」。命名比照同族的
	# map.node_kind.*（值 token 直接對應 InRunHudShell 的 PROGRESS_STATE_* 常數）。
	_register(&"map.node_state.completed", "已完成", "Completed")
	_register(&"map.node_state.current", "目前所在", "Current")
	_register(&"map.node_state.unreached", "未到達", "Not Reached")
	_register(&"map.act.1.title", "第一幕", "Act I")
	_register(&"map.act.2.title", "第二幕", "Act II")
	_register(&"map.act.3.title", "第三幕", "Act III")
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
		&"error.presentation.equip_item_slots_full",
		"該單位的裝備欄位已滿",
		"That unit has no free equipment slot"
	)
	_register(
		&"error.presentation.prepare_start_not_ready",
		"隊伍尚未符合開戰條件",
		"The party is not ready to start combat"
	)
	_register(
		&"error.presentation.resolve_overflow_item_not_in_tray",
		"找不到待處理的溢出裝備",
		"The overflow equipment is no longer in the tray"
	)
	_register(
		&"error.presentation.run_command_failed",
		"遠征操作失敗，請檢查目前狀態後再試",
		"The expedition action failed; check the current state and try again"
	)
	_register(
		&"error.presentation.run_map_node_selection_unavailable",
		"目前沒有可前往的節點",
		"No selectable map node is available"
	)
	_register(
		&"error.presentation.run_transition_failed",
		"遠征狀態切換失敗",
		"The expedition state could not transition"
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
		&"error.presentation.expedition_challenge_prerequisite_unmet",
		"此指揮官尚未解鎖所選挑戰等級",
		"The selected challenge level is not unlocked for this commander."
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
		&"error.settings.activation_diagnostic",
		"設定已儲存，但部分介面未能立即更新；已重新載入已儲存設定",
		"Settings were saved, but part of the interface could not update immediately; the saved settings were reloaded"
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
	var monster_names: Array = [
		["根牙野豬", "Roottusk Boar"],
		["瓶花蟹", "Pitcher Crab"],
		["稜光母體", "Prism Matriarch"],
		["熔甲巨獸", "Lavashell Brute"],
		["冰冠梟皇", "Icequill Sovereign"],
		["闇燭蛞蝓", "Gloomwax Slug"],
		["廢鐵爐甲", "Scrapfurnace Beetle"],
		["弩臂螳螂", "Boltarm Mantis"],
		["晶燈洞蛾", "Lanternmoth"],
		["骨冠泥魁", "Bonecrown Brute"],
		["齒脊箭豬", "Gearspine Porcupine"],
		["星籠觸妖", "Starcage Horror"],
	]
	for index: int in range(monster_names.size()):
		_register_indexed("loc.effect_slice_event_gen_", index, "事件效果", "Event Effect")
		_register(
			StringName("loc.effect_slice_event_gen_%02d_description" % index),
			"事件節點的既有進入效果。",
			"Existing event-node entry effect."
		)
		_register_indexed("loc.map_node_slice_event_", index, "事件節點", "Event Node")
		_register(
			StringName("loc.unit_slice_monster_%02d" % index),
			String(monster_names[index][0]),
			String(monster_names[index][1])
		)
		_register_formal_unit_content(
			"slice_monster_%02d" % index,
			"怪物技能",
			"Monster Ability",
			32 + index * 3
		)
	var player_names: Array = [
		["晶苔衛", "Gemmoss Guard"],
		["燼藤弩", "Embervine Arbalist"],
		["冰焰使", "Frostfire Adept"],
		["霜鐵衛", "Frostiron Guard"],
		["齒輪客", "Chakram Tinker"],
		["幽燈守", "Gloamlight Warden"],
		["稜晶衛", "Facetshield"],
		["暮棘弓手", "Duskthorn Archer"],
		["窯環侍", "Kilnring Acolyte"],
		["雪履衛", "Snowshoe Guard"],
		["銅籌客", "Coinwheel Rogue"],
		["蝕鐘僧", "Eclipse Monk"],
		["星環衛", "Orrery Guard"],
		["菇冠吹手", "Sporepipe Scout"],
		["熔鏈先知", "Molten Oracle"],
		["冰甲水手", "Icecarapace Sailor"],
		["磁軌匠", "Lodestone Tinker"],
		["蛾燈葬士", "Mothlight Reaper"],
		["星圖重衛", "Starchart Bulwark"],
		["葦弓獵手", "Reedbow Hunter"],
		["爐扇舞者", "Furnace Dancer"],
		["海象盾衛", "Walrus Guard"],
		["發條信使", "Clockwork Courier"],
		["黑鏡守騎", "Blackmirror Knight"],
		["晶甲龜衛", "Crystal Tortoise"],
		["蜂巢獵手", "Hivebow Ranger"],
		["蝕霧術師", "Caustic Savant"],
		["寒潛重衛", "Frostdiver Guard"],
		["鋼索舞槍", "Wiregun Dancer"],
		["鴉獄典守", "Raven Gaoler"],
		["天碑巨像", "Runestone Colossus"],
		["冠林翔弓", "Canopy Windbow"],
	]
	for index: int in range(player_names.size()):
		_register(
			StringName("loc.unit_slice_player_%02d" % index),
			String(player_names[index][0]),
			String(player_names[index][1])
		)
		_register_formal_unit_content(
			"slice_player_%02d" % index,
			"棋士技能",
			"Unit Ability",
			48 + index * 2
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
		(
			[
				"秘法同調",
				"餘燼之盟",
				"凜霜之裔",
				"鐵誓同盟",
				"暮影之裔",
				"翠蔭之盟",
			][ELEMENTS.find(token)]
			if family == "faction"
			else ["神射手", "秘術師", "哨衛", "詭術師", "先鋒", "守望者"][ROLES.find(token)]
		),
		_title(token)
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
	# difficulty-curve T04：trait 門檻階梯化新增的 tier2/tier3 分段 effect loc key
	# （命名對齊 localization/catalog.v2.csv 的 _t2/_t3 慣例）。
	for tier_suffix: Array in [
		["t2", "二階", "Tier 2", "tier-2"],
		["t3", "三階", "Tier 3", "tier-3"],
	]:
		_register(
			StringName("loc.effect_trait_%s_%s_%s" % [family, token, tier_suffix[0]]),
			"%s效果：%s（%s）" % [zh_family, _title(token), tier_suffix[1]],
			"%s Effect: %s (%s)" % [en_family, _title(token), tier_suffix[2]]
		)
		_register(
			StringName(
				"loc.effect_trait_%s_%s_%s_description" % [family, token, tier_suffix[0]]
			),
			"%s「%s」的%s正式階段效果。" % [zh_family, _title(token), tier_suffix[1]],
			"Formal %s effect for %s %s." % [
				tier_suffix[3], en_family.to_lower(), _title(token),
			]
		)


func _register_formal_unit_content(
	token: String,
	zh_ability: String,
	en_ability: String,
	damage_base: int
) -> void:
	_register(
		StringName("loc.ability_" + token),
		"%s：%s" % [zh_ability, _title(token)],
		"%s: %s" % [en_ability, _title(token)]
	)
	_register(
		StringName("loc.ability_%s_description" % token),
		"對目前目標造成「自身攻擊力＋%d」點物理傷害。" % damage_base,
		"Deals physical damage equal to this unit's Attack + %d to the current target."
		% damage_base
	)
	_register(
		StringName("loc.effect_%s_primary" % token),
		"對目前目標造成「自身攻擊力＋%d」點物理傷害。" % damage_base,
		"Deals physical damage equal to this unit's Attack + %d to the current target."
		% damage_base
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
