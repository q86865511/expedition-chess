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
	var selector := composition.find_child("UnitSelector", true, false) as ItemList
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
	var panel := composition.find_child("InspectionPanel", true, false)
	var source := panel.get_node_or_null(^"SourceValue") as Label if panel != null else null
	var target := panel.get_node_or_null(^"TargetValue") as Label if panel != null else null
	var stats := panel.get_node_or_null(^"StatsValue") as Label if panel != null else null
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
	# drive_to_combat commits the replacement synchronously. VBoxContainer owns
	# the cue geometry, and its sort notification runs on the following layout
	# pass; reading positions in the commit call stack only observes each newly
	# created Control's default (0, 0), not the mounted production layout.
	await wait_process_frames(2)
	var hud := composition.find_child(
		"InRunHudShell", true, false
	) as InRunHudShell
	assert_not_null(hud)
	if hud == null:
		return
	var left_stack := hud.find_child(
		"InRunLeftStack", true, false
	) as VBoxContainer
	assert_not_null(left_stack)
	var right_host := hud.host(ProductionLayoutShell.REGION_RIGHT)
	var inspection_panel := composition.find_child(
		"InspectionPanel", true, false
	) as Control
	assert_not_null(right_host)
	assert_not_null(inspection_panel)
	if left_stack == null or right_host == null or inspection_panel == null:
		return
	assert_eq(
		inspection_panel.get_parent(),
		right_host,
		"the inspector must remain in the dedicated right HUD host"
	)

	var previous: Control
	for host_name: StringName in [
		&"AllySemantics",
		&"RaritySemantics",
		&"EnemySemantics",
		&"TraitSemantics",
		&"DangerSemantics",
	]:
		var host := composition.find_child(String(host_name), true, false) as Control
		assert_not_null(host, "%s must exist" % String(host_name))
		if host == null:
			continue
		assert_eq(
			host.get_parent(),
			left_stack,
			"%s must be a direct Container-owned left HUD row"
			% String(host_name)
		)
		assert_gte(
			host.size.y,
			42.0,
			"%s must retain its authored semantic-row height"
			% String(host_name)
		)
		if previous != null:
			assert_gt(
				host.position.y,
				previous.position.y,
				"VBox order must advance for %s" % String(host_name)
			)
			assert_lte(
				previous.position.y + previous.size.y,
				host.position.y + 0.5,
				"semantic rows must not overlap: %s then %s" % [
					previous.name, host.name,
				]
			)
			assert_false(
				previous.get_global_rect().intersects(host.get_global_rect()),
				"mounted semantic rectangles must remain disjoint"
			)
		previous = host

	var danger := composition.find_child(
		"DangerSemantics", true, false
	) as Control
	assert_not_null(danger)
	if danger == null or danger.get_child_count() == 0:
		return
	var danger_label := danger.get_child(0) as Label
	assert_not_null(danger_label)
	if danger_label == null:
		return
	var snapshot := Support.snapshot(harness)
	var current_node_id := snapshot.map.current_node_id.value
	var danger_key: StringName = &""
	for node: MapNodeState in snapshot.map.nodes:
		if node != null and node.node_id == current_node_id:
			danger_key = StringName(
				"map.node_kind.%s" % String(
					MapNodeState.node_kind_to_token(node.node_kind)
				)
			)
			break
	assert_false(danger_key.is_empty())
	assert_eq(danger_label.get_meta(&"typed_data_id"), danger_key)
	assert_eq(danger_label.get_meta(&"semantic_pattern"), &"warning-stripes")
	assert_eq(
		danger_label.text,
		String(composition.call(&"_localized_ui_text", danger_key)),
		"danger cue must use the current node's localized kind, never runtime id"
	)
	assert_ne(danger_label.text, current_node_id)
	assert_ne(
		danger_label.text,
		String(composition.call(
			&"_localized_ui_text", &"prepare.panel.expedition"
		)),
		"danger cue must not reuse the generic expedition panel title"
	)
