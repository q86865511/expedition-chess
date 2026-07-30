extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r13_terminal/"
	+ "r13_terminal_test_support.gd"
)


func test_unlock_time_caller_mutation_cannot_replace_installed_snapshot() -> void:
	var repository := Support.repository_with_terminal_root()
	add_child_autofree(repository)
	if (
		not repository.has_method("_issue_terminal_settlement_presentation_capability")
		or not repository.has_method("_consume_terminal_settlement_presentation_capability")
	):
		assert_true(false, "repository terminal issue/consume hooks are required")
		return
	var concrete := Support.RecordingInstalledPort.new()
	var application_port := ApplicationTerminalHandoffPort.new(
		func(
			_capability: TerminalSettlementPresentationCapability,
			_snapshot: ResultsPresentationSnapshot
		) -> AppActionResult:
			return AppActionResult.success(true),
		concrete
	)
	var snapshot := Support.authoritative_snapshot(
		&"run.r13.digest",
		repository._committed_file_digest()
	)
	assert_true(repository._begin_writer_ownership())
	var terminal: Variant = repository.call(
		"_issue_terminal_settlement_presentation_capability",
		snapshot.run_id,
		snapshot.receipt_id
	)
	assert_true(bool(repository.call(
		"_consume_terminal_settlement_presentation_capability",
		terminal,
		snapshot
	)))
	assert_true(application_port.install_application_handoff(terminal, snapshot).ok)
	repository._release_writer_ownership()

	var installed_currency := snapshot.profile.meta_currency
	snapshot.profile.meta_currency += 999
	var accepted := application_port.present_installed_handoff()
	assert_true(accepted.ok)
	assert_eq(concrete.installed_capabilities.size(), 1)
	assert_eq(
		concrete.snapshots[0].profile.meta_currency,
		installed_currency,
		"zero-argument present can only use the AppRoot-installed clone"
	)


func test_unbound_retry_rejects_without_not_implemented_fallback() -> void:
	var port := ResultsFallbackNavigationPort.new()
	assert_true(
		port.has_method("bind_installed_results"),
		"fallback navigation must bind repository CAS to an AppRoot snapshot provider"
	)
	if not port.has_method("bind_installed_results"):
		return
	var rejected := port.retry_installed()
	assert_false(rejected.ok, "an unbound port rejects safely")
	assert_ne(
		rejected.error.source_code,
		ResultsFallbackNavigationPort.NOT_IMPLEMENTED,
		"production fallback actions must never return NOT_IMPLEMENTED"
	)


