extends GutTest

const RUN_LAB_PATH := "res://scripts/dev/run/run_lab_session.gd"
const COMBAT_LAB_PATH := "res://scripts/dev/combat_lab/combat_lab_session.gd"

const FORBIDDEN_RUN_LAB_RULE_TOKENS: Array[String] = [
	"RunController",
	"RunCommandFactory",
	"ChooseRewardCommand.new(",
	"ResolveUnitRewardCommand.new(",
	"ResolveItemRewardCommand.new(",
	"ResolveRelicRewardCommand.new(",
	"AdvanceRewardCommand.new(",
	"AbandonExpeditionCommand.new(",
	"StartCombatEvent.new(",
]

const FORBIDDEN_COMBAT_LAB_RULE_TOKENS: Array[String] = [
	"BattleSimulation.new(",
]


func test_run_lab_is_a_thin_consumer_of_the_production_facade() -> void:
	var source := _source(RUN_LAB_PATH)

	assert_true(
		source.contains("RunPresentationSession"),
		"Run Lab must consume the production RunPresentationSession"
	)
	for token: String in FORBIDDEN_RUN_LAB_RULE_TOKENS:
		assert_false(
			source.contains(token),
			"Run Lab must not retain a second writer/rule path: %s" % token
		)


func test_combat_lab_consumes_an_injected_production_battle_port() -> void:
	var source := _source(COMBAT_LAB_PATH)

	assert_true(
		source.contains("BattleSimulationPort")
			or source.contains("BattlePresentationPort")
			or source.contains("CombatLabBattlePort"),
		"Combat Lab must depend on an injected typed production battle port"
	)
	for token: String in FORBIDDEN_COMBAT_LAB_RULE_TOKENS:
		assert_false(
			source.contains(token),
			"Combat Lab must not instantiate a second battle-rules engine: %s" % token
		)


func test_dev_component_wrappers_do_not_own_cli_parse_or_app_root_binding() -> void:
	var combined := "%s\n%s" % [_source(RUN_LAB_PATH), _source(COMBAT_LAB_PATH)]

	assert_false(
		combined.contains("--combat-lab"),
		"T04 wrappers are components; exact CLI allowlist parsing belongs to T05"
	)
	assert_false(
		combined.contains("ApplicationRoot") or combined.contains("AppRoot"),
		"T04 wrappers must not bind the composition root"
	)


func _source(path: String) -> String:
	assert_true(FileAccess.file_exists(path), "required source missing: %s" % path)
	return FileAccess.get_file_as_string(path)
