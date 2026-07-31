extends GutTest

const VALIDATOR_PATH := "res://tools/content-production/production_asset_validator.gd"
const INVENTORY_PATH := "res://assets/production/inventory.json"


func test_production_asset_inventory_passes_formal_contract() -> void:
	assert_true(FileAccess.file_exists(VALIDATOR_PATH), "production asset validator is required")
	if not FileAccess.file_exists(VALIDATOR_PATH):
		return
	var validator_script := load(VALIDATOR_PATH) as GDScript
	assert_not_null(validator_script)
	if validator_script == null:
		return
	var report: Dictionary = validator_script.new().validate(INVENTORY_PATH)
	assert_true(report.get("ok", false), JSON.stringify(report.get("issues", [])))
	assert_eq(report.get("unit_count", 0), 44)
	assert_eq(report.get("frames_per_unit", 0), 240)
	assert_eq(report.get("shared_atlas_count", 0), 5)
	assert_gte(report.get("distinct_alpha_bounds", 0), 5)


func test_formal_unit_presentations_only_reference_adopted_assets() -> void:
	assert_true(FileAccess.file_exists(VALIDATOR_PATH), "production asset validator is required")
	if not FileAccess.file_exists(VALIDATOR_PATH):
		return
	var validator_script := load(VALIDATOR_PATH) as GDScript
	var report: Dictionary = validator_script.new().validate_presentations(
		"res://content/packs/vertical_slice/unit_presentations",
		INVENTORY_PATH
	)
	assert_true(report.get("ok", false), JSON.stringify(report.get("issues", [])))
	assert_eq(report.get("presentation_count", 0), 44)
