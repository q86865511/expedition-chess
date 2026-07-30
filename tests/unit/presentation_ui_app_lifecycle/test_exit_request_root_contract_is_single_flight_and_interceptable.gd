extends GutTest

const Support = preload("res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd")


class SignalCounter:
	extends RefCounted

	var count: int = 0

	func record() -> void:
		count += 1


func test_exit_request_root_contract_is_single_flight_and_interceptable() -> void:
	var storage := FakeSaveStorage.new()
	var menu: Variant = Support.boot(self, storage)
	var has_contract: bool = (
		menu.root.has_signal("exit_requested")
		and menu.root.has_method("request_exit")
		and menu.root.app_state() == AppStateMachine.State.MENU
	)
	assert_true(
		has_contract,
		"T05 must boot to MENU and expose interceptable request_exit/exit_requested"
	)
	if not has_contract:
		return

	var signal_counter := SignalCounter.new()
	menu.root.connect(&"exit_requested", signal_counter.record)
	var before_state: int = menu.root.app_state()
	var before_children: Array[int] = Support.host_identity(menu.host)
	var before_save: PackedByteArray = Support.main_bytes(storage)
	var first: Variant = menu.root.call("request_exit")
	assert_true(first is AppActionResult)
	if not (first is AppActionResult):
		return
	assert_true(first.ok)
	assert_false(first.committed, "exit request is never a gameplay commit")
	assert_true(first.presentation_ok)
	assert_eq(signal_counter.count, 1, "first legal request emits exactly once")
	assert_eq(menu.root.app_state(), before_state)
	assert_eq(Support.host_identity(menu.host), before_children)
	assert_eq(Support.main_bytes(storage), before_save)
	assert_true(menu.root.is_inside_tree(), "ApplicationRoot must not call SceneTree.quit()")

	var repeated: Variant = menu.root.call("request_exit")
	assert_true(repeated is AppActionResult)
	if repeated is AppActionResult:
		assert_false(repeated.ok)
		assert_false(repeated.committed)
		assert_eq(
			Support.app_action_error_code(repeated),
			&"EXIT_REQUEST_ALREADY_PENDING"
		)
	assert_eq(signal_counter.count, 1, "pending repeat must not emit again")
	assert_eq(menu.root.app_state(), before_state)
	assert_eq(Support.host_identity(menu.host), before_children)
	assert_eq(Support.main_bytes(storage), before_save)

	var wrong_storage := FakeSaveStorage.new()
	var wrong: Variant = Support.boot(self, wrong_storage)
	if not wrong.root.has_method("open_camp"):
		assert_true(false, "typed open_camp is required to create wrong-lifecycle evidence")
		return
	var opened: Variant = wrong.root.call("open_camp")
	assert_true(opened is AppActionResult and opened.ok)
	if not (opened is AppActionResult) or not opened.ok:
		return
	var wrong_signal_counter := SignalCounter.new()
	wrong.root.connect(&"exit_requested", wrong_signal_counter.record)
	var wrong_before_state: int = wrong.root.app_state()
	var wrong_before_children: Array[int] = Support.host_identity(wrong.host)
	var wrong_before_save: PackedByteArray = Support.main_bytes(wrong_storage)
	var unavailable: Variant = wrong.root.call("request_exit")
	assert_true(unavailable is AppActionResult)
	if unavailable is AppActionResult:
		assert_false(unavailable.ok)
		assert_eq(
			Support.app_action_error_code(unavailable),
			&"APP_ACTION_NOT_AVAILABLE"
		)
	assert_eq(wrong_signal_counter.count, 0)
	assert_eq(wrong.root.app_state(), wrong_before_state)
	assert_eq(Support.host_identity(wrong.host), wrong_before_children)
	assert_eq(Support.main_bytes(wrong_storage), wrong_before_save)
	assert_true(wrong.root.is_inside_tree(), "wrong-lifecycle exit must leave runner alive")
	await wait_process_frames(2)
