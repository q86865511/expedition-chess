extends GutTest

const Candidate := preload(
	"res://tests/unit/presentation_ui_static_gate/fixtures/"
	+ "minimal_static_gate_candidate.gd"
)
const StaticSupport := preload(
	"res://tests/unit/presentation_ui_static_gate/static_gate_test_support.gd"
)

const ROUTE_ACTIONS: Dictionary = {
	&"MENU_MAIN": [
		&"menu.continue",
		&"menu.start",
		&"menu.recovery",
		&"menu.recovery.confirm",
		&"menu.recovery.cancel",
		&"menu.settings",
		&"menu.exit",
	],
	&"SETTINGS": [&"settings.apply", &"settings.back"],
	&"CAMP_WORLD": [
		&"camp.expedition_gate",
		&"camp.commander_hall",
		&"camp.collection",
		&"camp.forge",
		&"camp.challenge_monument",
		&"camp.settings",
		&"camp.start",
		&"camp.menu",
	],
	&"FACILITY_EXPEDITION_GATE": [&"camp.back"],
	&"FACILITY_COMMANDER_HALL": [&"camp.back"],
	&"COLLECTION": [&"camp.back"],
	&"FACILITY_UNLOCK_WORKSHOP": [&"camp.back"],
	&"FACILITY_CHALLENGE_MONUMENT": [&"camp.back"],
	&"RUN_MAP": [&"map.select", &"map.confirm", &"run.menu"],
	&"RUN_PREPARE": [&"prepare.unit", &"prepare.start", &"run.menu"],
	&"RUN_COMBAT": [
		&"combat.pause",
		&"combat.inspect",
		&"combat.speed",
		&"run.menu",
	],
	&"RUN_REWARD": [&"reward.select", &"reward.confirm", &"run.menu"],
	&"RUN_ROUTE_FALLBACK": [&"run.retry_route", &"run.menu"],
	# G2 F4：MENU／CAMP／RESULTS 的 post-commit route 失敗共用的復原畫面。
	&"APP_ROUTE_FALLBACK": [&"app.retry_route", &"menu.exit"],
	&"RESULTS": [&"results.camp", &"results.menu"],
	&"RESULTS_FALLBACK": [
		&"results.retry",
		&"results.camp",
		&"results.menu",
	],
}


func test_dotted_action_ids_produce_stable_unique_node_names() -> void:
	var screen := ProductionScreen.new()
	var action_ids: Array[StringName] = [
		&"menu.recovery",
		&"menu.recovery.confirm",
		&"menu.recovery.cancel",
		&"results.retry",
		&"run.retry_route",
	]
	var names: Dictionary = {}
	for action_id: StringName in action_ids:
		var node_name := String(screen.call(&"_button_name", action_id))
		assert_false(node_name.is_empty(), "%s requires a node name" % action_id)
		assert_false(
			names.has(node_name),
			"%s collides at node name %s" % [action_id, node_name]
		)
		names[node_name] = action_id
	assert_eq(names.size(), action_ids.size())
	screen.free()


func test_focus_graph_covers_every_production_route_action() -> void:
	var graph := KeyboardFocusGraph.new()
	for route: StringName in ROUTE_ACTIONS:
		var order: Array[StringName] = []
		order.assign(graph.focus_order(route, 100, []))
		assert_eq(
			order,
			ROUTE_ACTIONS[route],
			"%s focus order must match every reachable production action" % route
		)


func test_static_gate_rejects_english_visible_text_in_gdscript() -> void:
	var candidate := Candidate.build()
	StaticSupport.append_source(
		candidate,
		"res://presentation/screens/menu_main.gd",
		(
			"func forbidden_visible_text(button: Button, choices: OptionButton) -> void:\n"
			+ "\tbutton.text = \"Start Expedition\"\n"
			+ "\tbutton.tooltip_text = \"Begin a new run\"\n"
			+ "\tchoices.add_item(\"English choice\")\n"
		)
	)

	var report := StaticSupport.validate(self, candidate)

	StaticSupport.assert_rejected_with(
		self,
		report,
		&"PUI_HARDCODED_PLAYER_TEXT"
	)
