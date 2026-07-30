extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_accessibility/accessibility_test_support.gd"
)

const PRIMARY_ACTIONS := {
	&"MENU": [&"menu.continue", &"menu.start", &"menu.settings", &"menu.exit"],
	&"CAMP": [&"camp.collection", &"camp.forge", &"camp.settings", &"camp.start"],
	&"MAP": [&"map.select", &"map.confirm"],
	&"PREPARE": [&"prepare.unit", &"prepare.start"],
	&"COMBAT": [&"combat.pause", &"combat.inspect"],
	&"REWARD": [&"reward.select", &"reward.confirm"],
	&"RESULTS": [&"results.camp", &"results.menu"],
}


func test_keyboard_focus_reaches_every_primary_action_at_all_ui_scales() -> void:
	var script := Support.load_script(self, Support.FOCUS_GRAPH_PATH)
	if script == null:
		return
	var graph: Object = script.new()
	if not Support.require_methods(
		self,
		graph,
		[&"focus_order"],
		Support.FOCUS_GRAPH_PATH
	):
		return

	for scale_percent: int in [100, 125, 150]:
		for screen: StringName in PRIMARY_ACTIONS:
			var order := Support.names(
				graph.call(&"focus_order", screen, scale_percent, [])
			)
			assert_false(
				order.is_empty(),
				"%s at %d%% must retain keyboard focus" % [screen, scale_percent]
			)
			assert_eq(
				order.size(),
				Support.names(PRIMARY_ACTIONS[screen]).size(),
				"%s at %d%% must not lose or duplicate actions" % [
					screen,
					scale_percent,
				]
			)
			for action: StringName in Support.names(PRIMARY_ACTIONS[screen]):
				assert_has(
					order,
					action,
					"%s at %d%% must reach %s" % [
						screen,
						scale_percent,
						action,
					]
				)


func test_hidden_or_disabled_controls_are_removed_without_trapping_focus() -> void:
	var script := Support.load_script(self, Support.FOCUS_GRAPH_PATH)
	if script == null:
		return
	var graph: Object = script.new()
	if not Support.require_methods(
		self,
		graph,
		[&"focus_order"],
		Support.FOCUS_GRAPH_PATH
	):
		return

	var blocked: Array[StringName] = [&"menu.continue", &"menu.settings"]
	var order := Support.names(
		graph.call(&"focus_order", &"MENU", 150, blocked)
	)
	assert_false(order.has(&"menu.continue"))
	assert_false(order.has(&"menu.settings"))
	assert_has(order, &"menu.start")
	assert_has(order, &"menu.exit")
	assert_eq(
		order.size(),
		2,
		"focus traversal must skip hidden/disabled controls, not enter a trap"
	)
