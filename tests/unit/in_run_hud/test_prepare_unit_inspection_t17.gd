extends GutTest

const MANIFEST := "manifest.t17"
const BOARD_ID := "u_0000000000000011"
const BENCH_ID := "u_0000000000000012"
const BOARD_DEF: StringName = &"unit.t17_board"
const BENCH_DEF: StringName = &"unit.t17_bench"
const EQUIPMENT_ID := "i_0000000000000021"
const ProductionFrames = preload(
	"res://assets/production/units/slice_player_00.tres"
)


func test_projection_includes_board_and_bench_with_catalog_fields() -> void:
	var source := _source_snapshot(MANIFEST)
	var inspections := _build_inspections(source, _catalog(MANIFEST))

	assert_eq(inspections.size(), 2)
	var board: PrepareUnitInspectionSnapshot = inspections[0]
	var bench: PrepareUnitInspectionSnapshot = inspections[1]
	assert_eq(board.unit_instance_id, StringName(BOARD_ID))
	assert_eq(board.unit_id, BOARD_DEF)
	assert_eq(board.unit_def_id, BOARD_DEF)
	assert_eq(board.star, 1)
	assert_eq(board.cost_tier, 3)
	assert_eq(board.trait_ids, [&"trait.faction_test", &"trait.role_guard"])
	assert_eq(board.ability_id, &"ability.t17_board")
	assert_eq(board.ai_profile, &"frontline")
	assert_eq(board.equipment_instance_ids, [EQUIPMENT_ID])
	assert_eq(board.stats.health, 111)
	assert_eq(bench.unit_instance_id, StringName(BENCH_ID))
	assert_eq(bench.unit_def_id, BENCH_DEF)
	assert_eq(bench.star, 2)
	assert_eq(bench.cost_tier, 5)
	assert_eq(bench.stats.health, 222)


func test_manifest_mismatch_fails_closed_without_partial_rows() -> void:
	var source := _source_snapshot(MANIFEST)
	var inspections := _build_inspections(
		source, _catalog("different.manifest")
	)
	assert_true(inspections.is_empty())


func test_snapshot_clone_out_isolates_nested_inspection_and_stats() -> void:
	var source := _projected_snapshot()
	var first := source.deep_clone()
	first.prepare_unit_inspections[0].trait_ids.append(&"trait.injected")
	first.prepare_unit_inspections[0].equipment_instance_ids.append("i_injected")
	first.prepare_unit_inspections[0].stats.health = 999

	var second := source.deep_clone()
	assert_false(second.prepare_unit_inspections[0].trait_ids.has(&"trait.injected"))
	assert_false(
		second.prepare_unit_inspections[0].equipment_instance_ids.has("i_injected")
	)
	assert_eq(second.prepare_unit_inspections[0].stats.health, 111)


func test_shell_renders_typed_fields_fixed_slots_stats_and_portrait_fallback() -> void:
	var source := _projected_snapshot()
	var shell := _bound_shell(source)
	source.prepare_unit_inspections[0].unit_def_id = &"unit.mutated_after_bind"
	source.prepare_unit_inspections[0].stats.health = 999
	shell.show_prepare_unit(BOARD_ID)
	var panel := shell.find_child("UnitInspector", true, false) as VBoxContainer

	assert_eq(panel.get_meta(&"unit_instance_id"), StringName(BOARD_ID))
	var portrait := panel.find_child("PrepareUnitPortrait", true, false) as TextureRect
	assert_not_null(portrait)
	assert_null(portrait.texture)
	assert_not_null(panel.find_child("PortraitUnavailable", true, false))
	assert_eq(
		(panel.find_child("PrepareUnitName", true, false) as Label).text,
		"棋士甲"
	)
	assert_true(
		(panel.find_child("PrepareUnitStar", true, false) as Label).text.contains("1")
	)
	assert_true(
		(panel.find_child("PrepareUnitCostTier", true, false) as Label).text.contains("3")
	)
	assert_eq(panel.find_children("PrepareTrait_*", "Label", true, false).size(), 2)
	assert_eq(
		(panel.find_child("PrepareUnitAbility", true, false) as Label).text,
		"守護技能"
	)
	var role := panel.find_child("PrepareUnitRole", true, false) as Label
	assert_eq(role.text, "守護者")
	assert_eq(role.get_meta(&"ai_profile"), &"frontline")
	assert_eq(
		(panel.find_child("PrepareEquipmentSlot0", true, false) as Label).text,
		"測試裝備"
	)
	assert_eq(
		(panel.find_child("PrepareEquipmentSlot1", true, false) as Label).text,
		"無"
	)
	assert_eq(
		(panel.find_child("PrepareEquipmentSlot2", true, false) as Label).text,
		"無"
	)
	assert_eq(panel.find_children("PrepareStat_*", "Label", true, false).size(), 9)
	assert_true(
		(panel.find_child("PrepareStat_combat_stat_health", true, false) as Label)
		.text.contains("111")
	)


