extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r12_terminal/"
	+ "r12_terminal_test_support.gd"
)
const APPLICATION_PORT_PATH := \
	"res://app/state/application_terminal_handoff_port.gd"


func test_terminal_handoff_captures_authoritative_snapshot_before_release() -> void:
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	assert_true(repository.save(Support.terminal_root()).ok)
	var events: Array[StringName] = []
	var concrete := Support.CompetingPresentationPort.new(repository, events)
	var installed_snapshots: Array[ResultsPresentationSnapshot] = []
	var application_callback := func(
		capability: TerminalSettlementPresentationCapability,
		snapshot: ResultsPresentationSnapshot
	) -> AppActionResult:
		events.append(&"application")
		installed_snapshots.append(snapshot.deep_clone())
		if not capability.has_method("_authorizes_snapshot"):
			assert_true(false, "terminal capability must authorize the captured snapshot pair")
			return AppActionResult.committed_presentation_failure(
				DiagnosticError.new(
					&"TERMINAL_CAPABILITY_INVALID",
					&"error.presentation.terminal_capability_invalid"
				)
			)
		assert_true(
			bool(capability.call("_authorizes_snapshot", snapshot)),
			"root accepts only the receipt/profile/digest-bound capability"
		)
		return AppActionResult.success(true)
	var application_port_script := load(APPLICATION_PORT_PATH) as GDScript
	assert_not_null(application_port_script)
	if application_port_script == null:
		return
	var application_port: Variant = application_port_script.new(application_callback)
	var has_split_port: bool = (
		application_port.has_method("bind_presentation_port")
		and application_port.has_method("install_application_handoff")
		and application_port.has_method("present_installed_handoff")
	)
	assert_true(has_split_port, "R12 handoff port must expose the split ownership boundary")
	if not has_split_port:
		return
	assert_eq(application_port.call("bind_presentation_port", concrete), &"")
	var coordinator := TerminalSettlementCoordinator.new(
		repository,
		application_port,
		func() -> void: events.append(&"revoke"),
		func() -> void: events.append(&"invalidate"),
		func() -> void: events.append(&"session_release")
	)

	var settled := coordinator.settle(Support.reward_table())

	assert_true(settled.ok)
	assert_eq(
		events,
		[&"revoke", &"invalidate", &"session_release", &"application", &"presentation"],
		"application RESULTS state/snapshot installs before repository release and presentation"
	)
	assert_true(concrete.public_load_ok, "presentation begins only after writer ownership releases")
	assert_true(concrete.competing_save_ok)
	var installed_snapshot: ResultsPresentationSnapshot = (
		installed_snapshots[0] if not installed_snapshots.is_empty() else null
	)
	assert_not_null(installed_snapshot)
	assert_not_null(concrete.presented_snapshot)
	if installed_snapshot == null or concrete.presented_snapshot == null:
		return
	assert_true(installed_snapshot.call("has_authoritative_pair"))
	assert_eq(
		installed_snapshot.get("committed_file_digest"),
		concrete.presented_snapshot.get("committed_file_digest")
	)
	assert_eq(
		installed_snapshot.get("receipt_id"),
		concrete.presented_snapshot.get("receipt_id")
	)
	var installed_profile: ProfileState = installed_snapshot.get("profile")
	var presented_profile: ProfileState = concrete.presented_snapshot.get("profile")
	assert_not_null(installed_profile)
	assert_not_null(presented_profile)
	if installed_profile == null or presented_profile == null:
		return
	assert_eq(
		installed_profile.meta_currency,
		presented_profile.meta_currency,
		"release-time competing save cannot drift the captured Results profile"
	)
	var post_competition := repository.load()
	assert_true(post_competition.ok)
	assert_eq(
		post_competition.profile.meta_currency,
		installed_profile.meta_currency + 1000,
		"probe must actually replace the public committed profile after release"
	)


