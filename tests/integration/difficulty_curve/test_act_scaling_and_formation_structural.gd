extends GutTest

## G2 difficulty-curve T09（快篩三層之 (a) 結構硬斷言）：驗證 T01–T03 合起來確實
## 產生跨幕梯度，非單點回歸。決定性可判，走正式 content bootstrap + EncounterCompiler，
## 不跑戰鬥模擬。
## - DC-REQ-001／Acceptance 1：同一 encounter 固定，只換 act_index，敵方合計
##   health/attack 必須嚴格遞增（act2 > act1、act3 > act2）；節奏／可達性欄位三幕不變。
## - DC-REQ-002／Acceptance 2：三幕 Boss encounter id 互異（BOSS_ENCOUNTER_ID_BY_ACT
##   查表生效），且三者在 pinned catalog 中皆可編譯成功。
## - DC-REQ-003／Acceptance 3：五個 encounter 編譯後敵方單位數為 2／3／3／4／5。

const NODE_ID: StringName = &"node_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

var _registry: ContentRegistryService
var _content: ProjectContentBootstrapResult
var _catalog: BattleRuleCatalog


func before_all() -> void:
	_registry = ContentRegistryService.new()
	add_child(_registry)
	_content = ProjectContentBootstrap.new().run(_registry)
	if _content.ok:
		var roots: Array[StringName] = []
		roots.append_array(_content.unit_ids)
		roots.append_array(_content.equipment_ids)
		roots.append_array(_content.battle_relic_ids)
		roots.append_array(_content.encounter_ids)
		var built := BattleRuleCatalogBuilder.new().build(
			_registry,
			_content.manifest_digest,
			RunCompositionSupport.required_battle_ids(roots, 0)
		)
		if built.ok:
			_catalog = built.catalog


func after_all() -> void:
	_catalog = null
	if _registry != null:
		remove_child(_registry)
		_registry.free()
		_registry = null


func test_act2_and_act3_enemy_totals_strictly_exceed_previous_act_for_every_encounter() -> void:
	if not _assert_ready():
		return
	for encounter_id: StringName in [
		&"encounter.slice_normal", &"encounter.slice_elite",
		&"encounter.slice_boss_0", &"encounter.slice_boss_1", &"encounter.slice_boss_2",
	]:
		var act1 := _compile(encounter_id, 1)
		var act2 := _compile(encounter_id, 2)
		var act3 := _compile(encounter_id, 3)
		assert_true(act1.ok, "%s act1 必須編譯成功：%s" % [encounter_id, _err(act1)])
		assert_true(act2.ok, "%s act2 必須編譯成功：%s" % [encounter_id, _err(act2)])
		assert_true(act3.ok, "%s act3 必須編譯成功：%s" % [encounter_id, _err(act3)])
		if not (act1.ok and act2.ok and act3.ok):
			continue

		var totals1 := _totals(act1.preview.enemy_units)
		var totals2 := _totals(act2.preview.enemy_units)
		var totals3 := _totals(act3.preview.enemy_units)

		assert_gt(
			totals2.health, totals1.health,
			"%s act2 合計 HP 必須嚴格大於 act1（%d vs %d）" % [
				encounter_id, totals2.health, totals1.health,
			]
		)
		assert_gt(
			totals3.health, totals2.health,
			"%s act3 合計 HP 必須嚴格大於 act2（%d vs %d）" % [
				encounter_id, totals3.health, totals2.health,
			]
		)
		assert_gt(
			totals2.attack, totals1.attack,
			"%s act2 合計 ATK 必須嚴格大於 act1（%d vs %d）" % [
				encounter_id, totals2.attack, totals1.attack,
			]
		)
		assert_gt(
			totals3.attack, totals2.attack,
			"%s act3 合計 ATK 必須嚴格大於 act2（%d vs %d）" % [
				encounter_id, totals3.attack, totals2.attack,
			]
		)

		# 節奏／可達性欄位是固定規則，三幕必須完全相同（design.md「資料與介面」段）。
		assert_eq(
			_pace_signature(act1.preview.enemy_units),
			_pace_signature(act2.preview.enemy_units),
			"%s attack_speed/move_speed/range/mana 三幕不得因 act 乘數改變（act1 vs act2）" % (
				encounter_id
			)
		)
		assert_eq(
			_pace_signature(act1.preview.enemy_units),
			_pace_signature(act3.preview.enemy_units),
			"%s attack_speed/move_speed/range/mana 三幕不得因 act 乘數改變（act1 vs act3）" % (
				encounter_id
			)
		)


