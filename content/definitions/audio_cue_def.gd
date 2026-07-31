class_name AudioCueDef
extends ContentDefinition

@export var bus: StringName
@export_file("*.ogg") var stream_path: String
@export var loop: bool

func category_name() -> StringName:
	return &"audio_cue"
