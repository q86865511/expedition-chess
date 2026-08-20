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


func test_unit_names_remain_numbered_until_the_follow_up_naming_decision() -> void:
	var catalog := LocalizationCatalog.restricted_emergency_catalog()
	for index: int in range(12):
		_assert_copy(
			catalog,
			StringName("loc.unit_slice_monster_%02d" % index),
			"怪物 %02d" % (index + 1),
			"Monster %02d" % (index + 1)
		)
	for index: int in range(32):
		_assert_copy(
			catalog,
			StringName("loc.unit_slice_player_%02d" % index),
			"遠征棋士 %02d" % (index + 1),
			"Expedition Unit %02d" % (index + 1)
		)


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
