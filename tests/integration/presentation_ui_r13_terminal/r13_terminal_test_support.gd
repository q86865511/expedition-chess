extends RefCounted


class RecordingInstalledPort:
	extends TerminalPresentationHandoffPort

	var installed_capabilities: Array[RefCounted] = []
	var snapshots: Array[ResultsPresentationSnapshot] = []
	var commit_result: AppActionResult = AppActionResult.success(true)
	var consume_installed_capability: bool = true

	func commit_installed_handoff(
		capability: InstalledResultsPresentationCapability,
		snapshot: ResultsPresentationSnapshot
	) -> AppActionResult:
		installed_capabilities.append(capability)
		snapshots.append(snapshot.deep_clone())
		if consume_installed_capability:
			capability.call(
				"_consume",
				snapshot,
				AppStateMachine.State.RESULTS,
				1
			)
		return commit_result


class FaultInjectingSceneRouter:
	extends SceneRouterService

	var routes: Array[StringName] = []
	var contexts: Array[StagedScreenContext] = []
	var fail_results_once: bool = true

	func install_production(
		route_kind: StringName,
		context: StagedScreenContext
	) -> StringName:
		routes.append(route_kind)
		contexts.append(context)
		if route_kind == &"RESULTS" and fail_results_once:
			fail_results_once = false
			return &"INJECTED_RESULTS_INSTALL_FAULT"
		return &""


class ProbedRetryRepository:
	extends SaveRepository

	var before_issue: Callable
	var after_consume: Callable

	func _init(
		storage: SaveStoragePort,
		receipt_port: PinnedCatalogReceiptPort,
		migration_port: ContentIdMigrationPort,
		validator: RunStateValidator
	) -> void:
		super(storage, receipt_port, migration_port, validator)

	func _issue_results_render_retry_capability(
		installed_snapshot: ResultsPresentationSnapshot,
		route_generation: int,
		attempt_generation: int,
		issuer: Object
	) -> ResultsRenderRetryCapability:
		if before_issue.is_valid():
			before_issue.call()
		return super._issue_results_render_retry_capability(
			installed_snapshot,
			route_generation,
			attempt_generation,
			issuer
		)

	func _consume_results_render_retry_capability(
		capability: ResultsRenderRetryCapability,
		installed_snapshot: ResultsPresentationSnapshot,
		route_generation: int,
		attempt_generation: int,
		issuer: Object
	) -> bool:
		var result := super._consume_results_render_retry_capability(
			capability,
			installed_snapshot,
			route_generation,
			attempt_generation,
			issuer
		)
		if after_consume.is_valid():
			after_consume.call()
		return result


static func repository_with_terminal_root() -> SaveRepository:
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	var saved := repository.save(terminal_root())
	assert(saved.ok)
	return repository


static func probed_retry_repository() -> ProbedRetryRepository:
	return ProbedRetryRepository.new(
		FakeSaveStorage.new(),
		FakePinnedCatalogReceiptPort.new(SaveRootFixture.create_receipt()),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)


static func settle_for_retry(
	repository: SaveRepository
) -> ResultsPresentationSnapshot:
	assert(repository != null)
	assert(repository.save(terminal_root()).ok)
	var installed_snapshots: Array[ResultsPresentationSnapshot] = []
	var concrete := RecordingInstalledPort.new()
	var application_port := ApplicationTerminalHandoffPort.new(
		func(
			_capability: TerminalSettlementPresentationCapability,
			snapshot: ResultsPresentationSnapshot
		) -> AppActionResult:
			installed_snapshots.append(snapshot.deep_clone())
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
	assert(coordinator.settle(reward_table()).ok)
	assert(installed_snapshots.size() == 1)
	return (
		installed_snapshots[0].deep_clone()
		if installed_snapshots.size() == 1
		else null
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
	table.id = &"meta_reward_table.r13_terminal"
	table.display_name_key = &"loc.meta_reward_table_r13_terminal"
	return table


static func authoritative_snapshot(
	run_id: StringName = &"run.r13",
	committed_digest: String = "a".repeat(64)
) -> ResultsPresentationSnapshot:
	var profile := SaveRootFixture.create_valid_root().profile
	var receipt_key_result := RuntimeKeySchemaRegistry.new().build_settlement_receipt(
		run_id
	)
	assert(receipt_key_result.ok)
	var receipt := SettlementReceiptState.new(
		receipt_key_result.key_state as SettlementReceiptKeyState,
		SettlementReceiptState.Outcome.FAILED,
		7,
		"receipt.payload.r13"
	)
	profile.settlement_receipts.append(receipt)
	return ResultsPresentationSnapshot.capture(
		profile,
		receipt,
		run_id,
		committed_digest,
		true
	)


static func settled_snapshot_from(repository: SaveRepository) -> ResultsPresentationSnapshot:
	var loaded := repository.load()
	assert(loaded.ok)
	assert(loaded.profile != null)
	assert(not loaded.profile.settlement_receipts.is_empty())
	var receipt: SettlementReceiptState = loaded.profile.settlement_receipts.back()
	var run_id := _run_id_from_receipt(receipt)
	return ResultsPresentationSnapshot.capture(
		loaded.profile,
		receipt,
		run_id,
		loaded._committed_digest,
		true
	)


static func cleared_root_with_profile(profile: ProfileState) -> SaveRoot:
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


static func _run_id_from_receipt(receipt: SettlementReceiptState) -> StringName:
	if receipt == null or receipt.key == null:
		return &""
	for property: Dictionary in receipt.key.get_property_list():
		if String(property.get("name", "")) == "run_id":
			return StringName(receipt.key.get("run_id"))
	return &""
