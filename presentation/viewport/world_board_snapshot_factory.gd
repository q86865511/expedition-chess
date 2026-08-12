class_name WorldBoardSnapshotFactory
extends RefCounted

## Converts immutable presentation clones into renderer DTOs. No domain rule is
## reimplemented here: prepare stats come only from UnitStatsPreviewSnapshot;
## combat stats/cells come only from CombatUnitInspectionSnapshot.

var _visuals := ProductionUnitVisualCatalog.new()


func build_prepare(
	snapshot: RunPresentationSnapshot,
	board: BoardState
) -> WorldBoardSnapshot:
	var result := WorldBoardSnapshot.new()
	if snapshot == null or snapshot.roster == null or board == null:
		return _invalid_snapshot(result)
	# These arrays are canonical clones, not sparse presentation caches. A null
	# entry means the source is malformed even when that entry is not referenced
	# by the board, so fail the whole build instead of accepting a partial view.
	for unit: UnitInstance in snapshot.roster.unit_instances:
		if unit == null:
			return _invalid_snapshot(result)
	for preview: UnitStatsPreviewSnapshot in snapshot.unit_stats_previews:
		if preview == null:
			return _invalid_snapshot(result)
	for placement: BoardPlacementState in board.placements:
		if placement == null:
			return _invalid_snapshot(result)
		var dto := WorldBoardUnitSnapshot.new()
		dto.presentation_instance_id = StringName(placement.unit_instance_id)
		dto.logical_cell = Vector2i(placement.logical_x, placement.logical_y)
		var unit := _find_unit(snapshot, placement.unit_instance_id)
		if unit == null:
			# Preserve the canonical placement as an invalid renderer DTO. An empty
			# or partial snapshot would otherwise look like a successful build and
			# leave a previously mounted board visible.
			return _invalid_snapshot(result, dto)
		var visual := _visual_for(unit.def_id, unit.star)
		dto.sprite_frames = visual["frames"] as SpriteFrames
		dto.animation = visual["animation"] as StringName
		var preview := _find_preview(snapshot, unit.instance_id)
		dto.overlay_visible = preview != null
		if preview != null:
			dto.health = preview.health
			dto.max_health = maxi(1, preview.health)
			dto.mana = preview.start_mana
			dto.max_mana = maxi(1, preview.max_mana)
		result.append_unit(dto)
		if not dto.is_valid():
			# Stop at the first missing/malformed visual. Keeping this invalid DTO
			# makes WorldBoardSnapshot.is_valid() fail, so the formal surface rejects
			# the entire build and clears its previous renderer state atomically.
			return result
	return result


func build_combat(snapshot: RunPresentationSnapshot) -> WorldBoardSnapshot:
	var result := WorldBoardSnapshot.new()
	if snapshot == null:
		return _invalid_snapshot(result)
	if snapshot.combat_inspections.is_empty():
		# Active combat setup must provide typed visual/stat authority. A freshly
		# rebuilt presentation session at BATTLE_RESULT_PENDING is different: the
		# canonical result has already committed and intentionally carries no setup
		# or transcript. Permit only that typed summary-recovery state to mount a
		# genuinely empty world so the first-frame/settlement contract can finish.
		if not _is_committed_summary_recovery(snapshot):
			return _invalid_snapshot(result)
		return result
	for inspection: CombatUnitInspectionSnapshot in snapshot.combat_inspections:
		if inspection == null:
			return _invalid_snapshot(result)
		var dto := WorldBoardUnitSnapshot.new()
		# Transcript events address units by the stable presentation instance
		# identity. A serial-derived fallback cannot be joined back to those
		# payloads, so an absent identity must fail closed at the setup boundary.
		dto.presentation_instance_id = inspection.presentation_instance_id
		dto.logical_cell = inspection.logical_cell
		var star := int(inspection.stats.get("star", 1))
		var visual := _visual_for(inspection.source_id, star)
		dto.sprite_frames = visual["frames"] as SpriteFrames
		dto.animation = visual["animation"] as StringName
		dto.health = int(inspection.stats.get("health", 0))
		dto.max_health = maxi(1, dto.health)
		dto.mana = int(inspection.stats.get("start_mana", 0))
		dto.max_mana = maxi(1, int(inspection.stats.get("max_mana", 0)))
		result.append_unit(dto)
		if not dto.is_valid():
			return result
	return result


func _invalid_snapshot(
	result: WorldBoardSnapshot,
	sentinel: WorldBoardUnitSnapshot = null
) -> WorldBoardSnapshot:
	# WorldBoardSnapshot deliberately permits a genuinely empty board. Append a
	# typed, invalid unit sentinel so malformed input cannot collapse into that
	# valid empty state. append_unit() clones it, preserving factory isolation.
	result.append_unit(
		sentinel if sentinel != null else WorldBoardUnitSnapshot.new()
	)
	return result


func _is_committed_summary_recovery(snapshot: RunPresentationSnapshot) -> bool:
	return (
		snapshot.app_phase == &"COMBAT"
		and snapshot.view != null
		and snapshot.view.resolution_kind
			== ResolutionState.Kind.BATTLE_RESULT_PENDING
	)


func _visual_for(unit_def_id: StringName, star: int) -> Dictionary:
	var frames := _visuals.try_sprite_frames(unit_def_id)
	var animation := _visuals.idle_animation(frames, star)
	return {"frames": frames, "animation": animation}


func _find_unit(snapshot: RunPresentationSnapshot, instance_id: String) -> UnitInstance:
	for unit: UnitInstance in snapshot.roster.unit_instances:
		if unit != null and unit.instance_id == instance_id:
			return unit
	return null


func _find_preview(
	snapshot: RunPresentationSnapshot,
	instance_id: String
) -> UnitStatsPreviewSnapshot:
	for preview: UnitStatsPreviewSnapshot in snapshot.unit_stats_previews:
		if preview != null and String(preview.instance_id) == instance_id:
			return preview
	return null
