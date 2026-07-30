extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r13_terminal/"
	+ "r13_terminal_test_support.gd"
)


func test_atomic_retry_owns_root_guard_before_repository_issue_until_route_commit() -> void:
	var repository := Support.probed_retry_repository()
	add_child_autofree(repository)
	var installed := Support.settle_for_retry(repository)
	assert_not_null(installed)
	if installed == null:
		return
	var leases := LiveScreenLeaseRegistry.new()
	leases.activate(AppStateMachine.State.RESULTS, 7)
	var root_guard: Array[bool] = [false]
	var begin_calls: Array[int] = [0]
	var end_calls: Array[int] = [0]
	var observed_guard: Array[bool] = []
	var reentrant_codes: Array[StringName] = []
	var presented: Array[ResultsPresentationSnapshot] = []
	var port := ResultsFallbackNavigationPort.new()
	var begin_root_action := func() -> bool:
		if root_guard[0]:
			return false
		root_guard[0] = true
		begin_calls[0] += 1
		return true
	var end_root_action := func() -> void:
		root_guard[0] = false
		end_calls[0] += 1
	assert_eq(
		port.bind_installed_results(
			SaveRepositoryResultsRenderRetryAuthority.new(repository),
			func() -> ResultsPresentationSnapshot:
				return installed.deep_clone(),
			func(
				candidate: ResultsPresentationSnapshot,
				_generation: int
			) -> AppActionResult:
				observed_guard.append(root_guard[0])
				presented.append(candidate.deep_clone())
				return AppActionResult.success(false),
			func() -> AppActionResult:
				return AppActionResult.success(false),
			func() -> AppActionResult:
				return AppActionResult.success(false),
			leases,
			7,
			installed,
			begin_root_action,
			end_root_action
		),
		&""
	)
	repository.before_issue = func() -> void:
		observed_guard.append(root_guard[0])
		reentrant_codes.append(
			port.return_to_camp().error.source_code
		)
	repository.after_consume = func() -> void:
		observed_guard.append(root_guard[0])
		reentrant_codes.append(
			port.return_to_menu().error.source_code
		)

	assert_true(
		port.has_method(&"retry_installed"),
		"production retry must be one root-owned transaction, not prepare/retry"
	)
	if not port.has_method(&"retry_installed"):
		return
	var result: Variant = port.call(&"retry_installed")

	assert_true(result is AppActionResult)
	if not result is AppActionResult:
		return
	assert_true((result as AppActionResult).ok)
	assert_eq(begin_calls[0], 1)
	assert_eq(end_calls[0], 1)
	assert_false(root_guard[0])
	assert_eq(observed_guard, [true, true, true])
	assert_eq(
		reentrant_codes,
		[
			ResultsFallbackNavigationPort.BUSY,
			ResultsFallbackNavigationPort.BUSY,
		]
	)
	assert_eq(presented.size(), 1)