func test_empty_selection_clears_previous_inspector_state() -> void:
	var shell := _bound_shell(_projected_snapshot())
	shell.show_prepare_unit(BOARD_ID)
	assert_not_null(shell.find_child("PrepareUnitName", true, false))

	shell.show_prepare_unit("u_unknown")
	var panel := shell.find_child("UnitInspector", true, false) as VBoxContainer
	assert_false(panel.has_meta(&"unit_instance_id"))
	assert_null(shell.find_child("PrepareUnitName", true, false))
	assert_null(shell.find_child("PreparePortraitBlock", true, false))
	assert_not_null(shell.find_child("InspectorEmptyState", true, false))


func test_prepare_composition_updates_the_single_mounted_inspector() -> void:
	var screen := RunPrepareScreen.new()
	add_child_autofree(screen)
	var issues: Array[BoardValidationIssue] = []
	assert_eq(
		screen.compose(
			_projected_snapshot(),
			BoardValidationReport.new(2, issues),
			LiveScreenIntentPort.new()
		),
		&""
	)
	var right := screen.find_child(
		"PrepareRightContent", true, false
	) as VBoxContainer
	var right_scroll := screen.find_child(
		"PrepareRightScroll", true, false
	) as ScrollContainer
	var panels := screen.find_children(
		"UnitInspector", "VBoxContainer", true, false
	)
	assert_eq(panels.size(), 1)
	assert_not_null(right)
	assert_not_null(right_scroll)
	var panel := panels[0] as VBoxContainer
	assert_eq(panel.get_parent(), right)
	assert_eq(right.get_parent(), right_scroll)
	assert_eq(panel.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	assert_not_null(panel.find_child("InspectorEmptyState", true, false))

	var selector := screen.find_child(
		"BuildUnitSelector", true, false
	) as ItemList
	assert_not_null(selector)
	var board_index := -1
	for index: int in range(selector.item_count):
		if String(selector.get_item_metadata(index)) == BOARD_ID:
			board_index = index
			break
	assert_gte(board_index, 0)
	selector.select(board_index)
	selector.item_selected.emit(board_index)
	assert_eq(
		panel.get_meta(&"unit_instance_id"), StringName(BOARD_ID)
	)
	assert_eq(
		(panel.get_node(^"PrepareUnitName") as Label).text,
		String(BOARD_DEF)
	)
	assert_true(
		(panel.get_node(^"PrepareUnitStar") as Label).text.contains("1")
	)
	assert_not_null(panel.find_child(
		"PrepareStat_combat_stat_health", true, false
	))
	assert_eq(
		screen.find_children(
			"UnitInspector", "VBoxContainer", true, false
		).size(),
		1
	)

	# A hover preview must never replace the formal selector authority. Exiting
	# the world target restores the selected unit; with no selection it clears.
	screen.call(&"_on_world_unit_hovered", BENCH_ID)
	assert_eq(panel.get_meta(&"unit_instance_id"), StringName(BENCH_ID))
	screen.call(&"_on_world_unit_hovered", "")
	assert_eq(panel.get_meta(&"unit_instance_id"), StringName(BOARD_ID))
	selector.deselect_all()
	screen.call(&"_on_build_unit_selected", -1)
	screen.call(&"_on_world_unit_hovered", BOARD_ID)
	assert_eq(panel.get_meta(&"unit_instance_id"), StringName(BOARD_ID))
	screen.call(&"_on_world_unit_hovered", "")
	assert_false(panel.has_meta(&"unit_instance_id"))
	assert_null(panel.find_child("PrepareUnitName", true, false))
	assert_not_null(panel.find_child("InspectorEmptyState", true, false))
	assert_eq(
		screen.find_children(
			"UnitInspector", "VBoxContainer", true, false
		).size(),
		1
	)


func test_projected_hover_exit_relays_through_surface_and_restores_selector() -> void:
	var screen := RunPrepareScreen.new()
	screen.size = Vector2(1920.0, 1080.0)
	add_child_autofree(screen)
	var issues: Array[BoardValidationIssue] = []
	assert_eq(
		screen.compose(
			_projected_snapshot(),
			BoardValidationReport.new(2, issues),
			LiveScreenIntentPort.new()
		),
		&""
	)
	var panel := screen.find_child(
		"UnitInspector", true, false
	) as VBoxContainer
	var selector := screen.find_child(
		"BuildUnitSelector", true, false
	) as ItemList
	assert_not_null(panel)
	assert_not_null(selector)
	if panel == null or selector == null:
		return
	var bench_index := -1
	for index: int in range(selector.item_count):
		if String(selector.get_item_metadata(index)) == BENCH_ID:
			bench_index = index
			break
	assert_gte(bench_index, 0)
	if bench_index < 0:
		return
	selector.select(bench_index)
	selector.item_selected.emit(bench_index)
	assert_eq(panel.get_meta(&"unit_instance_id"), StringName(BENCH_ID))

	var surface := ProductionWorldSurface.new()
	surface.size = Vector2(640.0, 360.0)
	add_child_autofree(surface)
	var mapper := WindowCoordinateMapper.new()
	assert_eq(
		mapper.configure(
			WorldViewportPolicy.new().layout_for_window(
				Vector2i(1920, 1080)
			),
			100
		),
		&""
	)
	var shell := screen.find_child(
		"InRunHudShell", true, false
	) as InRunHudShell
	assert_not_null(shell)
	if shell == null:
		return
	var overlay_mount := shell.host(ProductionLayoutShell.REGION_OVERLAY)
	assert_not_null(overlay_mount)
	if overlay_mount == null:
		return
	var player_half_validator := func(cell: Vector2i) -> bool:
		return (
			cell.x >= 0
			and cell.x < BoardPreparationValidator.BOARD_WIDTH
			and cell.y >= 0
			and cell.y <= BoardPreparationValidator.PLAYER_MAX_Y
		)
	assert_eq(
		surface.mount_board_snapshot(
			_world_snapshot_for_hover(),
			mapper,
			overlay_mount,
			player_half_validator
		),
		&""
	)
	screen.call(&"_connect_world_surface_inputs")
	var overlay := surface.ui_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	var target := overlay.drag_target()
	assert_not_null(target)
	if target == null:
		return
	var board_screen := mapper.world_to_screen(
		BoardProjection.new().project_cell(Vector2i(0, 0))
	)
	var motion := InputEventMouseMotion.new()
	motion.position = (
		target.get_global_transform_with_canvas().affine_inverse()
		* board_screen
	)
	target.call(&"_gui_input", motion)
	assert_eq(
		panel.get_meta(&"unit_instance_id"),
		StringName(BOARD_ID),
		"target -> overlay -> surface -> prepare screen must preview hover"
	)
	target.mouse_exited.emit()
	assert_eq(
		panel.get_meta(&"unit_instance_id"),
		StringName(BENCH_ID),
		"mouse exit must relay an empty hover and restore selector authority"
	)
	assert_eq(
		screen.find_children(
			"UnitInspector", "VBoxContainer", true, false
		).size(),
		1
	)


func test_shared_hud_does_not_mislabel_trait_tier_or_relic_slots() -> void:
	var snapshot := _projected_snapshot()
	var trait_preview := TraitBattleSnapshot.new()
	trait_preview.trait_id = &"trait.faction_test"
	trait_preview.tier = 2
	trait_preview.member_instance_ids = [StringName(BOARD_ID)]
	snapshot.active_trait_previews = [trait_preview]
	var progress := TraitProgressPresentationSnapshot.new()
	progress.trait_id = trait_preview.trait_id
	progress.current_tier = trait_preview.tier
	progress.member_count = trait_preview.member_instance_ids.size()
	for row: Array in [
		[1, 2, &"effect.trait_1"],
		[2, 4, &"effect.trait_2"],
		[3, 6, &"effect.trait_3"],
	]:
		var threshold := TraitThresholdPresentationSnapshot.new()
		threshold.tier = row[0]
		threshold.required_count = row[1]
		threshold.effect_ids = [row[2] as StringName]
		progress.thresholds.append(threshold)
	snapshot.active_trait_progress.append(progress)
	var shell := _bound_shell(snapshot)
	var traits := shell.find_child("TraitList", true, false) as ItemList
	var relics := shell.find_child("HudRelicSlots", true, false) as ItemList
	assert_not_null(traits)
	assert_not_null(relics)
	assert_eq(traits.item_count, 1)
	assert_false(traits.get_item_text(0).contains("星級"))
	assert_false(traits.get_item_tooltip(0).contains("星級"))
	assert_true(traits.get_item_text(0).begins_with("▶"))
	assert_false(
		traits.get_item_text(0).contains("2"),
		"trait row must not present member/tier numbers as distinct progress"
	)
	var tooltip := traits.get_item_tooltip(0)
	assert_true(tooltip.contains("○ 單位 2 · 階段一"))
	assert_true(tooltip.contains("▶ 單位 4 · 階段二"))
	assert_true(tooltip.contains("○ 單位 6 · 階段三"))
	var left_stack := shell.find_child(
		"InRunLeftStack", true, false
	) as VBoxContainer
	assert_not_null(left_stack)
	for child: Node in left_stack.get_children():
		if child is Label:
			assert_false(
				(child as Label).text.contains("loc.reward_table_slice_relic")
			)
	assert_eq(relics.get_meta(&"typed_data_kind"), &"relic_slot")


func _projected_snapshot() -> RunPresentationSnapshot:
	var source := _source_snapshot(MANIFEST)
	var inspections := _build_inspections(source, _catalog(MANIFEST))
	for inspection: PrepareUnitInspectionSnapshot in inspections:
		source.prepare_unit_inspections.append(inspection.deep_clone())
	return source


func _world_snapshot_for_hover() -> WorldBoardSnapshot:
	var snapshot := WorldBoardSnapshot.new()
	var unit := WorldBoardUnitSnapshot.new()
	unit.presentation_instance_id = StringName(BOARD_ID)
	unit.logical_cell = Vector2i(0, 0)
	unit.sprite_frames = ProductionFrames
	unit.animation = &"idle_n_star1"
	unit.health = 111
	unit.max_health = 111
	unit.mana = 10
	unit.max_mana = 60
	snapshot.append_unit(unit)
	return snapshot


func _build_inspections(
	snapshot: RunPresentationSnapshot,
	catalog: BattleRuleCatalog
) -> Array:
	var session := RunPresentationSession.new()
	session.set(&"_battle_catalog", catalog.deep_clone())
	return session.call(&"_build_prepare_unit_inspections", snapshot)


func _source_snapshot(manifest_digest: String) -> RunPresentationSnapshot:
	var result := RunPresentationSnapshot.new()
	result.manifest_digest = manifest_digest
	result.roster = _roster()
	var board_equipment: Array[String] = [EQUIPMENT_ID]
	var no_equipment: Array[String] = []
	result.unit_stats_previews.append(
		_preview(BOARD_ID, BOARD_DEF, 1, 111, board_equipment)
	)
	result.unit_stats_previews.append(
		_preview(BENCH_ID, BENCH_DEF, 2, 222, no_equipment)
	)
	return result


func _roster() -> RosterState:
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, BOARD_ID),
	]
	var bench: Array[String] = [BENCH_ID]
	var board_equipment: Array[String] = [EQUIPMENT_ID]
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		UnitInstance.new(BENCH_ID, BENCH_DEF, 2, no_equipment, U64Bits.zero()),
		UnitInstance.new(BOARD_ID, BOARD_DEF, 1, board_equipment, U64Bits.zero()),
	]
	var items: Array[ItemInstanceState] = [
		ItemInstanceState.new(
			EQUIPMENT_ID,
			&"equipment.t17",
			OptionalStringValue.new(BOARD_ID),
			U64Bits.zero()
		),
	]
	var empty: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	return RosterState.new(
		BoardState.new(placements), bench, units, items, empty, empty, relics
	)


