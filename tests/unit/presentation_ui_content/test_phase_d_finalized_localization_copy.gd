extends GutTest

const FACTION_ZH := {
	&"arcane": "秘法同調",
	&"ember": "餘燼之盟",
	&"frost": "凜霜之裔",
	&"iron": "鐵誓同盟",
	&"shadow": "暮影之裔",
	&"verdant": "翠蔭之盟",
}
const FACTION_EN := {
	&"arcane": "Arcane",
	&"ember": "Ember",
	&"frost": "Frost",
	&"iron": "Iron",
	&"shadow": "Shadow",
	&"verdant": "Verdant",
}
const ROLE_ZH := {
	&"marksman": "神射手",
	&"mystic": "秘術師",
	&"sentinel": "哨衛",
	&"trickster": "詭術師",
	&"vanguard": "先鋒",
	&"warden": "守望者",
}
const ROLE_EN := {
	&"marksman": "Marksman",
	&"mystic": "Mystic",
	&"sentinel": "Sentinel",
	&"trickster": "Trickster",
	&"vanguard": "Vanguard",
	&"warden": "Warden",
}
const MONSTER_NAMES: Array[Array] = [
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
const PLAYER_NAMES: Array[Array] = [
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


func test_finalized_trait_display_copy_matches_phase_d_decision() -> void:
	var catalog := LocalizationCatalog.restricted_emergency_catalog()
	for token: StringName in FACTION_ZH:
		var key := StringName("loc.trait_faction_%s" % token)
		_assert_copy(catalog, key, FACTION_ZH[token], FACTION_EN[token])
	for token: StringName in ROLE_ZH:
		var key := StringName("loc.trait_role_%s" % token)
		_assert_copy(catalog, key, ROLE_ZH[token], ROLE_EN[token])


func test_all_44_ability_descriptions_match_approved_effect_values() -> void:
	var catalog := LocalizationCatalog.restricted_emergency_catalog()
	for index: int in range(12):
		_assert_ability_description(catalog, "monster", index, 32 + index * 3)
	for index: int in range(32):
		_assert_ability_description(catalog, "player", index, 48 + index * 2)


func test_phase_e_unit_names_match_the_approved_naming_decision() -> void:
	var catalog := LocalizationCatalog.restricted_emergency_catalog()
	for index: int in range(MONSTER_NAMES.size()):
		_assert_copy(
			catalog,
			StringName("loc.unit_slice_monster_%02d" % index),
			String(MONSTER_NAMES[index][0]),
			String(MONSTER_NAMES[index][1])
		)
	for index: int in range(PLAYER_NAMES.size()):
		_assert_copy(
			catalog,
			StringName("loc.unit_slice_player_%02d" % index),
			String(PLAYER_NAMES[index][0]),
			String(PLAYER_NAMES[index][1])
		)
	_assert_copy(catalog, &"screen.menu_main.title", "遠征棋", "Expedition Chess")


func _assert_ability_description(
	catalog: LocalizationCatalog,
	kind: String,
	index: int,
	damage_base: int
) -> void:
	var zh_tw := "對目前目標造成「自身攻擊力＋%d」點物理傷害。" % damage_base
	var en := (
		"Deals physical damage equal to this unit's Attack + %d to the current target."
		% damage_base
	)
	_assert_copy(
		catalog,
		StringName("loc.ability_slice_%s_%02d_description" % [kind, index]),
		zh_tw,
		en
	)
	# RUN_COMBAT 的 status inspection 目前消費 effect display key；同步同一份
	# 已核可 copy，避免 canonical description 已定稿但產品仍顯示舊佔位名。
	_assert_copy(
		catalog,
		StringName("loc.effect_slice_%s_%02d_primary" % [kind, index]),
		zh_tw,
		en
	)


func _assert_copy(
	catalog: LocalizationCatalog,
	key: StringName,
	zh_tw: String,
	en: String
) -> void:
	var zh_result := catalog.resolve(&"zh_TW", key)
	var en_result := catalog.resolve(&"en", key)
	assert_true(zh_result.ok, "%s must resolve in zh_TW" % key)
	assert_true(en_result.ok, "%s must resolve in en" % key)
	if zh_result.ok:
		assert_eq(zh_result.value, zh_tw, "%s zh_TW" % key)
	if en_result.ok:
		assert_eq(en_result.value, en, "%s en" % key)
