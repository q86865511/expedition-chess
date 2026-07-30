extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_scene_routing/scene_routing_test_support.gd"
)


func test_formal_scene_routes_and_command_only_writes() -> void:
	var catalog_script := Support.load_script(self, Support.CATALOG_PATH)
	var screen_script := Support.load_script(self, Support.PRODUCTION_SCREEN_PATH)
	var context_script := Support.load_script(self, Support.STAGED_CONTEXT_PATH)
	if catalog_script == null or screen_script == null or context_script == null:
		return

	var catalog: Variant = catalog_script.new()
	if not Support.require_method(self, catalog, &"required_route_kinds") \
		or not Support.require_method(self, catalog, &"scene_path") \
		or not Support.require_method(self, catalog, &"instantiate"):
		return

	var advertised: Array = catalog.call(&"required_route_kinds")
	for route_kind: StringName in Support.REQUIRED_ROUTES:
		assert_has(advertised, route_kind, "catalog must advertise %s" % String(route_kind))
		var scene_path: String = str(catalog.call(&"scene_path", route_kind))
		assert_false(scene_path.is_empty(), "%s must have a production scene path" % route_kind)
		assert_true(
			scene_path.begins_with("res://scenes/production/"),
			"%s must not resolve to a dev scene" % route_kind
		)
		assert_true(
			ResourceLoader.exists(scene_path, "PackedScene"),
			"%s scene must be importable" % route_kind
		)
		var screen: Variant = catalog.call(&"instantiate", route_kind)
		assert_not_null(screen, "%s must instantiate" % route_kind)
		if screen == null:
			continue
		assert_true(
			screen.get_script() == screen_script,
			"%s must implement ProductionScreen directly" % route_kind
		)
		if screen is Node:
			(screen as Node).free()

	var staged_context: Variant = context_script.new(&"RUN_MAP", RunPresentationSnapshot.new())
	var staged_screen: Variant = screen_script.new()
	if not Support.require_method(self, staged_screen, &"bind") \
		or not Support.require_method(self, staged_screen, &"request_intent"):
		if staged_screen is Node:
			(staged_screen as Node).free()
		return
	var bind_code: StringName = staged_screen.call(&"bind", staged_context)
	assert_eq(bind_code, &"", "staged screen must bind read-only context")
	var rejected: Variant = staged_screen.call(
		&"request_intent",
		RunPresentationIntent.new(RunPresentationIntent.Kind.GENERATE_MAP)
	)
	assert_false(bool(rejected.get("ok")), "staged candidate may not dispatch gameplay")
	assert_eq(
		Support.error_code(rejected),
		&"SCREEN_NOT_ACTIVE",
		"bind/_ready-time intent must be rejected before activation"
	)
	if staged_screen is Node:
		(staged_screen as Node).free()


func test_results_fallback_catalog_entry_is_results_only() -> void:
	var catalog_script := Support.load_script(self, Support.CATALOG_PATH)
	var context_script := Support.load_script(self, Support.STAGED_CONTEXT_PATH)
	if catalog_script == null or context_script == null:
		return
	var catalog: Variant = catalog_script.new()
	if not Support.require_method(self, catalog, &"instantiate"):
		return
	var fallback: Variant = catalog.call(&"instantiate", &"RESULTS_FALLBACK")
	assert_not_null(fallback, "RESULTS_FALLBACK shell must instantiate")
	if fallback == null:
		return
	var context: Variant = context_script.new(&"RESULTS_FALLBACK", ResultsPresentationSnapshot.new())
	if not Support.require_method(self, fallback, &"bind"):
		(fallback as Node).free()
		return
	assert_eq(fallback.call(&"bind", context), &"")
	assert_null(
		context.get("intent_port"),
		"fallback context must never expose a gameplay intent port"
	)
	assert_null(
		context.get("run_session"),
		"fallback context must never expose a raw RunPresentationSession"
	)
	if fallback is Node:
		(fallback as Node).free()
