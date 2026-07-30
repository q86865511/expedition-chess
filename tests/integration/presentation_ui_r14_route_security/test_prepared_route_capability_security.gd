extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_route_security/"
	+ "r14_route_security_test_support.gd"
)


func test_default_and_wrong_router_prepared_routes_are_typed_rejections() -> void:
	var first := Support.router_fixture(self)
	var second := Support.router_fixture(self)
	var router_a := first.get("router") as SceneRouterService
	var router_b := second.get("router") as SceneRouterService
	assert_eq(
		Support.commit_code(self, router_a, PreparedProductionRoute.new()),
		&"SCENE_ROUTER_PREPARED_FORGED"
	)
	var prepared := Support.prepare_menu(self, router_a)
	assert_eq(
		Support.commit_code(self, router_b, prepared),
		&"SCENE_ROUTER_PREPARED_WRONG_ROUTER"
	)
	router_a.discard_prepared(prepared)


func test_prepared_route_is_single_use_and_replay_is_typed() -> void:
	var fixture := Support.router_fixture(self)
	var router := fixture.get("router") as SceneRouterService
	var prepared := Support.prepare_menu(self, router)
	assert_eq(Support.commit_code(self, router, prepared), &"")
	assert_eq(
		Support.commit_code(self, router, prepared),
		&"SCENE_ROUTER_PREPARED_REPLAYED"
	)
	if not Support.typed_commit_contract_ready():
		router.discard_prepared(prepared)


func test_prepared_route_uses_opaque_issuer_bound_identity() -> void:
	var source := Support.source(
		"res://presentation/screens/prepared_production_route.gd"
	)
	assert_false(
		source.contains("var _router_identity: StringName"),
		"predictable router strings are not issuer capabilities"
	)
	assert_true(
		source.contains("_issuer") or source.contains("_capability"),
		"prepared route must carry opaque issuer-bound identity"
	)
	assert_true(
		Support.source(Support.ROUTER_SOURCE).contains("_pending_prepared"),
		"issuer must retain exact issued-object identity until commit/discard"
	)
