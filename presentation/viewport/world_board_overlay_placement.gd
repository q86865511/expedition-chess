class_name WorldBoardOverlayPlacement
extends RefCounted

var presentation_instance_id: StringName = &""
var screen_foot_position := Vector2.ZERO
var health_rect := Rect2()
var mana_rect := Rect2()
var selection_rect := Rect2()
var health_ratio: float
var mana_ratio: float
var hud_visible: bool
var selected: bool


func deep_clone() -> WorldBoardOverlayPlacement:
	var clone := WorldBoardOverlayPlacement.new()
	clone.presentation_instance_id = presentation_instance_id
	clone.screen_foot_position = screen_foot_position
	clone.health_rect = health_rect
	clone.mana_rect = mana_rect
	clone.selection_rect = selection_rect
	clone.health_ratio = health_ratio
	clone.mana_ratio = mana_ratio
	clone.hud_visible = hud_visible
	clone.selected = selected
	return clone