func test_boss_encounter_ids_are_distinct_per_act_and_all_compile() -> void:
	if not _assert_ready():
		return
	var ids := NodeEntryService.BOSS_ENCOUNTER_ID_BY_ACT
	assert_eq(ids.size(), 3, "三幕 Boss 映射表必須恰有三筆")
	assert_eq(ids[1], &"encounter.slice_boss_0")
	assert_eq(ids[2], &"encounter.slice_boss_1")
	assert_eq(ids[3], &"encounter.slice_boss_2")
	assert_ne(ids[1], ids[2], "act1/act2 Boss encounter id 必須互異")
	assert_ne(ids[2], ids[3], "act2/act3 Boss encounter id 必須互異")
	assert_ne(ids[1], ids[3], "act1/act3 Boss encounter id 必須互異")

	for act_index: int in [1, 2, 3]:
		var encounter_id: StringName = ids[act_index]
		var compiled := _compile(encounter_id, act_index)
		assert_true(
			compiled.ok,
			"%s（act%d）必須在 pinned catalog 中編譯成功：%s" % [
				encounter_id, act_index, _err(compiled),
			]
		)


func test_multi_enemy_formation_counts_match_design_table() -> void:
	if not _assert_ready():
		return
	var expected_counts := {
		&"encounter.slice_normal": 2,
		&"encounter.slice_elite": 3,
		&"encounter.slice_boss_0": 3,
		&"encounter.slice_boss_1": 4,
		&"encounter.slice_boss_2": 5,
	}
	for encounter_id: StringName in expected_counts.keys():
		var compiled := _compile(encounter_id, 1)
		assert_true(compiled.ok, "%s 必須編譯成功：%s" % [encounter_id, _err(compiled)])
		if not compiled.ok:
			continue
		assert_eq(
			compiled.preview.enemy_units.size(), int(expected_counts[encounter_id]),
			"%s 敵方單位數必須符合 design 表" % encounter_id
		)
		var seen_cells: Dictionary = {}
		for unit: UnitBattleSnapshot in compiled.preview.enemy_units:
			assert_true(
				unit.logical_y >= 4 and unit.logical_y <= 7,
				"%s 敵方單位必須落在敵方半場 logical_y 4-7（實際 %d）" % [
					encounter_id, unit.logical_y,
				]
			)
			var cell_key := unit.logical_y * 8 + unit.logical_x
			assert_false(
				seen_cells.has(cell_key),
				"%s 敵方單位格位不得重疊（%d,%d）" % [encounter_id, unit.logical_y, unit.logical_x]
			)
			seen_cells[cell_key] = true


func _compile(encounter_id: StringName, act_index: int) -> EncounterCompileResult:
	var request := EncounterCompileRequest.new()
	request.manifest_digest = _content.manifest_digest
	request.encounter_id = encounter_id
	request.node_id = NODE_ID
	request.act_index = act_index
	request.depth = 6
	request.challenge_level = 0
	return EncounterCompiler.new().compile(request, _catalog)


func _totals(units: Array[UnitBattleSnapshot]) -> Dictionary:
	var health := 0
	var attack := 0
	for unit: UnitBattleSnapshot in units:
		health += unit.health
		attack += unit.attack
	return {"health": health, "attack": attack}


func _pace_signature(units: Array[UnitBattleSnapshot]) -> String:
	var parts: Array[String] = []
	for unit: UnitBattleSnapshot in units:
		parts.append("%s:%d:%d:%d:%d:%d" % [
			unit.instance_id, unit.attack_speed_milli, unit.move_speed_milli,
			unit.attack_range_cells, unit.start_mana, unit.max_mana,
		])
	return "|".join(parts)


func _assert_ready() -> bool:
	assert_true(
		_content != null and _content.ok,
		"正式內容 bootstrap 必須成功：%s" % (
			String(_content.error_code) if _content != null else "null"
		)
	)
	assert_true(_catalog != null, "battle rule catalog 必須建置成功")
	return _content != null and _content.ok and _catalog != null


func _err(result: EncounterCompileResult) -> String:
	return "" if result.ok else "%s:%s" % [result.error.code, result.error.field_path]
