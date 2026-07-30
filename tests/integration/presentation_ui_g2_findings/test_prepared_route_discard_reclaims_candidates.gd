extends GutTest

## G2 F6／F7（fresh review `.pipeline/reviews/fix-branch-fresh-review.md`）：
## F6 — `_commit_route()` 的第一個早退（staged_lease == null）是本函式唯一沒有
##      `_discard_route(prepared)` 的分支，會同時洩漏 prepared candidate 的整棵
##      Control 樹與未取消的 activation capability。
## F7 — `SceneRouterService.discard_prepared()` 開頭就 `prepared_error()` 早退，
##      驗證失敗時 candidate 從不釋放；而 app_root 的 prepared_error 分支正是靠
##      這條路徑回收那棵沒掛上樹的 Control（註解說「一起收掉」，route 那一半
##      其實沒發生）。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_findings/"
	+ "g2_findings_test_support.gd"
)


func test_commit_without_a_staged_lease_reclaims_the_prepared_candidate() -> void:
	var harness: Variant = Support.boot(self)
	var root := harness.root as ApplicationRoot
	var registry := Support.lease_registry(root)

	var prepared: Dictionary = root.call(
		&"_prepare_route",
		AppStateMachine.State.MENU,
		&"MENU_MAIN",
		root.current_menu_snapshot()
	)
	assert_true(bool(prepared.get("ok", false)))
	var route := prepared.get("prepared") as PreparedProductionRoute
	assert_not_null(route)
	if route == null:
		return
	var candidate := route._candidate
	assert_not_null(candidate, "precondition: prepare owns an unmounted screen")

	# activation 在 prepare 與 commit 之間失效（第三方消費掉 prepared lease）。
	registry.activate_prepared(
		prepared.get("activation") as ScreenActivationCapability
	)

	var code := StringName(root.call(&"_commit_route", prepared))
	assert_eq(code, ApplicationRoot.ERROR_ROUTE_ACTIVATION_INVALID)
	assert_false(
		is_instance_valid(candidate),
		"the early return must not leak the prepared Control tree"
	)
	assert_null(route._candidate)


func test_discard_reclaims_a_candidate_even_when_validation_already_failed() -> void:
	var router := SceneRouterService.new()
	add_child_autofree(router)
	var host := Control.new()
	add_child_autofree(host)
	router.bind_presentation_host(host)
	assert_eq(router.bind_production_catalog(ProductionSceneCatalog.new()), &"")

	var prepared := router.prepare_production(
		&"MENU_MAIN",
		StagedScreenContext.new(&"MENU_MAIN", MainMenuSnapshot.new())
	)
	assert_true(prepared.ok)
	if not prepared.ok:
		return
	var route := prepared.prepared
	var candidate := route._candidate
	assert_not_null(candidate)

	# 讓 prepared 進入「已失效但仍握著 candidate」的狀態：nonce 仍在 registry 裡，
	# 但 route_kind 被改掉 -> prepared_error() 回 FORGED。
	candidate.route_kind = &"CAMP_WORLD"
	assert_eq(router.prepared_error(route), SceneRouterService.ERROR_PREPARED_FORGED)

	var code := router.discard_prepared(route)
	assert_eq(
		code,
		SceneRouterService.ERROR_PREPARED_FORGED,
		"the diagnostic code still has to reach the caller"
	)
	assert_false(
		is_instance_valid(candidate),
		"discard exists to reclaim the candidate; a failed validation is not a reason to keep it"
	)
	assert_null(route._candidate)


func test_discard_from_a_foreign_router_is_reported_without_touching_the_candidate() -> void:
	var owner_router := _router()
	var foreign_router := _router()
	if owner_router == null or foreign_router == null:
		return
	var prepared := owner_router.prepare_production(
		&"MENU_MAIN",
		StagedScreenContext.new(&"MENU_MAIN", MainMenuSnapshot.new())
	)
	assert_true(prepared.ok)
	if not prepared.ok:
		return
	var route := prepared.prepared
	var candidate := route._candidate

	assert_eq(
		foreign_router.discard_prepared(route),
		SceneRouterService.ERROR_PREPARED_WRONG_ROUTER
	)
	assert_true(
		is_instance_valid(candidate),
		"a router that did not issue the route has no authority to free it"
	)
	assert_eq(owner_router.discard_prepared(route), &"")
	assert_false(is_instance_valid(candidate))


func _router() -> SceneRouterService:
	var router := SceneRouterService.new()
	add_child_autofree(router)
	var host := Control.new()
	add_child_autofree(host)
	router.bind_presentation_host(host)
	assert_eq(router.bind_production_catalog(ProductionSceneCatalog.new()), &"")
	return router
