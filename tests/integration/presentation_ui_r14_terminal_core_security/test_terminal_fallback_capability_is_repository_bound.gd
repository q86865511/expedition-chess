extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_terminal_core/"
	+ "r14_terminal_core_test_support.gd"
)


func test_manual_foreign_wrong_snapshot_and_replay_are_rejected() -> void:
	var repository := Support.repository(&"normal")
	var foreign_repository := Support.repository(&"normal")
	add_child_autofree(repository)
	add_child_autofree(foreign_repository)
	var terminal := Support.terminal_root()
	var run_id := StringName(terminal.run.run_id)
	var settled_profile := MetaSettlementService.try_settle(
		terminal.profile,
		terminal.run,
		Support.reward_table()
	)
	assert_not_null(settled_profile)
	var receipt: SettlementReceiptState = settled_profile.settlement_receipts.back()
	var root := _cleared_root(settled_profile)
	assert_true(repository._begin_writer_ownership())
	var saved := repository._save_while_owned(root)
	assert_true(saved.ok)
	var snapshot := ResultsPresentationSnapshot.capture(
		settled_profile,
		receipt,
		run_id,
		saved.committed_digest.value,
		true
	)
	var capability: Variant = repository.call(
		"_issue_terminal_postcommit_fallback_capability",
		snapshot.run_id,
		snapshot.receipt_id
	)
	assert_not_null(capability)

	assert_true(foreign_repository._begin_writer_ownership())
	assert_true(foreign_repository._save_while_owned(root).ok)
	assert_false(bool(foreign_repository.call(
		"_consume_terminal_postcommit_fallback_capability",
		capability,
		snapshot
	)))
	foreign_repository._release_writer_ownership()

	var wrong_snapshot := snapshot.deep_clone()
	wrong_snapshot.receipt.currency_delta += 1
	assert_false(bool(repository.call(
		"_consume_terminal_postcommit_fallback_capability",
		capability,
		wrong_snapshot
	)))
	assert_true(bool(repository.call(
		"_consume_terminal_postcommit_fallback_capability",
		capability,
		snapshot
	)))
	assert_false(bool(repository.call(
		"_consume_terminal_postcommit_fallback_capability",
		capability,
		snapshot
	)))

	var callback_counts: Array[int] = [0]
	var route_port := Support.AuthoritativeGenerationPort.new()
	var application_port := ApplicationTerminalHandoffPort.new(
		func(
			_capability: TerminalSettlementPresentationCapability,
			_snapshot: ResultsPresentationSnapshot
		) -> AppActionResult:
			return AppActionResult.success(true),
		route_port,
		func(
			_snapshot: ResultsPresentationSnapshot,
			_cause: StringName
		) -> AppActionResult:
			callback_counts[0] += 1
			return AppActionResult.success(true)
	)
	var manual := TerminalPostcommitFallbackCapability.new(
		RefCounted.new(),
		repository._current_operation_epoch(),
		snapshot.committed_file_digest,
		snapshot.run_id,
		snapshot.receipt_id,
		&"manual.forged"
	)
	assert_false(application_port._install_fail_closed_application_handoff(
		manual,
		snapshot,
		&"MANUAL_FORGED"
	).ok)
	assert_false(application_port._install_fail_closed_application_handoff(
		capability,
		wrong_snapshot,
		&"WRONG_SNAPSHOT"
	).ok)
	assert_true(application_port._install_fail_closed_application_handoff(
		capability,
		snapshot,
		&"PRIMARY_INSTALL_FAULT"
	).ok)
	assert_false(application_port._install_fail_closed_application_handoff(
		capability,
		snapshot,
		&"REPLAY"
	).ok)
	assert_eq(callback_counts[0], 1)
	repository._release_writer_ownership()
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
	assert_eq(
		loaded.profile.settlement_receipts.size(),
		settled_profile.settlement_receipts.size()
	)
	assert_eq(loaded.profile.meta_currency, settled_profile.meta_currency)


func _cleared_root(profile: ProfileState) -> SaveRoot:
	var base := SaveRootFixture.create_valid_root()
	return SaveRoot.new(
		base.schema_version,
		base.content_version,
		base.app_version,
		base.rng_version,
		base.hash_version,
		base.saved_at_utc,
		profile,
		null
	)
