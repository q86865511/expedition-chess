extends GutTest

## G2 F2（fresh review `.pipeline/reviews/fix-branch-fresh-review.md`）：
## M1 讓 `_confirm_menu_recovery()` 在「durable discard 成功、但 MENU route commit
## 失敗」時回 not-ok，但 ProductionScreen 只在 `ok` 為真時才關 modal。結果是
## modal 永不關、背景按鈕被 `_disable_modal_background()` 全部停用、玩家只剩
## confirm/cancel 兩顆，而 lease 已撤銷所以它們永遠回 SCREEN_NOT_ACTIVE——
## App 完全鎖死，只能殺行程。這個死結是 M1 那批改動新引入的。
##
## app 層的 confirmation 在 RecoveryConfirmationPresenter 一進 confirm/cancel 就
## 關掉了，之後的失敗只影響畫面；因此 confirm/cancel 不論結果都必須關 modal。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_findings/"
	+ "g2_findings_test_support.gd"
)
const MODAL_NODE := ^"RecoveryConfirmation"
const ACTION_IDS: Array[StringName] = [
	&"menu.start",
	&"menu.recovery",
	&"menu.recovery.confirm",
	&"menu.recovery.cancel",
	&"menu.settings",
	&"menu.exit",
]


func test_failed_confirm_still_closes_the_modal_and_restores_the_background() -> void:
	var counts: Dictionary = {"confirm": 0}
	var screen := _menu_screen(
		{
			&"menu.recovery.confirm": func() -> AppActionResult:
				counts["confirm"] += 1
				# discard 已落檔、state machine 已前進，只有畫面沒跟上。
				return AppActionResult.committed_presentation_failure(
					DiagnosticError.new(
						&"SCENE_BIND_FAILED",
						&"error.presentation.recovery_postcommit"
					)
				),
		}
	)
	if screen == null:
		return
	_open_modal(screen)

	var confirm := Support.button(screen, &"menu.recovery.confirm")
	assert_not_null(confirm)
	if confirm == null:
		return
	confirm.pressed.emit()
	assert_eq(int(counts["confirm"]), 1)

	assert_false(
		screen.is_confirmation_modal_open(),
		"a post-commit failure must not trap the player inside the modal"
	)
	assert_null(screen.get_node_or_null(MODAL_NODE))
	assert_false(
		screen.status_message_text().is_empty(),
		"the failure still has to be visible—closing the modal is not swallowing it"
	)
	assert_eq(screen.status_report().get("committed"), true)
	for node: Node in screen.get_node(^"Actions").find_children(
		"*",
		"Button",
		true,
		false
	):
		var background := node as Button
		assert_false(
			background.disabled,
			"background actions must be usable again once the modal is gone"
		)


func test_failed_cancel_also_closes_the_modal() -> void:
	var screen := _menu_screen(
		{
			&"menu.recovery.cancel": func() -> AppActionResult:
				return AppActionResult.failure(
					DiagnosticError.new(
						RecoveryConfirmationPresenter.CONFIRMATION_NOT_OPEN,
						&"error.presentation.app_action"
					)
				),
		}
	)
	if screen == null:
		return
	_open_modal(screen)

	var cancel := Support.button(screen, &"menu.recovery.cancel")
	assert_not_null(cancel)
	if cancel == null:
		return
	cancel.pressed.emit()
	assert_false(screen.is_confirmation_modal_open())
	assert_null(screen.get_node_or_null(MODAL_NODE))
	assert_false(screen.status_message_text().is_empty())


func _menu_screen(overrides: Dictionary) -> ProductionScreen:
	var snapshot := MainMenuSnapshot.new()
	snapshot.can_start = true
	snapshot.has_recovery = true
	var screen := ProductionSceneCatalog.new().instantiate(&"MENU_MAIN")
	assert_not_null(screen)
	if screen == null:
		return null
	assert_eq(
		screen.bind(
			StagedScreenContext.new(
				&"MENU_MAIN",
				snapshot,
				null,
				&"zh_TW",
				Support.localized(ACTION_IDS)
			)
		),
		&""
	)
	var callbacks: Dictionary = {
		&"menu.recovery": func() -> AppActionResult:
			return AppActionResult.success(false),
		&"menu.recovery.confirm": func() -> AppActionResult:
			return AppActionResult.success(true),
		&"menu.recovery.cancel": func() -> AppActionResult:
			return AppActionResult.success(false),
	}
	for action_id: Variant in overrides.keys():
		callbacks[StringName(action_id)] = overrides[action_id]
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.MENU, 271)
	assert_eq(
		screen.prepare_live_binding(
			ProductionLiveScreenContext.new(
				&"MENU_MAIN",
				snapshot,
				null,
				ProductionScreenActionPort.new(lease, registry, callbacks),
				LiveScreenNavigationPort.new()
			)
		),
		&""
	)
	add_child_autofree(screen)
	screen.activate_live()
	return screen


func _open_modal(screen: ProductionScreen) -> void:
	var trigger := Support.button(screen, &"menu.recovery")
	assert_not_null(trigger)
	if trigger == null:
		return
	trigger.pressed.emit()
	assert_true(
		screen.is_confirmation_modal_open(),
		"precondition: the recovery modal must be open"
	)
