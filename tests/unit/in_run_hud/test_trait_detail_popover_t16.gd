extends GutTest

const EVIDENCE_PATH := (
	"res://specs/in-run-hud/evidence/p8-batch2/t16-trait-detail-popover.png"
)


class TraitSupplySession:
	extends RunPresentationSession

	var rows: Array[TraitProgressSnapshot] = []


	func trait_progress() -> Array[TraitProgressSnapshot]:
		var result: Array[TraitProgressSnapshot] = []
		for row: TraitProgressSnapshot in rows:
			result.append(row.deep_clone())
		return result


func test_supply_progress_renders_inactive_and_active_rows_with_detail_popover() -> void:
	var snapshot := _snapshot()
	var session := TraitSupplySession.new()
	session.rows = [_inactive_progress(), _active_progress()]
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 16)
	var port := LiveScreenSupplyPort.new(lease, registry, session)
	var shell := InRunHudShell.new()
	add_child_autofree(shell)
	assert_eq(shell.bind(
		snapshot,
		&"RUN_PREPARE",
		Callable(self, &"_region_rect"),
		Callable(self, &"_ui_text"),
		Callable(self, &"_content_text"),
		port
	), &"")

	var traits := shell.find_child("TraitList", true, false) as ItemList
	assert_not_null(traits)
	if traits == null:
		return
	assert_eq(traits.item_count, 2, "inactive rows must survive the supply boundary")
	assert_true(traits.get_item_text(0).begins_with("○"))
	assert_true(traits.get_item_text(0).contains("0/2"))
	assert_true(traits.get_item_text(1).begins_with("◆"))
	assert_true(traits.get_item_text(1).contains("2/4"))
	assert_true(traits.get_item_tooltip(0).contains("○ 羈絆"))
	assert_true(traits.get_item_tooltip(1).contains("◆ 羈絆"))

	traits.select(1)
	traits.item_selected.emit(1)
	await get_tree().process_frame
	var popover := shell.find_child(
		"TraitDetailPopover", true, false
	) as PanelContainer
	assert_not_null(popover)
	if popover == null:
		return
	assert_eq(popover.get_meta(&"trait_id"), &"trait.active")
	assert_eq(popover.get_meta(&"non_color_tier_signal"), "◆")
	var cues := popover.find_child("TraitTierCues", true, false) as HBoxContainer
	assert_not_null(cues)
	if cues != null:
		assert_eq(cues.get_meta(&"non_color_cue"), &"tier-shapes")
		assert_eq(cues.get_child_count(), 2)
		assert_true(bool(cues.get_child(0).get_meta(&"reached")))
		assert_false(bool(cues.get_child(1).get_meta(&"reached")))
	var members := popover.find_child("TraitMemberGrid", true, false) as GridContainer
	assert_not_null(members)
	if members != null:
		assert_eq(members.get_child_count(), 2)
		for child: Node in members.get_children():
			var card := child as PanelContainer
			assert_true(bool(card.get_meta(&"held")))
			assert_eq(card.get_meta(&"non_color_cue"), &"owned-diamond-frame")
			assert_not_null(card.find_child("Portrait", true, false))
			assert_not_null(card.find_child("OwnedCue", true, false))
	var safe_rect := popover.get_meta(&"safe_area_rect") as Rect2
	assert_true(safe_rect.encloses(Rect2(popover.position, popover.size)))
	assert_true(bool(popover.get_meta(&"flipped_horizontal")))
	assert_true(bool(popover.get_meta(&"flipped_vertical")))
	assert_lte(popover.size.y, 1080.0 - ProductionLayoutShell.SAFE_MARGIN * 2.0)
	if DisplayServer.get_name() != "headless":
		await wait_process_frames(2)
		var image := get_viewport().get_texture().get_image()
		assert_not_null(image)
		if image != null:
			assert_eq(
				image.save_png(ProjectSettings.globalize_path(EVIDENCE_PATH)),
				OK
			)


