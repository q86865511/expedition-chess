class_name BoardState
extends RefCounted

var placements: Array[BoardPlacementState] = []

func _init(p_placements: Array[BoardPlacementState]) -> void:
	for placement: BoardPlacementState in p_placements:
		placements.append(placement.deep_clone())

func deep_clone() -> BoardState:
	return BoardState.new(placements)
