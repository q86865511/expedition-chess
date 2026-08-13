class_name WorldBoardSnapshot
extends RefCounted

const BOARD_SIZE := Vector2i(
	BoardPreparationValidator.BOARD_WIDTH,
	BoardPreparationValidator.BOARD_HEIGHT
)

var units: Array[WorldBoardUnitSnapshot] = []
var drag_preview_visible: bool
var drag_preview_cell := Vector2i(-1, -1)
var drag_preview_legal: bool


func append_unit(unit: WorldBoardUnitSnapshot) -> void:
	if unit != null:
		units.append(unit.deep_clone())


func deep_clone() -> WorldBoardSnapshot:
	var clone := WorldBoardSnapshot.new()
	for unit: WorldBoardUnitSnapshot in units:
		if unit != null:
			clone.units.append(unit.deep_clone())
	clone.drag_preview_visible = drag_preview_visible
	clone.drag_preview_cell = drag_preview_cell
	clone.drag_preview_legal = drag_preview_legal
	return clone


func is_valid() -> bool:
	var seen_ids: Dictionary = {}
	var seen_cells: Dictionary = {}
	for unit: WorldBoardUnitSnapshot in units:
		if unit == null or not unit.is_valid():
			return false
		if seen_ids.has(unit.presentation_instance_id):
			return false
		if seen_cells.has(unit.logical_cell):
			return false
		seen_ids[unit.presentation_instance_id] = true
		seen_cells[unit.logical_cell] = true
	if drag_preview_visible and not _cell_in_footprint(drag_preview_cell):
		return false
	return true


func _cell_in_footprint(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.x < BOARD_SIZE.x
		and cell.y >= 0
		and cell.y < BOARD_SIZE.y
	)