func _preview(
	instance_id: String,
	unit_id: StringName,
	star: int,
	health: int,
	equipment: Array[String]
) -> UnitStatsPreviewSnapshot:
	var result := UnitStatsPreviewSnapshot.new()
	result.instance_id = StringName(instance_id)
	result.unit_id = unit_id
	result.star = star
	result.health = health
	result.attack = 20
	result.armor = 30
	result.magic_resist = 40
	result.attack_speed_milli = 900
	result.attack_range_cells = 2
	result.start_mana = 10
	result.max_mana = 60
	result.move_speed_milli = 1000
	result.equipment_instance_ids.assign(equipment)
	return result


func _catalog(manifest_digest: String) -> BattleRuleCatalog:
	var board_traits: Array[StringName] = [
		&"trait.faction_test", &"trait.role_guard",
	]
	var bench_traits: Array[StringName] = [
		&"trait.faction_test", &"trait.role_scout",
	]
	var units: Array[BattleUnitRule] = [
		_rule(
			BOARD_DEF, 3, board_traits,
			&"ability.t17_board", &"frontline"
		),
		_rule(
			BENCH_DEF, 5, bench_traits,
			&"ability.t17_bench", &"backline"
		),
	]
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		manifest_digest, units, traits, abilities, effects, encounters,
		equipment, configs
	)


