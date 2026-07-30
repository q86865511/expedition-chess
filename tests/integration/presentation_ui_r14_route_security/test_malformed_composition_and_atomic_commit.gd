extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_route_security/"
	+ "r14_route_security_test_support.gd"
)


func test_missing_and_wrong_composition_children_return_named_bind_errors() -> void:
	var missing := ProductionScreen.new()
	autofree(missing)
	missing.route_kind = &"RUN_MAP"
	assert_eq(
		missing.prepare_live_binding(
			ProductionLiveScreenContext.new(
				&"RUN_MAP",
				RunPresentationSnapshot.new()
			)
		),
		&"SCREEN_COMPOSITION_MISSING"
	)

	if not Support.malformed_composition_contract_ready():
		assert_true(
			false,
			"wrong composition types must be checked before typed method dispatch"
		)
		return
	var wrong := ProductionScreen.new()
	autofree(wrong)
	wrong.route_kind = &"RUN_MAP"
	var malformed := Node.new()
	malformed.name = "Composition"
	wrong.add_child(malformed)
	assert_eq(
		wrong.prepare_live_binding(
			ProductionLiveScreenContext.new(
				&"RUN_MAP",
				RunPresentationSnapshot.new()
			)
		),
		&"SCREEN_COMPOSITION_TYPE_INVALID"
	)


func test_app_root_invalid_activation_returns_typed_failure_without_mutation() -> void:
	if not Support.app_commit_contract_ready():
		assert_true(
			false,
			"ApplicationRoot._commit_route must not assert on invalid activation"
		)
		return
	var root := ApplicationRoot.new()
	autofree(root)
	var before_generation: int = int(root.get("_route_generation"))
	var before_kind: StringName = StringName(root.get("_active_route_kind"))
	var code := StringName(root.call(&"_commit_route", {}))
	assert_eq(code, &"APP_ROUTE_ACTIVATION_INVALID")
	assert_eq(int(root.get("_route_generation")), before_generation)
	assert_eq(StringName(root.get("_active_route_kind")), before_kind)


func test_install_production_propagates_typed_commit_result() -> void:
	var source := Support.source(Support.ROUTER_SOURCE)
	assert_true(
		source.contains("return commit_prepared(prepared.prepared)"),
		"install_production must propagate commit rejection"
	)
