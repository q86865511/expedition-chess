extends RefCounted

const CATALOG_PATH := "res://presentation/screens/production_scene_catalog.gd"
const PRODUCTION_SCREEN_PATH := "res://presentation/screens/production_screen.gd"
const STAGED_CONTEXT_PATH := "res://presentation/screens/staged_screen_context.gd"
const ROUTE_COORDINATOR_PATH := "res://presentation/screens/presentation_route_coordinator.gd"
const LEASE_REGISTRY_PATH := "res://presentation/screens/live_screen_lease_registry.gd"
const INTENT_PORT_PATH := "res://presentation/screens/live_screen_intent_port.gd"
const NAVIGATION_PORT_PATH := "res://presentation/screens/live_screen_navigation_port.gd"

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
	&"RESULTS",
	&"RESULTS_FALLBACK",
]


static func load_script(test: GutTest, path: String) -> Script:
	var exists := FileAccess.file_exists(path)
	test.assert_true(exists, "T07 production contract missing: %s" % path)
	if not exists:
		return null
	var resource := load(path)
	test.assert_not_null(resource, "T07 script must load: %s" % path)
	return resource as Script


static func require_method(
	test: GutTest,
	target: Variant,
	method_name: StringName
) -> bool:
	var present: bool = target != null and target.has_method(method_name)
	test.assert_true(present, "T07 contract requires method %s" % String(method_name))
	return present


static func error_code(result: Variant) -> StringName:
	if result == null:
		return &""
	var error: Variant = result.get("error")
	if error == null:
		return &""
	var source_code: Variant = error.get("source_code")
	return StringName(source_code) if source_code != null else &""


static func app_action_error_code(result: Variant) -> StringName:
	return error_code(result)
