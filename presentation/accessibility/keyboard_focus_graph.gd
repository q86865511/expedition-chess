class_name KeyboardFocusGraph
extends RefCounted

const _VALID_UI_SCALES: Array[int] = [100, 125, 150]
const _PRIMARY_ACTIONS: Dictionary = {
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
	&"RESULTS_FALLBACK": [
		&"results.retry",
		&"results.camp",
		&"results.menu",
	],
	# Legacy aliases remain for the pre-production accessibility contract tests.
	&"MENU": [
		&"menu.continue",
		&"menu.start",
		&"menu.settings",
		&"menu.exit",
	],
	&"CAMP": [
		&"camp.collection",
		&"camp.forge",
		&"camp.settings",
		&"camp.start",
	],
	&"MAP": [&"map.select", &"map.confirm"],
	&"PREPARE": [&"prepare.unit", &"prepare.start"],
	&"COMBAT": [&"combat.pause", &"combat.inspect"],
	&"REWARD": [&"reward.select", &"reward.confirm"],
	&"RESULTS": [&"results.camp", &"results.menu"],
}


func focus_order(
	screen: StringName,
	scale_percent: int,
	blocked_actions: Array
) -> Array[StringName]:
	var result: Array[StringName] = []
	if scale_percent not in _VALID_UI_SCALES:
		return result
	var configured: Variant = _PRIMARY_ACTIONS.get(screen)
	if not configured is Array:
		return result
	for action_value: Variant in configured:
		var action := StringName(action_value)
		if not blocked_actions.has(action):
			result.append(action)
	return result
