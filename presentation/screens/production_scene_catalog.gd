class_name ProductionSceneCatalog
extends RefCounted

const REQUIRED_ROUTES: Array[StringName] = [
	&"MENU_MAIN",
	&"SETTINGS",
	&"CAMP_WORLD",
	&"FACILITY_EXPEDITION_GATE",
	&"FACILITY_COMMANDER_HALL",
	&"COLLECTION",
	&"FACILITY_UNLOCK_WORKSHOP",
	&"FACILITY_CHALLENGE_MONUMENT",
	&"RUN_CONTAINER",
	&"RUN_MAP",
	&"RUN_PREPARE",
	&"RUN_COMBAT",
	&"RUN_REWARD",
	&"RUN_ROUTE_FALLBACK",
	&"RESULTS",
	&"RESULTS_FALLBACK",
]


func required_route_kinds() -> Array[StringName]:
	var routes: Array[StringName] = []
	routes.assign(REQUIRED_ROUTES)
	return routes


func scene_path(route_kind: StringName) -> String:
	match route_kind:
		&"MENU_MAIN":
			return "res://scenes/production/menu_main.tscn"
		&"SETTINGS":
			return "res://scenes/production/settings.tscn"
		&"CAMP_WORLD":
			return "res://scenes/production/camp_world.tscn"
		&"FACILITY_EXPEDITION_GATE":
			return "res://scenes/production/facility_expedition_gate.tscn"
		&"FACILITY_COMMANDER_HALL":
			return "res://scenes/production/facility_commander_hall.tscn"
		&"COLLECTION":
			return "res://scenes/production/collection.tscn"
		&"FACILITY_UNLOCK_WORKSHOP":
			return "res://scenes/production/facility_unlock_workshop.tscn"
		&"FACILITY_CHALLENGE_MONUMENT":
			return "res://scenes/production/facility_challenge_monument.tscn"
		&"RUN_CONTAINER":
			return "res://scenes/production/run_container.tscn"
		&"RUN_MAP":
			return "res://scenes/production/run_map.tscn"
		&"RUN_PREPARE":
			return "res://scenes/production/run_prepare.tscn"
		&"RUN_COMBAT":
			return "res://scenes/production/run_combat.tscn"
		&"RUN_REWARD":
			return "res://scenes/production/run_reward.tscn"
		&"RUN_ROUTE_FALLBACK":
			return "res://scenes/production/run_route_fallback.tscn"
		&"RESULTS":
			return "res://scenes/production/results.tscn"
		&"RESULTS_FALLBACK":
			return "res://scenes/production/results_fallback.tscn"
	return ""


func instantiate(route_kind: StringName) -> ProductionScreen:
	var path := scene_path(route_kind)
	if path.is_empty():
		return null
	var packed_scene := load(path) as PackedScene
	if packed_scene == null:
		return null
	return packed_scene.instantiate() as ProductionScreen