func test_application_port_orders_root_install_before_root_free_concrete_adapter() -> void:
	var application_port_script := load(APPLICATION_PORT_PATH) as GDScript
	assert_not_null(application_port_script)
	if application_port_script == null:
		return
	var events: Array[StringName] = []
	var concrete := RecordingConcretePort.new(events)
	var root_snapshots: Array[ResultsPresentationSnapshot] = []
	var port: Variant = application_port_script.new(
		func(
			_capability: TerminalSettlementPresentationCapability,
			snapshot: ResultsPresentationSnapshot
		) -> AppActionResult:
			events.append(&"root")
			root_snapshots.append(snapshot.deep_clone())
			return AppActionResult.success(true)
	)
	var has_split_port: bool = (
		port.has_method("bind_presentation_port")
		and port.has_method("install_application_handoff")
		and port.has_method("present_installed_handoff")
	)
	assert_true(has_split_port, "R12 application port must split install from presentation")
	if not has_split_port:
		return
	assert_eq(port.call("bind_presentation_port", concrete), &"")
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(repository)
	assert_true(repository.save(Support.terminal_root()).ok)
	var snapshot := _authoritative_snapshot(repository._committed_file_digest())
	if snapshot == null:
		return
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
	var installed: Variant = port.call(
		"install_application_handoff",
		capability,
		snapshot
	)
	repository._release_writer_ownership()
	assert_true(installed is AppActionResult and installed.ok)
	assert_eq(events, [&"root"])
	var presented: Variant = port.call("present_installed_handoff")
	assert_true(presented is AppActionResult and presented.ok)
	assert_eq(events, [&"root", &"concrete"])
	var root_snapshot: ResultsPresentationSnapshot = (
		root_snapshots[0] if not root_snapshots.is_empty() else null
	)
	assert_not_null(root_snapshot)
	var concrete_retains_root: bool = false
	for property: Dictionary in concrete.get_property_list():
		if String(property.get("name", "")).contains("root"):
			concrete_retains_root = true
	assert_false(
		concrete_retains_root,
		"concrete route/lease adapter must not retain an ApplicationRoot backreference"
	)


class RecordingConcretePort:
	extends TerminalPresentationHandoffPort

	var events: Array[StringName]

	func _init(p_events: Array[StringName]) -> void:
		events = p_events

	func commit_handoff(
		_capability: TerminalSettlementPresentationCapability,
		_snapshot: ResultsPresentationSnapshot
	) -> AppActionResult:
		events.append(&"concrete")
		return AppActionResult.success(true)

	func commit_installed_handoff(
		capability: InstalledResultsPresentationCapability,
		snapshot: ResultsPresentationSnapshot
	) -> AppActionResult:
		if not capability._consume(
			snapshot,
			AppStateMachine.State.RESULTS,
			1
		):
			return AppActionResult.committed_presentation_failure(
				DiagnosticError.new(
					&"INSTALLED_CAPABILITY_INVALID",
					&"error.presentation.installed_capability_invalid"
				)
			)
		return commit_handoff(null, snapshot)


func _authoritative_snapshot(
	committed_digest: String = "a".repeat(64)
) -> ResultsPresentationSnapshot:
	var profile := SaveRootFixture.create_valid_root().profile
	var receipt_key_result := RuntimeKeySchemaRegistry.new().build_settlement_receipt(
		&"run.r12"
	)
	assert_true(receipt_key_result.ok)
	var receipt := SettlementReceiptState.new(
		receipt_key_result.key_state as SettlementReceiptKeyState,
		SettlementReceiptState.Outcome.FAILED,
		0,
		"receipt.payload"
	)
	profile.settlement_receipts.append(receipt)
	var script := load("res://app/state/results_presentation_snapshot.gd") as GDScript
	var has_capture: bool = script != null and script.has_method("capture")
	assert_true(has_capture, "ResultsPresentationSnapshot.capture is required")
	if not has_capture:
		return null
	return script.call(
		"capture",
		profile,
		receipt,
		&"run.r12",
		committed_digest,
		true
	) as ResultsPresentationSnapshot
