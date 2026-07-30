extends GutTest

const Support = preload("res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd")


class CompositionFailingApplicationRoot:
	extends ApplicationRoot

	func _try_compose_active_run(_profile: ProfileState, _run: RunState) -> StringName:
		return ERROR_RUN_BATTLE_CATALOG_FAILED


func test_camp_start_expedition_typed_transaction_and_route() -> void:
	var success_storage := FakeSaveStorage.new()
	var success: Variant = Support.boot(self, success_storage)
	if not _require_typed_lifecycle(success.root):
		return
	var opened: AppActionResult = success.root.call("open_camp")
	assert_true(opened.ok, "run-free MENU may enter CAMP")
	assert_false(opened.committed, "opening CAMP is presentation-only")
	assert_eq(success.root.app_state(), AppStateMachine.State.CAMP)
	var commander_id: StringName = _first_commander(success.root)
	assert_ne(commander_id, &"")
	if commander_id.is_empty():
		return

	var before_profile: ProfileState = success.root.try_camp_view_model().get("_profile")
	assert_not_null(before_profile)
	if before_profile == null:
		return
	var before_serial: String = before_profile.next_run_serial.to_hex()
	var started: Variant = success.root.call(
		"start_expedition",
		StartExpeditionRequest.new(commander_id, 0)
	)
	assert_true(started is AppActionResult, "start must return typed AppActionResult")
	if not (started is AppActionResult):
		return
	assert_true(started.ok)
	assert_true(started.committed, "successful start atomically commits profile+run")
	assert_true(started.presentation_ok)
	assert_eq(success.root.app_state(), AppStateMachine.State.RUN)
	var committed: LoadResult = success.repository.load()
	assert_true(committed.ok)
	if committed.ok:
		assert_eq(committed.run_status, LoadResult.RunStatus.LOADED)
		assert_not_null(committed.run)
		assert_ne(committed.profile.next_run_serial.to_hex(), before_serial)

	var rejected_storage := FakeSaveStorage.new()
	var rejected: Variant = Support.boot(self, rejected_storage)
	if not _require_typed_lifecycle(rejected.root):
		return
	var rejected_open: Variant = rejected.root.call("open_camp")
	assert_true(rejected_open is AppActionResult)
	if not (rejected_open is AppActionResult):
		return
	assert_true(rejected_open.ok)
	var rejected_before: PackedByteArray = Support.main_bytes(rejected_storage)
	var invalid: Variant = rejected.root.call(
		"start_expedition",
		StartExpeditionRequest.new(&"commander.missing", 0)
	)
	assert_true(invalid is AppActionResult)
	if invalid is AppActionResult:
		assert_false(invalid.ok)
		assert_false(invalid.committed, "domain/pre-commit reject must remain zero-write")
		assert_false(invalid.error == null, "pre-commit reject must remain diagnosable")
	assert_eq(rejected.root.app_state(), AppStateMachine.State.CAMP)
	assert_eq(Support.main_bytes(rejected_storage), rejected_before)

	var post_storage := FakeSaveStorage.new()
	var post: Variant = Support.boot(
		self,
		post_storage,
		CompositionFailingApplicationRoot.new()
	)
	if not _require_typed_lifecycle(post.root):
		return
	var post_open: Variant = post.root.call("open_camp")
	assert_true(post_open is AppActionResult)
	if not (post_open is AppActionResult):
		return
	assert_true(post_open.ok)
	var post_commander: StringName = _first_commander(post.root)
	assert_ne(post_commander, &"")
	if post_commander.is_empty():
		return
	var post_result: Variant = post.root.call(
		"start_expedition",
		StartExpeditionRequest.new(post_commander, 0)
	)
	assert_true(post_result is AppActionResult)
	if post_result is AppActionResult:
		assert_false(post_result.ok)
		assert_true(post_result.committed, "compose failure occurs after durable run commit")
		assert_false(post_result.presentation_ok)
		assert_not_null(post_result.error)
		if post_result.error != null:
			assert_eq(
				post_result.error.source_code,
				ApplicationRoot.ERROR_RUN_BATTLE_CATALOG_FAILED
			)
	var retained: LoadResult = post.repository.load()
	assert_true(retained.ok)
	if retained.ok:
		assert_eq(retained.run_status, LoadResult.RunStatus.LOADED)
		assert_not_null(retained.run, "post-commit failure must retain the unique run")
	await wait_process_frames(2)


func _require_typed_lifecycle(root: ApplicationRoot) -> bool:
	var present: bool = (
		root.has_method("open_camp")
		and Support.method_argument_count(root, &"start_expedition") == 1
	)
	assert_true(
		present,
		"T05 must replace the old two-argument/StringName start boundary"
	)
	return present


func _first_commander(root: ApplicationRoot) -> StringName:
	var view_model: CampViewModel = root.try_camp_view_model()
	if view_model == null:
		return &""
	var commanders: Array[StringName] = view_model.commander_hall_unlocked_commander_ids()
	return commanders[0] if not commanders.is_empty() else &""
