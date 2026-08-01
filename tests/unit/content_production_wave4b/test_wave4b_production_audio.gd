extends GutTest

const VALIDATOR_PATH := "res://tools/content-production/production_asset_validator.gd"
const AUDIO_INVENTORY_PATH := "res://assets/production/audio/inventory.json"


func test_production_audio_inventory_passes_locked_ogg_contract() -> void:
	var validator: RefCounted = (load(VALIDATOR_PATH) as GDScript).new()
	assert_true(validator.has_method("validate_audio"), "audio validator contract is required")
	if not validator.has_method("validate_audio"):
		return
	var report: Dictionary = validator.validate_audio(AUDIO_INVENTORY_PATH)
	assert_true(report.get("ok", false), JSON.stringify(report.get("issues", [])))
	assert_eq(report.get("music_count", 0), 5)
	assert_eq(report.get("sfx_count", 0), 21)
	assert_eq(report.get("sample_rate", 0), 48000)
	assert_eq(report.get("channels", 0), 2)
	assert_eq(report.get("vorbis_quality", 0.0), 0.5)
	assert_eq(report.get("music_seconds", 0), 24)
	assert_lte(report.get("max_true_peak_dbfs", 0.0), -1.0)
	assert_lte(report.get("max_loop_seam_rms_dbfs", 0.0), -45.0)
	assert_eq(report.get("container", ""), "OGG")
	assert_eq(report.get("codec", ""), "VORBIS")
