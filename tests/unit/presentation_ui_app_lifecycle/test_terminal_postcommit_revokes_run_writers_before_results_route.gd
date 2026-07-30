extends GutTest

const Support = preload("res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd")
const COORDINATOR_PATH := "res://app/state/terminal_settlement_coordinator.gd"
const CAPABILITY_PATH := "res://app/state/terminal_settlement_presentation_capability.gd"
const HANDOFF_PORT_PATH := "res://app/state/terminal_presentation_handoff_port.gd"
const ROOT_PATH := "res://app/app_root.gd"
const REPOSITORY_PATH := "res://services/save/save_repository.gd"


## Review debt deliberately remains open:
## - G2-R12-A01: T05 fake-port evidence does not prove the future T07/T09 concrete route/lease DAG.
## - G2-R12-A02: this test does not choose whether snapshot capture occurs before or after repository
##   release; fresh review must resolve that authoritative receipt/profile boundary.
func test_terminal_postcommit_revokes_run_writers_before_results_route() -> void:
	var coordinator_source := Support.source(COORDINATOR_PATH)
	var capability_source := Support.source(CAPABILITY_PATH)
	var port_source := Support.source(HANDOFF_PORT_PATH)
	var root_source := Support.source(ROOT_PATH)
	var repository_source := Support.source(REPOSITORY_PATH)

	assert_false(coordinator_source.is_empty(), "TerminalSettlementCoordinator is required")
	assert_true(
		coordinator_source.contains("class_name TerminalSettlementCoordinator"),
		"terminal handoff must have one coordinator owner"
	)
	assert_true(
		coordinator_source.contains("TerminalPresentationHandoffPort"),
		"T05 must depend on the typed handoff port, not a T07 concrete router"
	)
	assert_false(
		coordinator_source.contains("SceneRouterService")
			or coordinator_source.contains("LiveScreenLease.new("),
		"T05 fake-port evidence must not invade T07 concrete ownership"
	)
	assert_false(
		coordinator_source.contains("await "),
		"save→consume→revoke→invalidate→RESULTS handoff may not yield"
	)

	for field_name: String in [
		"_repository_identity",
		"_operation_epoch",
		"_committed_file_digest",
		"_run_id",
		"_receipt_id",
		"_use_nonce",
	]:
		assert_true(
			capability_source.contains(field_name),
			"terminal capability must bind %s" % field_name
		)
	assert_true(
		port_source.contains("commit_handoff("),
		"typed handoff port must carry capability plus Results snapshot"
	)
	assert_true(
		coordinator_source.contains("TerminalSettlementPresentationCapability"),
		"coordinator must consume repository-issued terminal capability internally"
	)
	assert_true(
		coordinator_source.contains("RESULTS")
			and coordinator_source.contains("FALLBACK"),
		"post-save handoff failure must fail closed into RESULTS/FALLBACK"
	)
	assert_true(
		coordinator_source.contains("revoke")
			and coordinator_source.contains("invalidate")
			and coordinator_source.contains("release"),
		"old RUN writers/session must be revoked before a Results route is attempted"
	)
	assert_true(
		repository_source.contains("_begin_writer_ownership")
			or repository_source.contains("_claim_operation_if_epoch"),
		"SaveRepository must expose an internal ownership boundary for terminal handoff"
	)
	assert_true(
		root_source.contains("TerminalSettlementCoordinator"),
		"ApplicationRoot must route terminal dispatch through the coordinator"
	)
	assert_false(
		root_source.contains("MetaSettlementCommand.new(")
			and root_source.contains("func settle_active_run() -> StringName"),
		"legacy public settle path must not return before typed postcommit handoff"
	)
