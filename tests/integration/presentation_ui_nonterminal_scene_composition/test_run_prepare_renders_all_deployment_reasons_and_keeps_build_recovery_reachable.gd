extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)

const SCENE_PATH := "res://scenes/production/run_prepare.tscn"


func test_run_prepare_renders_all_deployment_reasons_and_keeps_build_recovery_reachable() -> void:
	if Support.require_script(
		self,
		Support.RUN_PREPARE_SCREEN_PATH,
		"AC-004/005/017 RUN_PREPARE composition"
	) == null:
		return
	var invalid_screen: Object = Support.instantiate_scene(
		self,
		SCENE_PATH,
		Support.RUN_PREPARE_SCREEN_PATH
	)
	if invalid_screen == null:
		return
	if not Support.require_methods(
		self,
		invalid_screen,
		[
			&"compose",
			&"deployment_issue_codes",
			&"deployment_issue_message_keys",
			&"displayed_capacity",
			&"start_enabled",
			&"request",
			&"recovery_action_kinds",
			&"overflow_ids",
			&"focused_action_id",
		],
		"AC-004/005/017 RUN_PREPARE screen"
	):
		return

	var session: Variant = \
		Support.SpyRunPresentationSession.new()
	session.current_snapshot = Support.prepare_snapshot()
	var port_values: Array = Support.live_intent_port(session)
	var port: LiveScreenIntentPort = port_values[0]
	var report: BoardValidationReport = Support.invalid_board_report()
	assert_eq(
		invalid_screen.call(&"compose", session.snapshot(), report, port),
		&""
	)
	assert_eq(invalid_screen.call(&"displayed_capacity"), 11)
	assert_false(invalid_screen.call(&"start_enabled"))
	assert_eq(
		invalid_screen.call(&"deployment_issue_codes"),
		Support.ALL_BOARD_ISSUE_CODES,
		"formal prepare UI must not collapse the validator's complete reason list"
	)
	var expected_message_keys: Array[StringName] = []
	for code: StringName in Support.ALL_BOARD_ISSUE_CODES:
		expected_message_keys.append(
			StringName("error.board.%s" % String(code).to_lower())
		)
	assert_eq(
		invalid_screen.call(&"deployment_issue_message_keys"),
		expected_message_keys
	)

	var start: RunPresentationIntent = RunPresentationIntent.new(
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT
	)
	var blocked: Variant = invalid_screen.call(&"request", start)
	assert_false(bool(blocked.get("ok")))
	assert_eq(Support.error_code(blocked), &"RUN_PREPARE_START_NOT_READY")
	assert_eq(session.dispatch_count, 0, "invalid deployment must dispatch zero intents")

	var recovery_actions: Array = invalid_screen.call(&"recovery_action_kinds")
	assert_eq(
		recovery_actions,
		[
			RunPresentationIntent.Kind.SELL_UNIT,
			RunPresentationIntent.Kind.EQUIP_ITEM,
			RunPresentationIntent.Kind.DISMANTLE_EQUIPMENT,
			RunPresentationIntent.Kind.RESOLVE_ITEM_OVERFLOW,
		]
	)
	assert_eq(invalid_screen.call(&"overflow_ids"), ["overflow.item"])
	assert_eq(
		invalid_screen.call(&"focused_action_id"),
		&"run.prepare.resolve_overflow"
	)

	session.reject_code = &"SELL_EQUIPPED_UNIT_OVERFLOW_PENDING"
	var sell: RunPresentationIntent = RunPresentationIntent.new(
		RunPresentationIntent.Kind.SELL_UNIT
	)
	sell.unit_instance_id = "unit.bound"
	var rejected: Variant = invalid_screen.call(&"request", sell)
	assert_false(bool(rejected.get("ok")))
	assert_eq(session.dispatch_count, 1)
	assert_eq(
		invalid_screen.call(&"overflow_ids"),
		["overflow.item"],
		"rejected build action must retain recoverable overflow projection"
	)
	assert_eq(
		invalid_screen.call(&"focused_action_id"),
		&"run.prepare.resolve_overflow"
	)

	var valid_screen: Object = Support.instantiate_scene(
		self,
		SCENE_PATH,
		Support.RUN_PREPARE_SCREEN_PATH
	)
	if valid_screen == null:
		return
	session.reject_code = &""
	assert_eq(
		valid_screen.call(
			&"compose",
			session.snapshot(),
			Support.valid_board_report(),
			port
		),
		&""
	)
	assert_eq(valid_screen.call(&"displayed_capacity"), 12)
	assert_true(
		valid_screen.call(&"start_enabled"),
		"a canonical 12-capacity valid report enables the start action"
	)
