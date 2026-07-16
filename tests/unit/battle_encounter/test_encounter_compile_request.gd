extends GutTest

func test_request_has_only_pinned_encounter_and_difficulty_context() -> void:
	var request := EncounterCompileRequest.new()
	var script_fields: Array[String] = []
	for property: Dictionary in request.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			script_fields.append(String(property["name"]))
	script_fields.sort()
	assert_eq(
		script_fields,
		[
			"act_index",
			"challenge_level",
			"depth",
			"encounter_id",
			"manifest_digest",
			"node_id",
		]
	)

func test_request_source_does_not_admit_build_or_rng_inputs() -> void:
	var source := FileAccess.get_file_as_string(
		"res://domain/battle/encounter/encounter_compile_request.gd"
	).to_lower()
	for forbidden: String in [
		"roster",
		"trait",
		"equipment",
		"item",
		"rng",
		"random",
	]:
		assert_eq(source.find(forbidden), -1, forbidden)

func test_request_deep_clone_is_value_isolated() -> void:
	var request := EncounterCompileRequest.new()
	request.manifest_digest = "a".repeat(64)
	request.encounter_id = &"encounter.boss"
	request.node_id = &"node_ascii"
	request.act_index = 2
	request.depth = 4
	request.challenge_level = 5
	var copied := request.deep_clone()
	request.node_id = &"node_changed"
	assert_eq(copied.node_id, &"node_ascii")
	assert_eq(copied.act_index, 2)
	assert_eq(copied.depth, 4)
	assert_eq(copied.challenge_level, 5)
