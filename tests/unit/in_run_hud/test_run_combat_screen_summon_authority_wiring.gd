extends GutTest

## Renderer seam coverage for IRH-REQ-007. Production content currently has no
## summon effect, so this fixture supplies one pinned template exactly where the
## live supply port would and drives the transcript event through the screen's
## real CombatWorldEventProjection.

const RENDERABLE_UNIT_ID: StringName = &"unit.slice_monster_00"
const ALLY_ID: StringName = &"u_0000000000000001"
const SUMMON_ID: StringName = &"s_0000000000000001"


class SummonSupplyPort:
	extends LiveScreenSupplyPort

	var _templates: Array[SummonedUnitRuleSnapshot] = []


	func _init(templates: Array[SummonedUnitRuleSnapshot]) -> void:
		for template: SummonedUnitRuleSnapshot in templates:
			_templates.append(template.deep_clone() if template != null else null)


	func combat_summoned_unit_templates() -> Array[SummonedUnitRuleSnapshot]:
		var result: Array[SummonedUnitRuleSnapshot] = []
		for template: SummonedUnitRuleSnapshot in _templates:
			result.append(template.deep_clone() if template != null else null)
		return result


func test_screen_injects_pinned_summon_authority_into_renderer_projection() -> void:
	var template := _summoned_template()
	var templates: Array[SummonedUnitRuleSnapshot] = [template]
	var combat := RunCombatScreen.new()
	var compose_error := combat.compose(
			_combat_snapshot(),
			LiveScreenIntentPort.new(),
			SummonSupplyPort.new(templates)
	)
	assert_eq(compose_error, &"")
	if not compose_error.is_empty():
		combat.free()
		return

	var projection := combat.get(
		&"_combat_world_projection"
	) as CombatWorldEventProjection
	assert_not_null(projection)
	if projection == null:
		combat.free()
		return
	assert_eq(projection.apply_window([_spawn_event()]), &"")

	var presented := projection.snapshot_clone()
	var summoned := _unit(presented, SUMMON_ID)
	assert_not_null(summoned, "screen 必須把 supply port 的 pinned 模板注入投影")
	if summoned != null:
		assert_eq(summoned.logical_cell, Vector2i(4, 3))
		assert_eq(summoned.health, template.health)
		assert_eq(summoned.max_health, template.health)
		assert_eq(summoned.mana, template.start_mana)
		assert_eq(summoned.max_mana, template.max_mana)

	var renderer := WorldBoardRenderer.new()
	add_child_autofree(renderer)
	assert_eq(renderer.render_snapshot(presented), &"")
	assert_not_null(
		renderer.unit_sprite(SUMMON_ID),
		"fixture 召喚必須通過正式 WorldBoardRenderer 形成 sprite body"
	)
	combat.free()


func test_screen_without_supply_keeps_summon_unrenderable() -> void:
	var combat := RunCombatScreen.new()
	var compose_error := combat.compose(
		_combat_snapshot(),
		LiveScreenIntentPort.new()
	)
	assert_eq(compose_error, &"")
	if not compose_error.is_empty():
		combat.free()
		return
	var projection := combat.get(
		&"_combat_world_projection"
	) as CombatWorldEventProjection
	assert_not_null(projection)
	if projection != null:
		assert_eq(projection.apply_window([_spawn_event()]), &"")
		assert_null(
			_unit(projection.snapshot_clone(), SUMMON_ID),
			"缺 supply authority 時不得虛構召喚視覺或最大值"
		)
	combat.free()


func _combat_snapshot() -> RunPresentationSnapshot:
	var snapshot := RunPresentationSnapshot.new()
	snapshot.app_phase = &"COMBAT"
	var preview := EncounterPreviewSnapshot.new()
	var node := MapNodeState.new(
		"node.fixture",
		NodeKeyState.create(
			&"run.fixture", 0, &"normal", 0, 0, &"node.fixture.digest"
		),
		&"map.node.normal",
		0,
		0,
		0,
		MapNodeState.NodeKind.NORMAL,
		"fixture",
		preview,
		false
	)
	var nodes: Array[MapNodeState] = [node]
	var edges: Array[MapEdgeState] = []
	var completed_node_ids: Array[String] = []
	snapshot.map = MapState.new(
		nodes,
		edges,
		OptionalStringValue.new("node.fixture"),
		completed_node_ids
	)
	var inspection := CombatUnitInspectionSnapshot.new()
	inspection.unit_serial = 1
	inspection.presentation_instance_id = ALLY_ID
	inspection.source_id = &"unit.slice_player_00"
	inspection.side_id = &"player"
	inspection.logical_cell = Vector2i(1, 5)
	inspection.stats = {
		"star": 1,
		"health": 100,
		"start_mana": 10,
		"max_mana": 100,
	}
	snapshot.combat_inspections.append(inspection)
	return snapshot


func _summoned_template() -> SummonedUnitRuleSnapshot:
	var template := SummonedUnitRuleSnapshot.new()
	template.unit_id = RENDERABLE_UNIT_ID
	template.star = 1
	template.health = 45
	template.attack = 7
	template.armor = 0
	template.magic_resist = 0
	template.attack_speed_milli = 900
	template.attack_range_cells = 1
	template.start_mana = 3
	template.max_mana = 30
	template.move_speed_milli = 1000
	template.ai_profile = &"frontline"
	template.basic_attack_profile = &"melee"
	return template


func _spawn_event() -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"spawn"
	event.target_instance_ids.assign([SUMMON_ID])
	var payload := SpawnEventPayload.new()
	payload.unit_id = RENDERABLE_UNIT_ID
	payload.side = &"player"
	payload.origin = &"summon"
	payload.logical_x = 4
	payload.logical_y = 3
	event.payload = payload
	return event


func _unit(
	snapshot: WorldBoardSnapshot,
	presentation_instance_id: StringName
) -> WorldBoardUnitSnapshot:
	for unit: WorldBoardUnitSnapshot in snapshot.units:
		if unit != null and unit.presentation_instance_id == presentation_instance_id:
			return unit
	return null
