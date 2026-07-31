extends GutTest

## T07 (specs/meta-progression) — 挑戰詞綴內容著作：五條新 EffectDef
## effect.slice_challenge_affix_00..04（content_role=challenge_affix、四類全覆蓋、loc key），
## 重指 content/packs/vertical_slice/unlocks/slice_challenge_1..5.tres 的 modifier_refs（現指向
## content_role=elite_affix 的 slice_affix_00..04 佔位）。菁英詞綴與其被 treasure/rest/merchant
## generator_ref 複用之處、map nodes 一律不動。
## Covers：S5-AC-010；design.md §7.1（"新著作 5 條 challenge 詞綴...重指
## unlocks/slice_challenge_1..5.tres 的 modifier_refs...不動菁英詞綴與其被 treasure/rest/
## merchant generator 複用之處、不動 map nodes"）；tasks.md T07 驗收「五條
## effect.slice_challenge_affix_00..04...重指 slice_challenge_1..5 modifier_refs...菁英詞綴/
## map nodes 不動；Ch0 無詞綴」。
##
## 內容斷言策略（依派工簡報二擇一）：本檔選擇「載入正式 pack 後檢查」——直接從磁碟讀取
## content/packs/vertical_slice（＋ content/packs/build_systems，validator 的最小計數規則
## 需要兩包合併才成立，同 tests/unit/content_validation/test_vertical_slice_content_pack.gd
## 既有慣例）並對真實 .tres 內容斷言，不使用 SyntheticContentFixture 合成表達——因為本檔的
## 目的就是驗證「真的著作了」這件事本身，合成內容無法覆蓋這個目標。
##
## 假設聲明：
## 1. 五條新效果 id 與 challenge_level 的對應關係比照現行 slice_affix_00..04 的既有映射
##    （unlock.slice_challenge_N 的 modifier_refs 現指向 effect.slice_affix_(N-1)，見
##    content/packs/vertical_slice/unlocks/slice_challenge_1..5.tres 逐檔核對）：
##      slice_challenge_1 -> effect.slice_challenge_affix_00
##      slice_challenge_2 -> effect.slice_challenge_affix_01
##      slice_challenge_3 -> effect.slice_challenge_affix_02
##      slice_challenge_4 -> effect.slice_challenge_affix_03
##      slice_challenge_5 -> effect.slice_challenge_affix_04
## 2. 四類覆蓋判準與 tests/unit/content_validation/test_challenge_affix_operation_validation.gd
##    的假設聲明第 2 點完全一致（3 個可機械判別的桶：battle_operations 非空／
##    operation_type()==0x3109／operation_type()==0x310A），此處對「五條效果聯集」驗證同一
##    件事，不重複展開理由。
## 3. 不得變動的既有內容（本檔逐項迴歸斷言，任一項改變都視為違反 design 的「不得動」約束）：
##      effect.slice_affix_00..04 的 content_role 仍是 &"elite_affix"；
##      map_node.slice_treasure.generator_ref 仍是 &"choice_set.treasure"；
##      map_node.slice_merchant.generator_ref 仍是 &"effect.slice_affix_02"；
##      map_node.slice_rest.generator_ref     仍是 &"choice_set.rest"。
##    （treasure／rest 的 generator_ref 已由本分支改指向 NodeChoiceSetDef，不再直接指向
##    elite_affix 效果；merchant 未變動，仍直接指向 effect.slice_affix_02。此三個
##    generator_ref 現值於本次同步前實測核對，見本檔 header 對應常數。）

const VERTICAL_SLICE_ROOT := "res://content/packs/vertical_slice"
const BUILD_SYSTEMS_ROOT := "res://content/packs/build_systems"

const EXPECTED_CHALLENGE_AFFIX_IDS := [
	&"effect.slice_challenge_affix_00",
	&"effect.slice_challenge_affix_01",
	&"effect.slice_challenge_affix_02",
	&"effect.slice_challenge_affix_03",
	&"effect.slice_challenge_affix_04",
]

# 派工前實測值（不得被 T07 變動——見 design.md §7.1「不動菁英詞綴與其被 treasure/rest/
# merchant generator 複用之處」）。
const UNCHANGED_TREASURE_GENERATOR := &"choice_set.treasure"
const UNCHANGED_MERCHANT_GENERATOR := &"effect.slice_affix_02"
const UNCHANGED_REST_GENERATOR := &"choice_set.rest"


func test_challenge_unlocks_1_to_5_are_repointed_to_new_challenge_affix_effects() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	for level in range(1, 6):
		var unlock := _find(pack, StringName("unlock.slice_challenge_%d" % level)) as UnlockDef
		assert_not_null(unlock, "缺少 unlock.slice_challenge_%d" % level)
		if unlock == null:
			continue
		assert_eq(
			unlock.modifier_refs, [EXPECTED_CHALLENGE_AFFIX_IDS[level - 1]],
			"unlock.slice_challenge_%d.modifier_refs 必須重指到 %s" % [level, EXPECTED_CHALLENGE_AFFIX_IDS[level - 1]]
		)


