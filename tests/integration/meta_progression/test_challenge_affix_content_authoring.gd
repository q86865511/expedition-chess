extends GutTest

## Phase 0 / BP-SI-001 → Phase 1 / G2 difficulty-curve T06（DC-REQ-006，BP-SI-001 已解除，
## 見 specs/balance-playtest/spec-issues.md）：五條 challenge EffectDef 保留 authoring 與
## localization；T06 回鏈 level 1/2/4/5（affix_00/01/03/04），level 3（affix_02，
## BP-SI-002 續 OPEN）仍不掛 modifier_refs。菁英詞綴、treasure/rest/merchant generator_ref
## 與 map nodes 一律不動。
## Covers：S5-AC-010／DC-REQ-006；design.md §7.1、specs/difficulty-curve/design.md「決定性與
## 失敗政策」；tasks.md T07/T06 驗收。
##
## 內容斷言策略（依派工簡報二擇一）：本檔選擇「載入正式 pack 後檢查」——直接從磁碟讀取
## content/packs/vertical_slice（＋ content/packs/build_systems，validator 的最小計數規則
## 需要兩包合併才成立，同 tests/unit/content_validation/test_vertical_slice_content_pack.gd
## 既有慣例）並對真實 .tres 內容斷言，不使用 SyntheticContentFixture 合成表達——因為本檔的
## 目的就是驗證「真的著作了」這件事本身，合成內容無法覆蓋這個目標。
##
## 假設聲明（T06 更新）：
## 1. 現行掛載為 level 1 -> affix_00（battle）、level 2 -> affix_01（ShopSurcharge run
##    track）、level 3 -> 空（BP-SI-002 續 OPEN，affix_02 維持未連線）、
##    level 4 -> affix_03（DrainExpeditionHp run track）、level 5 -> affix_04（battle）。
## 2. affix_00/04 只有 battle_operations；affix_01/03 只有 run_operations（純 run track，
##    design §7.2／combat-core/design.md:117/:236 已釐清此類效果不進 BattleSetup，
##    不受 challenge global source 的 RunOperation 禁令限制）。
## 3. 不得變動的既有內容（本檔逐項迴歸斷言）：
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


func test_only_current_battle_challenge_layers_reference_affix_effects() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	var expected_by_level := {
		1: [EXPECTED_CHALLENGE_AFFIX_IDS[0]] as Array[StringName],
		2: [EXPECTED_CHALLENGE_AFFIX_IDS[1]] as Array[StringName],
		3: [] as Array[StringName],
		4: [EXPECTED_CHALLENGE_AFFIX_IDS[3]] as Array[StringName],
		5: [EXPECTED_CHALLENGE_AFFIX_IDS[4]] as Array[StringName],
	}
	for level in range(1, 6):
		var unlock := _find(pack, StringName("unlock.slice_challenge_%d" % level)) as UnlockDef
		assert_not_null(unlock, "缺少 unlock.slice_challenge_%d" % level)
		if unlock == null:
			continue
		assert_eq(
			unlock.modifier_refs,
			expected_by_level[level],
			"T06 回鏈後只允許 level 1/2/4/5 掛載對應 affix；level 3（affix_02，BP-SI-002 續 OPEN）維持空"
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


func test_currently_referenced_challenge_affixes_are_battle_only() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	var referenced_ids: Array[StringName] = []
	for level in range(1, 6):
		var unlock := _find(pack, StringName("unlock.slice_challenge_%d" % level)) as UnlockDef
		if unlock != null:
			referenced_ids.append_array(unlock.modifier_refs)
	var battle_track_ids: Array[StringName] = [
		EXPECTED_CHALLENGE_AFFIX_IDS[0], EXPECTED_CHALLENGE_AFFIX_IDS[4],
	]
	var run_track_ids: Array[StringName] = [
		EXPECTED_CHALLENGE_AFFIX_IDS[1], EXPECTED_CHALLENGE_AFFIX_IDS[3],
	]
	assert_eq(
		referenced_ids,
		[
			EXPECTED_CHALLENGE_AFFIX_IDS[0], EXPECTED_CHALLENGE_AFFIX_IDS[1],
			EXPECTED_CHALLENGE_AFFIX_IDS[3], EXPECTED_CHALLENGE_AFFIX_IDS[4],
		] as Array[StringName],
		"T06 回鏈後 level 1/2/4/5 分別掛載 affix_00（battle）/01（ShopSurcharge）/03（DrainExpeditionHp）/04（battle）"
	)
	for effect_id: StringName in referenced_ids:
		var effect := _find(pack, effect_id) as EffectDef
		assert_not_null(effect, "缺少目前掛載的 challenge affix: %s" % effect_id)
		if effect == null:
			continue
		if effect_id in battle_track_ids:
			assert_false(effect.battle_operations.is_empty(), "%s 必須走軌 A battle track" % effect_id)
			assert_true(effect.run_operations.is_empty(), "%s 屬軌 A，不應同時攜帶 run_operations" % effect_id)
		elif effect_id in run_track_ids:
			assert_true(effect.battle_operations.is_empty(), "%s 屬純軌 B，不應攜帶 battle_operations" % effect_id)
			assert_false(effect.run_operations.is_empty(), "%s 必須走軌 B run track（ShopSurcharge／DrainExpeditionHp）" % effect_id)


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