func _rule(
	unit_id: StringName,
	cost_tier: int,
	traits: Array[StringName],
	ability_id: StringName,
	ai_profile: StringName
) -> BattleUnitRule:
	var result := BattleUnitRule.new()
	result.unit_id = unit_id
	result.cost_tier = cost_tier
	result.trait_ids.assign(traits)
	result.ability_id = OptionalStringNameValue.new(ability_id)
	result.ai_profile = ai_profile
	result.basic_attack_profile = &"melee"
	return result


func _bound_shell(snapshot: RunPresentationSnapshot) -> InRunHudShell:
	var shell := InRunHudShell.new()
	add_child_autofree(shell)
	assert_eq(shell.bind(
		snapshot,
		&"RUN_PREPARE",
		Callable(self, "_region_rect"),
		Callable(self, "_ui_text"),
		Callable(self, "_content_text")
	), &"")
	return shell


func _region_rect(_region: StringName) -> Rect2:
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


func _ui_text(key: StringName) -> String:
	return {
		&"prepare.panel.units": "單位",
		&"prepare.panel.synergies": "羈絆",
		&"prepare.panel.party": "隊伍",
		&"prepare.group.forge_equipment": "鍛造裝備",
		&"combat.inspect": "檢視單位",
		&"combat.inspection.none": "無",
		&"combat.stat.star": "星級",
		&"tooltip.cost": "花費",
		&"combat.stat.health": "生命",
		&"combat.stat.attack": "攻擊",
		&"combat.stat.armor": "護甲",
		&"combat.stat.magic_resist": "魔抗",
		&"combat.stat.attack_speed_milli": "攻速",
		&"combat.stat.attack_range_cells": "攻擊距離",
		&"combat.stat.start_mana": "初始法力",
		&"combat.stat.max_mana": "法力上限",
		&"combat.stat.move_speed_milli": "移速",
		&"prepare.panel.expedition": "遠征",
		&"prepare.resource.hp": "遠征生命",
	}.get(key, String(key))


func _content_text(key: StringName) -> String:
	return {
		BOARD_DEF: "棋士甲",
		BENCH_DEF: "棋士乙",
		&"trait.faction_test": "測試陣營",
		&"trait.role_guard": "守護者",
		&"trait.role_scout": "斥候",
		&"ability.t17_board": "守護技能",
		&"ability.t17_bench": "斥候技能",
		&"equipment.t17": "測試裝備",
		&"effect.trait_1": "階段一",
		&"effect.trait_2": "階段二",
		&"effect.trait_3": "階段三",
	}.get(key, String(key))
