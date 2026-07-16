class_name EffectTrigger
extends RefCounted

const VALUES: Array[StringName] = [
	&"battle_start", &"attack", &"hit", &"damaged", &"cast", &"kill", &"death",
	&"periodic", &"battle_end",
]

var kind: StringName

func _init(p_kind: StringName) -> void:
	kind = p_kind

func is_valid() -> bool:
	return VALUES.has(kind)

func deep_clone() -> EffectTrigger:
	return EffectTrigger.new(kind)
