class_name AudioBusAssignment
extends RefCounted

var bus: StringName
var volume_bps: int
var volume_db: float
var muted: bool


func _init(
	p_bus: StringName,
	p_volume_bps: int,
	p_volume_db: float,
	p_muted: bool
) -> void:
	bus = p_bus
	volume_bps = p_volume_bps
	volume_db = p_volume_db
	muted = p_muted


func deep_clone() -> AudioBusAssignment:
	return AudioBusAssignment.new(bus, volume_bps, volume_db, muted)
