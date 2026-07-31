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
	&"RUN_PREPARE": [
		&"prepare.unit",
		&"choice.begin",
		&"choice.confirm",
		&"choice.cancel",
		&"prepare.start",
		&"run.menu",
	],
	&"RUN_COMBAT": [
		&"combat.pause",
		&"combat.inspect",
		&"combat.speed",
		&"run.menu",
	],
	&"RUN_REWARD": [&"reward.select", &"reward.confirm", &"run.menu"],
	&"RUN_ROUTE_FALLBACK": [&"run.retry_route", &"run.menu"],
	&"APP_ROUTE_FALLBACK": [&"app.retry_route", &"menu.exit"],
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

## G2 建議項2／F9：誤觸代價高的動作退出焦點環的按鈕段前面（仍然鍵盤可達）。
## 焦點順序的唯一權威在本類別——ProductionScreen 以前另存一份同名常數，
## 造成改焦點圖不會反映到畫面上的雙權威。
const _DEFERRED_ACTIONS: Dictionary = {
	&"RUN_PREPARE": [&"prepare.start"],
	&"PREPARE": [&"prepare.start"],
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


## 本畫面要排到按鈕段最後的動作（無此類動作時回空陣列）。
func deferred_actions(screen: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var configured: Variant = _DEFERRED_ACTIONS.get(screen)
	if not configured is Array:
		return result
	for action_value: Variant in configured:
		result.append(StringName(action_value))
	return result
