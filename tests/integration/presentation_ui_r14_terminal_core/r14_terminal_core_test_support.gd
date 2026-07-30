extends RefCounted


class PostSaveDigestFaultRepository:
	extends SaveRepository

	var committed_digest_reads: int = 0

	func _init(
		storage: SaveStoragePort,
		receipt_port: PinnedCatalogReceiptPort,
		migration_port: ContentIdMigrationPort,
		validator: RunStateValidator
	) -> void:
		super(storage, receipt_port, migration_port, validator)

	func _committed_file_digest() -> String:
		committed_digest_reads += 1
		return ""


class CapabilityIssueFaultRepository:
	extends SaveRepository

	func _init(
		storage: SaveStoragePort,
		receipt_port: PinnedCatalogReceiptPort,
		migration_port: ContentIdMigrationPort,
		validator: RunStateValidator
	) -> void:
		super(storage, receipt_port, migration_port, validator)

	func _issue_terminal_settlement_presentation_capability(
		_run_id: StringName,
		_receipt_id: StringName
	) -> TerminalSettlementPresentationCapability:
		return null


class CapabilityConsumeFaultRepository:
	extends SaveRepository

	func _init(
		storage: SaveStoragePort,
		receipt_port: PinnedCatalogReceiptPort,
		migration_port: ContentIdMigrationPort,
		validator: RunStateValidator
	) -> void:
		super(storage, receipt_port, migration_port, validator)

	func _consume_terminal_settlement_presentation_capability(
		_capability: TerminalSettlementPresentationCapability,
		_snapshot: ResultsPresentationSnapshot
	) -> bool:
		return false


class FailClosedRecordingPort:
	extends TerminalPresentationHandoffPort

	var primary_install_fault: bool = false
	var application_snapshots: Array[ResultsPresentationSnapshot] = []
	var fail_closed_snapshots: Array[ResultsPresentationSnapshot] = []
	var presented_snapshots: Array[ResultsPresentationSnapshot] = []
	var fallback_causes: Array[StringName] = []
	var revoked: int = 0
	var invalidated: int = 0
	var released: int = 0
	var _installed_snapshot: ResultsPresentationSnapshot
	var _route_generation: int = 41

	func prepare_results_route_generation() -> int:
		return _route_generation

	func install_application_handoff(
		_capability: TerminalSettlementPresentationCapability,
		snapshot: ResultsPresentationSnapshot
	) -> AppActionResult:
		application_snapshots.append(snapshot.deep_clone())
		if primary_install_fault:
			return AppActionResult.committed_presentation_failure(
				DiagnosticError.new(
					&"INJECTED_APPLICATION_INSTALL_FAULT",
					&"error.presentation.results_fallback"
				)
			)
		_installed_snapshot = snapshot.deep_clone()
		return AppActionResult.success(true)

	func _install_fail_closed_application_handoff(
		_fallback_capability: Variant,
		snapshot: ResultsPresentationSnapshot,
		cause: StringName
	) -> AppActionResult:
		fail_closed_snapshots.append(snapshot.deep_clone())
		fallback_causes.append(cause)
		_installed_snapshot = snapshot.deep_clone()
		return AppActionResult.success(true)

	func present_installed_handoff() -> AppActionResult:
		if _installed_snapshot == null:
			return AppActionResult.committed_presentation_failure(
				DiagnosticError.new(
					&"R14_HANDOFF_NOT_INSTALLED",
					&"error.presentation.results_fallback"
				)
			)
		presented_snapshots.append(_installed_snapshot.deep_clone())
		_installed_snapshot = null
		return AppActionResult.success(true)

	func revoke() -> void:
		revoked += 1

	func invalidate() -> void:
		invalidated += 1

	func release_session() -> void:
		released += 1


class AuthoritativeGenerationPort:
	extends TerminalPresentationHandoffPort

	var prepared_generation: int = 41
	var presentations: int = 0

	func prepare_results_route_generation() -> int:
		return prepared_generation

	func commit_installed_handoff(
		capability: InstalledResultsPresentationCapability,
		snapshot: ResultsPresentationSnapshot
	) -> AppActionResult:
		if not capability._consume(
			snapshot,
			AppStateMachine.State.RESULTS,
			prepared_generation
		):
			return AppActionResult.committed_presentation_failure(
				DiagnosticError.new(
					&"R14_ROUTE_GENERATION_DRIFT",
					&"error.presentation.results_fallback"
				)
			)
		presentations += 1
		return AppActionResult.success(true)


static func repository(kind: StringName) -> SaveRepository:
	var storage := FakeSaveStorage.new()
	var receipt_port := FakePinnedCatalogReceiptPort.new(
		SaveRootFixture.create_receipt()
	)
	var migration_port := FakeContentIdMigrationPort.new()
	match kind:
		&"digest":
			return PostSaveDigestFaultRepository.new(
				storage, receipt_port, migration_port, RunStateValidator.new()
			)
		&"issue":
			return CapabilityIssueFaultRepository.new(
				storage, receipt_port, migration_port, RunStateValidator.new()
			)
		&"consume":
			return CapabilityConsumeFaultRepository.new(
				storage, receipt_port, migration_port, RunStateValidator.new()
			)
		_:
			return SaveRepository.new(
				storage, receipt_port, migration_port, RunStateValidator.new()
			)


static func terminal_root() -> SaveRoot:
	var base := SaveRootFixture.create_valid_root()
	var run := base.run.deep_clone()
	run.run_phase = RunState.RunPhase.RESULTS
	run.resolution_state = IdleResolutionState.new()
	run.expedition_hp = 0
	run.defeated_boss_count = 0
	run.cleared_normal_count = 2
	run.cleared_elite_count = 1
	run.current_node_id = null
	return SaveRoot.new(
		base.schema_version,
		base.content_version,
		base.app_version,
		base.rng_version,
		base.hash_version,
		base.saved_at_utc,
		base.profile,
		run
	)


static func reward_table() -> MetaRewardTableDef:
	var table := MetaRewardTableDef.new()
	var scores: Array[EnumIntPairDef] = []
	for pair: Array in [
		[&"normal", 1],
		[&"elite", 3],
		[&"merchant", 0],
		[&"event", 0],
		[&"rest", 0],
		[&"treasure", 0],
		[&"boss", 5],
	]:
		var score := EnumIntPairDef.new()
		score.enum_key = pair[0]
		score.value_i32 = pair[1]
		scores.append(score)
	table.node_scores = scores
	table.completion_reward = 10
	table.failure_reward = 0
	var multiplier := ChallengeMultiplierDef.new()
	multiplier.challenge_level = 0
	multiplier.basis_points = 10000
	var multipliers: Array[ChallengeMultiplierDef] = [multiplier]
	table.challenge_multiplier_bps = multipliers
	table.id = &"meta_reward_table.r14_terminal_core"
	table.display_name_key = &"loc.meta_reward_table_r14_terminal_core"
	return table


static func authoritative_snapshot(
	run_id: StringName = &"run.r14.route",
	committed_digest: String = "a".repeat(64)
) -> ResultsPresentationSnapshot:
	var profile := SaveRootFixture.create_valid_root().profile
	var key_result := RuntimeKeySchemaRegistry.new().build_settlement_receipt(run_id)
	assert(key_result.ok)
	var receipt := SettlementReceiptState.new(
		key_result.key_state as SettlementReceiptKeyState,
		SettlementReceiptState.Outcome.FAILED,
		7,
		"receipt.payload.r14"
	)
	profile.settlement_receipts.append(receipt)
	return ResultsPresentationSnapshot.capture(
		profile,
		receipt,
		run_id,
		committed_digest,
		true
	)