func test_unrelated_profile_write_allows_fresh_retry_but_stales_prior_observation() -> void:
	var repository := Support.probed_retry_repository()
	add_child_autofree(repository)
	var installed := Support.settle_for_retry(repository)
	assert_not_null(installed)
	var initial := repository.load()
	assert_true(initial.ok)
	assert_false(
		repository._operation_in_progress,
		"settlement and initial observation must release repository ownership"
	)
	assert_true(
		repository._results_retry_receipt_matches(initial, installed),
		"installed receipt content must match the authoritative settled profile"
	)
	var leases := LiveScreenLeaseRegistry.new()
	leases.activate(AppStateMachine.State.RESULTS, 1)
	var presented: Array[ResultsPresentationSnapshot] = []
	var reentrant_codes: Array[StringName] = []
	var camp_calls: Array[int] = [0]
	var menu_calls: Array[int] = [0]
	var port_holder: Array[ResultsFallbackNavigationPort] = []
	var port := ResultsFallbackNavigationPort.new()
	port_holder.append(port)
	var retry_authority := SaveRepositoryResultsRenderRetryAuthority.new(
		repository
	)
	assert_eq(
		port.bind_installed_results(
			retry_authority,
			func() -> ResultsPresentationSnapshot: return installed.deep_clone(),
			func(
				candidate: ResultsPresentationSnapshot,
				_generation: int
			) -> AppActionResult:
				reentrant_codes.append(port.return_to_camp().error.source_code)
				reentrant_codes.append(port.return_to_menu().error.source_code)
				presented.append(candidate.deep_clone())
				return AppActionResult.success(false),
			func() -> AppActionResult:
				camp_calls[0] += 1
				return AppActionResult.success(false),
			func() -> AppActionResult:
				menu_calls[0] += 1
				return AppActionResult.success(false),
			leases,
			1,
			installed
		),
		&""
	)
	var stale_observation := retry_authority.issue_retry_capability(
		installed,
		1,
		1
	)
	assert_true(stale_observation.ok)
	if not stale_observation.ok:
		return

	var unrelated_profile := initial.profile.deep_clone()
	unrelated_profile.meta_currency += 100
	assert_true(
		repository.save(
			Support.cleared_root_with_profile(unrelated_profile)
		).ok
	)
	assert_false(
		retry_authority.consume_retry_capability(
			stale_observation.capability,
			installed,
			1,
			1
		),
		"write after prepare invalidates the observation digest/epoch CAS"
	)
	repository.before_issue = func() -> void:
		reentrant_codes.append(
			port_holder[0].return_to_camp().error.source_code
		)
		reentrant_codes.append(
			port_holder[0].return_to_menu().error.source_code
		)
	repository.after_consume = func() -> void:
		reentrant_codes.append(
			port_holder[0].return_to_camp().error.source_code
		)
		reentrant_codes.append(
			port_holder[0].return_to_menu().error.source_code
		)
	assert_true(
		port.retry_installed().ok,
		"unrelated write preserving the exact receipt permits a fresh atomic retry"
	)
	assert_eq(presented.size(), 1)
	assert_eq(
		presented[0].presentation_digest(),
		installed.presentation_digest(),
		"retry candidate remains the immutable AppRoot-installed pair"
	)
	assert_eq(
		presented[0].profile.meta_currency,
		initial.profile.meta_currency,
		"new repository profile data cannot reconstruct the Results candidate"
	)
	assert_eq(
		reentrant_codes,
		[
			ResultsFallbackNavigationPort.BUSY,
			ResultsFallbackNavigationPort.BUSY,
			ResultsFallbackNavigationPort.BUSY,
			ResultsFallbackNavigationPort.BUSY,
			ResultsFallbackNavigationPort.BUSY,
			ResultsFallbackNavigationPort.BUSY,
		],
		"ownership entry, CAS release, and candidate bind keep Camp/Menu behind single-flight"
	)
	assert_eq(camp_calls[0], 0)
	assert_eq(menu_calls[0], 0)
	assert_true(
		port.return_to_camp().ok,
		"guard releases after retry so one fresh Results action can win"
	)
	assert_eq(camp_calls[0], 1)


func test_receipt_removal_or_replacement_is_stale() -> void:
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(repository)
	var installed := Support.settle_for_retry(repository)
	assert_not_null(installed)
	var loaded := repository.load()
	assert_true(loaded.ok)
	var leases := LiveScreenLeaseRegistry.new()
	leases.activate(AppStateMachine.State.RESULTS, 1)
	var port := ResultsFallbackNavigationPort.new()
	assert_eq(
		port.bind_installed_results(
			SaveRepositoryResultsRenderRetryAuthority.new(repository),
			func() -> ResultsPresentationSnapshot: return installed.deep_clone(),
			func(
				_snapshot: ResultsPresentationSnapshot,
				_generation: int
			) -> AppActionResult: return AppActionResult.success(false),
			func() -> AppActionResult: return AppActionResult.success(false),
			func() -> AppActionResult: return AppActionResult.success(false),
			leases,
			1,
			installed
		),
		&""
	)
	var removed := loaded.profile.deep_clone()
	removed.settlement_receipts.clear()
	assert_true(
		repository.save(Support.cleared_root_with_profile(removed)).ok
	)
	var rejected := port.retry_installed()
	assert_false(rejected.ok)
	assert_eq(
		rejected.error.source_code,
		ResultsFallbackNavigationPort.STALE
	)
