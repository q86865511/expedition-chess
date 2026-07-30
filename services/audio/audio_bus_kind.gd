class_name AudioBusKind
extends RefCounted

enum Kind {
	MASTER,
	MUSIC,
	SFX,
	UI,
}

const MASTER: StringName = &"Master"
const MUSIC: StringName = &"Music"
const SFX: StringName = &"SFX"
const UI: StringName = &"UI"


static func name_for(kind: Kind) -> StringName:
	match kind:
		Kind.MASTER:
			return MASTER
		Kind.MUSIC:
			return MUSIC
		Kind.SFX:
			return SFX
		Kind.UI:
			return UI
	return &""


static func ordered_names() -> Array[StringName]:
	return [MASTER, MUSIC, SFX, UI]
