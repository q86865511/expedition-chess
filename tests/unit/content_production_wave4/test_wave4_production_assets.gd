extends GutTest

const VALIDATOR_PATH := "res://tools/content-production/production_asset_validator.gd"
const INVENTORY_PATH := "res://assets/production/inventory.json"
const ATTEMPT_LEDGER_PATH := "res://assets/production/production-asset-attempts.json"


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
	assert_eq(report.get("animation_count_per_unit", 0), 72)
	assert_eq(report.get("inventory_status", ""), "adopted")
	assert_lte(report.get("max_player_silhouette_iou", 1.0), 0.92)
	assert_lte(report.get("max_player_ssim", 1.0), 0.95)


func test_attempt_ledger_has_one_independently_reviewed_adoption_per_unit() -> void:
	var validator_script := load(VALIDATOR_PATH) as GDScript
	assert_not_null(validator_script)
	if validator_script == null:
		return
	var validator: RefCounted = validator_script.new()
	assert_true(validator.has_method("validate_attempt_ledger"))
	if not validator.has_method("validate_attempt_ledger"):
		return
	var report: Dictionary = validator.validate_attempt_ledger(
		ATTEMPT_LEDGER_PATH,
		INVENTORY_PATH
	)
	assert_true(report.get("ok", false), JSON.stringify(report.get("issues", [])))
	assert_eq(report.get("unit_count", 0), 44)
	assert_eq(report.get("adopted_count", 0), 44)
	assert_eq(report.get("unreviewed_count", -1), 0)
	assert_eq(report.get("duplicate_call_id_count", -1), 0)


func test_sprite_frames_expose_action_direction_star_animation_grammar() -> void:
	var frames := load("res://assets/production/units/slice_player_00.tres") as SpriteFrames
	assert_not_null(frames)
	if frames == null:
		return
	assert_eq(frames.get_animation_names().size(), 72)
	var expected := {
		"idle": {"frames": 2, "speed": 4.0, "loop": true},
		"move": {"frames": 4, "speed": 8.0, "loop": true},
		"attack": {"frames": 4, "speed": 10.0, "loop": false},
		"cast": {"frames": 4, "speed": 10.0, "loop": false},
		"hit": {"frames": 2, "speed": 8.0, "loop": false},
		"death": {"frames": 4, "speed": 8.0, "loop": false},
	}
	var total_frames := 0
	for star in range(1, 4):
		for direction in ["n", "e", "s", "w"]:
			for action: String in expected:
				var animation := StringName("%s_%s_star%d" % [action, direction, star])
				assert_true(frames.has_animation(animation), String(animation))
				if not frames.has_animation(animation):
					continue
				var contract: Dictionary = expected[action]
				assert_eq(frames.get_frame_count(animation), contract.frames)
				assert_eq(frames.get_animation_speed(animation), contract.speed)
				assert_eq(frames.get_animation_loop(animation), contract.loop)
				total_frames += frames.get_frame_count(animation)
	assert_eq(total_frames, 240)


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
