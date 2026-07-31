extends GutTest

const INTENT_PATH := "res://presentation/run/run_presentation_intent.gd"
const FACTORY_PATH := "res://domain/run/controller/run_command_factory.gd"
const SESSION_PATH := "res://presentation/run/run_presentation_session.gd"

const EXPECTED_INTENTS: Array[StringName] = [
	&"GENERATE_MAP",
	&"ENTER_NODE",
	&"REFRESH_SHOP",
	&"BUY_UNIT",
	&"BUY_XP",
	&"SELL_UNIT",
	&"COMMIT_BOARD_LAYOUT",
	&"FORGE_EQUIPMENT",
	&"EQUIP_ITEM",
	&"DISMANTLE_EQUIPMENT",
	&"START_OR_RESUME_COMBAT",
	&"SETTLE_BATTLE",
	&"RESOLVE_NON_COMBAT",
	&"CHOOSE_STANDARD_REWARD",
	&"RESOLVE_UNIT_REWARD",
	&"RESOLVE_ITEM_REWARD",
	&"RESOLVE_RELIC_REWARD",
	&"ADVANCE_REWARD",
	&"RESOLVE_UNIT_OVERFLOW",
	&"RESOLVE_ITEM_OVERFLOW",
	&"REPLACE_RELIC",
	&"ABANDON_RELIC",
	&"ABANDON_BOSS_RETRY",
	&"SETTLE_TERMINAL_RUN",
	&"COMMIT_NODE_CHOICE",
	# G2 content-production：design.md §5:201-214 的三個具名 writer——ack、
	# 服務內拆解、node service 離場。前者關掉結果重播，後兩者是 dismantle 服務
	# 唯一的「多次執行」與「離場」路徑（少了離場命令 run 會永久卡死）。
	&"ACKNOWLEDGE_NODE_CHOICE_RESULT",
	&"DISMANTLE_WITH_NODE_SERVICE",
	&"EXIT_NODE_SERVICE",
]

const EXPECTED_FACTORY_METHODS: Array[String] = [
	"generate_expedition_map_command",
	"enter_node_event",
	"refresh_shop_command",
	"buy_offer_command",
	"buy_xp_command",
	"sell_unit_command",
	"commit_board_layout_command",
	"forge_equipment_command",
	"equip_item_command",
	"dismantle_equipment_command",
	"start_combat_event",
	"settle_battle_result_command",
	"resolve_non_combat_node_command",
	"choose_reward_command",
	"resolve_unit_reward_command",
	"resolve_item_reward_command",
	"resolve_relic_reward_command",
	"advance_reward_command",
	"resolve_unit_overflow_command",
	"resolve_item_overflow_command",
	"replace_relic_command",
	"abandon_relic_command",
	"abandon_boss_retry_command",
	"settle_terminal_run_command",
	"commit_node_choice_command",
	"acknowledge_node_choice_result_command",
	"dismantle_with_node_service_command",
	"exit_node_service_command",
]


func test_run_presentation_intent_declares_every_existing_player_writer() -> void:
	var enum_names: Array[StringName] = []
	for key: String in RunPresentationIntent.Kind.keys():
		enum_names.append(StringName(key))

	assert_eq(
		enum_names,
		EXPECTED_INTENTS,
		"intent enum is a stable exhaustive map of existing player writer operations"
	)


func test_run_command_factory_owns_every_intent_construction_path() -> void:
	var factory_source := _source(FACTORY_PATH)
	var missing: Array[String] = []
	for method_name: String in EXPECTED_FACTORY_METHODS:
		if not factory_source.contains("func %s(" % method_name):
			missing.append(method_name)

	assert_eq(
		missing,
		[],
		"all presentation writers must have one RunCommandFactory construction path"
	)


func test_session_has_an_explicit_exhaustive_intent_mapping() -> void:
	var session_source := _source(SESSION_PATH)
	var missing: Array[StringName] = []
	for intent_name: StringName in EXPECTED_INTENTS:
		var token := "RunPresentationIntent.Kind.%s" % String(intent_name)
		if not session_source.contains(token):
			missing.append(intent_name)

	assert_eq(
		missing,
		[],
		"facade dispatch must explicitly map every intent kind; fall-through is not exhaustive"
	)
	assert_false(
		session_source.contains("RunCommand.new("),
		"facade must not construct generic/ad-hoc commands"
	)


func test_intent_clone_is_consumer_owned_and_never_dictionary_payload() -> void:
	var intent := RunPresentationIntent.new(RunPresentationIntent.Kind.ABANDON_BOSS_RETRY)
	var clone := intent.deep_clone()

	assert_ne(intent, clone, "intent clone must own a new object")
	assert_eq(clone.kind, RunPresentationIntent.Kind.ABANDON_BOSS_RETRY)
	assert_false(
		_source(INTENT_PATH).contains("Dictionary"),
		"intent payload must use named typed state, never Dictionary"
	)


func _source(path: String) -> String:
	assert_true(FileAccess.file_exists(path), "required source missing: %s" % path)
	return FileAccess.get_file_as_string(path)