func test_challenge_unlock_0_still_has_no_modifiers() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	var unlock := _find(pack, &"unlock.slice_challenge_0") as UnlockDef
	assert_not_null(unlock)
	if unlock == null:
		return
	assert_eq(unlock.modifier_refs, [] as Array[StringName], "Challenge 0 無詞綴")


func test_five_challenge_affix_effects_exist_with_challenge_affix_content_role_and_localization() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	for effect_id: StringName in EXPECTED_CHALLENGE_AFFIX_IDS:
		var effect := _find(pack, effect_id) as EffectDef
		assert_not_null(effect, "缺少 %s" % effect_id)
		if effect == null:
			continue
		assert_eq(effect.content_role, &"challenge_affix", "%s.content_role 必須是 challenge_affix（非 elite_affix）" % effect_id)
		assert_false(effect.display_name_key.is_empty(), "%s 缺 loc key" % effect_id)


func test_five_challenge_affix_effects_collectively_cover_all_three_mechanical_buckets() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	var has_battle_track := false
	var has_shop_surcharge := false
	var has_drain_expedition_hp := false
	for effect_id: StringName in EXPECTED_CHALLENGE_AFFIX_IDS:
		var effect := _find(pack, effect_id) as EffectDef
		if effect == null:
			continue
		if not effect.battle_operations.is_empty():
			has_battle_track = true
		for operation: RunOperationDef in effect.run_operations:
			if operation == null:
				continue
			if operation.operation_type() == 0x3109:
				has_shop_surcharge = true
			elif operation.operation_type() == 0x310A:
				has_drain_expedition_hp = true
	assert_true(has_battle_track, "五條效果聯集必須至少一條有非空 battle_operations（軌 A：敵人編成/遭遇規則）")
	assert_true(has_shop_surcharge, "五條效果聯集必須至少一條含 ShopSurchargeOperationDef（經濟壓力）")
	assert_true(has_drain_expedition_hp, "五條效果聯集必須至少一條含 DrainExpeditionHpOperationDef（遠征傷害）")


func test_elite_affix_effects_are_unchanged() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	for index in range(5):
		var effect_id := StringName("effect.slice_affix_%02d" % index)
		var effect := _find(pack, effect_id) as EffectDef
		assert_not_null(effect, "%s 不得被移除" % effect_id)
		if effect == null:
			continue
		assert_eq(effect.content_role, &"elite_affix", "%s 不得被重新分類" % effect_id)


func test_treasure_rest_merchant_generator_refs_are_unchanged() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	var treasure := _find(pack, &"map_node.slice_treasure") as MapNodeDef
	var merchant := _find(pack, &"map_node.slice_merchant") as MapNodeDef
	var rest := _find(pack, &"map_node.slice_rest") as MapNodeDef
	assert_not_null(treasure)
	assert_not_null(merchant)
	assert_not_null(rest)
	if treasure != null:
		assert_eq(treasure.generator_ref, UNCHANGED_TREASURE_GENERATOR)
	if merchant != null:
		assert_eq(merchant.generator_ref, UNCHANGED_MERCHANT_GENERATOR)
	if rest != null:
		assert_eq(rest.generator_ref, UNCHANGED_REST_GENERATOR)


func test_combined_pack_still_installs_validated_with_zero_issues() -> void:
	var build_systems_pack := _load_pack(BUILD_SYSTEMS_ROOT)
	var vertical_slice_pack := _load_pack(VERTICAL_SLICE_ROOT)
	var combined: Array[ContentDefinition] = []
	combined.append_array(build_systems_pack)
	combined.append_array(vertical_slice_pack)

	var dependency_port := FakeContentDependencyPort.new()
	var input := ContentValidationInput.new(combined, [], [], dependency_port, 9)

	var report := ContentValidator.new().validate(input)
	assert_true(report.valid, _issue_text(report))
	if not report.valid:
		return

	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var pack_ids: Array[StringName] = [&"pack.build_systems", &"pack.vertical_slice"]
	var result := registry.install_validated(input, "0.1.0-vertical-slice-t07", pack_ids)
	assert_true(result.ok, "install_validated 失敗: %s field=%s" % [
		result.error.code if not result.ok else "", result.error.field_path if not result.ok else "",
	])


func _load_pack(root: String) -> Array[ContentDefinition]:
	var result: Array[ContentDefinition] = []
	_load_dir(root, result)
	return result


func _load_dir(path: String, result: Array[ContentDefinition]) -> void:
	var dir := DirAccess.open(path)
	assert_not_null(dir, "無法開啟目錄: %s" % path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full_path := "%s/%s" % [path, entry]
			if dir.current_is_dir():
				_load_dir(full_path, result)
			elif entry.ends_with(".tres"):
				var resource := load(full_path)
				assert_true(resource is ContentDefinition, "非預期的資源型別: %s" % full_path)
				if resource is ContentDefinition:
					result.append(resource)
		entry = dir.get_next()
	dir.list_dir_end()


func _find(definitions: Array[ContentDefinition], content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in definitions:
		if definition.id == content_id:
			return definition
	return null


func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)
