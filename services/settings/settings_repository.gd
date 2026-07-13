class_name SettingsRepository
extends Node

signal settings_changed

const MIN_VOLUME_DB: float = -80.0
const MAX_VOLUME_DB: float = 6.0

var _master_volume_db: float = 0.0
var _pixel_scale: int = 1


func master_volume_db() -> float:
	return _master_volume_db


func set_master_volume_db(value: float) -> bool:
	if is_nan(value) or is_inf(value):
		return false
	_master_volume_db = clampf(value, MIN_VOLUME_DB, MAX_VOLUME_DB)
	settings_changed.emit()
	return true


func pixel_scale() -> int:
	return _pixel_scale


func set_pixel_scale(value: int) -> bool:
	if value < 1 or value > 4:
		return false
	_pixel_scale = value
	settings_changed.emit()
	return true