func test_trait_model_builder_clones_supply_data_at_single_hook() -> void:
	var shell := InRunHudShell.new()
	add_child_autofree(shell)
	assert_eq(shell.bind(
		_snapshot(),
		&"RUN_PREPARE",
		Callable(self, &"_region_rect"),
		Callable(self, &"_ui_text"),
		Callable(self, &"_content_text")
	), &"")
	var source: Array[TraitProgressSnapshot] = [_active_progress()]
	var models := shell.call(&"_trait_popover_models", source) as Array
	assert_eq(models.size(), 1)
	source[0].trait_id = &"trait.mutated"
	source[0].member_instance_ids.clear()
	source[0].thresholds[0].required_count = 99
	var model := models[0] as Dictionary
	assert_eq(model.get("trait_id"), &"trait.active")
	assert_eq((model.get("members") as Array).size(), 2)
	assert_eq(
		int(((model.get("thresholds") as Array)[0] as Dictionary).get("required_count")),
		2
	)


func _snapshot() -> RunPresentationSnapshot:
	var result := RunPresentationSnapshot.new()
	result.app_phase = &"PREPARE"
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, "unit.a"),
		BoardPlacementState.new(0, 1, "unit.b"),
	]
	var units: Array[UnitInstance] = [
		UnitInstance.new("unit.a", &"unit.slice_player_00", 1, [], U64Bits.zero()),
		UnitInstance.new("unit.b", &"unit.slice_player_01", 1, [], U64Bits.one()),
	]
	var strings: Array[String] = []
	var items: Array[ItemInstanceState] = []
	var relics: Array[RelicSlotState] = []
	result.roster = RosterState.new(
		BoardState.new(placements), strings, units, items, strings, strings, relics
	)
	return result


func _inactive_progress() -> TraitProgressSnapshot:
	var progress := TraitProgressSnapshot.new()
	progress.trait_id = &"trait.inactive"
	progress.distinct_count = 0
	progress.active_tier = 0
	progress.next_required_count = 2
	progress.thresholds.append(_threshold(1, 2, &"effect.inactive"))
	return progress


func _active_progress() -> TraitProgressSnapshot:
	var progress := TraitProgressSnapshot.new()
	progress.trait_id = &"trait.active"
	progress.distinct_count = 2
	progress.active_tier = 1
	progress.next_required_count = 4
	progress.member_instance_ids.assign([&"unit.a", &"unit.b"])
	progress.thresholds.append(_threshold(1, 2, &"effect.active_1"))
	progress.thresholds.append(_threshold(2, 4, &"effect.active_2"))
	return progress


func _threshold(
	tier: int,
	required_count: int,
	effect_id: StringName
) -> TraitProgressThresholdSnapshot:
	var threshold := TraitProgressThresholdSnapshot.new()
	threshold.tier = tier
	threshold.required_count = required_count
	threshold.effect_ids.assign([effect_id])
	return threshold


func _region_rect(region: StringName) -> Rect2:
	if region == ProductionLayoutShell.REGION_LEFT:
		return Rect2(1680.0, 880.0, 200.0, 150.0)
	if region == ProductionLayoutShell.REGION_OVERLAY:
		return Rect2(Vector2.ZERO, Vector2(1920.0, 1080.0))
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


func _ui_text(key: StringName) -> String:
	return {
		&"prepare.panel.synergies": "羈絆",
		&"prepare.panel.inventory": "裝備庫",
		&"prepare.panel.units": "單位",
		&"prepare.panel.expedition": "遠征",
		&"prepare.resource.hp": "遠征生命",
		&"combat.inspection.none": "無",
	}.get(key, String(key))


func _content_text(key: StringName) -> String:
	return {
		&"trait.active": "啟用羈絆",
		&"trait.inactive": "未啟用羈絆",
		&"unit.slice_player_00": "先鋒甲",
		&"unit.slice_player_01": "先鋒乙",
		&"effect.active_1": "第一階效果",
		&"effect.active_2": "第二階效果",
		&"effect.inactive": "未啟用效果",
	}.get(key, String(key))
