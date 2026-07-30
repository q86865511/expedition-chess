extends GutTest

## G2 M1：`_commit_route()` 的回傳值以前在六個 state-machine transition 之後的呼叫點
## 被丟棄，換場失敗仍回報 success（畫面停在舊畫面／新畫面按鈕全被拒，玩家零回饋）。
##
## G2 F4（fresh review）：M1 的第一版把「撤銷全部 lease、畫面停在舊畫面」固化成契約
## ——那是個沒有出口的狀態（連 menu.exit 都回 SCREEN_NOT_ACTIVE）。現在改為與 RUN 的
## `_install_run_route_fallback` 對齊：撤銷舊 lease 之後裝 APP_ROUTE_FALLBACK，
## 玩家至少有 app.retry_route 與 menu.exit 兩條路。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_findings/"
	+ "g2_findings_test_support.gd"
)


func test_return_to_menu_reports_committed_presentation_failure() -> void:
	var router := Support.FailingCommitRouter.new()
	var harness: Variant = Support.boot(self, router)
	assert_true(Support.press(self, Support.active_screen(harness), &"menu.start"))
	var camp := Support.active_screen(harness)
	assert_eq(camp.route_kind, &"CAMP_WORLD")

	router.fail_next_commit = true
	assert_true(Support.press(self, camp, &"camp.menu"))
	assert_eq(router.commit_failures, 1)

	var result: Variant = camp.last_control_result()
	assert_true(result is AppActionResult)
	if not result is AppActionResult:
		return
	var typed := result as AppActionResult
	assert_false(typed.ok, "a failed route commit must not report success")
	assert_true(typed.committed, "the state machine already moved on")
	assert_false(typed.presentation_ok)
	assert_eq(typed.error.source_code, &"SCENE_BIND_FAILED")
	assert_eq(
		(harness.root as ApplicationRoot).app_state(),
		AppStateMachine.State.MENU
	)
	assert_false(
		camp.status_message_text().is_empty(),
		"the post-commit failure must reach the error surface"
	)
	assert_eq(camp.status_report().get("committed"), true)

	# 舊畫面的 lease 已被撤銷（它不能再發任何命令），但玩家不能被留在死路上：
	# fail-closed 的落點是 APP_ROUTE_FALLBACK，且它自己是 live 的。
	var fallback := Support.active_screen(harness)
	assert_not_null(fallback)
	if fallback == null:
		return
	assert_eq(fallback.route_kind, &"APP_ROUTE_FALLBACK")
	assert_not_null(
		Support.lease_registry(harness.root).active_lease(),
		"the recovery screen must be able to accept its own two actions"
	)
	assert_not_null(Support.button(fallback, &"app.retry_route"))
	assert_not_null(Support.button(fallback, &"menu.exit"))

	# 重試真的能把玩家帶回正式畫面（router 這次不再武裝失敗）。
	assert_true(Support.press(self, fallback, &"app.retry_route"))
	assert_eq(Support.active_screen(harness).route_kind, &"MENU_MAIN")


func test_results_and_camp_route_commits_share_the_fail_closed_helper() -> void:
	var harness: Variant = Support.boot(self)
	var root := harness.root as ApplicationRoot
	var failure: Variant = root.call(&"_commit_route_or_fail_closed", {})
	assert_true(failure is AppActionResult)
	if not failure is AppActionResult:
		return
	var typed := failure as AppActionResult
	assert_false(typed.ok)
	assert_true(typed.committed)
	assert_eq(typed.error.source_code, ApplicationRoot.ERROR_ROUTE_ACTIVATION_INVALID)
	assert_eq(typed.error.message_key, &"error.presentation.route_commit_failed")
	assert_eq(
		Support.active_screen(harness).route_kind,
		&"APP_ROUTE_FALLBACK",
		"the shared helper must leave a recovery surface, not a dead screen"
	)
	assert_not_null(Support.lease_registry(root).active_lease())


func test_activation_lost_after_scene_commit_revokes_every_lease() -> void:
	var router := Support.FailingCommitRouter.new()
	var harness: Variant = Support.boot(self, router)
	var root := harness.root as ApplicationRoot
	var registry := Support.lease_registry(root)
	assert_not_null(registry.active_lease(), "boot installs a live MENU screen")

	var prepared: Dictionary = root.call(
		&"_prepare_route",
		AppStateMachine.State.MENU,
		&"MENU_MAIN",
		root.current_menu_snapshot()
	)
	assert_true(bool(prepared.get("ok", false)))
	router.steal_registry = registry
	router.steal_activation = (
		prepared.get("activation") as ScreenActivationCapability
	)

	var code := StringName(root.call(&"_commit_route", prepared))
	assert_eq(
		code,
		ApplicationRoot.ERROR_ROUTE_ACTIVATION_INVALID,
		"a committed scene without an active lease must not report success"
	)
	assert_null(
		registry.active_lease(),
		"fail-closed: the screen is visible but nothing may dispatch through it"
	)
