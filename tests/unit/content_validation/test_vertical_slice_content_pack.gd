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

# G2 difficulty-curve T03（specs/difficulty-curve/design.md「敵方成長與遭遇編成」表）：
# 五個 encounter 的多敵編成需逐列與 design 表一致，防未來內容漂移。
func test_vertical_slice_encounters_match_difficulty_curve_spawn_table() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	var expected: Dictionary = {
		&"encounter.slice_normal": [
			{"spawn_key": "enemy_0", "unit_ref": &"unit.slice_monster_00", "star": 1, "logical_y": 6, "logical_x": 3},
			{"spawn_key": "enemy_1", "unit_ref": &"unit.slice_monster_01", "star": 1, "logical_y": 7, "logical_x": 4},
		],
		&"encounter.slice_elite": [
			{"spawn_key": "enemy_0", "unit_ref": &"unit.slice_monster_01", "star": 1, "logical_y": 6, "logical_x": 3},
			{"spawn_key": "enemy_1", "unit_ref": &"unit.slice_monster_06", "star": 1, "logical_y": 5, "logical_x": 2},
			{"spawn_key": "enemy_2", "unit_ref": &"unit.slice_monster_07", "star": 1, "logical_y": 7, "logical_x": 4},
		],
		&"encounter.slice_boss_0": [
			{"spawn_key": "boss_0", "unit_ref": &"unit.slice_monster_02", "star": 1, "logical_y": 6, "logical_x": 3},
			{"spawn_key": "add_0", "unit_ref": &"unit.slice_monster_00", "star": 1, "logical_y": 5, "logical_x": 2},
			{"spawn_key": "add_1", "unit_ref": &"unit.slice_monster_01", "star": 1, "logical_y": 7, "logical_x": 4},
		],
		&"encounter.slice_boss_1": [
			{"spawn_key": "boss_1", "unit_ref": &"unit.slice_monster_03", "star": 2, "logical_y": 6, "logical_x": 3},
			{"spawn_key": "add_0", "unit_ref": &"unit.slice_monster_06", "star": 1, "logical_y": 5, "logical_x": 2},
			{"spawn_key": "add_1", "unit_ref": &"unit.slice_monster_07", "star": 1, "logical_y": 5, "logical_x": 4},
			{"spawn_key": "add_2", "unit_ref": &"unit.slice_monster_08", "star": 1, "logical_y": 7, "logical_x": 3},
		],
		&"encounter.slice_boss_2": [
			{"spawn_key": "boss_2", "unit_ref": &"unit.slice_monster_04", "star": 2, "logical_y": 6, "logical_x": 3},
			{"spawn_key": "add_0", "unit_ref": &"unit.slice_monster_09", "star": 2, "logical_y": 5, "logical_x": 2},
			{"spawn_key": "add_1", "unit_ref": &"unit.slice_monster_10", "star": 1, "logical_y": 5, "logical_x": 4},
			{"spawn_key": "add_2", "unit_ref": &"unit.slice_monster_11", "star": 1, "logical_y": 7, "logical_x": 2},
			{"spawn_key": "add_3", "unit_ref": &"unit.slice_monster_05", "star": 1, "logical_y": 7, "logical_x": 4},
		],
	}
	var found: Dictionary = {}
	for definition in pack:
		if not definition is EncounterDef: continue
		var encounter := definition as EncounterDef
		if not expected.has(encounter.id): continue
		found[encounter.id] = true
		var expected_spawns: Array = expected[encounter.id]
		assert_eq(encounter.enemy_spawns.size(), expected_spawns.size(), "%s 敵方單位數應為 %d" % [String(encounter.id), expected_spawns.size()])
		var seen_keys: Dictionary = {}
		var seen_positions: Dictionary = {}
		for spawn in encounter.enemy_spawns:
			var spawn_def := spawn as EnemySpawnDef
			assert_false(seen_keys.has(spawn_def.spawn_key), "%s spawn_key 重複: %s" % [String(encounter.id), spawn_def.spawn_key])
			seen_keys[spawn_def.spawn_key] = true
			var position := "%d,%d" % [spawn_def.logical_y, spawn_def.logical_x]
			assert_false(seen_positions.has(position), "%s 格位碰撞: %s" % [String(encounter.id), position])
			seen_positions[position] = true
			assert_true(spawn_def.logical_y >= 4 and spawn_def.logical_y <= 7, "%s spawn %s 的 logical_y 應落在敵方半場 4-7" % [String(encounter.id), spawn_def.spawn_key])
			var matched := false
			for row in expected_spawns:
				if row["spawn_key"] != spawn_def.spawn_key: continue
				matched = true
				assert_eq(spawn_def.unit_ref, row["unit_ref"], "%s/%s unit_ref 應與 design 表一致" % [String(encounter.id), spawn_def.spawn_key])
				assert_eq(spawn_def.star, int(row["star"]), "%s/%s star 應與 design 表一致" % [String(encounter.id), spawn_def.spawn_key])
				assert_eq(spawn_def.logical_y, int(row["logical_y"]), "%s/%s logical_y 應與 design 表一致" % [String(encounter.id), spawn_def.spawn_key])
				assert_eq(spawn_def.logical_x, int(row["logical_x"]), "%s/%s logical_x 應與 design 表一致" % [String(encounter.id), spawn_def.spawn_key])
				break
			assert_true(matched, "%s 出現 design 表外的 spawn_key: %s" % [String(encounter.id), spawn_def.spawn_key])
	for encounter_id in expected.keys():
		assert_true(found.has(encounter_id), "缺少 encounter: %s" % String(encounter_id))

