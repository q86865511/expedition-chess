extends GutTest

## G2 M5／L2：檢視面板原本把 Dictionary 字面值與內部 serial 直接倒給玩家
## （來源欄 unit_slice_player_03、目標欄 7），而同一面板另三欄早已在地化；
## 敵我兩個 semantics host 又落在同一座標，cue 文字互相疊住。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_combat_flow/"
	+ "g2_combat_flow_test_support.gd"
)


func _inspect_first_unit(harness: Variant) -> RunCombatScreen:
	var composition := Support.composition(harness) as RunCombatScreen
	if composition == null:
		return null
	var selector := composition.get_node_or_null(^"UnitSelector") as ItemList
	assert_not_null(selector)
	if selector == null or selector.item_count == 0:
		return null
	selector.select(0)
	selector.item_selected.emit(0)
	var inspection := composition.inspect()
	assert_true(inspection.ok, String(Support.error_code(inspection)))
	return composition


func test_inspection_panel_shows_localized_values_instead_of_raw_state() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.start_run(harness).ok)
	assert_eq(Support.drive_to_combat(harness), &"")
	var composition := _inspect_first_unit(harness)
	assert_not_null(composition)
	if composition == null:
		return
	var source := composition.get_node_or_null(
		^"InspectionPanel/SourceValue"
	) as Label
	var target := composition.get_node_or_null(
		^"InspectionPanel/TargetValue"
	) as Label
	var stats := composition.get_node_or_null(
		^"InspectionPanel/StatsValue"
	) as Label
	assert_not_null(source)
	assert_not_null(target)
	assert_not_null(stats)
	if source == null or target == null or stats == null:
		return
	var snapshot: RunPresentationSnapshot = Support.snapshot(harness)
	var inspected: CombatUnitInspectionSnapshot = snapshot.combat_inspections[0]
	assert_ne(
		source.text,
		String(inspected.source_id),
		"the source column must resolve the content id, not print it"
	)
	assert_false(source.text.strip_edges().is_empty())
	assert_ne(
		target.text,
		str(inspected.target_serial),
		"the target column must not be the bare internal unit serial"
	)
	assert_false(target.text.strip_edges().is_empty())
	assert_eq(
		stats.text.find("{"),
		-1,
		"the stats column must not dump a Dictionary literal"
	)
	assert_eq(stats.text.find("\"health\""), -1)
	assert_true(
		stats.text.contains(str(inspected.stats.get("health", -1))),
		"the stats column must still show the committed values"
	)


func test_ally_enemy_and_rarity_cues_do_not_share_one_position() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.start_run(harness).ok)
	assert_eq(Support.drive_to_combat(harness), &"")
	var composition := Support.composition(harness) as RunCombatScreen
	assert_not_null(composition)
	if composition == null:
		return
	var positions: Dictionary = {}
	for host_name: StringName in [
		&"AllySemantics",
		&"EnemySemantics",
		&"RaritySemantics",
		&"TraitSemantics",
		&"DangerSemantics",
	]:
		var host := composition.get_node_or_null(NodePath(String(host_name))) as Control
		assert_not_null(host, "%s must exist" % String(host_name))
		if host == null:
			continue
		var key := "%d,%d" % [int(host.position.x), int(host.position.y)]
		assert_false(
			positions.has(key),
			"%s overlaps %s at %s" % [
				String(host_name),
				String(positions.get(key, &"")),
				key,
			]
		)
		positions[key] = host_name
