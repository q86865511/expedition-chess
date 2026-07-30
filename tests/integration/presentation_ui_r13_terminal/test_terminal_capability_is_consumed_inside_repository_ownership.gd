extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r13_terminal/"
	+ "r13_terminal_test_support.gd"
)


func test_terminal_capability_is_consumed_before_application_and_never_reaches_router() -> void:
	var repository := Support.repository_with_terminal_root()
	add_child_autofree(repository)
	assert_true(
		repository.has_method("_issue_terminal_settlement_presentation_capability"),
		"repository must be the only terminal settlement authority"
	)
	assert_true(
		repository.has_method("_consume_terminal_settlement_presentation_capability"),
		"repository must atomically consume the terminal capability while writer-owned"
	)
	if (
		not repository.has_method("_issue_terminal_settlement_presentation_capability")
		or not repository.has_method("_consume_terminal_settlement_presentation_capability")
	):
		return

	var terminal_capabilities: Array[TerminalSettlementPresentationCapability] = []
	var concrete := Support.RecordingInstalledPort.new()
	var application_port := ApplicationTerminalHandoffPort.new(
		func(
			capability: TerminalSettlementPresentationCapability,
			_snapshot: ResultsPresentationSnapshot
		) -> AppActionResult:
			terminal_capabilities.append(capability)
			assert_true(
				capability.has_method("_is_consumed") and capability.call("_is_consumed"),
				"AppRoot receives only an already-consumed settlement proof"
			)
			return AppActionResult.success(true),
		concrete
	)
	var coordinator := TerminalSettlementCoordinator.new(
		repository,
		application_port,
		func() -> void: pass,
		func() -> void: pass,
		func() -> void: pass
	)

	var settled := coordinator.settle(Support.reward_table())

	assert_true(settled.ok)
	assert_eq(terminal_capabilities.size(), 1)
	assert_eq(concrete.installed_capabilities.size(), 1)
	if terminal_capabilities.is_empty() or concrete.installed_capabilities.is_empty():
		return
	var terminal := terminal_capabilities[0]
	var installed := concrete.installed_capabilities[0]
	assert_ne(
		installed,
		terminal,
		"repository settlement authority must not cross into presentation"
	)
	assert_true(
		installed.get_script() != null
		and String(installed.get_script().resource_path).ends_with(
			"/installed_results_presentation_capability.gd"
		),
		"presentation receives the AppRoot-issued installed capability only"
	)
	assert_false(
		bool(repository.call(
			"_consume_terminal_settlement_presentation_capability",
			terminal,
			concrete.snapshots[0]
		)),
		"consumed settlement authority is permanently replay-proof"
	)


func test_direct_application_commit_and_duplicate_present_are_rejected_without_route_change() -> void:
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
		&"run.r13.replay",
		repository._committed_file_digest()
	)
	assert_true(repository._begin_writer_ownership())
	var terminal: Variant = repository.call(
		"_issue_terminal_settlement_presentation_capability",
		snapshot.run_id,
		snapshot.receipt_id
	)
	assert_not_null(terminal)
	assert_true(bool(repository.call(
		"_consume_terminal_settlement_presentation_capability",
		terminal,
		snapshot
	)))
	var installed := application_port.install_application_handoff(terminal, snapshot)
	var duplicate_terminal: Variant = repository.call(
		"_issue_terminal_settlement_presentation_capability",
		snapshot.run_id,
		snapshot.receipt_id
	)
	assert_true(bool(repository.call(
		"_consume_terminal_settlement_presentation_capability",
		duplicate_terminal,
		snapshot
	)))
	assert_false(
		application_port.install_application_handoff(
			duplicate_terminal,
			snapshot
		).ok,
		"duplicate install cannot replace the pending AppRoot snapshot/capability"
	)
	repository._release_writer_ownership()
	assert_true(installed.ok)

	var direct := application_port.commit_handoff(terminal, snapshot)
	assert_false(direct.ok, "direct split-boundary bypass must be rejected")
	assert_eq(concrete.installed_capabilities.size(), 0)
	var first := application_port.present_installed_handoff()
	assert_true(first.ok)
	assert_eq(concrete.installed_capabilities.size(), 1)
	var active_capability := concrete.installed_capabilities[0]
	var duplicate := application_port.present_installed_handoff()
	assert_false(duplicate.ok)
	assert_eq(
		concrete.installed_capabilities.size(),
		1,
		"duplicate present cannot rotate route or lease"
	)
	assert_true(
		active_capability.has_method("_is_consumed")
		and active_capability.call("_is_consumed"),
		"installed presentation capability is consumed exactly once"
	)


func test_manual_terminal_capability_and_non_consuming_adapter_fail_closed() -> void:
	var snapshot := Support.authoritative_snapshot(&"run.r13.manual")
	var manual := TerminalSettlementPresentationCapability.new(
		RefCounted.new(),
		7,
		snapshot.committed_file_digest,
		snapshot.run_id,
		snapshot.receipt_id,
		&"manual.bypass"
	)
	var manual_port := ApplicationTerminalHandoffPort.new(
		func(
			_capability: TerminalSettlementPresentationCapability,
			_snapshot: ResultsPresentationSnapshot
		) -> AppActionResult:
			return AppActionResult.success(true),
		Support.RecordingInstalledPort.new()
	)
	assert_false(
		manual_port.install_application_handoff(manual, snapshot).ok,
		"constructor-created settlement authority is never installable"
	)

	var repository := Support.repository_with_terminal_root()
	add_child_autofree(repository)
	snapshot = Support.authoritative_snapshot(
		&"run.r13.nonconsuming",
		repository._committed_file_digest()
	)
	assert_true(repository._begin_writer_ownership())
	var issued := repository._issue_terminal_settlement_presentation_capability(
		snapshot.run_id,
		snapshot.receipt_id
	)
	assert_true(
		repository._consume_terminal_settlement_presentation_capability(
			issued,
			snapshot
		)
	)
	var non_consuming := Support.RecordingInstalledPort.new()
	non_consuming.consume_installed_capability = false
	var application_port := ApplicationTerminalHandoffPort.new(
		func(
			_capability: TerminalSettlementPresentationCapability,
			_snapshot: ResultsPresentationSnapshot
		) -> AppActionResult:
			return AppActionResult.success(true),
		non_consuming
	)
	assert_true(application_port.install_application_handoff(issued, snapshot).ok)
	repository._release_writer_ownership()
	var rejected := application_port.present_installed_handoff()
	assert_false(rejected.ok)
	assert_eq(
		rejected.error.source_code,
		ApplicationTerminalHandoffPort.INSTALLED_CAPABILITY_NOT_CONSUMED
	)
	assert_false(
		application_port.present_installed_handoff().ok,
		"failed presentation still clears the installed handoff exactly once"
	)
