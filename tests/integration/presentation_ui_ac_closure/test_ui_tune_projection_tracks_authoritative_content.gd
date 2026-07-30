extends GutTest

const Support := preload(
	"res://tests/integration/presentation_ui_ac_closure/ac_closure_test_support.gd"
)


func test_ui_tune_projection_tracks_authoritative_content() -> void:
	var result_source := FileAccess.get_file_as_string(Support.BOOTSTRAP_RESULT_PATH)
	assert_true(
		result_source.contains("func maximum_population() -> int"),
		"AC-049 requires bootstrap to expose ContentValidator's authoritative population"
	)
	var script := Support.load_script(
		self,
		Support.TUNE_VIEW_MODEL_PATH,
		"AC-049 authoritative TUNE projection"
	)
	if script == null:
		return
	var source := FileAccess.get_file_as_string(Support.TUNE_VIEW_MODEL_PATH)
	assert_true(
		source.contains("content.maximum_population()"),
		"RunTuneViewModel.from_content must consume the authoritative bootstrap value"
	)
	assert_false(
		source.contains("MAX_PARTY") or source.contains("PARTY_LIMIT"),
		"UI projection must not declare a duplicate party-limit TUNE"
	)
	var twelve: Variant = script.new(12)
	var thirteen: Variant = script.new(13)
	if not Support.require_methods(
		self,
		twelve,
		[&"population_limit", &"population_limit_text"],
		"RunTuneViewModel"
	):
		return
	assert_eq(twelve.call(&"population_limit"), 12)
	assert_eq(twelve.call(&"population_limit_text"), "12")
	assert_eq(thirteen.call(&"population_limit"), 13)
	assert_eq(thirteen.call(&"population_limit_text"), "13")
