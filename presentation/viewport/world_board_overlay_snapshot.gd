class_name WorldBoardOverlaySnapshot
extends RefCounted

const INVALID_CELL := Vector2i(-1, -1)

var placements: Array[WorldBoardOverlayPlacement] = []
var drag_preview_visible: bool
var drag_preview_legal: bool
var drag_preview_rect := Rect2()
var drag_preview_source_kind: StringName = &""
var drag_preview_source_cell := INVALID_CELL
var drag_preview_source_slot: int = -1
var drag_preview_target_cell := INVALID_CELL
var drag_preview_source_instance_id: StringName = &""
var drag_preview_target_instance_id: StringName = &""
var drag_preview_swap: bool
var drag_preview_source_rect := Rect2()
var drag_preview_arrow_start := Vector2()
var drag_preview_arrow_end := Vector2()
var error: StringName = &""


func deep_clone() -> WorldBoardOverlaySnapshot:
	var clone := WorldBoardOverlaySnapshot.new()
	for placement: WorldBoardOverlayPlacement in placements:
		clone.placements.append(placement.deep_clone())
	clone.drag_preview_visible = drag_preview_visible
	clone.drag_preview_legal = drag_preview_legal
	clone.drag_preview_rect = drag_preview_rect
	clone.drag_preview_source_kind = drag_preview_source_kind
	clone.drag_preview_source_cell = drag_preview_source_cell
	clone.drag_preview_source_slot = drag_preview_source_slot
	clone.drag_preview_target_cell = drag_preview_target_cell
	clone.drag_preview_source_instance_id = drag_preview_source_instance_id
	clone.drag_preview_target_instance_id = drag_preview_target_instance_id
	clone.drag_preview_swap = drag_preview_swap
	clone.drag_preview_source_rect = drag_preview_source_rect
	clone.drag_preview_arrow_start = drag_preview_arrow_start
	clone.drag_preview_arrow_end = drag_preview_arrow_end
	clone.error = error
	return clone


func placement_for(
	presentation_instance_id: StringName
) -> WorldBoardOverlayPlacement:
	for placement: WorldBoardOverlayPlacement in placements:
		if placement.presentation_instance_id == presentation_instance_id:
			return placement.deep_clone()
	return null
