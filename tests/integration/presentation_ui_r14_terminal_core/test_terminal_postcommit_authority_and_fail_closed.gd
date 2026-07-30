extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_terminal_core/"
	+ "r14_terminal_core_test_support.gd"
)


func test_terminal_commit_uses_authoritative_save_result_without_storage_digest_reread() -> void:
	var repository := Support.repository(&"digest")
	add_child_autofree(repository)
	assert_true(repository.save(Support.terminal_root()).ok)
	var port := Support.FailClosedRecordingPort.new()
	var coordinator := TerminalSettlementCoordinator.new(
		repository,
		port,
		port.revoke,
		port.invalidate,
		port.release_session
	)

	var settled := coordinator.settle(Support.reward_table())

	assert_true(settled.ok)
	assert_eq(repository.committed_digest_reads, 0)
	assert_eq(port.revoked, 1)
	assert_eq(port.invalidated, 1)
	assert_eq(port.released, 1)
	assert_eq(port.application_snapshots.size(), 1)
	assert_eq(port.presented_snapshots.size(), 1)
	_assert_settled_exactly_once(repository, port.presented_snapshots)


func test_capability_issue_fault_installs_sealed_results_fail_closed() -> void:
	_assert_fault_installs_fail_closed(&"issue", false)


func test_capability_consume_fault_installs_sealed_results_fail_closed() -> void:
	_assert_fault_installs_fail_closed(&"consume", false)


func test_application_install_fault_installs_sealed_results_fail_closed() -> void:
	_assert_fault_installs_fail_closed(&"normal", true)


func _assert_fault_installs_fail_closed(
	repository_kind: StringName,
	primary_install_fault: bool
) -> void:
	var repository := Support.repository(repository_kind)
	add_child_autofree(repository)
	assert_true(repository.save(Support.terminal_root()).ok)
	var port := Support.FailClosedRecordingPort.new()
	port.primary_install_fault = primary_install_fault
	var coordinator := TerminalSettlementCoordinator.new(
		repository,
		port,
		port.revoke,
		port.invalidate,
		port.release_session
	)

	var settled := coordinator.settle(Support.reward_table())

	assert_true(settled.committed)
	assert_eq(port.revoked, 1)
	assert_eq(port.invalidated, 1)
	assert_eq(port.released, 1)
	assert_eq(port.fail_closed_snapshots.size(), 1)
	assert_eq(port.presented_snapshots.size(), 1)
	_assert_settled_exactly_once(repository, port.presented_snapshots)


func _assert_settled_exactly_once(
	repository: SaveRepository,
	presented: Array[ResultsPresentationSnapshot]
) -> void:
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
	assert_null(loaded.run)
	assert_eq(loaded.profile.settlement_receipts.size(), 1)
	assert_eq(presented.size(), 1)
	if presented.is_empty():
		return
	assert_true(presented[0].has_authoritative_pair())
	assert_eq(
		presented[0].receipt_id,
		StringName(loaded.profile.settlement_receipts[0].key.digest)
	)
