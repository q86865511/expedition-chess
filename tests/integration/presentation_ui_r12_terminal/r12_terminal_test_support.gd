extends RefCounted


class CompetingPresentationPort:
	extends TerminalPresentationHandoffPort

	var repository: SaveRepository
	var events: Array[StringName]
	var public_load_ok: bool = false
	var competing_save_ok: bool = false
	var presented_snapshot: ResultsPresentationSnapshot

	func _init(
		p_repository: SaveRepository,
		p_events: Array[StringName]
	) -> void:
		repository = p_repository
		events = p_events

	func commit_handoff(
		_capability: TerminalSettlementPresentationCapability,
		snapshot: ResultsPresentationSnapshot
	) -> AppActionResult:
		events.append(&"presentation")
		presented_snapshot = snapshot.deep_clone()
		var loaded := repository.load()
		public_load_ok = loaded.ok
		if not loaded.ok:
			return AppActionResult.committed_presentation_failure(
				DiagnosticError.new(
					&"REPOSITORY_STILL_OWNED",
					&"error.presentation.repository_still_owned"
				)
			)
		var competing_profile := loaded.profile.deep_clone()
		competing_profile.meta_currency += 1000
		var competing_root := SaveRoot.new(
			SaveSchemaContract.CURRENT,
			SaveRootFixture.CONTENT_VERSION,
			"0.2.0",
			1,
			1,
			"2026-07-29T00:00:00Z",
			competing_profile,
			null
		)
		competing_save_ok = repository.save(competing_root).ok
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
	table.id = &"meta_reward_table.r12_terminal"
	table.display_name_key = &"loc.meta_reward_table_r12_terminal"
	return table
