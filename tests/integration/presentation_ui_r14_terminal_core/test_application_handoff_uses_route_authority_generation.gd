extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_terminal_core/"
	+ "r14_terminal_core_test_support.gd"
)


func test_installed_capability_uses_generation_prepared_by_route_authority() -> void:
	var route_port := Support.AuthoritativeGenerationPort.new()
	var application_port := ApplicationTerminalHandoffPort.new(
		func(
			_capability: TerminalSettlementPresentationCapability,
			_snapshot: ResultsPresentationSnapshot
		) -> AppActionResult:
			return AppActionResult.success(true),
		route_port
	)
	var repository := Support.repository(&"normal")
	add_child_autofree(repository)
	assert_true(repository.save(Support.terminal_root()).ok)
	var snapshot := Support.authoritative_snapshot(
		&"run.r14.route",
		repository._committed_file_digest()
	)
	assert_true(repository._begin_writer_ownership())
	var capability := (
		repository._issue_terminal_settlement_presentation_capability(
			snapshot.run_id,
			snapshot.receipt_id
		)
	)
	assert_not_null(capability)
	assert_true(
		repository._consume_terminal_settlement_presentation_capability(
			capability,
			snapshot
		)
	)
	assert_true(
		application_port.install_application_handoff(
			capability,
			snapshot
		).ok
	)
	repository._release_writer_ownership()

	var presented := application_port.present_installed_handoff()

	assert_true(presented.ok)
	assert_eq(route_port.presentations, 1)
