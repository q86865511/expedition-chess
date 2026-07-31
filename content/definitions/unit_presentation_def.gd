class_name UnitPresentationDef
extends ContentDefinition

@export_file("*.png") var portrait_path: String
@export_file("*.tres") var sprite_frames_path: String
@export_file("*.png") var board_icon_path: String
@export_file("*.png") var ability_icon_path: String
@export var combat_vfx_refs: Array[StringName] = []
@export var audio_cue_refs: Array[StringName] = []

func category_name() -> StringName:
	return &"unit_presentation"
