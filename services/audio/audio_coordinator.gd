class_name AudioCoordinator
extends Node

var _muted: bool = false


func set_muted(value: bool) -> void:
	_muted = value
	var master_index: int = AudioServer.get_bus_index(&"Master")
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, value)


func is_muted() -> bool:
	return _muted

