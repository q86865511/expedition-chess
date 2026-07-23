extends GutTest

# T09(S4 build-systems，免 TDD：內容資料授權，同 T08)驗收測試。
# 對應 specs/build-systems/design.md §7、tasks.md T09：
#   把 content/packs/build_systems/ 與 content/packs/vertical_slice/ 兩個正式 .tres pack
#   （皆為授權內容、無 synthetic 補充）合併成 ContentValidator 要求的完整 manifest，
#   斷言 0 issue、關鍵計數成立，且 manifest digest 可經 ContentRegistryService 進 canonical
#   snapshot（install_validated 後 latest_catalog_handle／resolve 可查得同一份內容）。
#
# 本檔不修改 content/packs/build_systems 或 tests/fixtures/content/synthetic_content_fixture.gd
# ——僅新增獨立測試，讀取磁碟上兩個真實 pack 目錄。

const BUILD_SYSTEMS_ROOT := "res://content/packs/build_systems"
const VERTICAL_SLICE_ROOT := "res://content/packs/vertical_slice"

# ================= 頂層驗收 =================

func test_vertical_slice_pack_has_expected_definition_counts() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	assert_eq(_count(pack, &"unit"), 44, "UnitDef 應為 44（32 棋子＋12 monster）")
	assert_eq(_count_players(pack), 32, "player/shared 棋子應為 32")
	assert_eq(_count_monsters(pack), 12, "monster 應為 12")
	assert_eq(_count(pack, &"commander"), 3, "CommanderDef 應為 3")
	assert_eq(_count(pack, &"encounter"), 5, "EncounterDef 應為 5（normal/elite/boss*3）")
	assert_eq(_count_bosses(pack), 3, "boss EncounterDef 應為 3")
	assert_eq(_count(pack, &"map_node"), 18, "MapNodeDef 應為 18（6 固定＋12 event）")
	assert_eq(_count(pack, &"unlock"), 7, "UnlockDef 應為 7（base_profile＋6 challenge）")
	assert_eq(_count(pack, &"economy_config"), 1, "EconomyConfigDef 應為 1")
	assert_eq(_count(pack, &"combat_config"), 1, "CombatConfigDef 應為 1")
	assert_eq(_count(pack, &"reward_table"), 2, "RewardTableDef 應為 2（standard／relic）")
	var affix_count := 0
	for definition in pack:
		if definition is EffectDef and (definition as EffectDef).content_role == &"elite_affix": affix_count += 1
	assert_true(affix_count >= 6, "elite_affix EffectDef 應 >= 6")

func test_vertical_slice_players_cover_cost_distribution_and_three_tag_count() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	var cost_counts := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	var three_tag := 0
	for definition in pack:
		if not definition is UnitDef: continue
		var unit := definition as UnitDef
		if unit.availability not in [&"player", &"shared"]: continue
		cost_counts[unit.cost_tier] = int(cost_counts[unit.cost_tier]) + 1
		if unit.trait_refs.size() == 3: three_tag += 1
	assert_eq([cost_counts[1], cost_counts[2], cost_counts[3], cost_counts[4], cost_counts[5]], [10, 8, 6, 5, 3], "cost_tier 分布應為 10/8/6/5/3")
	assert_eq(three_tag, 4, "三標籤棋應恰 4 隻")

func test_vertical_slice_map_nodes_cover_all_kinds_with_normal_elite_parity() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	var kinds: Dictionary = {}
	for definition in pack:
		if not definition is MapNodeDef: continue
		var kind := (definition as MapNodeDef).node_type
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	for kind in [&"normal", &"elite", &"merchant", &"event", &"rest", &"treasure", &"boss"]:
		assert_true(kinds.has(kind), "缺少 node_type: %s" % String(kind))
	assert_eq(int(kinds.get(&"normal", 0)), int(kinds.get(&"elite", 0)), "normal／elite 節點數須相等（W2-F6）")
	assert_true(int(kinds.get(&"event", 0)) >= 12, "event 節點應 >= 12（generator_ref 各不相同）")

func test_combined_manifest_installs_validated_with_zero_issues_and_pins_into_canonical_snapshot() -> void:
	var build_systems_pack := _load_pack(BUILD_SYSTEMS_ROOT)
	var vertical_slice_pack := _load_pack(VERTICAL_SLICE_ROOT)
	var combined: Array[ContentDefinition] = []
	combined.append_array(build_systems_pack)
	combined.append_array(vertical_slice_pack)

	var dependency_port := FakeContentDependencyPort.new()
	var input := ContentValidationInput.new(combined, [], [], dependency_port, 9)

	var report := ContentValidator.new().validate(input)
	assert_true(report.valid, _issue_text(report))
	if not report.valid: return

	# 完整 manifest 的人口／entity 壓力上界必須是有限、可解的數字（非驗證失敗的副作用）。
	assert_true(report.version_maximum_population >= 9)
	assert_true(report.entity_stress_minimum >= 64)

	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var pack_ids: Array[StringName] = [&"pack.build_systems", &"pack.vertical_slice"]
	var result := registry.install_validated(input, "0.1.0-vertical-slice-t09", pack_ids)
	if not result.ok:
		var source := String(result.error.source_id.value) if result.error.source_id != null else "?"
		assert_true(result.ok, "install_validated 失敗: %s field=%s source=%s" % [result.error.code, result.error.field_path, source])
		return
	assert_false(result.handle.manifest_digest.is_empty(), "manifest digest 不應為空")

	# digest 進 canonical snapshot：latest_catalog_handle／resolve 可用同一份 digest 查回內容。
	var latest := registry.latest_catalog_handle()
	assert_true(latest.ok, "latest_catalog_handle 應成功")
	assert_eq(latest.value.manifest_digest, result.handle.manifest_digest, "latest handle 應與剛安裝的 digest 一致")

	var ref := ContentRef.new(result.handle.manifest_digest, &"unit.slice_player_00")
	var resolved := registry.resolve(ref)
	assert_true(resolved.ok, "resolve 應能查回剛 pin 的 unit.slice_player_00")

# ================= pack 載入 =================

func _load_pack(root: String) -> Array[ContentDefinition]:
	var result: Array[ContentDefinition] = []
	_load_dir(root, result)
	return result

func _load_dir(path: String, result: Array[ContentDefinition]) -> void:
	var dir := DirAccess.open(path)
	assert_not_null(dir, "無法開啟目錄: %s" % path)
	if dir == null: return
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

func _count(definitions: Array[ContentDefinition], category: StringName) -> int:
	var total := 0
	for definition in definitions:
		if definition.category_name() == category: total += 1
	return total

func _count_players(definitions: Array[ContentDefinition]) -> int:
	var total := 0
	for definition in definitions:
		if definition is UnitDef and (definition as UnitDef).availability in [&"player", &"shared"]: total += 1
	return total

func _count_monsters(definitions: Array[ContentDefinition]) -> int:
	var total := 0
	for definition in definitions:
		if definition is UnitDef and (definition as UnitDef).availability == &"monster": total += 1
	return total

func _count_bosses(definitions: Array[ContentDefinition]) -> int:
	var total := 0
	for definition in definitions:
		if definition is EncounterDef and (definition as EncounterDef).encounter_kind == &"boss": total += 1
	return total

func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)
