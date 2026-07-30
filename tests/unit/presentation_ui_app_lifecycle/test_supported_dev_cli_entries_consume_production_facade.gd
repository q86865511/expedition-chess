extends GutTest

const Support = preload("res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd")
const ROOT_PATH := "res://app/app_root.gd"
const COMBAT_WRAPPER_PATH := "res://scripts/dev/combat_lab/combat_lab_session.gd"


func test_supported_dev_cli_entries_consume_production_facade() -> void:
	var root_source := Support.source(ROOT_PATH)
	var wrapper_source := Support.source(COMBAT_WRAPPER_PATH)
	var flags := _command_line_flags(root_source)

	assert_eq(
		flags,
		["--combat-lab"],
		"the exact supported dev CLI allowlist contains only --combat-lab"
	)
	assert_true(
		root_source.contains("ProjectContentBootstrap"),
		"CLI and production boot must consume the same production bootstrap"
	)
	assert_true(
		root_source.contains("RunPresentationSession")
			or root_source.contains("RunPresentationSessionPort"),
		"composition root must bind the production facade/battle ports into the dev consumer"
	)
	assert_false(
		root_source.contains("BuildLabContentBootstrap"),
		"AppRoot may not retain the dev content bootstrap"
	)
	assert_false(
		root_source.contains("ContentValidator.new(")
			or root_source.contains("install_validated("),
		"CLI integration may not construct a second validation/install graph"
	)
	assert_true(
		root_source.contains("_content_bootstrap")
			or root_source.contains("ProjectContentBootstrap.new("),
		"production bootstrap must be an injected/countable composition dependency"
	)
	assert_true(
		root_source.contains("_content_bootstrap_receipt")
			or root_source.contains("_content_bootstrap_result")
			or root_source.contains("_content"),
		"the validated bootstrap result must be reused rather than run twice"
	)
	assert_true(
		wrapper_source.contains("RunPresentationSession")
			or wrapper_source.contains("RunPresentationSessionPort"),
		"Combat Lab wrapper must consume the production facade boundary"
	)
	assert_false(
		wrapper_source.contains("RunController.new(")
			or wrapper_source.contains("BattleSimulation.new("),
		"dev wrapper may not own a second command/simulation flow"
	)
	assert_false(
		root_source.contains("SceneTree.quit(") or root_source.contains("get_tree().quit("),
		"headless CLI composition must not terminate the test runner"
	)


func _command_line_flags(source_text: String) -> Array[String]:
	var flags: Array[String] = []
	var expression := RegEx.new()
	expression.compile("--[a-z0-9-]+")
	for match_value: RegExMatch in expression.search_all(source_text):
		var flag := match_value.get_string()
		if not flags.has(flag):
			flags.append(flag)
	flags.sort()
	return flags