# G2 difficulty-curve T05（DC-REQ-005／Acceptance 5）：全庫每個 faction trait 成員數 >= 6，
# 且 cost_tier == 1（tier-1）子集內每個 faction 至少有 2 名成員，確保 2/4/6 三階皆可達成。
func test_vertical_slice_faction_distribution_meets_tier1_and_library_thresholds() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	var faction_traits: Array[StringName] = [
		&"trait.faction_arcane", &"trait.faction_ember", &"trait.faction_frost",
		&"trait.faction_iron", &"trait.faction_shadow", &"trait.faction_verdant",
	]
	var total_counts: Dictionary = {}
	var tier1_counts: Dictionary = {}
	for faction in faction_traits:
		total_counts[faction] = 0
		tier1_counts[faction] = 0
	for definition in pack:
		if not definition is UnitDef: continue
		var unit := definition as UnitDef
		if unit.availability not in [&"player", &"shared"]: continue
		for trait_ref in unit.trait_refs:
			if not total_counts.has(trait_ref): continue
			total_counts[trait_ref] = int(total_counts[trait_ref]) + 1
			if unit.cost_tier == 1:
				tier1_counts[trait_ref] = int(tier1_counts[trait_ref]) + 1
	for faction in faction_traits:
		assert_true(int(total_counts[faction]) >= 6, "faction %s 全庫成員數應 >= 6（實際 %d）" % [String(faction), total_counts[faction]])
		assert_true(int(tier1_counts[faction]) >= 2, "faction %s tier-1（cost_tier=1）子集成員數應 >= 2（實際 %d）" % [String(faction), tier1_counts[faction]])

# G2 difficulty-curve T06（DC-REQ-006／Acceptance 6，DC-REQ-006 已於 T06 回鏈
# slice_challenge_affix_01/03）：challenge 鏈 modifier_refs 三桶 gate（軌 A／
# ShopSurcharge／DrainExpeditionHp）正向（現內容覆蓋三桶）與負向（移除 affix_01
# 引用即缺 ShopSurcharge 桶→FAIL）案例。只用 vertical_slice 單一 pack（不含
# build_systems），避免與其他切片（T04 trait 階梯）並行工作中的內容耦合。
func test_vertical_slice_challenge_chain_covers_three_buckets_and_regresses_when_surcharge_missing() -> void:
	var pack := _load_pack(VERTICAL_SLICE_ROOT)
	var input := ContentValidationInput.new(pack, [], [], FakeContentDependencyPort.new(), 9)
	var report := ContentValidator.new().validate(input)
	assert_false(
		_has_issue(report, &"CONTENT_CHALLENGE_AFFIX_COVERAGE"),
		"現行 vertical_slice challenge 鏈應覆蓋三桶: %s" % _issue_text(report)
	)
	assert_false(_has_issue(report, &"CONTENT_CHALLENGE_AFFIX_ROLE"), _issue_text(report))

	var mutated := _load_pack(VERTICAL_SLICE_ROOT)
	for definition in mutated:
		if definition.id == &"unlock.slice_challenge_2":
			(definition as UnlockDef).modifier_refs = []
	var mutated_input := ContentValidationInput.new(mutated, [], [], FakeContentDependencyPort.new(), 9)
	var mutated_report := ContentValidator.new().validate(mutated_input)
	assert_true(
		_has_issue(mutated_report, &"CONTENT_CHALLENGE_AFFIX_COVERAGE"),
		"移除 unlock.slice_challenge_2 對 effect.slice_challenge_affix_01（ShopSurcharge 桶）的引用後三桶 gate 必須 FAIL: %s" % _issue_text(mutated_report)
	)

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

# T11 wave4(見 content/packs/vertical_slice/README.md「T11 wave4 內容缺口修復」)：
# economy_config 原本缺 layer_income/xp_thresholds 等必填欄位，被
# EconomyExpeditionCatalogBuilder._valid_config() 拒絕——S3 測試至今只用過
# EconomyTestFixture 合成 config，從未把這份正式內容餵進 production builder。
# 本測試把雙 pack 安裝進 registry 後，直接呼叫該 builder 驗證正式內容現在能真正
# build 成功。
func test_vertical_slice_economy_config_builds_via_production_builder() -> void:
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

	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var pack_ids: Array[StringName] = [&"pack.build_systems", &"pack.vertical_slice"]
	var install_result := registry.install_validated(input, "0.1.0-vertical-slice-t11", pack_ids)
	if not install_result.ok:
		assert_true(install_result.ok, "install_validated 失敗: %s" % install_result.error.code)
		return
	var digest := install_result.handle.manifest_digest

	var unit_ids: Array[StringName] = []
	var map_node_ids: Array[StringName] = []
	var reward_table_ids: Array[StringName] = []
	var economy_config_id: StringName = &""
	for definition: ContentDefinition in combined:
		match definition.category_name():
			&"unit": unit_ids.append(definition.id)
			&"map_node": map_node_ids.append(definition.id)
			&"reward_table": reward_table_ids.append(definition.id)
			&"economy_config": economy_config_id = definition.id
	assert_ne(economy_config_id, &"", "應能找到 economy_config")

	var economy_result := EconomyExpeditionCatalogBuilder.new().build(
		registry, digest, economy_config_id, unit_ids, map_node_ids, reward_table_ids
	)
	assert_true(
		economy_result.ok,
		"EconomyExpeditionCatalogBuilder 應對正式內容 build 成功: %s field=%s" % [
			economy_result.error.code if not economy_result.ok else "",
			economy_result.error.field_path if not economy_result.ok else "",
		]
	)

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

func _has_issue(report: ContentValidationReport, code: StringName) -> bool:
	for issue: ContentValidationIssue in report.issues:
		if issue.code == code: return true
	return false

func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)
