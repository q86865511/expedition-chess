class_name SettingsSnapshot
extends RefCounted

const LOCALE_EN: StringName = &"en"
const COLOR_VISION_PROTANOPIA: StringName = &"protanopia"
const COLOR_VISION_DEUTERANOPIA: StringName = &"deuteranopia"
const COLOR_VISION_TRITANOPIA: StringName = &"tritanopia"
const DENSITY_OFF: StringName = &"off"
const DENSITY_REDUCED: StringName = &"reduced"
const DENSITY_FULL: StringName = &"full"

var schema_version: int = 1
var locale: StringName = &"zh_TW"
var ui_scale_percent: int = 100
var color_vision_mode: StringName = &"default"
var reduced_motion: bool = false
var reduced_flash: bool = false
var reduced_particles: bool = false
var damage_number_density: StringName = &"full"
var master_volume_bps: int = 10000
var master_muted: bool = false
var music_volume_bps: int = 10000
var music_muted: bool = false
var sfx_volume_bps: int = 10000
var sfx_muted: bool = false
var ui_volume_bps: int = 10000
var ui_muted: bool = false


func deep_clone() -> SettingsSnapshot:
	var clone := SettingsSnapshot.new()
	clone.schema_version = schema_version
	clone.locale = locale
	clone.ui_scale_percent = ui_scale_percent
	clone.color_vision_mode = color_vision_mode
	clone.reduced_motion = reduced_motion
	clone.reduced_flash = reduced_flash
	clone.reduced_particles = reduced_particles
	clone.damage_number_density = damage_number_density
	clone.master_volume_bps = master_volume_bps
	clone.master_muted = master_muted
	clone.music_volume_bps = music_volume_bps
	clone.music_muted = music_muted
	clone.sfx_volume_bps = sfx_volume_bps
	clone.sfx_muted = sfx_muted
	clone.ui_volume_bps = ui_volume_bps
	clone.ui_muted = ui_muted
	return clone
