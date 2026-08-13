extends GutTest

## G2 M2＋建議項1：進行中的遠征按「返回主選單」、主選單按「離開」都是代價高的動作，
## 必須先出確認 modal；取消零 dispatch，確認才真的執行。
## CAMP 的 `camp.menu` 沒有進行中遠征之虞，維持直接離開。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_findings/"
	+ "g2_findings_test_support.gd"
)


func test_leaving_an_active_run_asks_first_and_cancel_is_zero_dispatch() -> void:
	var harness: Variant = Support.boot(self)
	var run_screen := Support.enter_run(self, harness)
	assert_not_null(run_screen)
	if run_screen == null:
		return
	assert_eq(run_screen.route_kind, &"RUN_MAP")
	assert_null(run_screen.last_control_result())

	assert_true(Support.press(self, run_screen, &"run.menu"))
	assert_true(run_screen.is_confirmation_modal_open())
	assert_eq(run_screen.confirmation_modal_node_name(), "RunMenuConfirmation")
	assert_eq(
		(harness.root as ApplicationRoot).app_state(),
		AppStateMachine.State.RUN,
		"opening the confirmation must not leave the run"
	)
	assert_null(
		run_screen.last_control_result(),
		"opening the confirmation must not dispatch anything"
	)

	assert_true(Support.press(self, run_screen, &"run.menu.cancel"))
	assert_false(run_screen.is_confirmation_modal_open())
	assert_eq(
		(harness.root as ApplicationRoot).app_state(),
		AppStateMachine.State.RUN
	)
	assert_eq(Support.active_screen(harness), run_screen)
	assert_null(
		run_screen.last_control_result(),
		"cancel is zero dispatch"
	)

	assert_true(Support.press(self, run_screen, &"run.menu"))
	assert_true(run_screen.is_confirmation_modal_open())
	assert_true(Support.press(self, run_screen, &"run.menu.confirm"))
	assert_eq(
		(harness.root as ApplicationRoot).app_state(),
		AppStateMachine.State.MENU,
		"confirming must actually leave the run"
	)


func test_camp_returns_to_menu_without_a_confirmation() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.press(self, Support.active_screen(harness), &"menu.start"))
	var camp := Support.active_screen(harness)
	assert_eq(camp.route_kind, &"CAMP_WORLD")

	assert_true(Support.press(self, camp, &"camp.menu"))
	assert_false(camp.is_confirmation_modal_open())
	assert_eq(
		(harness.root as ApplicationRoot).app_state(),
		AppStateMachine.State.MENU
	)


func test_exit_signal_is_emitted_only_after_confirmation() -> void:
	var harness: Variant = Support.boot(self)
	var menu := Support.active_screen(harness)
	assert_eq(menu.route_kind, &"MENU_MAIN")
	var emitted: Array[int] = []
	(harness.root as ApplicationRoot).exit_requested.connect(
		func() -> void:
			emitted.append(1)
	)

	assert_true(Support.press(self, menu, &"menu.exit"))
	assert_true(menu.is_confirmation_modal_open())
	assert_eq(menu.confirmation_modal_node_name(), "ExitConfirmation")
	assert_eq(emitted.size(), 0, "exit must not fire before confirmation")

	assert_true(Support.press(self, menu, &"menu.exit.cancel"))
	assert_false(menu.is_confirmation_modal_open())
	assert_eq(emitted.size(), 0, "cancel is zero dispatch")

	assert_true(Support.press(self, menu, &"menu.exit"))
	assert_true(Support.press(self, menu, &"menu.exit.confirm"))
	assert_eq(emitted.size(), 1, "exit fires exactly once, after confirmation")


func test_confirmation_modal_reopens_within_the_same_frame() -> void:
	# G2 L4：關閉時只 queue_free 的話，同一影格重新觸發會撞上「節點還在」的守衛，
	# app 層 confirmation 已開啟、畫面卻沒有 modal（且背景仍可操作）。
	var harness: Variant = Support.boot(self)
	var run_screen := Support.enter_run(self, harness)
	assert_not_null(run_screen)
	if run_screen == null:
		return

	assert_true(Support.press(self, run_screen, &"run.menu"))
	assert_true(run_screen.is_confirmation_modal_open())
	assert_true(Support.press(self, run_screen, &"run.menu.cancel"))
	assert_false(run_screen.is_confirmation_modal_open())
	assert_null(
		run_screen.find_child("RunMenuConfirmation", true, false),
		"the closed dialog must leave the tree immediately, not next frame"
	)

	# 同一影格（沒有 await）立刻再觸發一次。
	assert_true(Support.press(self, run_screen, &"run.menu"))
	assert_true(
		run_screen.is_confirmation_modal_open(),
		"a same-frame retrigger must reopen a real modal"
	)
	assert_not_null(run_screen.find_child("RunMenuConfirmation", true, false))
	for node: Node in run_screen.find_child(
		"Actions", true, false
	).find_children(
		"*",
		"Button",
		true,
		false
	):
		var background := node as Button
		assert_true(
			background.disabled
			or background.focus_mode == Control.FOCUS_NONE,
			"the reopened modal must block the background again"
		)
